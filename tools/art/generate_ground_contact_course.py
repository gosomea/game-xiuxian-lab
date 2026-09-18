"""地形接触训练场（ground_contact_course）的程序建模资产生成器（全部原创几何，无外部素材）。

运行（仓库根）：
  /Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup \
      --python tools/art/generate_ground_contact_course.py -- course
      -> src/levels/experiments/character_movement/ground_contact_course.glb
      -> docs/art/ground_contact_course/ground_contact_course.blend
      -> docs/art/ground_contact_course/preview_*.png（5 张）

职责边界：
  - 几何尺寸真源是同目录 ground_contact_course_layout.json。本文件与 Godot 场景
    各自从同一份 devices 字段推导形状：Godot 建碰撞，本文件建可见几何。
    两面用同一套推导（run = slope_length·cosθ、rise = slope_length·sinθ、
    斜面中心 = base + (run/2, rise/2) − (t/2)·法线），因此「看得见的斜面」
    与「走得上去的斜面」是同一个数学对象。
  - 碰撞不在本文件：场景按 JSON 建 BoxShape3D。视觉与碰撞的对齐由 playtest
    读回两侧数值断言，而不是靠手工校对。
  - 本文件不生成任何角色、能力、HUD 或场景编排资产。
  - 全局工作台 empty_stage 与既有庭院 / 群山资产完全不动。

坐标：GLB 按 Godot 世界坐标一次导出（Y 上、北 = -Z），场景在原点实例化即可。
Blender 为 Z 上，全部顶点经 to_blender() 换算。
GLB 只含网格：预览相机 / 灯光 / 地面装饰在导出后加入 .blend，不进 GLB。
"""
from __future__ import annotations

import json
import math
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCENE_DIR = ROOT / "src" / "levels" / "experiments" / "character_movement"
LAYOUT_PATH = SCENE_DIR / "ground_contact_course_layout.json"
OUT_GLB = SCENE_DIR / "ground_contact_course.glb"
ART_DIR = ROOT / "docs" / "art" / "ground_contact_course"

## 预览镜头：Godot 世界坐标（相机位 / 看点 / 正交尺寸）。
PREVIEW_SHOTS = [
    ("overview", (-10.0, 40.0, 50.0), (2.0, 0.0, -1.0), 66.0),
    ("ramps", (-4.0, 12.0, 17.0), (-11.0, 1.4, 0.5), 17.0),
    ("steps", (12.0, 11.0, 16.0), (1.5, 0.9, 0.4), 17.0),
    ("corner_narrow", (18.0, 14.0, 18.0), (9.0, 0.6, 0.6), 22.0),
    ("edge_void", (18.0, 15.0, 21.0), (24.0, 0.2, -1.0), 26.0),
]


def to_blender(point):
    """Godot (Y-up, 北 = -Z) -> Blender (Z-up)；导出 export_yup 后回到同一世界坐标。"""
    gx, gy, gz = point
    return (gx, -gz, gy)


def load_layout():
    return json.loads(LAYOUT_PATH.read_text(encoding="utf-8"))


# ---------------------------------------------------------------- 材质


def make_palette():
    """沿用 mountains / courtyards 的素材语言（同色同粗糙度，画面才像同一个宗门）。"""
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
        "stone": mat("Warm limestone", (0.59, 0.62, 0.51)),
        "ivory": mat("Ivory paving", (0.78, 0.77, 0.64)),
        "cut": mat("Cut stone edges", (0.24, 0.35, 0.28)),
        "jade": mat("Celadon ceramic", (0.075, 0.24, 0.18)),
        "roof": mat("Jade roof tiles", (0.078, 0.235, 0.185)),
        "ridge": mat("Roof ridge bronze", (0.51, 0.34, 0.09), 0.45, 0.35),
        "timber": mat("Warm cedar", (0.22, 0.115, 0.053)),
        "stepstone": mat("Step stone", (0.665, 0.645, 0.555), 0.82),
        "moss": mat("Moss", (0.22, 0.33, 0.105)),
        "bamboo": mat("Bamboo stems", (0.25, 0.38, 0.12)),
        "leaf": mat("Bamboo leaves", (0.12, 0.29, 0.09)),
        "granite": mat("Granite mid", (0.215, 0.238, 0.223)),
        "lantern": mat("Lantern paper", (0.98, 0.75, 0.37), 0.6, 0.0, 0.6),
        "mist": mat("Valley mist", (0.86, 0.91, 0.94), 0.95, 0.0, 0.25),
    }


