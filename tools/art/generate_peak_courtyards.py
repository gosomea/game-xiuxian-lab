"""群山宗门「峰顶庭院」建筑资产生成器（全部程序原创几何，无外部素材）。

运行（仓库根）：
  /Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup \
      --python tools/art/generate_peak_courtyards.py -- courtyards
      -> src/levels/experiments/character_movement/mountain_realm_courtyards.glb
      -> src/levels/experiments/character_movement/mountain_realm_courtyards_collision.json
      -> docs/art/peak_courtyards/mountain_realm_courtyards.blend
  ... -- courtyards spawn,summit     （只建子集，用于代表性预览）
  ... -- preview                     （只渲染预览，不开 GLB）

职责边界（依据 notes/implemented/art/2026-09-18-mountain-realm-visual-rebuild.md 与派工单）：
  - 本生成器呈现现 mountain_realm_layout.json 中全部 building / roof / stairs /
    stone_lantern / bamboo_clump / jump_step 实体，形状与坐标逐项对齐既有 75 盒，留门洞；
  - 山体、大型 ground 顶面（ground_valley / *_top / *_terrace / main_plateau_30）与 9 棵松
    由 terrain 代理的 mountain_realm.glb 呈现，本文件不重复；north_plinth 属北峰亭院台基，
    由本文件呈现并在接口短报中声明；
  - 五峰庭院新增构件（门楼、灯、铺装、栏杆、亭）中需要碰撞的部分写入附加文件
    mountain_realm_courtyards_collision.json（schema peak_courtyards_collision/1），
    不改公共 layout；已由 layout 覆盖的实体不重复登记。

坐标：GLB 按 Godot 世界坐标一次导出（Y 上、北 = -Z），场景在原点实例化即可；
Blender 为 Z 上，全部顶点经 to_blender() 换算。
GLB 只含网格：预览相机/灯光/地面装饰在导出后加入 .blend，不进 GLB。
"""
from __future__ import annotations

import json
import math
import random
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCENE_DIR = ROOT / "src" / "levels" / "experiments" / "character_movement"
LAYOUT_PATH = SCENE_DIR / "mountain_realm_layout.json"
OUT_GLB = SCENE_DIR / "mountain_realm_courtyards.glb"
OUT_COLLISION = SCENE_DIR / "mountain_realm_courtyards_collision.json"
ART_DIR = ROOT / "docs" / "art" / "peak_courtyards"
COLLISION_SCHEMA = "peak_courtyards_collision/1"

# 本文件负责呈现的既有盒（前缀/精确名）。其余盒子属其它代理。
OWNED_PREFIXES = ("main_hall_", "shanmen_", "corridor_", "rail_summit", "north_pavilion_",
                  "stair_step_", "stone_lantern_", "bamboo_clump_")
OWNED_NAMES = ("jump_step", "north_plinth")

# 新增实体碰撞登记（Godot 坐标，center/size）。仅登记 layout 未覆盖的新增实体。
NEW_COLLIDERS: list[dict] = []

# 逐项记录「本文件已为哪个既有盒呈现可见几何」，用于覆盖校验（避免隐形墙）。
PRESENTED: set[str] = set()


def present(box_name):
    PRESENTED.add(box_name)
    return box_name


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
    """沿用 mountain_realm 的素材语言（同色同粗糙度，便于画面统一）。"""
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
        "cut": mat("Cut stone edges", (0.24, 0.35, 0.28)),
        "ivory": mat("Ivory paving", (0.78, 0.77, 0.64)),
        "sand": mat("Raked sand", (0.54, 0.59, 0.45)),
        "jade": mat("Celadon ceramic", (0.075, 0.24, 0.18)),
        "roof": mat("Jade roof tiles", (0.078, 0.235, 0.185)),
        "ridge": mat("Roof ridge bronze", (0.51, 0.34, 0.09), 0.45, 0.35),
        "timber": mat("Warm cedar", (0.22, 0.115, 0.053)),
        "plaster": mat("Ivory plaster wall", (0.745, 0.715, 0.625), 0.86),
        "wall": mat("Jade hall wall", (0.30, 0.42, 0.35)),
        "stepstone": mat("Step stone", (0.665, 0.645, 0.555), 0.82),
        "moss": mat("Moss", (0.22, 0.33, 0.105)),
        "leaf": mat("Bamboo leaves", (0.12, 0.29, 0.09)),
        "bamboo": mat("Bamboo stems", (0.25, 0.38, 0.12)),
        "rock_mid": mat("Granite mid", (0.215, 0.238, 0.223)),
        "gold": mat("Aged bronze", (0.51, 0.34, 0.09), 0.42, 0.35),
        "lantern": mat("Lantern paper", (0.98, 0.75, 0.37), 0.6, 0.0, 0.6),
        "lattice": mat("Lattice dark wood", (0.13, 0.075, 0.04)),
        "door": mat("Lacquer door", (0.32, 0.10, 0.07), 0.55),
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


def cbox(name, center, size, material, bevel=0.04, rotation_z=0.0, collision=False):
    """Godot 坐标的盒；size 为 Godot (x, y, z)。"""
    import bpy
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=to_blender(center))
    obj = bpy.context.object
    obj.scale = (size[0], size[2], size[1])
    if rotation_z:
        obj.rotation_euler = (0.0, 0.0, -rotation_z)
    bpy.ops.object.transform_apply(location=False, rotation=bool(rotation_z), scale=True)
    if collision:
        NEW_COLLIDERS.append({"name": name, "center": [round(v, 4) for v in center],
                              "size": [round(v, 4) for v in size]})
    return finish(obj, name, material, bevel)


def ccyl(name, center, radius, depth, material, verts=12, collision=False):
    import bpy
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=radius, depth=depth,
                                        location=to_blender(center))
    if collision:
        NEW_COLLIDERS.append({"name": name, "center": [round(v, 4) for v in center],
                              "size": [round(radius * 2.0, 4), round(depth, 4), round(radius * 2.0, 4)]})
    return finish(bpy.context.object, name, material, 0.02)


def ccone(name, center, r1, r2, depth, material, verts=10):
    import bpy
    bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r1, radius2=r2, depth=depth,
                                    location=to_blender(center))
    return finish(bpy.context.object, name, material, 0.02)


def cblob(name, center, size, material, subdivisions=2):
    import bpy
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdivisions, radius=1.0,
                                          location=to_blender(center))
    obj = bpy.context.object
    obj.scale = (size[0], size[2], size[1])
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish(obj, name, material)


def mesh_object(name, verts_godot, faces, material, thickness=0.0):
    """由 Godot 坐标顶点建面片；thickness>0 时加居中的实体化壳。"""
    import bpy
    verts = [to_blender(v) for v in verts_godot]
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(material)
    if thickness:
        mod = obj.modifiers.new("Ceramic thickness", "SOLIDIFY")
        mod.thickness = thickness
        mod.offset = 0.0
    return obj


