"""御剑飞行训练场「云路玉环」资产生成器（全部程序原创几何，无外部素材）。

运行（仓库根）：
  /Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup \
      --python tools/art/generate_sword_flight_course.py -- course
      -> src/levels/experiments/character_movement/sword_flight_course.glb
      -> src/levels/experiments/character_movement/sword_flight_course_collision.json
      -> docs/art/sword_flight_course/sword_flight_course.blend
  ... -- preview            （只渲染预览，不导出 GLB）
  ... -- all                （导出 + 预览）

职责边界（依据 notes/implemented/gameplay/2026-09-18-character-movement-subexperiments.md）：
  - 只服务御剑飞行训练场：浮空玉环门、云阶、落剑台、悬浮石、远山剪影、指示光柱。
  - 不呈现角色、不做完整地图、不做群山审美重建；远山只作剪影背景。
  - 碰撞/trigger 由 Godot 场景精确装配；本文件导出可碰撞实体的 center/size 到
    sword_flight_course_collision.json（schema sword_flight_course_collision/1），
    保证视觉与碰撞对齐（同一份数值既建几何又写 JSON）。

坐标：GLB 按 Godot 世界坐标一次导出（Y 上、北 = -Z），场景在原点实例化即可；
Blender 为 Z 上，全部顶点经 to_blender() 换算。
GLB 只含网格：预览相机/灯光在导出后加入 .blend，不进 GLB。
"""
from __future__ import annotations

import json
import math
import random
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCENE_DIR = ROOT / "src" / "levels" / "experiments" / "character_movement"
OUT_GLB = SCENE_DIR / "sword_flight_course.glb"
OUT_COLLISION = SCENE_DIR / "sword_flight_course_collision.json"
ART_DIR = ROOT / "docs" / "art" / "sword_flight_course"
COLLISION_SCHEMA = "sword_flight_course_collision/1"

SEED = 20260918

# --------------------------------------------- 装饰层净空（共面闪烁修复，2026-09-18）
# 根因：平台主体与 rim / lip / mark 零间隙共面（装饰层中心 = 承托面顶 + 自身半高，
# 使底面严格等于承托面顶面），双面材质 + 正交相机移动时同深度面竞争导致闪烁。
# 依据 notes/implemented/art/2026-09-18-coplanar-surface-shimmer.md 与 mountain_realm 台账
# 「装饰面高出承载面 2 cm」的既有约定。
## A 类（水平装饰层）底面高于承托面的设计间隙。
CLEARANCE = 0.02
## 竖直构件（B 类，旗杆）底面埋入承托面的深度；沿用地形接触训练场的 5 mm 埋入量。
BURY_DEPTH = 0.005
## 装饰件厚度：建几何与自检共用同一常量，禁止两处各写一份。
MARK_THICKNESS = 0.06
LIP_HEIGHT = 0.12
RIM_HEIGHT = 0.16

## 净空契约：style -> (最小间隙, 最大间隙)，单位米。与生成时的取值分开声明——
## 自检用契约判定，而不是重算一遍生成时的加法（否则断言只是同义反复）。
STYLE_CONTRACT = {
    "accent_on_structure": (CLEARANCE, 0.12),
    "buried_member": (-0.02, -0.002),
}

## 已登记净空对：Blender 自检与导出后 GLB 复核共用同一张表（纯数据，不依赖 bpy）。
## 承托面高度一律取承托件的实际水平面最高值，不在表里再写一遍数值。
CLEARANCE_PAIRS = [
    ("takeoff_mark", "takeoff_pad", "accent_on_structure"),
    ("takeoff_mark_cross", "takeoff_pad", "accent_on_structure"),
    ("step_low_lip", "step_low", "accent_on_structure"),
    ("step_mid_lip", "step_mid", "accent_on_structure"),
    ("step_high_lip", "step_high", "accent_on_structure"),
    ("landing_near_rim", "landing_near", "accent_on_structure"),
    ("landing_near_mark", "landing_near_rim", "accent_on_structure"),
    ("landing_near_pole", "landing_near", "buried_member"),
    ("landing_far_rim", "landing_far", "accent_on_structure"),
    ("landing_far_mark", "landing_far_rim", "accent_on_structure"),
    ("landing_far_pole", "landing_far", "buried_member"),
]

## 共面扫描阈值（与 note 口径一致）：垂直重合 ≤1.5 mm 且水平重叠 ≥0.05 m² 判为冲突。
COPLANAR_GAP = 0.0015
COPLANAR_AREA = 0.05

# 本文件登记的全部可碰撞实体（Godot 坐标 center/size），供 Godot 侧装配。
COLLIDERS: list[dict] = []
# 只做视觉、不参与碰撞的实体名（报告用，避免"隐形墙"误解）。
VISUAL_ONLY: list[str] = []


def register_collider(name, center, size, kind="platform"):
    """登记一份 Godot 坐标碰撞盒；同时被建几何与写 JSON，保证视觉/碰撞同源。"""
    COLLIDERS.append({
        "name": name,
        "kind": kind,
        "center": [round(float(v), 4) for v in center],
        "size": [round(float(v), 4) for v in size],
    })


