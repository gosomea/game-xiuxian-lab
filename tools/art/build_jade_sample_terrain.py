# 青玉纸白样板地形：台基 + 台阶 + 铺装 + 收边。
# 运行方式 A（后台批处理）：
#   blender --background --factory-startup --python tools/art/build_jade_sample_terrain.py -- build export
# 运行方式 B（Blender MCP / GUI 会话内，cwd=仓库根）：
#   exec(compile(open("<abs>/tools/art/build_jade_sample_terrain.py").read(), "terrain", "exec"))
#
# 契约：
# - 正面朝 Blender +Y；export_yup 把 (x,y,z) 映射为 glTF (x,z,-y)，正面即 Godot -Z…注意：
#   +Y 映射后是 glTF **-Z 的反方向**，即 Godot +Z。本场景台阶在 Godot +Z 侧（面向出生点），
#   因此建模时台阶朝 Blender +Y 是**刻意**的：映射后台阶落在 Godot +Z。
# - 装饰面高出承载面 >= 0.02 m（coplanar-surface-shimmer）。
# - 色卡为线性值直接写 Principled base color（GLB baseColorFactor 线性约定）。
# - 另存不覆盖：.blend 与 GLB 均为 jade_sample_terrain 新名。

import bmesh
import bpy
import os
import sys

def _srgb_to_linear(c: float) -> float:
    """Godot 导入器把 glTF baseColorFactor 做 linear→sRGB 转换后写入 albedo（实测 0.434→0.690），
    因此要落到目标 albedo，必须导出 srgb_to_linear(目标)。"""
    if c <= 0.04045:
        return c / 12.92
    return ((c + 0.055) / 1.055) ** 2.4

# --- 色卡：先写 Godot albedo 语义的目标值（显示口径），导出前逐通道转线性 ---------
TARGETS_DISPLAY = {
    "cap": (0.50, 0.46, 0.38),   # 台基压顶 灰米（比铺装深一档）
    "body": (0.42, 0.38, 0.31),  # 台基/台阶立面 灰米暗部
    "tile": (0.58, 0.53, 0.44),  # 铺装 灰米
    "edge": (0.46, 0.42, 0.34),  # 收边 比铺装深
    "step": (0.54, 0.49, 0.41),  # 踏面略亮于立面
}
COL_CAP = tuple(_srgb_to_linear(c) for c in TARGETS_DISPLAY["cap"]) + (1.0,)
COL_BODY = tuple(_srgb_to_linear(c) for c in TARGETS_DISPLAY["body"]) + (1.0,)
COL_TILE = tuple(_srgb_to_linear(c) for c in TARGETS_DISPLAY["tile"]) + (1.0,)
COL_EDGE = tuple(_srgb_to_linear(c) for c in TARGETS_DISPLAY["edge"]) + (1.0,)
COL_STEP_TOP = tuple(_srgb_to_linear(c) for c in TARGETS_DISPLAY["step"]) + (1.0,)

ROUGH_BASE = 0.85

PLAZA_HALF = 8.0    # 铺装区半宽（米）
PLATFORM_H = 0.60   # 台基总高
PLATFORM_HALF = 3.2  # 台基半宽
CAP_T = 0.02        # 压顶厚（装饰面 +0.02）
STEP_W = 2.4        # 台阶总宽
STEP_D = 0.45       # 单级进深


def _clear_default_scene() -> None:
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for block in (bpy.data.meshes, bpy.data.materials):
        for item in list(block):
            if item.users == 0:
                block.remove(item)


def _mat(name: str, color, roughness: float = ROUGH_BASE) -> bpy.types.Material:
    mat = bpy.data.materials.get(name)
    if mat is None:
        mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Roughness"].default_value = roughness
    if "Specular IOR Level" in bsdf.inputs:
        bsdf.inputs["Specular IOR Level"].default_value = 0.2
    return mat


def _box(name: str, size, loc, mat) -> bpy.types.Object:
    mesh = bpy.data.meshes.new(name)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bm.to_mesh(mesh)
    bm.free()
    obj.scale = (size[0], size[1], size[2])
    obj.location = loc
    obj.data.materials.append(mat)
    return obj