def gable_roof(name, center_x, center_z, half_x, half_z, eave_y, ridge_y, material,
               bays=14, upturn=0.14, thickness=0.10, ridge_axis="x"):
    """双坡青瓦屋面：檐口起翘，AABB 与既有 roof 盒一致。

    ridge_axis="x"：屋脊沿 Godot X，沿 X 分条、向 Z 两侧下坡（主殿 / 山门）。
    ridge_axis="z"：屋脊沿 Godot Z，向 X 两侧下坡（沿 Z 延伸的廊台）。
    """
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
    for i in range(bays):
        a = i * 6
        faces.append((a + 1, a + 4, a + 3, a + 0))
        faces.append((a + 2, a + 5, a + 4, a + 1))
    return mesh_object(name, verts, faces, material, thickness)


def hip_roof(name, center_x, center_z, half_x, half_z, eave_y, ridge_y, material,
             thickness=0.10, upturn=0.10):
    """四坡攒尖屋面：脊心高于檐口，檐角起翘；AABB 与 roof 盒一致。"""
    cx, cz = center_x, center_z
    verts = [
        (cx - half_x, eave_y, cz - half_z), (cx + half_x, eave_y, cz - half_z),
        (cx + half_x, eave_y, cz + half_z), (cx - half_x, eave_y, cz + half_z),
        (cx, ridge_y, cz),
    ]
    faces = [(0, 1, 4), (1, 2, 4), (2, 3, 4), (3, 0, 4)]
    if upturn:
        # 檐角起翘：四角各加一小段翘头，视觉上明显但不上抬 AABB。
        for index, (sx, sz) in enumerate(((-1, -1), (1, -1), (1, 1), (-1, 1))):
            base = index
            tip = len(verts)
            verts.append((cx + sx * half_x * 1.06, eave_y + upturn, cz + sz * half_z * 1.06))
            faces.append((base, (index + 1) % 4, tip))
    return mesh_object(name, verts, faces, material, thickness)


# ---------------------------------------------------------------- 复用构件（旧庭院语言）


def stone_lantern(name, x, base_y, z, pal, scale=1.0, collision=False):
    """石灯：基座 + 灯柱 + 纸罩 + 檐盖 + 宝顶（沿用 movement_garden 构件做法）。
    collision=True 时按基座足印登记一根实体柱高（新增石灯才需要；既有 prop 盒已覆盖）。"""
    s = scale
    cbox(f"{name}_footing", (x, base_y + 0.12 * s, z), (0.80 * s, 0.24 * s, 0.80 * s), pal["stone"],
         bevel=0.05, collision=collision)
    ccyl(f"{name}_stem", (x, base_y + 0.70 * s, z), 0.155 * s, 0.95 * s, pal["cut"], verts=10)
    cbox(f"{name}_chamber", (x, base_y + 1.42 * s, z), (0.50 * s, 0.46 * s, 0.50 * s), pal["lantern"], bevel=0.02)
    for dx in (-0.26, 0.26):
        for dz in (-0.26, 0.26):
            cbox(f"{name}_frame_{'x' if dx < 0 else 'X'}{'z' if dz < 0 else 'Z'}",
                 (x + dx * s, base_y + 1.44 * s, z + dz * s),
                 (0.07 * s, 0.54 * s, 0.07 * s), pal["timber"], bevel=0.01)
    ccone(f"{name}_cap", (x, base_y + 1.80 * s, z), 0.60 * s, 0.17 * s, 0.24 * s, pal["jade"], verts=4)
    cblob(f"{name}_finial", (x, base_y + 1.98 * s, z), (0.10 * s, 0.12 * s, 0.10 * s), pal["gold"], subdivisions=1)


def bamboo_clump(name, x, base_y, z, pal, count=5, seed_name=None):
    """竹丛：多竿 + 竹节 + 尖叶（沿用 movement_garden 构件做法）。"""
    rng = random.Random(stable_seed(seed_name or name))
    cblob(f"{name}_bed", (x, base_y + 0.08, z), (1.0, 0.12, 0.95), pal["moss"], subdivisions=1)
    for k in range(count + 2):
        bx = x + rng.uniform(-0.62, 0.62)
        bz = z + rng.uniform(-0.58, 0.58)
        height = rng.uniform(3.4, 4.7)
        ccyl(f"{name}_culm_{k}", (bx, base_y + height / 2.0, bz), 0.075, height, pal["bamboo"], verts=6)
        for j in (1, 2, 3):
            ccyl(f"{name}_joint_{k}_{j}", (bx, base_y + height * j / 4.0, bz), 0.092, 0.05,
                 pal["jade"], verts=6)
        # 每竿 2–3 层尖叶簇：先尖后密，近景可辨竹冠。
        for tier, (height_ratio, spread) in enumerate(((0.62, 0.30), (0.78, 0.26), (0.92, 0.20))):
            for sign in (-1, 1):
                leaf = cblob(f"{name}_leaf_{k}_{tier}_{'w' if sign < 0 else 'e'}",
                             (bx + sign * spread, base_y + height * height_ratio, bz + rng.uniform(-0.1, 0.1)),
                             (0.5, 0.09, 0.22), pal["leaf"], subdivisions=1)
                leaf.rotation_euler = (0.0, 0.0, sign * -0.4)


def pave(prefix, cx, cz, top, nx, nz, spacing, pal, jitter=0.01):
    """石板铺装：灰米石 / 石灰岩 / 少量青苔色三色交替，避免大面积纯白。"""
    rng = random.Random(20260918)
    for ix in range(nx):
        for iz in range(nz):
            x = cx + (ix - (nx - 1) / 2.0) * spacing
            z = cz + (iz - (nz - 1) / 2.0) * spacing
            pick = (ix * 3 + iz * 5) % 7
            material = pal["stone"] if pick < 3 else (pal["stepstone"] if pick < 6 else pal["cut"])
            slab = cbox(f"{prefix}_slab_{ix}_{iz}", (x, top - 0.01, z),
                        (spacing * 0.94, 0.06, spacing * 0.94), material, bevel=0.04)
            slab.rotation_euler = (0.0, 0.0, rng.uniform(-jitter, jitter))


def wall_with_cap(name, center, size, pal, cap_material=None, collision=True):
    """矮墙：墙身 + 压顶（压顶比墙身宽 6 cm，避免共面）。"""
    cbox(name, center, size, pal["stone"], bevel=0.05, collision=collision)
    cap = cap_material or pal["ivory"]
    cbox(f"{name}_cap", (center[0], center[1] + size[1] / 2.0 + 0.05, center[2]),
         (size[0] + 0.12, 0.10, size[2] + 0.12), cap, bevel=0.03)


# ---------------------------------------------------------------- 各峰庭院