def to_blender(point):
    """Godot (Y-up, 北 = -Z) -> Blender (Z-up)；导出 export_yup 后回到同一世界坐标。"""
    gx, gy, gz = point
    return (gx, -gz, gy)


def stable_seed(text):
    """与 mountain_realm 相同的确定性种子：字符码累加，不受 PYTHONHASHSEED 影响。"""
    value = 0
    for ch in text:
        value += ord(ch)
    return 1709 + value


def make_palette():
    """青玉 + 素石 + 云白：与群山宗门同一素材语言，便于画面统一。"""
    import bpy

    def mat(name, color, rough=0.78, metallic=0.0, emission=0.0):
        m = bpy.data.materials.new(name)
        m.diffuse_color = (*color, 1.0)
        m.use_nodes = True
        bs = m.node_tree.nodes["Principled BSDF"]
        bs.inputs["Base Color"].default_value = (*color, 1.0)
        bs.inputs["Roughness"].default_value = rough
        bs.inputs["Metallic"].default_value = metallic
        if emission:
            bs.inputs["Emission Color"].default_value = (*color, 1.0)
            bs.inputs["Emission Strength"].default_value = emission
        return m

    return {
        "jade": mat("Celadon jade ring", (0.10, 0.34, 0.27), 0.42),
        "jade_deep": mat("Deep jade", (0.045, 0.19, 0.155), 0.5),
        "stone": mat("Warm limestone", (0.59, 0.62, 0.51)),
        "stone_dark": mat("Granite mid", (0.215, 0.238, 0.223)),
        "ivory": mat("Ivory paving", (0.78, 0.77, 0.64)),
        "bronze": mat("Aged bronze", (0.51, 0.34, 0.09), 0.42, 0.35),
        "cloud": mat("Cloud white", (0.86, 0.88, 0.90), 0.9),
        "glow": mat("Gate glow", (0.36, 0.86, 0.78), 0.3, 0.0, 2.2),
        "glow_warm": mat("Hover zone glow", (0.95, 0.78, 0.42), 0.3, 0.0, 1.8),
        "far": mat("Far mountain silhouette", (0.42, 0.47, 0.51), 1.0),
        "banner": mat("Course banner", (0.62, 0.15, 0.12), 0.6),
    }


# ---------------------------------------------------------------- 基础构件


def finish(obj, name, material, bevel=0.0):
    import bpy
    obj.name = name
    obj.data.materials.append(material)
    if bevel:
        mod = obj.modifiers.new("Soft crafted edges", "BEVEL")
        mod.width = bevel
        mod.segments = 2
        mod = obj.modifiers.new("Weighted corner normals", "WEIGHTED_NORMAL")
    return obj


def cbox(name, center, size, material, bevel=0.04, rotation_z=0.0, collision=False,
         collider_name=None, kind="platform"):
    """Godot 坐标的盒；size 为 Godot (x, y, z)。collision=True 时同源登记碰撞盒。"""
    import bpy
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=to_blender(center))
    obj = bpy.context.object
    obj.scale = (size[0], size[2], size[1])
    # Godot yaw 与 Blender 绕 Z 同号（to_blender 把 +Y 映到 +Z）。
    obj.rotation_euler = (0.0, 0.0, rotation_z)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    finish(obj, name, material, bevel)
    if collision:
        register_collider(collider_name or name, center, size, kind)
    return obj


def ccyl(name, center, radius, depth, material, verts=16, collision=False,
         collider_name=None, kind="platform", bevel=0.03):
    """竖直圆柱（Godot 轴为 Y）。depth 为 Godot 高度。"""
    import bpy
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=radius, depth=depth,
                                        location=to_blender(center))
    obj = bpy.context.object
    finish(obj, name, material, bevel)
    if collision:
        size = (radius * 2.0, depth, radius * 2.0)
        register_collider(collider_name or name, center, size, kind)
    return obj


def ccone(name, center, r1, r2, depth, material, verts=10, bevel=0.0):
    import bpy
    bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r1, radius2=r2, depth=depth,
                                    location=to_blender(center))
    obj = bpy.context.object
    return finish(obj, name, material, bevel)


def cblob(name, center, size, material, subdivisions=1, seed=0, jitter=0.22):
    """低多边形不规则石：正二十面体按确定性噪声位移顶点。"""
    import bpy
    from mathutils import Vector
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdivisions, radius=1.0,
                                          location=to_blender(center))
    obj = bpy.context.object
    rng = random.Random(seed)
    for vert in obj.data.vertices:
        direction = Vector(vert.co).normalized()
        vert.co += direction * rng.uniform(-jitter, jitter)
    obj.scale = (size[0], size[2], size[1])
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    finish(obj, name, material, 0.0)
    VISUAL_ONLY.append(name)
    return obj


# ---------------------------------------------------------------- 路线构件


