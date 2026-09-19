# 混元人物 → 命名分件切割（角色表现层契约适配）。
# blender --background --factory-startup --python tools/art/process_cultivator_jade.py -- cut export
#
# 契约（cultivator_presentation.gd 刚体分件）：
#   摆动件（枢轴 = 组内 AABB 顶面中心）：
#     Leg_L/R + Foot_L/R（髋枢轴）、Arm_Sleeve_L/R + Cuff_L/R + Hand_L/R（肩枢轴）、
#     Robe_Skirt + Robe_HemBand + Robe_Panel（腰枢轴）
#   静件：Robe_Upper（躯干+肩垫/腰带遮缝）、Head（头/发/脸一体，不参与摆动）
# 藏缝策略：腰缝被静部金腰带盖住；肩缝被静部肩垫盖住；髋缝藏于裙壳内；
#   踝/肘/腕缝与宿主同枢轴，永不张开。
# 切割 = 连续网格按高度带横切 + 左右竖切 + 裙前窄条竖切；碎片按「高度带 + 中心 x + 跨度」归类。
#
# 高度带以 HEIGHT 比例给出，须按 character_raw 预览实测微调（脚本只承诺结构，不承诺一次命中）。

import bmesh
import bpy
import math
import os
import sys

from mathutils import Matrix, Vector

ROOT = "/Users/yuqixian/forever-skills/projects/games/game-xiuxian-lab"
RAW = f"{ROOT}/docs/art/jade_paper_sample/hunyuan_raw/character_raw.glb"
SRC_DIR = f"{ROOT}/docs/art/cultivator_jade"
OUT = f"{ROOT}/src/game/actors/swordsman/models/cultivator_jade.glb"

HEIGHT = 1.75
# 高度带（占身高比例）：
F_ANKLE = 0.035   # 实测：0.06 高于靴筒顶切不开，脚与腿连体导致 Foot_L/R 缺失
F_HEM = 0.15       # 摆缘带下沿
F_HIP = 0.46       # 髋（裙内）
F_WRIST = 0.50
F_WAIST = 0.56
F_ELBOW = 0.63
F_SHOULDER = 0.80
F_NECK = 0.82
# 横向阈值（绝对米）：
TORSO_HALF_W = 0.19      # |cx| 小于此 = 躯干
LIMB_HALF_W = 0.115      # |cx| 大于此 = 手臂
LEG_MAX_SPAN = 0.17      # 腿碎片 x 跨度上限（裙壳更宽）
HEM_BAND = 0.05          # 摆缘带厚
PANEL_HALF_W = 0.055     # 裙前襟窄条半宽
SASH_R = 0.150
SASH_T = 0.05
CAP_R = 0.072

FRONT_IS_NEG_Z = False  # 实测：混元人物面朝 Blender -Y，与 v1 同约定，导出前转 180°


def _clear() -> None:
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for block in (bpy.data.meshes, bpy.data.materials):
        for item in list(block):
            if item.users == 0:
                block.remove(item)


def _meshes():
    return [o for o in bpy.data.objects if o.type == "MESH"]


def _import_and_normalize() -> None:
    bpy.ops.import_scene.gltf(filepath=RAW)
    meshes = _meshes()
    xs, ys, zs = [], [], []
    for obj in meshes:
        for corner in obj.bound_box:
            w = obj.matrix_world @ Vector(corner)
            xs.append(w.x)
            ys.append(w.y)
            zs.append(w.z)
    scale = HEIGHT / max(max(zs) - min(zs), 1e-6)
    roots = [o for o in bpy.data.objects if o.parent is None]
    for obj in roots:
        obj.scale = tuple(s * scale for s in obj.scale)
    bpy.context.view_layer.update()
    xs, ys, zs = [], [], []
    for obj in meshes:
        for corner in obj.bound_box:
            w = obj.matrix_world @ Vector(corner)
            xs.append(w.x)
            ys.append(w.y)
            zs.append(w.z)
    dx, dy, dz = -(min(xs) + max(xs)) / 2, -(min(ys) + max(ys)) / 2, -min(zs)
    for obj in roots:
        obj.location.x += dx
        obj.location.y += dy
        obj.location.z += dz
    bpy.context.view_layer.update()
    if not FRONT_IS_NEG_Z:
        for obj in roots:
            obj.rotation_euler.z += math.pi
        bpy.context.view_layer.update()