def build_spawn(boxes, pal):
    """起点庭院（前丘台顶 12 m，中心 -30,34）：门楼、矮墙、石灯、练跳石台。"""
    top = 12.0
    cx, cz = -30.0, 34.0
    pave("spawn_court", cx, cz - 1.0, top, 8, 6, 2.15, pal)
    # 练跳石台（既有 jump_step：2.2 × 0.55 × 2.2，顶 12.55）
    jump = boxes["jump_step"]
    present("jump_step")
    cbox("jump_step_body", jump["center"], jump["size"], pal["stepstone"], bevel=0.06)
    cbox("jump_step_cap", (jump["center"][0], jump["top_y"] - 0.01, jump["center"][2]),
         (jump["size"][0] * 0.96, 0.06, jump["size"][2] * 0.96), pal["ivory"], bevel=0.03)
    # 北侧院门（面向群山）：两柱 + 额枋 + 小瓦顶，中央 6 m 门洞
    # 门楼与院墙在落点净空 rect 北边缘外并留 0.4 m 余量（rect z ∈ [26,42]）。
    gate_z = cz - 9.0
    for sx, tag in ((-1, "w"), (1, "e")):
        px = cx + sx * 4.6
        cbox(f"spawn_gate_plinth_{tag}", (px, top + 0.15, gate_z), (0.95, 0.30, 0.95), pal["stone"],
             bevel=0.05, collision=True)
        cbox(f"spawn_gate_pillar_{tag}", (px, top + 1.55, gate_z), (0.62, 2.5, 0.62), pal["cut"],
             bevel=0.04, collision=True)
    cbox("spawn_gate_lintel", (cx, top + 3.02, gate_z), (10.4, 0.42, 0.7), pal["timber"], bevel=0.04)
    cbox("spawn_gate_plaque", (cx, top + 2.36, gate_z - 0.4), (2.3, 0.8, 0.12), pal["jade"], bevel=0.02)
    gable_roof("spawn_gate_roof", cx, gate_z, 5.9, 1.5, top + 3.24, top + 4.05, pal["roof"], bays=12)
    cbox("spawn_gate_ridge", (cx, top + 4.08, gate_z), (11.9, 0.14, 0.34), pal["ridge"], bevel=0.03)
    # 院墙：门洞两侧各一段，高 0.9 m，可跳可绕
    for sx, tag in ((-1, "w"), (1, "e")):
        seg_cx = cx + sx * 9.4
        wall_with_cap(f"spawn_wall_{tag}", (seg_cx, top + 0.45, gate_z), (8.4, 0.9, 0.42), pal)
    # 石灯一对（旧庭院构件语言）
    # 石灯同样留在净空外（rect 南边缘 z=42）之外的前丘台面上。
    stone_lantern("spawn_lantern_w", -38.6, top, cz + 8.6, pal, scale=1.0, collision=True)
    stone_lantern("spawn_lantern_e", -21.4, top, cz + 8.6, pal, scale=1.0, collision=True)
    # 苔石点缀（非实体）
    for i, (dx, dz, sx, sz) in enumerate(((-8.6, -5.6, 1.4, 1.2), (-1.6, -6.6, 1.1, 1.0),
                                          (7.2, -5.0, 1.5, 1.3), (8.6, 3.6, 1.2, 1.1))):
        cblob(f"spawn_moss_{i}", (cx + dx, top + 0.28, cz + dz), (sx, 0.5, sz), pal["moss"], subdivisions=2)
        cblob(f"spawn_rock_{i}", (cx + dx * 0.94, top + 0.42, cz + dz * 0.92),
              (sx * 0.72, 0.55, sz * 0.72), pal["rock_mid"], subdivisions=1)