def ring_gate(name, center, radius, yaw_degrees, pal, tube=0.17, spokes=4):
    """浮空玉环门：竖直圆环 + 环内发光带 + 4 个青铜系挂件。

    环平面垂直于飞行方向；yaw=0 表示穿越方向朝北（Godot -Z）。
    Blender 旋转推导：euler=(90°, 0, 180°-yaw) 使环轴映射到 Godot (sin yaw, 0, -cos yaw)。
    """
    import bpy
    yaw = math.radians(yaw_degrees)
    bpy.ops.mesh.primitive_torus_add(major_radius=radius, minor_radius=tube,
                                     major_segments=40, minor_segments=10,
                                     location=to_blender(center))
    ring = bpy.context.object
    ring.rotation_euler = (math.pi / 2.0, 0.0, math.pi - yaw)
    finish(ring, name, pal["jade"], 0.0)

    # 环内发光带：略小的细环，纯视觉，帮助在灰亮天空里读出环口。
    bpy.ops.mesh.primitive_torus_add(major_radius=radius - tube * 1.9, minor_radius=tube * 0.42,
                                     major_segments=40, minor_segments=6,
                                     location=to_blender(center))
    glow = bpy.context.object
    glow.rotation_euler = (math.pi / 2.0, 0.0, math.pi - yaw)
    finish(glow, f"{name}_glow", pal["glow"], 0.0)
    VISUAL_ONLY.append(f"{name}_glow")

    # 系挂件：环左右上下的小青铜块，强化"门"的可读朝向。
    right = (math.cos(yaw), 0.0, math.sin(yaw))
    up = (0.0, 1.0, 0.0)
    for index in range(spokes):
        angle = math.pi * 2.0 * index / spokes
        offset = (
            center[0] + right[0] * math.cos(angle) * (radius + tube * 1.6) + up[0] * math.sin(angle) * (radius + tube * 1.6),
            center[1] + math.cos(angle) * 0.0 + math.sin(angle) * (radius + tube * 1.6),
            center[2] + right[2] * math.cos(angle) * (radius + tube * 1.6) + up[2] * math.sin(angle) * (radius + tube * 1.6),
        )
        cbox(f"{name}_lug{index}", offset, (0.34, 0.34, 0.34), pal["bronze"], 0.05)
        VISUAL_ONLY.append(f"{name}_lug{index}")
    return ring


def cloud_step(name, center, size, pal, tilt_degrees=0.0):
    """云阶：一块可站立的浮空石板（有碰撞），边缘略厚。

    压顶（lip）底面 = 台面顶 + CLEARANCE：修复前底面严格等于台面顶面（共面闪烁）。
    """
    cbox(name, center, size, pal["stone"], 0.06, collision=True, kind="step")
    top = center[1] + size[1] * 0.5
    cbox(f"{name}_lip", (center[0], top + CLEARANCE + LIP_HEIGHT * 0.5, center[2]),
         (size[0] * 0.94, LIP_HEIGHT, size[2] * 0.94), pal["ivory"], 0.03)
    VISUAL_ONLY.append(f"{name}_lip")


def landing_platform(name, center, size, pal, height_marker=0.0, banner=True):
    """落剑台：八边台面 + 青铜围边 + 中央标记；可直接落站。

    净空（修复前围边底面、标记底面、旗杆底面全部与承托面零间隙共面）：
      - 围边（rim）底面 = 台面顶 + CLEARANCE；
      - 标记（mark）底面 = 围边顶 + CLEARANCE（修复前 mark 底面与 rim 顶面共面）；
      - 旗杆（pole）底面埋入台面 BURY_DEPTH，属 B 类竖向构件，不抬升。
    """
    radius = min(size[0], size[2]) * 0.5
    ccyl(name, center, radius, size[1], pal["stone"], verts=8, collision=True, kind="landing")
    top_y = center[1] + size[1] * 0.5
    ccyl(f"{name}_rim", (center[0], top_y + CLEARANCE + RIM_HEIGHT * 0.5, center[2]),
         radius * 0.94, RIM_HEIGHT, pal["bronze"], verts=8, bevel=0.03)
    VISUAL_ONLY.append(f"{name}_rim")
    ccyl(f"{name}_mark", (center[0], top_y + CLEARANCE + RIM_HEIGHT + CLEARANCE
                          + MARK_THICKNESS * 0.5, center[2]), radius * 0.3, MARK_THICKNESS,
         pal["glow_warm"] if height_marker else pal["glow"], verts=12, bevel=0.0)
    VISUAL_ONLY.append(f"{name}_mark")
    if banner:
        pole = (center[0] + radius * 0.72, top_y - BURY_DEPTH + 1.1, center[2] + radius * 0.72)
        cbox(f"{name}_pole", pole, (0.12, 2.2, 0.12), pal["bronze"], 0.02)
        cbox(f"{name}_flag", (pole[0], pole[1] + 0.55, pole[2] + 0.36), (0.05, 0.9, 0.72),
             pal["banner"], 0.01)
        VISUAL_ONLY.extend([f"{name}_pole", f"{name}_flag"])


