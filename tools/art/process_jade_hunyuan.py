# 青玉纸白样板：混元原始资产 → Blender 归一 + 色卡化 → 导出。
# 运行（Blender MCP / GUI 会话内）：
#   import importlib.util
#   spec = importlib.util.spec_from_file_location(
#       "process_jade", "<repo>/tools/art/process_jade_hunyuan.py")
#   mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
#   mod.process("pine")   # pine / rock / pavilion
# 或命令行：blender --background --factory-startup --python tools/art/process_jade_hunyuan.py -- pine
#
# 流程（每资产）：
#   1) 清场后导入 docs/art/jade_paper_sample/hunyuan_raw/<name>_raw.glb
#   2) 世界包围盒：等比缩放到目标高度，底面贴 z=0，xy 居中
#   3) 按烘焙贴图色相给面分段（冠/干/瓦/木/石），每段贴图 × 调色系数拉向色卡
#   4) 三角形超预算时 Decimate 减面
#   5) 另存 docs/art/jade_paper_sample/jade_<name>.blend，导出
#      src/levels/experiments/character_movement/jade_<name>.glb（export_yup）
#
# 色卡为线性值（GLB baseColorFactor 线性约定）；调色保留烘焙明暗，只校正色相/明度基线。

import colorsys
import sys

import bpy
import numpy as np
from mathutils import Vector

ROOT = "/Users/yuqixian/forever-skills/projects/games/game-xiuxian-lab"
RAW_DIR = f"{ROOT}/docs/art/jade_paper_sample/hunyuan_raw"
SRC_DIR = f"{ROOT}/docs/art/jade_paper_sample"
OUT_DIR = f"{ROOT}/src/levels/experiments/character_movement"

# 目标高度（米，人参照：人 1.70）与三角形预算。
TARGETS = {
    "pine": {"height": 6.0, "max_tris": 60000},
    "rock": {"height": 2.2, "max_tris": 30000},
    "pavilion": {"height": 4.6, "max_tris": 80000},  # 含基座；置于台基上顶约 5.2 m
    "mountain": {"height": 30.0, "max_tris": 50000},  # 远景剪影，场景内再放大 1.0–1.5
    "gate": {"height": 7.0, "max_tris": 80000},       # 三门牌坊，门洞可走
    "lantern": {"height": 1.6, "max_tris": 30000},
    "bamboo": {"height": 4.0, "max_tris": 40000},
    "character": {"height": 1.75, "max_tris": 60000},  # 混元人物（后处理前的基础归一）
}

# 色卡（线性值）。
PALETTE = {
    "foliage": (0.024, 0.085, 0.045),   # 深松绿（比 #1F3D2B 提亮一档，保冠内可读）
    "wood": (0.132, 0.060, 0.020),      # 暖棕木（微降饱和）
    "tile": (0.013, 0.147, 0.102),      # 青玉瓦 #1E6B5A
    "stone": (0.112, 0.144, 0.162),     # 青灰岩 #5E6A70
}

# 色相分段规则：[(hue_min, hue_max, min_sat, 类名)]；不匹配的整面归 fallback。
SEGMENTS = {
    "pine": ([(0.20, 0.60, 0.08, "foliage")], "wood"),
    "pavilion": ([(0.20, 0.60, 0.08, "tile"), (0.02, 0.14, 0.12, "wood")], "stone"),
    "rock": ([], "stone"),          # 单段整体青灰
    "mountain": ([], "stone"),      # 单段整体青灰（远景剪影）
    "gate": ([], "stone"),          # 单段整体青灰石牌坊
    "lantern": ([], "stone"),       # 单段整体青灰
    "bamboo": ([], "foliage"),      # 单段整体深松绿（竿叶同调）
}


def _clear() -> None:
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for block in (bpy.data.meshes, bpy.data.materials, bpy.data.images):
        for item in list(block):
            if item.users == 0:
                block.remove(item)


def _meshes():
    return [o for o in bpy.data.objects if o.type == "MESH"]


def _world_bbox() -> tuple:
    xs, ys, zs = [], [], []
    for obj in _meshes():
        for corner in obj.bound_box:
            world = obj.matrix_world @ Vector(corner)
            xs.append(world.x)
            ys.append(world.y)
            zs.append(world.z)
    return (min(xs), max(xs), min(ys), max(ys), min(zs), max(zs))