def build_summit(boxes, pal):
    """主峰宗门（36 m 台顶）：山门、主殿、廊台、石栏、石灯、8 级台阶。"""
    top = 36.0
    # --- 8 级台阶：实体石阶 + 踏面（与既有 stair_step_* 盒逐项对齐）
    for name, b in boxes.items():
        if name.startswith("stair_step_"):
            present(name)
            cbox(name, b["center"], b["size"], pal["stepstone"], bevel=0.05)
            # 踏面顶 = 台阶顶 + 0.02：共面叠面会在 Cycles/引擎里渲染成黑块（见 mountain_realm 台账）。
            cbox(f"{name}_tread", (b["center"][0], b["top_y"] - 0.01, b["center"][2]),
                 (b["size"][0] * 0.96, 0.06, b["size"][2] * 0.96), pal["ivory"], bevel=0.02)
    # --- 主殿：台基 + 墙身（门窗分件）+ 柱梁 + 重檐
    # 台基与地板采用「贴合原 36 m 站立面」的方案（父给的备选），因此不产生任何门槛台阶，
    # 门洞 4 m 全宽可走、不侵入 summit_sect 落点净空：
    # - 地板视觉顶 = 36.0 + 0.02（比铺装惯例高 2 cm，视觉可见但不上抬碰撞面）；
    #   殿内行走面仍由 layout 的 summit_terrace 碰撞盒（36.0）承担，故不重复登记碰撞。
    # - 台基顶收到 36.0 − 0.03（低于台面 3 cm，不与台面共面闪烁），作为殿身石基座外露。
    cbox("main_hall_plinth", (4.0, top - 0.28, -51.4), (18.6, 0.5, 11.0), pal["stone"], bevel=0.08)
    cbox("main_hall_floor", (4.0, top - 0.01, -51.0), (17.2, 0.06, 11.4), pal["ivory"], bevel=0.03)
    for name, b in boxes.items():
        if name.startswith("main_hall_wall") or name == "main_hall_lintel":
            present(name)
            cbox(name, b["center"], b["size"], pal["plaster"], bevel=0.05)
    # 门：南墙 4 m 门洞处两扇门扉（半开、不挡通行），门框与门簪
    cbox("main_hall_door_frame_w", (2.0, top + 2.3, -46.5), (0.3, 4.6, 1.2), pal["timber"], bevel=0.03)
    cbox("main_hall_door_frame_e", (6.0, top + 2.3, -46.5), (0.3, 4.6, 1.2), pal["timber"], bevel=0.03)
    cbox("main_hall_door_lintel", (4.0, top + 4.6, -46.5), (4.3, 0.3, 1.2), pal["timber"], bevel=0.03)
    for sx, tag in ((-1, "w"), (1, "e")):
        cbox(f"main_hall_door_leaf_{tag}", (4.0 + sx * 1.05, top + 2.2, -47.0),
             (0.12, 4.2, 0.9), pal["door"], bevel=0.02, rotation_z=sx * 0.5)
    # 窗：北墙与山墙的直棂窗（凹入 8 cm，避免与墙面共面）
    for i, (wx, wz, rot) in enumerate(((0.8, -55.98, 0.0), (7.2, -55.98, 0.0))):
        cbox(f"main_hall_window_{i}", (wx, top + 2.9, wz), (2.6, 2.0, 0.16), pal["lattice"], bevel=0.02)
    # 侧窗必须贴在墙外侧（西墙 x∈[-4,-3]、东墙 x∈[11,12]），不能埋进墙体里。
    # 做法：细木框 + 外凸窗棂贴片（不挖真窗），窗面在外侧可见。
    for side, wall_x, tag in ((-1, -4.0, "w"), (1, 12.0, "e")):
        face_x = wall_x + side * 0.12
        cbox(f"main_hall_side_window_frame_{tag}", (face_x, top + 2.9, -51.0), (0.24, 2.1, 3.5),
             pal["timber"], bevel=0.03)
        cbox(f"main_hall_side_window_{tag}", (wall_x + side * 0.20, top + 2.9, -51.0), (0.10, 1.7, 3.0),
             pal["lattice"], bevel=0.02)
        for k in range(4):
            cbox(f"main_hall_side_mullion_{tag}_{k}", (wall_x + side * 0.27, top + 2.9, -52.35 + k * 0.9),
                 (0.06, 1.7, 0.09), pal["plaster"], bevel=0.01)
    # 正面左右窗格（门洞两侧墙面 x∈[-3,2] 与 [6,11]），近景可读的木构门窗语言。
    for side, cx in ((-1, -0.5), (1, 8.5)):
        cbox(f"main_hall_front_window_frame_{'w' if side < 0 else 'e'}", (cx, top + 2.9, -45.9),
             (3.6, 2.1, 0.24), pal["timber"], bevel=0.03)
        cbox(f"main_hall_front_window_{'w' if side < 0 else 'e'}", (cx, top + 2.9, -45.82),
             (3.1, 1.7, 0.10), pal["lattice"], bevel=0.02)
        for k in range(4):
            cbox(f"main_hall_front_mullion_{'w' if side < 0 else 'e'}_{k}",
                 (cx - 1.35 + k * 0.9, top + 2.9, -45.75), (0.09, 1.7, 0.06), pal["plaster"], bevel=0.01)
    # 檐柱与额枋：殿前四柱（新增实体，登记碰撞）
    # 檐柱与柱础是主要实体，登记碰撞；柱位全部在门洞（x ∈ [2,6]）之外，不堵门。
    for i, wx in enumerate((-0.6, 1.5, 6.5, 8.6)):
        ccyl(f"main_hall_front_column_{i}", (wx, top + 1.8, -46.1), 0.24, 3.6, pal["timber"], verts=10)
        cbox(f"main_hall_front_column_base_{i}", (wx, top + 0.66, -46.1), (0.62, 0.28, 0.62),
             pal["stone"], bevel=0.04, collision=True)
    cbox("main_hall_front_beam", (4.0, top + 3.66, -46.1), (9.0, 0.30, 0.34), pal["timber"], bevel=0.03)
    # 重檐：依既有 roof 盒（eaves 20×1.2×11 顶 42.2；upper 14×2.8×8 顶 45）
    eaves = boxes["main_hall_roof_eaves"]
    upper = boxes["main_hall_roof_upper"]
    present("main_hall_roof_eaves")
    present("main_hall_roof_upper")
    gable_roof("main_hall_roof_tiles", eaves["center"][0], eaves["center"][2],
               eaves["size"][0] / 2.0, eaves["size"][2] / 2.0,
               eaves["center"][1] - eaves["size"][1] / 2.0, eaves["top_y"], pal["roof"], bays=18)
    cbox("main_hall_roof_eave_slab", (eaves["center"][0], eaves["center"][1], eaves["center"][2]),
         (eaves["size"][0] * 0.99, eaves["size"][1] * 0.5, eaves["size"][2] * 0.99), pal["roof"], bevel=0.06)
    gable_roof("main_hall_roof_upper_tiles", upper["center"][0], upper["center"][2],
               upper["size"][0] / 2.0, upper["size"][2] / 2.0,
               upper["center"][1] - upper["size"][1] / 2.0, upper["top_y"], pal["roof"], bays=14)
    cbox("main_hall_ridge", (4.0, upper["top_y"] + 0.12, -51.0), (upper["size"][0] + 0.3, 0.24, 0.4),
         pal["ridge"], bevel=0.03)
    for sx, tag in ((-1, "w"), (1, "e")):
        ccone(f"main_hall_eave_horn_{tag}", (eaves["center"][0] + sx * (eaves["size"][0] / 2.0 - 0.2),
                                             eaves["top_y"] + 0.06, -45.6),
              0.20, 0.03, 0.26, pal["ridge"], verts=8)
    # --- 宗门大院铺装：与起点/侧峰同源灰米石板，薄 6 cm、顶面 36.02（高出承载面 2 cm，
    # 既可见又不与 36.0 平台共面），不登记碰撞（行走面仍由 summit_terrace 承载）。
    # 留出主殿占地（x −5.3..13.3, z −57.6..−45.9）、8 级台阶（x 0..8, z −36..−26）与门洞通道。
    _summit_paving(boxes, pal)
    # --- 山门（月台南缘 4,-15）：柱 + 额枋 + 匾额 + 瓦顶
    for name, b in boxes.items():
        if name.startswith("shanmen_pillar") or name == "shanmen_lintel":
            present(name)
            cbox(name, b["center"], b["size"], pal["cut"], bevel=0.05)
    cbox("shanmen_plaque", (4.0, top - 1.0, -14.62), (2.6, 0.9, 0.16), pal["jade"], bevel=0.02)
    cbox("shanmen_door_sill", (4.0, top + 0.06, -15.0), (6.4, 0.12, 1.4), pal["stone"], bevel=0.03)
    shanmen_roof = boxes["shanmen_roof"]
    present("shanmen_roof")
    gable_roof("shanmen_roof_tiles", 4.0, -15.0, shanmen_roof["size"][0] / 2.0,
               shanmen_roof["size"][2] / 2.0,
               shanmen_roof["center"][1] - shanmen_roof["size"][1] / 2.0, shanmen_roof["top_y"],
               pal["roof"], bays=12)
    cbox("shanmen_ridge", (4.0, shanmen_roof["top_y"] + 0.1, -15.0),
         (shanmen_roof["size"][0] + 0.3, 0.2, 0.36), pal["ridge"], bevel=0.03)
    # --- 廊台：铺面 + 柱 + 雀替 + 双坡瓦顶（依既有 roof 盒与柱盒）
    for side, cx in (("west", -9.5), ("east", 17.5)):
        cbox(f"corridor_{side}_deck", (cx, top + 0.12, -46.0), (3.6, 0.24, 20.0), pal["ivory"], bevel=0.05)
        # 廊台檐下净高 ≥3 m：柱顶横梁 + 雀替，不做封死的方盒。
        cbox(f"corridor_{side}_beam", (cx, top + 3.7, -46.0), (0.28, 0.28, 20.0), pal["timber"], bevel=0.03)
        for j in range(5):
            pz = -38.0 - j * 4.0
            cbox(f"corridor_{side}_spandrel_{j}", (cx, top + 3.35, pz), (0.22, 0.62, 0.9),
                 pal["timber"], bevel=0.03)
    for name, b in boxes.items():
        if name.startswith("corridor_") and "_column_" in name:
            present(name)
            cbox(name, b["center"], b["size"], pal["timber"], bevel=0.03)
            cbox(f"{name}_base", (b["center"][0], b["center"][1] - b["size"][1] / 2.0 - 0.06, b["center"][2]),
                 (0.72, 0.12, 0.72), pal["stone"], bevel=0.03)
    for side, cx in (("west", -9.5), ("east", 17.5)):
        roof = boxes[f"corridor_{side}_roof_eaves"]
        present(f"corridor_{side}_roof_eaves")
        gable_roof(f"corridor_{side}_roof_tiles", cx, -46.0, 1.85, 10.0,
                   roof["center"][1] - roof["size"][1] / 2.0, roof["top_y"], pal["roof"], bays=10,
                   ridge_axis="z")
        upper = boxes[f"corridor_{side}_roof_upper"]
        present(f"corridor_{side}_roof_upper")
        # 屋脊压在已生成的双坡瓦脊上（roof_eaves.top_y），不是上层盒顶；
        # 用上层盒顶会让金脊悬空 2 m 以上，实机读成漂浮金条。
        cbox(f"corridor_{side}_ridge", (cx, roof["top_y"] + 0.1, -46.0),
             (0.36, 0.2, roof["size"][2] + 0.2), pal["ridge"], bevel=0.03)
    # --- 石栏（既有 rail_summit_* 盒）：栏板 + 望柱
    for name, b in boxes.items():
        if not name.startswith("rail_summit"):
            continue
        present(name)
        cbox(name, b["center"], b["size"], pal["ivory"], bevel=0.04)
        length = max(b["size"][0], b["size"][2])
        along_x = b["size"][0] > b["size"][2]
        count = max(2, int(length / 3.0))
        for i in range(count):
            t = (i / (count - 1) - 0.5) if count > 1 else 0.0
            px = b["center"][0] + t * b["size"][0] if along_x else b["center"][0]
            pz = b["center"][2] if along_x else b["center"][2] + t * b["size"][2]
            ccyl(f"{name}_post_{i}", (px, b["top_y"] + 0.16, pz), 0.11, 0.42, pal["stone"], verts=8)
    # --- 石灯 1..4（台顶）与 5..6（月台）
    for name, b in boxes.items():
        if name.startswith("stone_lantern"):
            present(name)
            stone_lantern(name, b["center"][0], b["top_y"] - 2.2, b["center"][2], pal, scale=1.32)