def hover_zone(name, center, pal, radius=3.4):
    """悬停计时区：地面发光盘 + 竖直光柱（视觉），用于悬停判定参考。"""
    ccyl(f"{name}_disc", (center[0], center[1] + 0.05, center[2]), radius, 0.1,
         pal["glow_warm"], verts=24, bevel=0.0)
    ccyl(f"{name}_column", (center[0], center[1] + 3.2, center[2]), radius * 0.16, 6.4,
         pal["glow_warm"], verts=10, bevel=0.0)
    VISUAL_ONLY.extend([f"{name}_disc", f"{name}_column"])


def floating_rock(name, center, size, pal, seed=None):
    """悬浮石：纯视觉（无碰撞），避免在航线中制造隐形障碍。"""
    cblob(name, center, size, pal["stone_dark"], subdivisions=1,
          seed=seed if seed is not None else stable_seed(name))


def far_mountain(name, center, radius, height, pal):
    """远山剪影：纯视觉、无碰撞，只做天际层次。"""
    ccone(name, center, radius, radius * 0.06, height, pal["far"], verts=7)
    VISUAL_ONLY.append(name)



# ---------------------------------------------------------------- 路线定义
# 单一真源：几何、碰撞 JSON、Godot 场景的路线判定全部读这里，保证视觉与判据对齐。
# 坐标 Godot：Y 上、北 = -Z。yaw=0 表示穿越方向朝北(-Z)；forward=(sin yaw,0,-cos yaw)。

TAKEOFF_CENTER = (0.0, 0.0, 11.0)
TAKEOFF_SIZE = (9.0, 1.2, 9.0)

# 玉环门：由低到高、由直到弯，最后一段下坡转向。
GATES = [
    {"id": "gate_1", "title": "初启", "center": (0.0, 5.0, -2.0), "yaw": 0.0, "radius": 2.40},
    {"id": "gate_2", "title": "升云", "center": (6.5, 9.0, -12.0), "yaw": 35.0, "radius": 2.30},
    {"id": "gate_3", "title": "揽月", "center": (16.5, 13.0, -16.5), "yaw": 80.0, "radius": 2.10},
    {"id": "gate_4", "title": "穿隙", "center": (32.0, 11.0, -10.0), "yaw": 130.0, "radius": 1.80},
    {"id": "gate_5", "title": "回风", "center": (34.0, 7.5, 2.0), "yaw": 176.0, "radius": 2.10},
]

# 悬停区放在末门与落点之间的自然航路上，避免为悬停刻意折返。
HOVER_CENTER = (30.0, 8.0, 7.0)
HOVER_RADIUS = 3.4
HOVER_SECONDS = 2.5

# 两个有取舍的落点：近而高（需控下降）与远而稳（低平宽大）。
LANDINGS = [
    {"id": "landing_near", "title": "落剑台·近", "center": (30.0, 3.0, 13.0),
     "size": (6.4, 3.0, 6.4), "top_y": 4.5},
    {"id": "landing_far", "title": "云台·稳", "center": (13.0, 0.4, 14.5),
     "size": (9.0, 0.8, 9.0), "top_y": 0.8},
]

# 云阶：航线外侧的中途可站立点（有碰撞），供失败后重新起步观察。
CLOUD_STEPS = [
    {"name": "step_low", "center": (5.5, 3.0, 3.0), "size": (3.4, 0.5, 3.4)},
    {"name": "step_mid", "center": (18.0, 8.5, -5.0), "size": (3.2, 0.5, 3.2)},
    {"name": "step_high", "center": (28.0, 12.5, -18.5), "size": (3.0, 0.5, 3.0)},
]

# 悬浮石：纯视觉，航线之外，避免在航线中制造隐形障碍。
FLOATING_ROCKS = [
    {"name": "rock_a", "center": (-8.0, 6.0, -6.0), "size": (2.4, 2.0, 2.2)},
    {"name": "rock_b", "center": (10.0, 4.5, -22.0), "size": (2.8, 2.2, 2.6)},
    {"name": "rock_c", "center": (40.0, 15.0, -22.0), "size": (3.4, 2.6, 3.0)},
    {"name": "rock_d", "center": (22.0, 2.0, 16.0), "size": (2.2, 1.8, 2.4)},
    {"name": "rock_e", "center": (-14.0, 12.0, 4.0), "size": (3.0, 2.4, 2.8)},
]

# 远山剪影：天际层次，纯视觉无碰撞。
FAR_MOUNTAINS = [
    {"name": "far_north", "center": (0.0, -2.0, -78.0), "radius": 34.0, "height": 30.0},
    {"name": "far_northeast", "center": (62.0, -2.0, -60.0), "radius": 26.0, "height": 24.0},
    {"name": "far_east", "center": (86.0, -2.0, -6.0), "radius": 30.0, "height": 27.0},
    {"name": "far_west", "center": (-72.0, -2.0, 6.0), "radius": 28.0, "height": 22.0},
]