# ---------------------------------------------------------------- 基础构件


def finish(obj, name, material, bevel=0.0):
    obj.name = name
    obj.data.materials.append(material)
    if bevel:
        mod = obj.modifiers.new("Soft crafted edges", "BEVEL")
        mod.width = bevel
        mod.segments = 2
        mod = obj.modifiers.new("Weighted corner normals", "WEIGHTED_NORMAL")
    return obj


def cbox(name, center, size, material, bevel=0.04, rotation_z=0.0):
    """Godot 坐标的盒；size 为 Godot (x, y, z)。

    rotation_z 是**绕 Godot Z 轴**的滚转（让盒子的 X 轴抬起，形成可走斜面）。
    轴向换算容易搞错，这里写清楚：
      Godot (x, y, z) -> Blender (x, -z, y)，于是
      Godot X = Blender X，Godot Y = Blender Z，Godot Z = Blender -Y。
    所以「绕 Godot Z 转 θ」= 「绕 Blender -Y 转 θ」= rotation_euler.y = -θ。
    若误写成 Blender Z 轴，盒子会绕着竖直方向偏航——斜面会变成一块平放的斜纹板，
    playtest 的可视/碰撞对齐检查就是用来抓这个的。
    """
    import bpy
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=to_blender(center))
    obj = bpy.context.object
    obj.scale = (size[0], size[2], size[1])
    if rotation_z:
        obj.rotation_euler = (0.0, -rotation_z, 0.0)
    bpy.ops.object.transform_apply(location=False, rotation=bool(rotation_z), scale=True)
    return finish(obj, name, material, bevel)


def ccyl(name, center, radius, depth, material, verts=12, rotation=None):
    import bpy
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=radius, depth=depth,
                                        location=to_blender(center))
    obj = bpy.context.object
    if rotation:
        obj.rotation_euler = (rotation[0], -rotation[2], rotation[1])
    return finish(obj, name, material, 0.02)


def cblob(name, center, size, material, subdivisions=2):
    """椭球体；size 是**全长**（x/y/z 三个方向的整体尺寸），不是半长。

    ico_sphere 的半径 1 对应全长 2，所以缩放取 size/2；这一步写错会让云雾、
    苔石这类装饰整体放大一倍，并且从包围盒上才看得出来。
    """
    import bpy
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdivisions, radius=1.0,
                                          location=to_blender(center))
    obj = bpy.context.object
    obj.scale = (size[0] * 0.5, size[2] * 0.5, size[1] * 0.5)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish(obj, name, material)