## 主峰宗门大院的石板铺装：只铺净空，薄板高出承载面 2 cm，无碰撞。
def _summit_paving(boxes, pal):
    import random
    rng = random.Random(20260918)
    top = 36.0
    slab = 2.3
    index = 0
    # 有效铺装矩形：summit_terrace 30×20（x −11..19, z −56..−36）。
    x = -10.4
    while x < 19.0:
        z = -55.4
        while z < -36.0:
            # 避开主殿占位（含墙与檐）、台阶、门口通道。
            in_hall = -5.4 < x < 13.4 and -57.8 < z < -45.7
            in_stairs = -0.4 < x < 8.4 and z > -36.4
            in_door_lane = 1.4 < x < 6.6 and z > -46.2
            if not (in_hall or in_stairs or in_door_lane):
                pick = int((x * 3 + z * 5) % 7)
                material = pal["stone"] if pick < 3 else (pal["stepstone"] if pick < 6 else pal["cut"])
                piece = cbox(f"summit_paving_{index}", (x, top - 0.01, z),
                             (slab * 0.94, 0.06, slab * 0.94), material, bevel=0.04)
                piece.rotation_euler = (0.0, 0.0, rng.uniform(-0.012, 0.012))
                index += 1
            z += slab
        x += slab
    # 中轴石道：从台阶顶经门洞进殿，2.6 m 宽，连续可读。
    z = -45.6
    path_index = 0
    while z < -36.2:
        cbox(f"summit_path_{path_index}", (4.0, top - 0.005, z), (2.6, 0.05, 2.1),
             pal["ivory"], bevel=0.03)
        path_index += 1
        z += 2.1


def build_north(boxes, pal):
    """北峰亭院（28 m 台顶）：台基、亭柱、攒尖顶、栏杆、竹、石灯。"""
    top = 28.0
    plinth = boxes["north_plinth"]
    present("north_plinth")
    cbox("north_plinth_body", plinth["center"], plinth["size"], pal["stone"], bevel=0.05)
    cbox("north_plinth_cap", (plinth["center"][0], plinth["top_y"] - 0.02, plinth["center"][2]),
         (plinth["size"][0] - 0.2, 0.06, plinth["size"][2] - 0.2), pal["ivory"], bevel=0.03)
    pave("north_court", -46.0, -52.0, top, 5, 4, 2.3, pal)
    for name, b in boxes.items():
        if name.startswith("north_pavilion_column"):
            present(name)
            cbox(name, b["center"], b["size"], pal["timber"], bevel=0.03)
            cbox(f"{name}_base", (b["center"][0], b["center"][1] - b["size"][1] / 2.0 - 0.06, b["center"][2]),
                 (0.66, 0.12, 0.66), pal["stone"], bevel=0.03)
    cbox("north_pavilion_beam_x", (-46.0, 31.4, -58.6), (5.6, 0.24, 0.24), pal["timber"], bevel=0.03)
    cbox("north_pavilion_beam_x2", (-46.0, 31.4, -53.4), (5.6, 0.24, 0.24), pal["timber"], bevel=0.03)
    cbox("north_pavilion_beam_z", (-48.6, 31.4, -56.0), (0.24, 0.24, 5.6), pal["timber"], bevel=0.03)
    cbox("north_pavilion_beam_z2", (-43.4, 31.4, -56.0), (0.24, 0.24, 5.6), pal["timber"], bevel=0.03)
    eaves = boxes["north_pavilion_roof_eaves"]
    upper = boxes["north_pavilion_roof_upper"]
    present("north_pavilion_roof_eaves")
    present("north_pavilion_roof_upper")
    hip_roof("north_pavilion_roof_tiles", -46.0, -56.0, eaves["size"][0] / 2.0, eaves["size"][2] / 2.0,
             eaves["center"][1] - eaves["size"][1] / 2.0, upper["top_y"], pal["roof"], upturn=0.16)
    ccone("north_pavilion_finial", (-46.0, upper["top_y"] + 0.34, -56.0), 0.24, 0.0, 0.55, pal["ridge"], verts=8)
    # 亭外竹与石灯（竹沿用既有 clump 位置由通用阶段处理）
    # 北峰落点 rect z ∈ [-58,-46]：石灯放在南边缘之外的台面上，保住净空。
    stone_lantern("north_lantern_w", -50.6, top, -45.4, pal, scale=1.15, collision=True)
    stone_lantern("north_lantern_e", -41.4, top, -45.4, pal, scale=1.15, collision=True)