def ring_axis(yaw_degrees):
    """返回环平面的 (right, up) 单位向量（Godot 坐标）。"""
    yaw = math.radians(yaw_degrees)
    return (math.cos(yaw), 0.0, math.sin(yaw)), (0.0, 1.0, 0.0)


def register_ring_rim(name, center, radius, yaw, segments=16, seg=0.46):
    """把玉环的环体登记成沿圆周排布的小方块碰撞：中心可穿，碰到环体被挡。

    方块按切向排布，间隙 << 角色胶囊直径(0.7 m)，因此不能从环体缝隙钻过。
    """
    right, up = ring_axis(yaw)
    for index in range(segments):
        angle = math.pi * 2.0 * index / segments
        ca, sa = math.cos(angle), math.sin(angle)
        point = (
            center[0] + right[0] * ca * radius + up[0] * sa * radius,
            center[1] + right[1] * ca * radius + up[1] * sa * radius,
            center[2] + right[2] * ca * radius + up[2] * sa * radius,
        )
        register_collider(f"{name}_rim{index:02d}", point, (seg, seg, seg), kind="ring_rim")


def build_course(pal):
    """建整条航线：起飞坪、玉环门、云阶、悬停区、落剑台、悬浮石、远山。"""
    # 起飞坪：方形石台 + 中央剑纹。
    cbox("takeoff_pad", TAKEOFF_CENTER, TAKEOFF_SIZE, pal["stone"], 0.08,
         collision=True, kind="takeoff")
    top = TAKEOFF_CENTER[1] + TAKEOFF_SIZE[1] * 0.5
    cbox("takeoff_mark", (TAKEOFF_CENTER[0], top + CLEARANCE + MARK_THICKNESS * 0.5,
                          TAKEOFF_CENTER[2]),
         (5.2, MARK_THICKNESS, 1.0), pal["glow"], 0.0)
    cbox("takeoff_mark_cross", (TAKEOFF_CENTER[0], top + CLEARANCE + MARK_THICKNESS * 0.5,
                                TAKEOFF_CENTER[2]),
         (1.0, MARK_THICKNESS, 5.2), pal["glow"], 0.0)
    VISUAL_ONLY.extend(["takeoff_mark", "takeoff_mark_cross"])

    # 玉环门：视觉环 + 环体碰撞。
    for gate in GATES:
        ring_gate(gate["id"], gate["center"], gate["radius"], gate["yaw"], pal)
        register_ring_rim(gate["id"], gate["center"], gate["radius"], gate["yaw"])

    # 云阶。
    for step in CLOUD_STEPS:
        cloud_step(step["name"], step["center"], step["size"], pal)

    # 悬停计时区。
    hover_zone("hover_zone", HOVER_CENTER, pal, HOVER_RADIUS)

    # 落剑台。
    for landing in LANDINGS:
        landing_platform(landing["id"], landing["center"], landing["size"], pal,
                         height_marker=1.0 if landing["id"] == "landing_near" else 0.0)

    # 悬浮石与远山（纯视觉）。
    for rock in FLOATING_ROCKS:
        floating_rock(rock["name"], rock["center"], rock["size"], pal)
    for mountain in FAR_MOUNTAINS:
        far_mountain(mountain["name"], mountain["center"], mountain["radius"],
                     mountain["height"], pal)


def build_route_payload():
    """导出给 Godot 的路线数据（与几何同源）。"""
    return {
        "schema": COLLISION_SCHEMA,
        "takeoff": {"center": list(TAKEOFF_CENTER), "size": list(TAKEOFF_SIZE),
                    "top_y": TAKEOFF_CENTER[1] + TAKEOFF_SIZE[1] * 0.5},
        "gates": [
            {"id": g["id"], "title": g["title"], "center": list(g["center"]),
             "yaw": g["yaw"], "radius": g["radius"]}
            for g in GATES
        ],
        "hover": {"center": list(HOVER_CENTER), "radius": HOVER_RADIUS,
                  "seconds": HOVER_SECONDS},
        "landings": [
            {"id": l["id"], "title": l["title"], "center": list(l["center"]),
             "top_y": l["top_y"], "radius": min(l["size"][0], l["size"][2]) * 0.5}
            for l in LANDINGS
        ],
        "cloud_steps": [
            {"name": s["name"], "center": list(s["center"]),
             "top_y": s["center"][1] + s["size"][1] * 0.5}
            for s in CLOUD_STEPS
        ],
        "colliders": COLLIDERS,
        "visual_only": VISUAL_ONLY,
        "bounds": {"min": [-26.0, -1.0, -30.0], "max": [48.0, 26.0, 24.0]},
    }



# ------------------------------------------------- 净空自检与 GLB 静态复核
# 不依赖引擎：Blender 内用对象包围盒自检，导出后用 GLB 顶点 min/max 复核。
# 判定使用 STYLE_CONTRACT 声明的契约区间，不复算生成时的加法（避免同义反复）。