def _normalize(name: str) -> None:
    x0, x1, y0, y1, z0, z1 = _world_bbox()
    scale = TARGETS[name]["height"] / max(z1 - z0, 1e-6)
    roots = [o for o in bpy.data.objects if o.parent is None]
    for obj in roots:
        obj.scale = tuple(s * scale for s in obj.scale)
    bpy.context.view_layer.update()
    x0, x1, y0, y1, z0, z1 = _world_bbox()
    dx, dy, dz = -(x0 + x1) / 2, -(y0 + y1) / 2, -z0
    for obj in roots:
        obj.location.x += dx
        obj.location.y += dy
        obj.location.z += dz
    bpy.context.view_layer.update()


def _tri_count() -> int:
    return sum(
        sum(len(p.vertices) - 2 for p in obj.data.polygons)
        for obj in _meshes()
    )


def _decimate_if_needed(name: str) -> None:
    total = _tri_count()
    budget = TARGETS[name]["max_tris"]
    if total <= budget:
        return
    ratio = max(budget / total, 0.05)
    for obj in _meshes():
        mod = obj.modifiers.new("Decimate", "DECIMATE")
        mod.ratio = ratio
    bpy.ops.object.select_all(action="DESELECT")
    for obj in _meshes():
        obj.select_set(True)
    for obj in _meshes():
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier="Decimate")


def _first_image() -> bpy.types.Image:
    for image in bpy.data.images:
        if image.users > 0 and image.size[0] > 0:
            return image
    raise RuntimeError("no imported image found")


def _sample_array(image: bpy.types.Image) -> np.ndarray:
    w, h = image.size
    pixels = np.empty(w * h * 4, dtype=np.float32)
    image.pixels.foreach_get(pixels)
    return pixels.reshape(h, w, 4)


def _classify_uv(uv, arr, w, h, rules, fallback) -> str:
    x = min(w - 1, max(0, int(uv[0] * (w - 1))))
    y = min(h - 1, max(0, int(uv[1] * (h - 1))))
    hh, ss, vv = colorsys.rgb_to_hsv(arr[y, x, 0], arr[y, x, 1], arr[y, x, 2])
    if ss < 0.10 or vv < 0.05:
        return fallback
    for h0, h1, s_min, cls in rules:
        if h0 <= hh <= h1 and ss >= s_min:
            return cls
    return fallback