def build_west(boxes, pal):
    """西峰小院（20 m 台顶）：望亭 + 屏墙 + 石灯，供飞越时读出人烟。"""
    top = 20.0
    cx, cz = -70.0, -6.0
    pave("west_court", cx, cz, top, 4, 4, 2.4, pal)
    # 小型望亭：四柱 + 攒尖顶（新增实体，登记碰撞）
    for sx, sz in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
        px, pz = cx + sx * 1.9, cz + sz * 1.9
        ccyl(f"west_pavilion_column_{'w' if sx < 0 else 'e'}{'n' if sz < 0 else 's'}",
             (px, top + 1.5, pz), 0.17, 3.0, pal["timber"], verts=8, collision=True)
        cbox(f"west_pavilion_base_{'w' if sx < 0 else 'e'}{'n' if sz < 0 else 's'}",
             (px, top + 0.09, pz), (0.5, 0.18, 0.5), pal["stone"], bevel=0.03)
    cbox("west_pavilion_beam_x_n", (cx, top + 3.05, cz - 1.9), (4.4, 0.22, 0.22), pal["timber"], bevel=0.03)
    cbox("west_pavilion_beam_x_s", (cx, top + 3.05, cz + 1.9), (4.4, 0.22, 0.22), pal["timber"], bevel=0.03)
    cbox("west_pavilion_beam_z_w", (cx - 1.9, top + 3.05, cz), (0.22, 0.22, 4.4), pal["timber"], bevel=0.03)
    cbox("west_pavilion_beam_z_e", (cx + 1.9, top + 3.05, cz), (0.22, 0.22, 4.4), pal["timber"], bevel=0.03)
    hip_roof("west_pavilion_roof", cx, cz, 2.5, 2.5, top + 3.2, top + 4.15, pal["roof"], upturn=0.18)
    ccone("west_pavilion_finial", (cx, top + 4.38, cz), 0.2, 0.0, 0.45, pal["ridge"], verts=8)
    # 西侧屏墙（可跳，登记碰撞）
    # 屏墙避开西峰既有竹丛 (-74,-2)：缩短并南移到 z ∈ [-8.6,-2.6]。
    wall_with_cap("west_screen_wall", (cx - 5.6, top + 0.5, cz - 0.6), (0.45, 1.0, 6.0), pal)
    stone_lantern("west_lantern_n", cx + 0.6, top, cz - 4.2, pal, scale=1.1, collision=True)
    stone_lantern("west_lantern_s", cx - 2.6, top, cz + 4.2, pal, scale=1.1, collision=True)


def build_east(boxes, pal):
    """东岭小院（16 m 台顶）：石桌 + 石灯 + 短墙，狭长横岭上的一处歇脚点。"""
    top = 16.0
    cx, cz = 56.0, 20.0
    pave("east_court", cx, cz, top, 5, 3, 2.25, pal)
    cbox("east_table_top", (cx, top + 0.78, cz), (1.9, 0.16, 1.9), pal["ivory"], bevel=0.05, collision=True)
    for sx, sz in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
        cbox(f"east_table_leg_{'w' if sx < 0 else 'e'}{'n' if sz < 0 else 's'}",
             (cx + sx * 0.65, top + 0.39, cz + sz * 0.65), (0.22, 0.78, 0.22), pal["stone"], bevel=0.03)
    for i, sx in enumerate((-1, 1)):
        cbox(f"east_stool_{i}", (cx + sx * 1.7, top + 0.26, cz), (0.62, 0.52, 0.62), pal["cut"], bevel=0.05)
    wall_with_cap("east_wall_n", (cx + 5.0, top + 0.5, cz - 5.0), (7.0, 1.0, 0.42), pal)
    wall_with_cap("east_wall_s", (cx - 5.0, top + 0.5, cz + 5.0), (7.0, 1.0, 0.42), pal)
    # 小院也要有屋：一座可穿行的单开间敞轩（柱 + 梁 + 双坡瓦顶），不是只摆桌子。
    for sx, tag in ((-1, "w"), (1, "e")):
        cbox(f"east_shelter_plinth_{tag}", (cx + sx * 2.4, top + 0.14, cz + 3.6), (0.7, 0.28, 0.7),
             pal["stone"], bevel=0.04, collision=True)
        cbox(f"east_shelter_column_{tag}", (cx + sx * 2.4, top + 1.5, cz + 3.6), (0.34, 2.7, 0.34),
             pal["timber"], bevel=0.03, collision=True)
    cbox("east_shelter_beam_n", (cx, top + 2.9, cz + 3.6), (5.4, 0.24, 0.28), pal["timber"], bevel=0.03)
    cbox("east_shelter_beam_s", (cx, top + 2.9, cz + 2.6), (5.4, 0.24, 0.28), pal["timber"], bevel=0.03)
    cbox("east_shelter_beam_w", (cx - 3.1, top + 2.9, cz + 3.1), (0.26, 0.24, 1.8), pal["timber"], bevel=0.03)
    cbox("east_shelter_beam_e", (cx + 3.1, top + 2.9, cz + 3.1), (0.26, 0.24, 1.8), pal["timber"], bevel=0.03)
    gable_roof("east_shelter_roof", cx, cz + 3.1, 3.5, 1.8, top + 3.02, top + 3.85, pal["roof"], bays=12)
    cbox("east_shelter_ridge", (cx, top + 3.88, cz + 3.1), (7.1, 0.18, 0.34), pal["ridge"], bevel=0.03)
    # 歇脚石与苔石，让院内不空。
    for i, (dx, dz) in enumerate(((-3.4, -2.0), (3.4, -2.0), (-1.6, -3.6))):
        cbox(f"east_bench_{i}", (cx + dx, top + 0.26, cz + dz), (1.5, 0.52, 0.6), pal["cut"], bevel=0.05,
             collision=True)
        cblob(f"east_moss_{i}", (cx + dx * 1.15, top + 0.2, cz + dz * 1.25), (1.0, 0.42, 0.9),
              pal["moss"], subdivisions=1)
    stone_lantern("east_lantern_w", cx - 7.4, top, cz - 3.0, pal, scale=1.15, collision=True)
    stone_lantern("east_lantern_e", cx + 7.4, top, cz + 3.0, pal, scale=1.15, collision=True)


def build_props(boxes, pal):
    """石灯 1..6 与竹丛 1..5：按既有 prop 盒逐项对齐（有盒必有所见）。"""
    for name, b in boxes.items():
        if name.startswith("bamboo_clump"):
            present(name)
            bamboo_clump(name, b["center"][0], b["top_y"] - b["size"][1], b["center"][2], pal,
                         count=4, seed_name=name)