def object_span(obj):
    """Blender 对象世界包围盒 -> ((xmin,ymin,zmin),(xmax,ymax,zmax))，Blender Z 为高度。"""
    from mathutils import Vector
    corners = [obj.matrix_world @ Vector(corner) for corner in obj.bound_box]
    lo = (min(c.x for c in corners), min(c.y for c in corners), min(c.z for c in corners))
    hi = (max(c.x for c in corners), max(c.y for c in corners), max(c.z for c in corners))
    return lo, hi


def clearance_rows(span_lookup, height_axis=2):
    """按 CLEARANCE_PAIRS 计算每对高度间隙（axis=2: Blender Z；axis=1: GLB/Godot Y）。"""
    rows = []
    for child, host, style in CLEARANCE_PAIRS:
        if child not in span_lookup:
            raise RuntimeError(f"净空自检：缺少装饰件对象 {child!r}")
        if host not in span_lookup:
            raise RuntimeError(f"净空自检：缺少承托件对象 {host!r}")
        child_lo, child_hi = span_lookup[child]
        host_lo, host_hi = span_lookup[host]
        # 契约按 0.1 mm 精度判定：世界坐标浮点末位不参与比较（0.019999999999999574 即 0.02 m）。
        gap = round(child_lo[height_axis] - host_hi[height_axis], 4)
        low, high = STYLE_CONTRACT[style]
        rows.append({"child": child, "host": host, "style": style,
                     "gap_m": gap, "min_m": low, "max_m": high,
                     "ok": low <= gap <= high})
    return rows


def assert_clearance(rows):
    bad = [r for r in rows if not r["ok"]]
    for row in rows:
        print(f"COURSE clearance {row['child']} -> {row['host']} "
              f"gap={row['gap_m']:+.4f}m [{row['min_m']:+.3f},{row['max_m']:+.3f}] "
              f"{'OK' if row['ok'] else 'FAIL'}")
    if bad:
        names = ", ".join(f"{r['child']}->{r['host']} gap={r['gap_m']:+.4f}"
                          for r in bad)
        raise SystemExit(f"净空自检失败：{len(bad)} 对不满足契约（{names}）；"
                         f"fix=tools/art/generate_sword_flight_course.py 的 CLEARANCE 常量与构件中心")


def glb_json(path):
    """读取 GLB 的 JSON chunk（标准库，不依赖引擎与第三方库）。"""
    data = path.read_bytes()
    _, _, length = struct.unpack_from("<III", data, 0)
    offset = 12
    while offset < length:
        chunk_len, chunk_type = struct.unpack_from("<II", data, offset)
        if chunk_type == 0x4E4F534A:
            return json.loads(data[offset + 8:offset + 8 + chunk_len].decode("utf-8"))
        offset += 8 + chunk_len
    raise RuntimeError("GLB 缺少 JSON chunk")


def glb_node_spans(path):
    """GLB 每个网格节点的世界包围盒。

    GLB 为 Y-up（export_yup）：高度轴是 Y（与 Godot 一致），不是 Blender 的 Z。
    节点变换按 glTF TRS 或 matrix 处理：把局部包围盒 8 角点变换到世界再取 min/max。
    """
    doc = glb_json(path)
    spans = {}
    for node in doc.get("nodes", []):
        if "mesh" not in node:
            continue
        matrix = glb_node_matrix(node)
        lo = [float("inf")] * 3
        hi = [float("-inf")] * 3
        for prim in doc["meshes"][node["mesh"]]["primitives"]:
            acc = doc["accessors"][prim["attributes"]["POSITION"]]
            amin = [float(v) for v in acc["min"]]
            amax = [float(v) for v in acc["max"]]
            for corner in range(8):
                local = [amin[axis] if not (corner >> axis) & 1 else amax[axis]
                         for axis in range(3)]
                world = [sum(matrix[row * 4 + col] * local[col] for col in range(3))
                         + matrix[row * 4 + 3] for row in range(3)]
                for axis in range(3):
                    lo[axis] = min(lo[axis], world[axis])
                    hi[axis] = max(hi[axis], world[axis])
        spans[node.get("name", f"node_{node['mesh']}")] = (tuple(lo), tuple(hi))
    return spans


def glb_node_matrix(node):
    """节点局部->世界矩阵（列主序 4x4）：优先 matrix，否则合成 T * R * S。"""
    if "matrix" in node:
        return [float(v) for v in node["matrix"]]
    tx, ty, tz = (float(v) for v in (node.get("translation") or [0.0, 0.0, 0.0]))
    qx, qy, qz, qw = (float(v) for v in (node.get("rotation") or [0.0, 0.0, 0.0, 1.0]))
    sx, sy, sz = (float(v) for v in (node.get("scale") or [1.0, 1.0, 1.0]))
    rot = [
        1 - 2 * (qy * qy + qz * qz), 2 * (qx * qy - qz * qw), 2 * (qx * qz + qy * qw),
        2 * (qx * qy + qz * qw), 1 - 2 * (qx * qx + qz * qz), 2 * (qy * qz - qx * qw),
        2 * (qx * qz - qy * qw), 2 * (qy * qz + qx * qw), 1 - 2 * (qx * qx + qy * qy),
    ]
    scale = (sx, sy, sz)
    matrix = [0.0] * 16
    for row in range(3):
        for col in range(3):
            matrix[row * 4 + col] = rot[row * 3 + col] * scale[col]
    matrix[3], matrix[7], matrix[11] = tx, ty, tz
    matrix[12], matrix[13], matrix[14], matrix[15] = 0.0, 0.0, 0.0, 1.0
    return matrix