def gable_roof(name, center_x, center_z, half_x, half_z, eave_y, ridge_y, material,
               bays=12, upturn=0.16, ridge_axis="x"):
    """双坡青瓦屋面（与庭院同一工艺，便于宗门语言统一）。"""
    import bpy
    verts, faces = [], []
    span = half_x if ridge_axis == "x" else half_z
    other = half_z if ridge_axis == "x" else half_x
    for i in range(bays):
        a0 = -span + 2.0 * span * i / bays
        a1 = span - 2.0 * span * (bays - i - 1) / bays - 0.02
        quad = []
        for a in (a0, a1):
            for t in (-1.0, 0.0, 1.0):
                lift = upturn * (abs(t) ** 5)
                y = eave_y + (ridge_y - eave_y - lift) * (1.0 - abs(t))
                offset = t * other
                if ridge_axis == "x":
                    quad.append((center_x + a, y, center_z + offset))
                else:
                    quad.append((center_x + offset, y, center_z + a))
        verts.extend(quad)
        base = i * 6
        faces.append((base + 0, base + 1, base + 4, base + 3))
        faces.append((base + 1, base + 2, base + 5, base + 4))
    bverts = [to_blender(v) for v in verts]
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(bverts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(material)
    mod = obj.modifiers.new("Roof thickness", "SOLIDIFY")
    mod.thickness = 0.16
    mod.offset = 0.0
    return obj


def stone_lantern(name, x, z, base_y, pal, scale=1.0):
    """石灯：基座 + 柱 + 火袋 + 檐 + 宝珠。"""
    s = scale
    cbox(name + "_base", (x, base_y + 0.12 * s, z), (0.62 * s, 0.24 * s, 0.62 * s), pal["stone"], 0.03)
    ccyl(name + "_shaft", (x, base_y + 0.62 * s, z), 0.11 * s, 0.78 * s, pal["stone"], verts=8)
    cbox(name + "_box", (x, base_y + 1.12 * s, z), (0.42 * s, 0.36 * s, 0.42 * s), pal["lantern"], 0.02)
    ccyl(name + "_cap", (x, base_y + 1.36 * s, z), 0.34 * s, 0.14 * s, pal["granite"], verts=6)
    cblob(name + "_finial", (x, base_y + 1.5 * s, z), (0.24 * s, 0.28 * s, 0.24 * s), pal["granite"], 1)


def bamboo_clump(name, x, z, base_y, pal, count=5):
    import random
    rng = random.Random(1709 + sum(ord(c) for c in name))
    for i in range(count):
        dx = rng.uniform(-0.5, 0.5)
        dz = rng.uniform(-0.5, 0.5)
        h = rng.uniform(2.2, 3.6)
        lean = rng.uniform(-0.05, 0.05)
        ccyl("%s_stem_%d" % (name, i), (x + dx, base_y + h * 0.5, z + dz),
             0.055, h, pal["bamboo"], verts=6, rotation=(lean, 0.0, lean))
        cblob("%s_leaf_%d" % (name, i), (x + dx * 1.1, base_y + h * 0.92, z + dz * 1.1),
              (1.3, 1.8, 1.3), pal["leaf"], 1)


def paver_border(name, center, size, top_y, pal, inset=0.35, band=0.18):
    """铺装边框：主体铺装 + 内嵌玉色带。

    主体网格用**装置 id 原名**，不带后缀：这样运行时 find_child(id) 能直接命中
    「那个装置的可见几何」，与同名碰撞体一眼对上（对齐检查依赖这条命名契约）。
    """
    cx, cz = center
    sx, sz = size
    cbox(name, (cx, top_y - 0.06, cz), (sx, 0.12, sz), pal["ivory"], 0.03)
    hx, hz = sx * 0.5 - inset, sz * 0.5 - inset
    for tag, (dx, dz, w, d) in {
        "n": (0.0, -hz, hx * 2.0, band),
        "s": (0.0, hz, hx * 2.0, band),
        "w": (-hx, 0.0, band, hz * 2.0),
        "e": (hx, 0.0, band, hz * 2.0),
    }.items():
        cbox("%s_band_%s" % (name, tag), (cx + dx, top_y + 0.012, cz + dz), (w, 0.03, d), pal["jade"], 0.01)


def wall_with_cap(name, center, size, pal):
    """院墙：墙身 + 玉色压顶（压顶略外挑，读起来像宗门矮墙）。"""
    cbox(name, center, size, pal["stone"], 0.03)
    top = center[1] + size[1] * 0.5
    over = (size[0] + 0.16, 0.12, size[2] + 0.16)
    cbox(name + "_cap", (center[0], top + 0.06, center[2]), over, pal["jade"], 0.03)


# ---------------------------------------------------------------- 尺寸推导（与 Godot 同式）


def ramp_shape(dev):
    """由原始字段推导斜面盒（中心 / 尺寸 / 绕 Z 旋转）。Godot 侧用同一公式。

    两种等价的声明方式：
    - 给 angle_deg + slope_length：适合「坡有多陡」这种可读参数；
    - 给 run_m + rise_m：适合坡顶必须精确落在某个高度（如登台坡顶 = 台面 0.90 m），
      避免角度→正弦的浮点漂移。两者不可同时给。
    """
    thickness = dev["thickness"]
    if "run_m" in dev or "rise_m" in dev:
        run = float(dev["run_m"])
        rise = float(dev["rise_m"])
        length = math.hypot(run, rise)
        angle = math.atan2(rise, run)
    else:
        angle = math.radians(dev["angle_deg"])
        length = dev["slope_length"]
        run = length * math.cos(angle)
        rise = length * math.sin(angle)
    bx, by, bz = dev["base"]
    center = (bx + run * 0.5 + thickness * 0.5 * math.sin(angle),
              by + rise * 0.5 - thickness * 0.5 * math.cos(angle),
              bz)
    return {
        "center": center, "size": (length, thickness, dev["width"]),
        "angle": angle, "run": run, "rise": rise,
        "top_y": by + rise, "top_x": bx + run,
    }


# ---------------------------------------------------------------- 装配


def build_ground(layout, pal):
    """训练场石铺地面：整片青石 + 玉色分格线，以及东侧两段台地（中留落下回收口）。"""
    for piece in layout["ground_pieces"]:
        cx, cy, cz = piece["center"]
        sx, sy, sz = piece["size"]
        cbox("ground_" + piece["name"], (cx, cy, cz), (sx, sy, sz), pal["granite"], 0.06)
        # 场地面用较沉的石色、装置铺装用象牙色：训练装置要能从地面里跳出来，
        # 全用亮色会让「看得见的装置」和「脚下的地」糊成一片。
        cbox("ground_" + piece["name"] + "_top", (cx, cy + sy * 0.5 + 0.02, cz),
             (sx - 0.4, 0.05, sz - 0.4), pal["stone"], 0.02)
    # 分格线沿 X 每 6 m 一道，帮助 HUD 之外用眼睛读距离。
    x = -21.0
    index = 0
    while x <= 28.0:
        cbox("ground_seam_%02d" % index, (x, 0.055, 0.0), (0.09, 0.03, 35.6), pal["jade"], 0.01)
        x += 6.0
        index += 1
    # 场内苔石与竹丛点缀：让石面不是一块空板，但仍不挡测量视线。
    for i, (mx, mz, size) in enumerate(((-14.0, 11.5, 1.7), (5.0, 12.6, 1.4), (14.6, -12.6, 1.6),
                                        (-3.0, -13.4, 1.5), (20.0, 12.0, 1.3))):
        cblob("ground_moss_%d" % i, (mx, 0.24, mz), (size, 0.48, size * 0.85), pal["moss"], 2)
        cbox("ground_moss_base_%d" % i, (mx, 0.07, mz), (size * 1.3, 0.14, size * 1.1),
             pal["granite"], 0.04)


def build_flats(layout, pal):
    for dev in layout["devices"]:
        if dev["kind"] != "pad":
            continue
        cx, _cy, cz = dev["center"]
        sx, _sy, sz = dev["size"]
        # 铺装主件直接用 device id 命名：可见几何与碰撞体同名，
        # 「看得见的装置」与「走得上去的装置」能在运行时按同一路径对上。
        paver_border(dev["id"], (cx, cz), (sx, sz), 0.03, pal, inset=0.5, band=0.22)
        for i in range(4):
            cbox("flat_tick_%d" % i, (cx - 3.0 + i * 2.0, 0.045, cz + 3.4),
                 (0.09, 0.03, 0.9), pal["cut"], 0.01)


def build_ramps(layout, pal):
    for dev in layout["devices"]:
        if dev["kind"] != "ramp":
            continue
        shape = ramp_shape(dev)
        name = dev["id"]
        cbox(name, shape["center"], shape["size"], pal["stone"], 0.03, rotation_z=shape["angle"])
        # 坡面边缘玉色压条：沿斜面方向贴在两侧。
        along = shape["size"][0]
        for side in (-1.0, 1.0):
            offset = (dev["width"] * 0.5 - 0.09) * side
            local = (0.0, shape["size"][1] * 0.5 + 0.02, 0.0)
            cos_a, sin_a = math.cos(shape["angle"]), math.sin(shape["angle"])
            dx = local[0] * cos_a - local[1] * sin_a
            dy = local[0] * sin_a + local[1] * cos_a
            cbox(name + "_edge_%d" % int(side), (shape["center"][0] + dx,
                 shape["center"][1] + dy, shape["center"][2] + offset),
                (along * 0.98, 0.05, 0.16), pal["jade"], 0.01, rotation_z=shape["angle"])
        # 坡顶平台 + 木栏（栏是视觉，碰撞由场景按 JSON 单独给或不给）。
        depth = dev.get("landing_depth", 0.0)
        if depth > 0.0:
            top_y = shape["top_y"]
            cbox(name + "_landing", (shape["top_x"] + depth * 0.5, top_y * 0.5, dev["base"][2]),
                 (depth, max(top_y, 0.12), dev["width"]), pal["stone"], 0.04)
            cbox(name + "_landing_cap", (shape["top_x"] + depth * 0.5, top_y + 0.02, dev["base"][2]),
                 (depth - 0.1, 0.04, dev["width"] - 0.1), pal["ivory"], 0.02)
            if dev.get("rail"):
                for side in (-1.0, 1.0):
                    z = dev["base"][2] + side * (dev["width"] * 0.5 - 0.07)
                    for post in range(3):
                        px = shape["top_x"] + 0.14 + post * (depth - 0.28) * 0.5
                        cbox("%s_rail_post_%d_%d" % (name, int(side), post),
                             (px, top_y + 0.45, z), (0.09, 0.9, 0.09), pal["timber"], 0.02)
                    cbox("%s_rail_bar_%d" % (name, int(side)),
                         (shape["top_x"] + depth * 0.5, top_y + 0.84, z),
                         (depth - 0.16, 0.09, 0.09), pal["timber"], 0.02)
        if dev.get("top_y") is not None and depth <= 0.0:
            cbox(name + "_nose", (shape["top_x"] + 0.08, shape["top_y"] - 0.05, dev["base"][2]),
                 (0.16, 0.1, dev["width"]), pal["jade"], 0.02)


def build_steps(layout, pal):
    for dev in layout["devices"]:
        if dev["kind"] != "step":
            continue
        cx, cy, cz = dev["center"]
        sx, sy, sz = dev["size"]
        cbox(dev["id"], (cx, cy, cz), (sx, sy, sz), pal["stepstone"], 0.04)
        cbox(dev["id"] + "_top", (cx, cy + sy * 0.5 + 0.015, cz), (sx - 0.12, 0.03, sz - 0.12),
             pal["ivory"], 0.02)
        # 玉色踏步边：正对来向的一条窄带，标出抬升高度所在。
        cbox(dev["id"] + "_band", (cx - sx * 0.5 + 0.09, cy + sy * 0.5 + 0.03, cz),
             (0.16, 0.04, sz - 0.12), pal["jade"], 0.01)
        cbox(dev["id"] + "_plinth", (cx, 0.05, cz), (sx + 0.5, 0.1, sz + 0.5), pal["cut"], 0.03)


def build_walls(layout, pal):
    for dev in layout["devices"]:
        if dev["kind"] != "wall":
            continue
        wall_with_cap(dev["id"], dev["center"], dev["size"], pal)
        if dev.get("corner") == "inner":
            cbox(dev["id"] + "_foot", (dev["center"][0], 0.07, dev["center"][2]),
                 (dev["size"][0] + 0.34, 0.14, dev["size"][2] + 0.34), pal["granite"], 0.03)


def build_narrow_lanes(layout, pal):
    """窄路：路面玉色导轨线标出净宽，并在入口画出门框式石柱，读起来像夹道。"""
    seen = {}
    for dev in layout["devices"]:
        if dev["kind"] != "wall" or "gap_m" not in dev:
            continue
        seen.setdefault(dev["gap_m"], []).append(dev)
    for gap, walls in sorted(seen.items()):
        z0 = min(w["center"][2] for w in walls)
        z1 = max(w["center"][2] for w in walls)
        lane_z = walls[0]["lane_z"]
        half = gap * 0.5
        for side, z in (("s", lane_z - half + 0.06), ("n", lane_z + half - 0.06)):
            cbox("lane_%s_rail_%s" % (str(gap).replace(".", ""), side),
                 (10.5, 0.05, z), (5.0, 0.04, 0.1), pal["jade"], 0.01)
        for end, ex in (("w", 8.0), ("e", 13.0)):
            cbox("lane_%s_post_%s" % (str(gap).replace(".", ""), end),
                 (ex, 1.05, lane_z), (0.3, 2.1, gap + 0.5), pal["cut"], 0.04)


def build_terrace(layout, pal):
    for dev in layout["devices"]:
        if dev["kind"] != "terrace":
            continue
        cx, cy, cz = dev["center"]
        sx, sy, sz = dev["size"]
        cbox(dev["id"], (cx, cy, cz), (sx, sy, sz), pal["stone"], 0.05)
        cbox(dev["id"] + "_deck", (cx, cy + sy * 0.5 + 0.02, cz), (sx - 0.24, 0.04, sz - 0.24),
             pal["ivory"], 0.02)
        # 无栏侧（+X）画一道临边警示带：看得见的边界，但没有任何碰撞。
        cbox(dev["id"] + "_warning", (cx + sx * 0.5 - 0.3, cy + sy * 0.5 + 0.055, cz),
             (0.34, 0.03, sz - 0.2), pal["jade"], 0.01)


def build_gate(layout, pal):
    gate = layout["decor"]["gate"]
    lx, ly, lz = gate["lintel"]
    span, height, depth = gate["span"], gate["height"], gate["depth"]
    cbox("gate_lintel", (lx, ly, lz), (0.7, height, span), pal["timber"], 0.04)
    gable_roof("gate_roof", lx, lz, 0.95, span * 0.5 + 0.4, ly + height * 0.5,
               gate["roof_peak"], pal["roof"], bays=12, ridge_axis="z")
    cbox("gate_ridge", (lx, gate["roof_peak"] + 0.03, lz), (0.34, 0.16, span + 0.9),
         pal["ridge"], 0.03)
    cbox("gate_plaque", (lx + 0.42, ly + 0.1, lz), (0.12, 0.62, 1.5), pal["jade"], 0.02)


def build_mist(layout, pal):
    for index, puff in enumerate(layout["decor"]["mist"]):
        cblob("mist_%02d" % index, puff["center"], puff["size"], pal["mist"], subdivisions=2)


def build_props(layout, pal):
    stone_lantern("lantern_gate_n", -19.4, -6.6, 0.0, pal, 1.15)
    stone_lantern("lantern_gate_s", -19.4, 6.6, 0.0, pal, 1.15)
    stone_lantern("lantern_steps", 4.6, 6.4, 0.0, pal, 1.05)
    stone_lantern("lantern_narrow", 15.4, 8.6, 0.0, pal, 1.0)
    bamboo_clump("bamboo_w", -20.4, -15.4, 0.0, pal, count=6)
    bamboo_clump("bamboo_n", 12.0, -15.6, 0.0, pal, count=5)
    bamboo_clump("bamboo_e", 28.4, 14.6, 0.0, pal, count=5)
    bamboo_clump("bamboo_mid", -6.0, 13.6, 0.0, pal, count=4)
    cblob("moss_rock_0", (-8.4, 0.34, 12.2), (1.5, 0.72, 1.2), pal["moss"], 2)
    cblob("moss_rock_1", (16.6, 0.3, 11.4), (1.3, 0.62, 1.1), pal["moss"], 2)
    cblob("moss_rock_2", (-16.0, 0.28, -8.6), (1.2, 0.58, 1.0), pal["moss"], 2)


def build_all(layout, pal):
    build_ground(layout, pal)
    build_flats(layout, pal)
    build_ramps(layout, pal)
    build_steps(layout, pal)
    build_walls(layout, pal)
    build_narrow_lanes(layout, pal)
    build_terrace(layout, pal)
    build_gate(layout, pal)
    build_mist(layout, pal)
    build_props(layout, pal)


# ---------------------------------------------------------------- 校验 / 导出


def bpy_objects():
    import bpy
    return bpy.context.scene.objects


def recalc_normals(objects):
    import bmesh as _bmesh
    import bpy  # noqa: F401
    for obj in objects:
        if obj.type != "MESH":
            continue
        mesh = obj.data
        bm = _bmesh.new()
        bm.from_mesh(mesh)
        _bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(mesh)
        bm.free()
        mesh.update()
    print("NORMALS recalculated on %d meshes" % len(objects))


def evaluated_totals(objects):
    import bpy
    deps = bpy.context.evaluated_depsgraph_get()
    tris = 0
    lo = [float("inf")] * 3
    hi = [float("-inf")] * 3
    for obj in objects:
        ev = obj.evaluated_get(deps)
        mesh = ev.to_mesh()
        for poly in mesh.polygons:
            tris += max(0, len(poly.vertices) - 2)
        for vert in mesh.vertices:
            world = ev.matrix_world @ vert.co
            for axis in range(3):
                lo[axis] = min(lo[axis], world[axis])
                hi[axis] = max(hi[axis], world[axis])
        ev.to_mesh_clear()
    return tris, lo, hi


def check_visual_alignment(layout):
    """可见装置必须与 JSON 声明一致：斜面顶面 / 台阶顶面 / 台面顶面逐项核对。

    这里只校验「由 JSON 推导出的可见几何」——它是 Godot 建碰撞用的同一份推导，
    因此这一步挡住的是「视觉与声明不一致」，物理对齐在 playtest 里回读。
    """
    problems = []
    for dev in layout["devices"]:
        if dev["kind"] == "ramp":
            shape = ramp_shape(dev)
            if dev.get("top_y") is not None and abs(shape["top_y"] - dev["top_y"]) > 1e-6:
                problems.append((dev["id"], "ramp top_y", shape["top_y"], dev["top_y"]))
        if dev["kind"] == "step":
            top = dev["center"][1] + dev["size"][1] * 0.5
            if abs(top - dev["rise"]) > 1e-6:
                problems.append((dev["id"], "step top", top, dev["rise"]))
        if dev["kind"] == "terrace":
            top = dev["center"][1] + dev["size"][1] * 0.5
            if abs(top - dev["top_y"]) > 1e-6:
                problems.append((dev["id"], "terrace top", top, dev["top_y"]))
    if problems:
        print("ALIGNMENT_FAIL", problems)
        raise SystemExit(2)
    ramps = [d for d in layout["devices"] if d["kind"] == "ramp"]
    print("ALIGNMENT ok ramps=%d steps=%d walls=%d"
          % (len(ramps),
             len([d for d in layout["devices"] if d["kind"] == "step"]),
             len([d for d in layout["devices"] if d["kind"] == "wall"])))


def stage_course():
    import bpy
    for obj in list(bpy.context.scene.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    pal = make_palette()
    layout = load_layout()
    build_all(layout, pal)
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    recalc_normals(meshes)
    check_visual_alignment(layout)
    tris_before, lo_before, hi_before = evaluated_totals(meshes)
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    OUT_GLB.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=str(OUT_GLB), export_format="GLB", use_selection=True,
                              export_apply=True, export_yup=True)
    print("EXPORTED %s meshes=%d tris=%d bbox=%s..%s"
          % (OUT_GLB, len(meshes), tris_before,
             [round(v, 2) for v in lo_before], [round(v, 2) for v in hi_before]))
    ART_DIR.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(ART_DIR / "ground_contact_course.blend"))
    print("BLEND %s" % (ART_DIR / "ground_contact_course.blend"))