def _bisect_all(plane_co: Vector, plane_no: Vector) -> None:
    """只切包围盒真正跨越切面的碎片（否则碎片数按 2^切割数 爆炸、编辑模式往返超时）；
    切后按连通块拆分成独立对象（bisect 本身不分离）。"""
    axis = 0 if abs(plane_no.x) > 0.5 else 2
    value = plane_co[axis]
    for obj in list(_meshes()):
        xs = [(obj.matrix_world @ Vector(c)).x for c in obj.bound_box]
        zs = [(obj.matrix_world @ Vector(c)).z for c in obj.bound_box]
        lo, hi = (min(xs), max(xs)) if axis == 0 else (min(zs), max(zs))
        if hi < value - 1e-4 or lo > value + 1e-4:
            continue
        bpy.context.view_layer.objects.active = obj
        obj.select_set(True)
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.mesh.bisect(plane_co=plane_co, plane_no=plane_no, use_fill=True,
                            clear_inner=False, clear_outer=False)
        bpy.ops.mesh.separate(type="LOOSE")
        bpy.ops.object.mode_set(mode="OBJECT")


def _frag_stats(obj):
    xs = [(obj.matrix_world @ Vector(c)).x for c in obj.bound_box]
    zs = [(obj.matrix_world @ Vector(c)).z for c in obj.bound_box]
    return (min(xs) + max(xs)) / 2, max(xs) - min(xs), (min(zs) + max(zs)) / 2, min(zs), max(zs)


def _side(cx: float) -> str:
    return "R" if cx > 0 else "L"


def classify() -> None:
    """碎片按「最低点 z0 + 跨度 + 中心 x」归类——切割线本身就是区界。

    每个碎片是切割后的一块连通面，其 z0 必然贴着某条切线：脚≈0、腿=踝切(0.061)、
    摆缘=摆切(0.26/0.31)、下裙=髋切(0.805) 之下但 z0=切线下沿…腕/肘/手按肩带切线分带；
    躯干碎片 |cx| < 0.2（含头/发，整件静）。相比区域盒（首轮实测裙/腿同域歧义），
    切线锚定无重叠歧义。
    """
    H = HEIGHT
    ankle = F_ANKLE * H          # 0.061
    hem_lo = (F_HEM + 0.05) * H  # 摆缘带上切 0.35
    waist = F_WAIST * H          # 0.98
    elbow = F_ELBOW * H          # 1.1025
    wrist = F_WRIST * H          # 0.875

    for obj in _meshes():
        xs = [(obj.matrix_world @ Vector(c)).x for c in obj.bound_box]
        zs = [(obj.matrix_world @ Vector(c)).z for c in obj.bound_box]
        cx = (min(xs) + max(xs)) / 2
        span = max(xs) - min(xs)
        z0, z1 = min(zs), max(zs)
        zmid = (z0 + z1) / 2
        side = "R" if cx > 0 else "L"

        if z0 >= waist - 0.03 and abs(cx) < TORSO_HALF_W:
            name = "Robe_Upper"                      # 躯干+头（腰切以上、中轴窄条静）
        elif z0 < 0.03 and span < 0.20 and z1 < 0.14:
            name = "Foot_" + side                    # 踝切以下
        elif z0 < ankle + 0.05 and span < 0.20 and z1 < F_HIP * H + 0.10:
            name = "Leg_" + side                     # 踝切～髋切之间窄条
        elif 0.18 <= z0 <= 0.34 and z1 <= 0.40 and span >= 0.20:
            name = "Robe_HemBand"                    # 摆缘双切带（z0 在下切线）
        elif abs(cx) < PANEL_HALF_W + 0.01 and z0 >= 0.12 and z1 <= waist + 0.02:
            name = "Robe_Panel"                      # 裙前襟窄条
        elif z0 >= 0.15 and z1 <= waist + 0.03:
            name = "Robe_Skirt"                      # 腰切以下裙壳（含上下段）
        elif z0 >= elbow - 0.04 and abs(cx) >= TORSO_HALF_W:
            name = "Arm_Sleeve_" + side              # 肘切～肩切
        elif z0 >= wrist - 0.04 and abs(cx) >= TORSO_HALF_W:
            name = "Cuff_" + side                    # 腕切～肘切
        elif abs(cx) >= TORSO_HALF_W:
            name = "Hand_" + side                    # 腕切以下
        elif zmid <= waist:
            name = "Robe_Skirt"
        else:
            name = "Robe_Upper"
        obj.name = name
        obj.data.name = name + "_mesh"


def join_named() -> None:
    """按去偶基名合并（classify 里 Blender 会把重名自动加 .001 后缀，直接按 name 分组每组只剩 1 个）。"""
    import re
    by_base = {}
    for obj in _meshes():
        base = re.sub(r"\.\d{3}$", "", obj.name)
        by_base.setdefault(base, []).append(obj)
    for base, objs in by_base.items():
        if len(objs) == 1:
            continue
        bpy.ops.object.select_all(action="DESELECT")
        for obj in objs:
            obj.select_set(True)
        bpy.context.view_layer.objects.active = objs[0]
        bpy.ops.object.join()
        objs[0].name = base
        objs[0].data.name = base + "_mesh"