def glb_coplanar_hits(spans):
    """全 GLB 共面扫描（受限口径）：只检 support 的 top 与 child 的 bottom 之间的
    轴向面间隙 ≤1.5 mm 且水平重叠 ≥0.05 m²。

    不检 top/top 与 bottom/bottom 共面，因此 `unregistered=0` 只代表本口径无命中，
    不得扩写为「所有方向的共面均为 0」。同材质十字标记（takeoff_mark ×
    takeoff_mark_cross）的 top/top 交叠属允许项，见 CLEARANCE_PAIRS 注释与台账。
    """
    hits = []
    names = sorted(spans)
    for index, a in enumerate(names):
        a_lo, a_hi = spans[a]
        for b in names[index + 1:]:
            b_lo, b_hi = spans[b]
            gap = min(abs(a_lo[1] - b_hi[1]), abs(b_lo[1] - a_hi[1]))
            if gap > COPLANAR_GAP:
                continue
            overlap_x = min(a_hi[0], b_hi[0]) - max(a_lo[0], b_lo[0])
            overlap_z = min(a_hi[2], b_hi[2]) - max(a_lo[2], b_lo[2])
            area = max(0.0, overlap_x) * max(0.0, overlap_z)
            if area >= COPLANAR_AREA:
                hits.append((a, b, round(gap, 5), round(area, 4)))
    return hits


def audit_glb(path):
    """导出后复核：登记对净空 + 全 GLB 未登记共面命中数（期望 0）；任一不满足即失败。"""
    spans = glb_node_spans(path)
    # GLB 为 Y-up：高度轴是 Y（与 Blender 的 Z 不同，用错轴会得到无意义的负间隙）。
    rows = clearance_rows(spans, height_axis=1)
    rows_path = ART_DIR / "surface_clearance_report.json"
    hits = glb_coplanar_hits(spans)
    bad_rows = [r for r in rows if not r["ok"]]
    report = {
        "asset": "sword_flight_course",
        "generated": "2026-09-18",
        "clearance_m": CLEARANCE,
        "bury_depth_m": BURY_DEPTH,
        "style_contract": {k: list(v) for k, v in STYLE_CONTRACT.items()},
        "coplanar_threshold": {"gap_m": COPLANAR_GAP, "area_m2": COPLANAR_AREA},
        "pairs": rows,
        "unregistered_coplanar_hits": [
            {"a": a, "b": b, "gap_m": gap, "overlap_m2": area} for a, b, gap, area in hits
        ],
        "result": "ok" if not bad_rows and not hits else "fail",
    }
    rows_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n",
                         encoding="utf-8")
    print(f"COURSE clearance_report={rows_path}")
    print(f"COURSE glb_coplanar_unregistered={len(hits)}")
    if bad_rows:
        names = ", ".join(f"{r['child']}->{r['host']} gap={r['gap_m']:+.4f}"
                          for r in bad_rows)
        raise SystemExit(f"GLB 净空复核失败：{len(bad_rows)} 对不满足契约（{names}）；"
                         f"fix=tools/art/generate_sword_flight_course.py 的 CLEARANCE 常量与构件中心")
    if hits:
        detail = ", ".join(f"{a}<->{b} gap={gap} area={area}" for a, b, gap, area in hits[:8])
        raise SystemExit(f"GLB 共面复核失败：{len(hits)} 对未登记共面（{detail}）；"
                         f"fix=tools/art/generate_sword_flight_course.py 的 CLEARANCE_PAIRS / CLEARANCE")
    return rows


# ---------------------------------------------------------------- 导出与预览


def bpy_objects():
    import bpy
    return [o for o in bpy.data.objects if o.type in {"MESH", "CURVE"}]