def add_preview_rig():
    import bpy
    from mathutils import Vector
    bpy.ops.object.light_add(type="SUN", location=(24.0, 44.0, 34.0))
    sun = bpy.context.object
    sun.name = "PREVIEW_sun"
    sun.data.angle = 0.16
    sun.data.energy = 3.2
    sun.rotation_euler = (Vector((0.0, 0.0, 0.0)) - sun.location).to_track_quat("-Z", "Y").to_euler()
    bpy.ops.object.light_add(type="AREA", location=(-26.0, 30.0, 26.0))
    fill = bpy.context.object
    fill.name = "PREVIEW_fill"
    fill.data.energy = 30000.0
    fill.data.shape = "DISK"
    fill.data.size = 70.0
    bpy.ops.object.camera_add(location=(0.0, 0.0, 0.0))
    bpy.context.object.name = "PREVIEW_camera"
    bpy.context.scene.camera = bpy.context.object


def stage_preview():
    import bpy
    from mathutils import Vector
    scene = bpy.context.scene
    world = scene.world or bpy.data.worlds.new("CourseSky")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    bg.inputs[0].default_value = (0.62, 0.72, 0.79, 1.0)
    bg.inputs[1].default_value = 0.85
    scene.view_settings.view_transform = "Standard"
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 16
    scene.cycles.use_denoising = True
    scene.render.resolution_x = 960
    scene.render.resolution_y = 620
    scene.render.image_settings.file_format = "PNG"
    cam = scene.camera
    assert cam is not None, "预览相机必须由 add_preview_rig() 先建好"
    ART_DIR.mkdir(parents=True, exist_ok=True)
    for name, cam_godot, look_godot, size in PREVIEW_SHOTS:
        cam.location = to_blender(cam_godot)
        direction = Vector(to_blender(look_godot)) - Vector(cam.location)
        cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
        cam.data.type = "ORTHO"
        cam.data.ortho_scale = size
        out = ART_DIR / ("preview_%s.png" % name)
        scene.render.filepath = str(out)
        bpy.ops.render.render(write_still=True)
        print("PREVIEW %s" % out)
    return 0


def main(argv):
    stage = argv[0] if argv else "course"
    if stage == "course":
        want_preview = "preview" in argv[1:]
        stage_course()
        if want_preview:
            # GLB 已在上面导出（不含相机/灯光）；预览装置只进 .blend。
            add_preview_rig()
            stage_preview()
            import bpy
            bpy.ops.wm.save_as_mainfile(filepath=str(ART_DIR / "ground_contact_course.blend"))
            print("BLEND(with preview rig) %s" % (ART_DIR / "ground_contact_course.blend"))
        return 0
    if stage == "preview":
        if not [o for o in bpy_objects() if o.type == "MESH"]:
            print("NO_MESH：请先在同一进程运行 course 阶段")
            return 3
        if bpy.context.scene.camera is None:
            add_preview_rig()
        return stage_preview()
    raise SystemExit("未知阶段 %r；可用：course / preview" % stage)


if __name__ == "__main__":
    import bpy  # noqa: F401
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    code = main(args)
    if code:
        sys.exit(code)