# ---------------------------------------------------------------- 装配与导出


def owned_names(boxes):
    """本文件负责呈现的既有盒：按 role 判定，不只看名字前缀。

    role=ground 的大型承载面（含 shanmen_terrace 这类名字带前缀但属山体/地面的盒）
    归 mountain_art；ground 里归本文件的只有 jump_step 与 north_plinth 两个小台。
    """
    result = {}
    for name, b in boxes.items():
        role = b.get("role")
        if name in OWNED_NAMES:
            result[name] = b
        elif role in ("building", "roof", "stairs"):
            result[name] = b
        elif role == "prop" and (name.startswith("stone_lantern") or name.startswith("bamboo_clump")):
            result[name] = b
    return result


def build_all(selected, layout, pal):
    boxes = {b["name"]: b for b in layout["boxes"]}
    owned = owned_names(boxes)
    builders = {
        "spawn": lambda: build_spawn(boxes, pal),
        "summit": lambda: build_summit(boxes, pal),
        "north": lambda: build_north(boxes, pal),
        "west": lambda: build_west(boxes, pal),
        "east": lambda: build_east(boxes, pal),
        "props": lambda: build_props(boxes, pal),
    }
    built_names = set()
    for key in selected:
        if key == "preview":
            continue
        builders[key]()
        # 归属标记：供导出前按「庭院分组 × 类别 × 材质」合并静态网格。
        for obj in bpy_objects():
            if "courtyard_group" not in obj:
                obj["courtyard_group"] = key
    # 覆盖校验：选中的分组必须让每个“本文件负责”的盒子都有可见几何。
    if set(selected) >= {"spawn", "summit", "north", "west", "east", "props"}:
        missing = sorted(set(owned) - PRESENTED)
        # 本文件只呈现，不生成碰撞盒；除 jump_step / north_plinth 外都已有 layout 盒。
        if missing:
            print("MISSING_OWNED_BOXES", missing)
            raise SystemExit(2)
        roles = {}
        for name in owned:
            roles[boxes[name]["role"]] = roles.get(boxes[name]["role"], 0) + 1
        print("COVERAGE ok owned=%d presented=%d roles=%s" % (len(owned), len(PRESENTED), roles))
    return owned


def bpy_objects():
    import bpy
    return bpy.context.scene.objects


def check_landing_clearance(layout):
    """新增碰撞盒不得侵入任何落点净空 rect（XZ 平面 AABB 相交判据）。

    落点高度处的新增实体都会改变「真实降落」的落面，破坏既有验收；这里机械拦住。
    north_plinth 属既有台基盒，不在新增清单里，天然豁免。
    """
    problems = []
    for point in layout["landing_points"]:
        cx, cz = float(point["center"][0]), float(point["center"][1])
        half_x, half_z = float(point["size"][0]) / 2.0, float(point["size"][1]) / 2.0
        for box in NEW_COLLIDERS:
            bx, by, bz = box["center"]
            sx, sy, sz = box["size"]
            overlap_x = abs(bx - cx) < half_x + sx / 2.0
            overlap_z = abs(bz - cz) < half_z + sz / 2.0
            tall_enough = by + sy / 2.0 > float(point["top_y"]) - 0.1
            if overlap_x and overlap_z and tall_enough:
                problems.append((point["name"], box["name"]))
    if problems:
        print("LANDING_CLEARANCE_FAIL", problems)
        raise SystemExit(3)
    print("LANDING_CLEARANCE ok landing_points=%d new_colliders=%d"
          % (len(layout["landing_points"]), len(NEW_COLLIDERS)))


def write_collision():
    """附加碰撞 JSON。子集构建只用于预览，不覆盖全量文件。"""
    payload = {"schema": COLLISION_SCHEMA, "generated_by": "tools/art/generate_peak_courtyards.py",
               "units": "meters", "up_axis": "Y", "boxes": NEW_COLLIDERS}
    OUT_COLLISION.write_text(json.dumps(payload, ensure_ascii=False, indent=1), encoding="utf-8")
    print("COLLISION", OUT_COLLISION, len(NEW_COLLIDERS))


def slug(text):
    return "".join(ch if ch.isalnum() else "_" for ch in text).strip("_").lower()


## 统一朝外法线：from_pydata 的环绕方向不保证，朝内时 Cycles/引擎会渲染成黑块
## （mountain_realm 台账已记录该根因）。所有生成网格在导出与合并前统一重算。
def recalc_normals(objects):
    import bmesh as _bmesh
    import bpy
    fixed = 0
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
        fixed += 1
    print("NORMALS recalculated on %d meshes" % fixed)


def evaluated_totals(objects):
    """求值后的（网格数, 三角形数, 包围盒）——用于合并前后的等价性核对。"""
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


## 导出副本合并：按主材质把所有零件烘焙后合成一个多材质网格。
## 只作用于副本，.blend 里的可编辑分件原样保留；世界坐标不变（合并后 apply 变换）。
## 目的：把 700+ MeshInstance 降到「材质数」量级，减少 drawcall。
def build_merged_copies(sources):
    import bpy
    buckets = {}
    for obj in sources:
        material = obj.data.materials[0] if obj.data.materials else None
        key = material.name if material is not None else "NoMaterial"
        buckets.setdefault(key, []).append(obj)
    merged = []
    for key, objs in sorted(buckets.items()):
        copies = []
        for src in objs:
            dup = src.copy()
            dup.data = src.data.copy()
            bpy.context.collection.objects.link(dup)
            bpy.ops.object.select_all(action="DESELECT")
            dup.select_set(True)
            bpy.context.view_layer.objects.active = dup
            # 先把修改器（Bevel / Solidify）烘焙到复制体，再合并，避免合并后修改器串味。
            bpy.ops.object.convert(target="MESH")
            copies.append(bpy.context.view_layer.objects.active)
        bpy.ops.object.select_all(action="DESELECT")
        for dup in copies:
            dup.select_set(True)
        bpy.context.view_layer.objects.active = copies[0]
        bpy.ops.object.join()
        joined = bpy.context.view_layer.objects.active
        joined.name = f"courtyards_{slug(key)}"
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        merged.append(joined)
    return merged