def _bake_tinted_image(image: bpy.types.Image, tint, cls: str) -> bpy.types.Image:
    """把调色系数烘进 1024 的贴图副本（原 atlas 保留在 hunyuan_raw 不动）。

    glTF 导出器不导出 MixRGB 乘法节点（baseColorFactor 会丢），因此调色必须烘进像素。
    """
    w, h = image.size
    arr = _sample_array(image)
    rgb = np.clip(arr[..., :3] * np.array(tint[:3], dtype=np.float32), 0.0, 1.0)
    out = np.concatenate([rgb, arr[..., 3:4]], axis=-1).astype(np.float32)
    # 盒式降采样到 1024（stylized 资产足够；降低运行时体积）。
    stride = max(1, w // 1024)
    if stride > 1:
        out = out[::stride, ::stride]
    new_image = bpy.data.images.new(f"Jade_{cls.capitalize()}_tex",
                                    width=out.shape[1], height=out.shape[0], alpha=True)
    new_image.pixels.foreach_set(out.ravel())
    return new_image


def _palette_material(cls: str, image, avg, tint_cap=8.0) -> bpy.types.Material:
    """调色烘进贴图后直连 Base Color 的 Principled 材质；系数 = 色卡 / 段均色（逐通道截断）。"""
    mat = bpy.data.materials.new(f"Jade_{cls.capitalize()}")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    bsdf.inputs["Roughness"].default_value = 0.85
    target = PALETTE[cls]
    tint = tuple(min(target[i] / max(avg[i], 1e-4), tint_cap) for i in range(3)) + (1.0,)
    baked = _bake_tinted_image(image, tint, cls)
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = baked
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    return mat


def _recolor(name: str) -> None:
    rules, fallback = SEGMENTS[name]
    image = _first_image()
    w, h = image.size
    arr = _sample_array(image)
    mesh_objs = _meshes()

    if not rules:
        # 单段整体调色（岩石）：均值按 UV 覆盖的纹元采样，避免烘焙贴图黑底拉偏。
        samples = []
        for obj in mesh_objs:
            layer = obj.data.uv_layers.active
            if layer is None:
                raise RuntimeError(f"{name}: {obj.name} 缺少 UV")
            for poly in obj.data.polygons:
                for li in poly.loop_indices:
                    uv = layer.data[li].uv
                    x = min(w - 1, max(0, int(uv[0] * (w - 1))))
                    y = min(h - 1, max(0, int(uv[1] * (h - 1))))
                    samples.append(arr[y, x, :3])
        if not samples:
            raise RuntimeError(f"{name}: UV 采样为空")
        avg = tuple(float(np.mean(samples, axis=0)[i]) for i in range(3))
        mat = _palette_material(fallback, image, avg)
        for obj in mesh_objs:
            obj.data.materials.clear()
            obj.data.materials.append(mat)
        return

    uv_of = {}
    for obj in mesh_objs:
        layer = obj.data.uv_layers.active
        if layer is None:
            raise RuntimeError(f"{name}: {obj.name} 缺少 UV，无法按贴图分段")
        uv_of[obj.name] = layer

    # 逐面多数票分类。
    buckets = {cls: [] for cls in PALETTE}
    for obj in mesh_objs:
        layer = uv_of[obj.name]
        for poly in obj.data.polygons:
            votes = {}
            for li in poly.loop_indices:
                uv = layer.data[li].uv
                cls = _classify_uv((uv[0], uv[1]), arr, w, h, rules, fallback)
                votes[cls] = votes.get(cls, 0) + 1
            cls = max(votes, key=votes.get)
            buckets[cls].append((obj.name, poly.index))

    # 段均色（每类最多 400 面抽样）。
    seg_avg = {}
    for cls, entries in buckets.items():
        samples = []
        for obj_name, fidx in entries[:400]:
            obj = bpy.data.objects[obj_name]
            layer = uv_of[obj_name]
            for li in obj.data.polygons[fidx].loop_indices:
                uv = layer.data[li].uv
                x = min(w - 1, max(0, int(uv[0] * (w - 1))))
                y = min(h - 1, max(0, int(uv[1] * (h - 1))))
                samples.append(arr[y, x, :3])
        if samples:
            seg_avg[cls] = tuple(float(np.mean(samples, axis=0)[i]) for i in range(3))

    # 建材质；对象面 → material_index。
    cls_list = [cls for cls in PALETTE if cls in seg_avg]
    mats = {cls: _palette_material(cls, image, seg_avg[cls]) for cls in cls_list}
    for obj in mesh_objs:
        mesh = obj.data
        mesh.materials.clear()
        for cls in cls_list:
            mesh.materials.append(mats[cls])
        # 该对象的面分类索引
        face_cls = {}
        for cls in cls_list:
            for obj_name, fidx in buckets[cls]:
                if obj_name == obj.name:
                    face_cls[fidx] = cls
        for poly in mesh.polygons:
            cls = face_cls.get(poly.index)
            poly.material_index = cls_list.index(cls) if cls in cls_list else 0


def process(name: str) -> None:
    _clear()
    bpy.ops.import_scene.gltf(filepath=f"{RAW_DIR}/{name}_raw.glb")
    _normalize(name)
    _decimate_if_needed(name)
    _recolor(name)
    blend = f"{SRC_DIR}/jade_{name}.blend"
    glb = f"{OUT_DIR}/jade_{name}.glb"
    bpy.ops.wm.save_as_mainfile(filepath=blend)
    bpy.ops.export_scene.gltf(filepath=glb, export_yup=True, export_apply=True)
    x0, x1, y0, y1, z0, z1 = _world_bbox()
    print("JADE_%s_OK tris=%d height=%.2f base_z=%.3f" % (name.upper(), _tri_count(), z1 - z0, z0))


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    for name in argv:
        process(name)