def cleanup_and_caps() -> None:
    # 补洞 + 去重边（上轮实测：填切缝环，不封袍前开）+ 薄壳加厚（摆动件与躯干，防切缝穿帮）。
    for obj in _meshes():
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.mesh.remove_doubles(threshold=0.0008)
        bpy.ops.mesh.fill_holes(sides=0)
        bpy.ops.mesh.normals_make_consistent(inside=False)
        bpy.ops.object.mode_set(mode="OBJECT")
    for obj in _meshes():
        if obj.name in ("Robe_Skirt", "Robe_HemBand", "Robe_Panel",
                        "Arm_Sleeve_L", "Arm_Sleeve_R", "Robe_Upper"):
            mod = obj.modifiers.new("Solidify", "SOLIDIFY")
            mod.thickness = 0.008

    # 摆缘带改深靛平涂：切面填充的 UV 拉伸白边被读成"深色下摆缘"（v1 同款设计）。
    hem_dark = bpy.data.materials.new("Jade_HemDark")
    hem_dark.use_nodes = True
    hem_dark.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.050, 0.092, 0.160, 1.0)
    for obj in _meshes():
        if obj.name == "Robe_HemBand":
            obj.data.materials.clear()
            obj.data.materials.append(hem_dark)

    # 肩垫（静件，遮肩缝）：取烘焙袍色采样 (0.058, 0.144, 0.356)，贴肩线缩小藏入。
    # 注意：不再生成腰封环——烘焙贴图自带腰带且跨腰缝，加环反而突兀（首轮实测）。
    cap_color = (0.058, 0.144, 0.356, 1.0)
    cap_mat = bpy.data.materials.new("Jade_RobeCap")
    cap_mat.use_nodes = True
    cap_mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = cap_color
    for side, sx in (("L", -1.0), ("R", 1.0)):
        mesh = bpy.data.meshes.new("Shoulder_Cap_" + side)
        cap_obj = bpy.data.objects.new("Shoulder_Cap_" + side, mesh)
        bpy.context.collection.objects.link(cap_obj)
        bm = bmesh.new()
        bmesh.ops.create_uvsphere(
            bm, u_segments=14, v_segments=7, radius=0.055,
            matrix=Matrix.Translation((sx * 0.148, 0.0, F_SHOULDER * HEIGHT - 0.045))
            @ Matrix.Diagonal((1.25, 0.85, 0.6, 1.0)))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(mesh)
        bm.free()
        mesh.materials.append(cap_mat)


def normalize_origins() -> None:
    """每对象世界原点归零（几何烘进网格），与 v1 约定一致，枢轴不偏移。"""
    for obj in _meshes():
        world = obj.matrix_world.copy()
        obj.data.transform(world)
        obj.matrix_world = Matrix.Identity(4)


def run_cuts() -> None:
    H = HEIGHT
    _clear()
    _import_and_normalize()
    print("CUT imported", flush=True)
    _bisect_all(Vector((0, 0, F_SHOULDER * H)), Vector((0, 0, 1)))
    _bisect_all(Vector((0, 0, F_ELBOW * H)), Vector((0, 0, 1)))
    _bisect_all(Vector((0, 0, F_WRIST * H)), Vector((0, 0, 1)))
    _bisect_all(Vector((0, 0, F_WAIST * H)), Vector((0, 0, 1)))
    _bisect_all(Vector((0, 0, F_HIP * H)), Vector((0, 0, 1)))
    _bisect_all(Vector((0, 0, (F_HEM + 0.05) * H)), Vector((0, 0, 1)))
    _bisect_all(Vector((0, 0, F_HEM * H)), Vector((0, 0, 1)))
    _bisect_all(Vector((0, 0, F_ANKLE * H)), Vector((0, 0, 1)))
    print("CUT z-bands done", len(_meshes()), flush=True)
    _bisect_all(Vector((0, 0, 0)), Vector((1, 0, 0)))                       # 左右
    _bisect_all(Vector((-PANEL_HALF_W, 0, 0)), Vector((1, 0, 0)))           # 裙前襟窄条
    _bisect_all(Vector((PANEL_HALF_W, 0, 0)), Vector((1, 0, 0)))
    print("CUT x-splits done", len(_meshes()), flush=True)
    classify()
    print("CUT classified", flush=True)
    join_named()
    print("CUT joined", flush=True)
    cleanup_and_caps()
    print("CUT caps done", flush=True)
    normalize_origins()


def export() -> None:
    os.makedirs(SRC_DIR, exist_ok=True)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=f"{SRC_DIR}/cultivator_jade.blend")
    bpy.ops.export_scene.gltf(filepath=OUT, export_yup=True, export_apply=True)


def main() -> None:
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else ["cut", "export"]
    if "cut" in argv:
        run_cuts()
    if "export" in argv:
        export()
    names = sorted(o.name for o in bpy.data.objects if o.type == "MESH")
    print("CULTIVATOR_JADE_OK parts=%s" % names)


if __name__ == "__main__":
    main()