def stage_courtyards(selected):
    import bpy
    for obj in list(bpy.context.scene.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    pal = make_palette()
    layout = json.loads(LAYOUT_PATH.read_text(encoding="utf-8"))
    build_all(selected, layout, pal)
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    recalc_normals(meshes)
    # 合并前后等价性核对：三角形数与包围盒必须一致（容差 1e-3）。
    tris_before, lo_before, hi_before = evaluated_totals(meshes)
    merged = build_merged_copies(meshes)
    tris_after, lo_after, hi_after = evaluated_totals(merged)
    box_delta = max(abs(a - b) for a, b in zip(lo_before + hi_before, lo_after + hi_after))
    if tris_after != tris_before or box_delta > 1e-3:
        print("MERGE_MISMATCH tris %d -> %d bbox_delta=%.6f" % (tris_before, tris_after, box_delta))
        raise SystemExit(4)
    print("MERGE ok objects %d -> %d tris=%d bbox_delta=%.6f materials=%d"
          % (len(meshes), len(merged), tris_after, box_delta, len(merged)))
    bpy.ops.object.select_all(action="DESELECT")
    for o in merged:
        o.select_set(True)
    bpy.context.view_layer.objects.active = merged[0]
    OUT_GLB.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=str(OUT_GLB), export_format="GLB", use_selection=True,
                              export_apply=True, export_yup=True)
    # 合并体只用于导出：删除后 .blend 里保留可编辑分件。
    for o in merged:
        bpy.data.objects.remove(o, do_unlink=True)
    bpy.ops.object.select_all(action="DESELECT")
    print("EDITABLE parts kept in .blend: %d" % len([o for o in bpy.context.scene.objects if o.type == "MESH"]))
    if len(selected) == len([g for g in ("spawn", "summit", "north", "west", "east", "props")
                             if g in selected]) and len(selected) == 6:
        layout = json.loads(LAYOUT_PATH.read_text(encoding="utf-8"))
        check_landing_clearance(layout)
        write_collision()
    else:
        print("SUBSET_BUILD 跳过覆盖附加碰撞 JSON（仅预览子集）")
    ART_DIR.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(ART_DIR / "mountain_realm_courtyards.blend"))
    print("EXPORTED", OUT_GLB, "meshes=%d colliders=%d" % (len(meshes), len(NEW_COLLIDERS)))


## 预览装置：承载台面 + 灯光 + 相机。只进 .blend 预览，永不进 GLB（名字带 PREVIEW_）。
def add_preview_rig():
    import bpy
    from mathutils import Vector
    preview_ground = make_palette()
    layout = json.loads(LAYOUT_PATH.read_text(encoding="utf-8"))
    preview_tops = {
        "front_mesa_top": "rock_mid",
        "main_plateau_30": "rock_mid",
        "summit_terrace": "stepstone",
        "north_peak_top": "rock_mid",
        "west_peak_top": "rock_mid",
        "east_ridge_top": "rock_mid",
    }
    for box in layout["boxes"]:
        if box["name"] not in preview_tops:
            continue
        cbox(f"PREVIEW_ground_{box['name']}", (box["center"][0], box["center"][1] - 0.35, box["center"][2]),
             (box["size"][0], box["size"][1], box["size"][2]), preview_ground[preview_tops[box["name"]]],
             bevel=0.15)
    bpy.ops.object.light_add(type="SUN", location=(20.0, 40.0, 50.0))
    sun = bpy.context.object
    sun.data.angle = 0.14
    sun.data.energy = 3.0
    sun.rotation_euler = (Vector((0.0, 0.0, 0.0)) - sun.location).to_track_quat("-Z", "Y").to_euler()
    bpy.ops.object.light_add(type="AREA", location=(-30.0, 40.0, 50.0))
    fill = bpy.context.object
    fill.data.energy = 24000.0
    fill.data.shape = "DISK"
    fill.data.size = 60.0
    bpy.ops.object.camera_add(location=(0.0, 0.0, 0.0))
    bpy.context.scene.camera = bpy.context.object


def stage_preview(tag=""):
    import bpy
    from mathutils import Vector
    scene = bpy.context.scene
    # 相机与看点都用 Godot 世界坐标声明，只在此处换算一次；避免双重换算导致空镜。
    shots = [
        ("spawn", (-48.0, 26.0, 60.0), (-30.0, 13.0, 34.0), 26.0),
        ("summit", (-22.0, 58.0, -18.0), (4.0, 37.0, -48.0), 52.0),
        ("north", (-64.0, 40.0, -30.0), (-46.0, 29.0, -53.0), 24.0),
        ("west", (-84.0, 34.0, 16.0), (-70.0, 20.0, -6.0), 22.0),
        ("east", (44.0, 30.0, 40.0), (56.0, 16.0, 20.0), 26.0),
        # 主殿侧前近景：核对门洞、正面窗格、侧窗与檐柱是否可读。
        ("hall_front", (14.0, 42.0, -34.0), (4.0, 38.5, -47.5), 22.0),
    ]
    world = scene.world or bpy.data.worlds.new("CourtyardSky")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    bg.inputs[0].default_value = (0.55, 0.66, 0.74, 1.0)
    bg.inputs[1].default_value = 0.9
    scene.view_settings.view_transform = "Standard"
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 16
    scene.cycles.use_denoising = True
    scene.render.resolution_x = 900
    scene.render.resolution_y = 600
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    cam = scene.camera
    assert cam is not None, "预览相机必须由 add_preview_rig() 先建好"
    ART_DIR.mkdir(parents=True, exist_ok=True)
    for name, cam_godot, look_godot, size in shots:
        cam.location = to_blender(cam_godot)
        direction = Vector(to_blender(look_godot)) - Vector(cam.location)
        cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
        cam.data.type = "ORTHO"
        cam.data.ortho_scale = size
        suffix = f"_{tag}" if tag else ""
        out = ART_DIR / f"courtyards_preview_{name}{suffix}.png"
        scene.render.filepath = str(out)
        bpy.ops.render.render(write_still=True)
        print("PREVIEW", out)
    return 0


def main(argv):
    stage = argv[0] if argv else "courtyards"
    groups = ["spawn", "summit", "north", "west", "east", "props"]
    selected = groups
    if stage.endswith(":") or ":" in stage:
        stage, extra = stage.split(":", 1)
        selected = [g for g in extra.split(",") if g]
    elif len(argv) > 1:
        selected = [g for g in argv[1].split(",") if g]
    if stage == "courtyards":
        stage_courtyards([g for g in selected if g != "preview"])
        if "preview" in selected:
            add_preview_rig()
            stage_preview("")
            # 保存含预览相机/灯光的源文件（GLB 已在预览之前导出，不含它们）。
            bpy.ops.wm.save_as_mainfile(filepath=str(ART_DIR / "mountain_realm_courtyards.blend"))
        return 0
    if stage == "preview":
        if not list(o for o in bpy_objects() if o.type == "MESH"):
            print("NO_MESH：请先在同一进程运行 courtyards 阶段，或直接运行 courtyards 阶段（会一并渲染预览）")
            return 3
        if bpy.context.scene.camera is None:
            add_preview_rig()
        return stage_preview("")
    raise SystemExit(f"未知阶段 {stage!r}；可用：courtyards / preview")


if __name__ == "__main__":
    import bpy  # noqa: F401
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    code = main(args)
    if code:
        sys.exit(code)