def _paving(tiles, mat) -> bpy.types.Object:
    """铺装：每砖一个 bmesh 立方体（1.9×1.9×0.02，中心 z=0.01），合并为单网格，缝 0.1 m。

    刻意走与 _box 相同的 bmesh.ops.create_cube 路径：from_pydata 手排顶点在本轮已实测
    产生蝴蝶结面（X 形三角花砖），不再手排。
    """
    from mathutils import Matrix

    tile = 1.9
    bm = bmesh.new()
    for x, y in tiles:
        matrix = Matrix.Translation((x, y, 0.01)) @ Matrix.Diagonal((tile, tile, 0.02, 1.0))
        bmesh.ops.create_cube(bm, size=1.0, matrix=matrix)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new("Paving")
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()
    mesh.materials.append(mat)
    obj = bpy.data.objects.new("Paving", mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def build() -> None:
    _clear_default_scene()
    m_cap = _mat("Jade_CapStone", COL_CAP)
    m_body = _mat("Jade_StoneBody", COL_BODY)
    m_tile = _mat("Jade_Paving", COL_TILE)
    m_edge = _mat("Jade_Edge", COL_EDGE)
    m_step = _mat("Jade_StepTop", COL_STEP_TOP)

    # 台基：主体到 0.58，压顶 0.02 盖到 0.60（装饰面高出承载面 0.02，外扩 2cm 读出边带）。
    body_top = PLATFORM_H - CAP_T
    _box("Platform_Body", (PLATFORM_HALF * 2, PLATFORM_HALF * 2, body_top),
         (0, 0, body_top / 2), m_body)
    _box("Platform_Cap", (PLATFORM_HALF * 2 + 0.04, PLATFORM_HALF * 2 + 0.04, CAP_T),
         (0, 0, PLATFORM_H - CAP_T / 2), m_cap)

    # 台阶朝 Blender +Y（映射后 Godot +Z，面向出生点）：两级踏步 + 压顶即第三级（0.2/0.4/0.6）。
    # 踏面条略外扩 0.02 并抬高 0.02，读出踏面。
    y1 = PLATFORM_HALF + STEP_D / 2
    y2 = PLATFORM_HALF + STEP_D * 1.5
    _box("Step_1", (STEP_W, STEP_D, 0.2), (0, y1, 0.1), m_body)
    _box("Step_1_Tread", (STEP_W + 0.04, 0.08, 0.02), (0, y1 + STEP_D / 2 - 0.04, 0.21), m_step)
    _box("Step_2", (STEP_W, STEP_D, 0.4), (0, y2, 0.2), m_body)
    _box("Step_2_Tread", (STEP_W + 0.04, 0.08, 0.02), (0, y2 + STEP_D / 2 - 0.04, 0.41), m_step)

    # 铺装：1.9 m 方砖 + 0.1 缝（露出 Godot 地面暗底），避开台基与台阶占地。
    tile = 1.9
    gap = 0.1
    pitch = tile + gap
    n = int(PLAZA_HALF * 2 / pitch)
    keep_y_min = -PLATFORM_HALF - STEP_D * 2 - 0.25
    tiles = []
    for ix in range(n):
        for iy in range(n):
            x = -PLAZA_HALF + tile / 2 + ix * pitch
            y = -PLAZA_HALF + tile / 2 + iy * pitch
            if abs(x) < PLATFORM_HALF + 0.25 and keep_y_min < y < PLATFORM_HALF + 0.25:
                continue
            tiles.append((x, y))
    _paving(tiles, m_tile)

    # 收边：铺装外圈一圈边石，顶面 0.03（高于砖面 0.01，读出收边）。
    edge_t = 0.03
    edge_w = 0.35
    per = PLAZA_HALF + edge_w / 2
    _box("Edge_North", (PLAZA_HALF * 2 + edge_w * 2, edge_w, edge_t), (0, per, edge_t / 2), m_edge)
    _box("Edge_South", (PLAZA_HALF * 2 + edge_w * 2, edge_w, edge_t), (0, -per, edge_t / 2), m_edge)
    _box("Edge_East", (edge_w, PLAZA_HALF * 2, edge_t), (per, 0, edge_t / 2), m_edge)
    _box("Edge_West", (edge_w, PLAZA_HALF * 2, edge_t), (-per, 0, edge_t / 2), m_edge)


def export(blend_path: str, glb_path: str) -> None:
    os.makedirs(os.path.dirname(blend_path), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=blend_path)
    bpy.ops.export_scene.gltf(filepath=glb_path, export_yup=True, export_apply=True)


def main() -> None:
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else ["build", "export"]
    root = "/Users/yuqixian/forever-skills/projects/games/game-xiuxian-lab"
    blend = os.path.join(root, "docs/art/jade_paper_sample/jade_sample_terrain.blend")
    glb = os.path.join(root, "src/levels/experiments/character_movement/jade_sample_terrain.glb")
    if "build" in argv:
        build()
    if "export" in argv:
        export(blend, glb)
    print("JADE_TERRAIN_OK objects=%d" % len(bpy.data.objects))


main()