def stage_course():
    """清场 -> 建全部几何 -> 导出 GLB + 碰撞/路线 JSON + 保存 .blend。"""
    import bpy
    bpy.ops.wm.read_factory_settings(use_empty=True)
    ART_DIR.mkdir(parents=True, exist_ok=True)
    COLLIDERS.clear()
    VISUAL_ONLY.clear()
    pal = make_palette()
    build_course(pal)

    objects = bpy_objects()
    tris = 0
    for obj in objects:
        mesh = obj.data
        if hasattr(mesh, "calc_loop_triangles"):
            mesh.calc_loop_triangles()
            tris += len(mesh.loop_triangles)

    payload = build_route_payload()
    OUT_COLLISION.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
                             encoding="utf-8")

    # 导出前自检：登记对的装饰层/承托面净空必须落在声明契约内。
    span_lookup = {obj.name: object_span(obj) for obj in objects}
    assert_clearance(clearance_rows(span_lookup))

    for obj in bpy.context.selected_objects:
        obj.select_set(False)
    for obj in objects:
        obj.select_set(True)
    bpy.ops.export_scene.gltf(filepath=str(OUT_GLB), export_format="GLB",
                              use_selection=True, export_apply=True, export_yup=True)

    audit_glb(OUT_GLB)

    # save_version=0：覆盖保存时不轮转 .blend1，防止未来重跑静默覆盖历史探索资产备份。
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=str(ART_DIR / "sword_flight_course.blend"))
    print(f"COURSE ok objects={len(objects)} tris={tris} "
          f"colliders={len(payload['colliders'])} visual_only={len(payload['visual_only'])}")
    print(f"COURSE glb={OUT_GLB}")
    print(f"COURSE route_json={OUT_COLLISION}")
    print(f"COURSE blend={ART_DIR / 'sword_flight_course.blend'}")


def aim_camera(camera, godot_target):
    """把相机朝向 Godot 坐标下的目标点。

    用手写欧拉角在相机自带 -Z 前向约定下极易写反——本轮首版预览整幅空白即此因
    （相机朝天）。统一走 Vector.to_track_quat('-Z', 'Y')，与相机自身轴向约定一致。
    """
    from mathutils import Vector
    direction = Vector(to_blender(godot_target)) - camera.location
    if direction.length < 1e-6:
        return
    camera.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def add_preview_rig():
    """预览相机/灯光：在导出之后加入，只影响 .blend 与渲染，不进 GLB。"""
    import bpy
    bpy.ops.object.camera_add(location=to_blender((58.0, 34.0, 34.0)))
    camera = bpy.context.object
    camera.name = "PreviewCamera"
    camera.data.lens = 42.0
    aim_camera(camera, (14.0, 7.0, -4.0))
    bpy.context.scene.camera = camera

    bpy.ops.object.light_add(type="SUN", location=to_blender((30.0, 40.0, -20.0)))
    sun = bpy.context.object
    sun.name = "PreviewSun"
    sun.data.energy = 3.4
    sun.rotation_euler = (math.radians(52.0), 0.0, math.radians(-38.0))

    world = bpy.data.worlds.new("PreviewWorld")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.72, 0.78, 0.84, 1.0)
    world.node_tree.nodes["Background"].inputs[1].default_value = 1.0
    bpy.context.scene.world = world


def render_preview(tag, location, target, lens=42.0, resolution=(960, 640)):
    import bpy
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 24
    scene.cycles.use_denoising = True
    scene.render.resolution_x = resolution[0]
    scene.render.resolution_y = resolution[1]
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"

    camera = bpy.data.objects.get("PreviewCamera")
    if camera is None:
        add_preview_rig()
        camera = bpy.data.objects.get("PreviewCamera")
    camera.location = to_blender(location)
    aim_camera(camera, target)
    camera.data.lens = lens
    out = ART_DIR / f"course_preview_{tag}.png"
    scene.render.filepath = str(out)
    bpy.ops.render.render(write_still=True)
    print(f"COURSE preview={out}")


def stage_preview():
    """重建几何后渲染多角度预览（不导出 GLB，避免覆盖交付产物）。"""
    import bpy
    bpy.ops.wm.read_factory_settings(use_empty=True)
    ART_DIR.mkdir(parents=True, exist_ok=True)
    COLLIDERS.clear()
    VISUAL_ONLY.clear()
    build_course(make_palette())
    add_preview_rig()
    views = [
        ("overview", (58.0, 34.0, 34.0), (14.0, 7.0, -4.0), 42.0),
        ("takeoff", (12.0, 9.0, 24.0), (0.0, 3.0, 8.0), 40.0),
        ("gates", (34.0, 20.0, 8.0), (16.0, 10.0, -12.0), 46.0),
        ("hover", (38.0, 20.0, -6.0), (24.5, 12.0, -16.5), 44.0),
        ("landing", (30.0, 16.0, 30.0), (26.0, 2.5, 13.0), 42.0),
    ]
    for tag, location, target, lens in views:
        render_preview(tag, location, target, lens)
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=str(ART_DIR / "sword_flight_course.blend"))
    print(f"COURSE blend={ART_DIR / 'sword_flight_course.blend'}")


def main(argv):
    action = argv[0] if argv else "course"
    if action == "course":
        stage_course()
        return 0
    if action == "preview":
        stage_preview()
        return 0
    if action == "all":
        stage_course()
        add_preview_rig()
        render_preview("overview", (58.0, 34.0, 34.0), (14.0, 7.0, -4.0), 42.0)
        return 0
    raise SystemExit(f"未知动作：{action!r}（可用 course / preview / all）")


if __name__ == "__main__":
    import bpy  # noqa: F401  (确认在 Blender 内运行)
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    code = main(args)
    if code:
        sys.exit(code)
