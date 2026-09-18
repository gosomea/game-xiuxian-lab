"""生成群山宗门布局 JSON 与 Blender 资产（全部为程序原创几何，无外部素材）。

阶段（每阶段一个独立短进程，在仓库根运行）：
  python3 tools/art/generate_mountain_realm.py layout
      -> src/levels/experiments/character_movement/mountain_realm_layout.json（坐标真源，含校验）
  /Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup \
      --python tools/art/generate_mountain_realm.py -- terrain
      -> .../mountain_realm.glb + docs/art/mountain_realm/mountain_realm.blend
  ... -- collision -> .../mountain_realm_collision.glb（每峰 PascalCase 节点）
  ... -- sword     -> src/game/abilities/sword_flight/models/flying_sword.glb
  ... -- preview   -> docs/art/mountain_realm/mountain_realm_preview.png（Cycles）

轴向：JSON 为 Godot 原生（Y 上、-Z 为北）；Blender 为 Z 上。本脚本内所有 Blender 坐标
都经 to_blender() 换算，视觉、碰撞、JSON 共用同一组轮廓参数，避免错位。
"""
from __future__ import annotations

import json
import math
import sys

bmesh = None  # 由 Blender 阶段在运行时 import 注入（Blender 自带模块，非仓库依赖）
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCENE_DIR = ROOT / "src" / "levels" / "experiments" / "character_movement"
SWORD_DIR = ROOT / "src" / "game" / "abilities" / "sword_flight" / "models"
ART_DIR = ROOT / "docs" / "art" / "mountain_realm"

LAYOUT_PATH = SCENE_DIR / "mountain_realm_layout.json"
VISUAL_GLB = SCENE_DIR / "mountain_realm.glb"
COLLISION_GLB = SCENE_DIR / "mountain_realm_collision.glb"
SWORD_GLB = SWORD_DIR / "flying_sword.glb"

SCHEMA = "mountain_realm_layout/1"
BOUNDS = {
    "min": [-90.0, -6.0, -80.0],
    "max": [90.0, 60.0, 80.0],
    "fall_out_y": -6.0,
    "limit_mode": "scene_collision_walls_and_ceiling",
}
SPAWN = {"position": [-30.0, 12.02, 34.0], "yaw_deg": 0.0, "landing_point": "spawn_courtyard"}
ROLES = ("ground", "mountain", "building", "roof", "stairs", "prop")

# 可选预览标签：参数 preview v3 输出 mountain_realm_preview_v3.png；缺省 _v2。
PREVIEW_TAG = ""

# ---------------------------------------------------------------- 山体轮廓（真源）
# 每峰一个碰撞对象；rings 为 Godot 坐标 (top_y, center_x, center_z, half_x, half_z)。
# 主峰分两个壳：0->30 山肩（顶环覆盖月台与台阶起点），30->36 高台实体（只在台阶以北），
# 因此月台与 30->36 台阶不会被封盖。北峰壳内含两处岩肩。
COLLISION_RING_SEGMENTS = 20
# 壳顶下沉量：平台盒顶面严格等于 JSON top_y，壳顶藏在其下，避免共面闪烁。
PLATFORM_INSET = 0.05
# 岩壁折面：每个轮廓环共用同一组棱线相位，形成连续纵向棱脊，而非每层独立光滑圆环。
RIDGE_PHASE = [0.00, 0.55, 1.30, 2.05, 2.75, 3.35, 4.10, 4.75, 5.40, 6.00]
# 每条棱线相对基准半径的收放；负值=岩沟，正值=凸脊（米，作用于当环半轴）。
RIDGE_GAIN = [-2.60, 1.70, -1.35, 2.60, -1.90, 1.45, -2.20, 2.35, -1.15, 1.95]
# 每层可见性的外扩/内收（m），让轮廓环之间出现折面与平台岩阶。
LEDGE_GAIN = [1.15, -0.7, 1.0, -1.05, 0.85, -0.6, 0.9, -0.8, 0.65, -0.5, 0.45, -0.35]

# 台阶：月台 30 -> 宗门台 36，8 段实体盒，单级抬升 0.75 m（跳速 6 / 重力 18 顶点 1.0 m）。
STAIR_W = 8.0
STAIR_RUN = 1.25
STAIR_RISE = 0.75
STAIR_BASE_Z = -26.0


def clamp01(value, low, high):
    """把 value 限制在 [low, high]；用于岩壁半径，防止折面自交。"""
    return max(low, min(high, value))


def stable_seed(text):
    """跨进程稳定的种子：字符码累加（内置 hash() 受 PYTHONHASHSEED 影响，不可复现）。"""
    value = 7
    for ch in str(text):
        value = (value * 131 + ord(ch)) % 2147483647
    return value


def box(name, role, center, size, solid=True, note=None):
    """最小盒子实体：center/size 为 Godot 坐标，top_y 恒等于 center.y + size.y/2。"""
    assert role in ROLES, f"非法 role: {role}"
    cx, cy, cz = center
    sx, sy, sz = size
    item = {
        "name": name, "role": role,
        "center": [round(cx, 3), round(cy, 3), round(cz, 3)],
        "size": [round(sx, 3), round(sy, 3), round(sz, 3)],
        "top_y": round(cy + sy / 2.0, 3),
        "solid": bool(solid),
    }
    if note:
        item["note"] = note
    return item


def build_boxes():
    b = []
    # --- 谷底与各峰台顶（站立面）
    b.append(box("ground_valley", "ground", (0, -0.5, 0), (180, 1, 160)))
    b.append(box("front_mesa_top", "ground", (-30, 11.0, 34), (42, 2, 34)))
    b.append(box("main_plateau_30", "ground", (4, 29.0, -35), (32, 2, 42)))
    # 顶面 30.02 而非 30.00：与 main_plateau_30 顶面错开 2 cm，避免共面导致 Cycles 自阴影全黑。
    b.append(box("shanmen_terrace", "ground", (4, 29.02, -20), (24, 2, 12)))
    b.append(box("summit_terrace", "ground", (4, 35.0, -46), (30, 2, 20)))
    b.append(box("north_peak_top", "ground", (-46, 27.0, -52), (26, 2, 22)))
    b.append(box("west_peak_top", "ground", (-70, 19.0, -6), (16, 2, 16)))
    b.append(box("east_ridge_top", "ground", (56, 15.0, 20), (30, 2, 18)))
    # --- 起点庭院练跳石台（0.55 m）
    b.append(box("jump_step", "ground", (-35.5, 12.275, 30.0), (2.2, 0.55, 2.2),
                 note="练跳石台：顶面 12.55，抬升 0.55；跳速 6 / 重力 18 顶点 1.0"))
    # --- 台阶（月台 30 -> 宗门台 36）
    for i in range(8):
        top = 30.0 + STAIR_RISE * (i + 1)
        cz = STAIR_BASE_Z - STAIR_RUN * (i + 0.5)
        b.append(box(f"stair_step_{i + 1}", "stairs", (4.0, top - 1.0, cz),
                     (STAIR_W, 2.0, STAIR_RUN), note="单级抬升 0.75，需起跳（顶点 1.0）"))
    # --- 青瓦主殿：分段墙体 + 真实门洞 + 重檐屋顶（无整栋实心盒）
    b.append(box("main_hall_wall_north", "building", (4.0, 38.5, -55.5), (16.0, 5.0, 1.0)))
    b.append(box("main_hall_wall_west", "building", (-3.5, 38.5, -51.0), (1.0, 5.0, 9.0)))
    b.append(box("main_hall_wall_east", "building", (11.5, 38.5, -51.0), (1.0, 5.0, 9.0)))
    b.append(box("main_hall_wall_south_a", "building", (-1.0, 38.5, -46.5), (6.0, 5.0, 1.0)))
    b.append(box("main_hall_wall_south_b", "building", (9.0, 38.5, -46.5), (6.0, 5.0, 1.0)))
    b.append(box("main_hall_lintel", "building", (4.0, 40.5, -46.5), (4.0, 1.0, 1.0),
                 note="门洞上方：洞高 36->40，宽 4（x 2..6）"))
    b.append(box("main_hall_roof_eaves", "roof", (4.0, 41.6, -51.0), (20.0, 1.2, 11.0)))
    b.append(box("main_hall_roof_upper", "roof", (4.0, 43.6, -51.0), (14.0, 2.8, 8.0)))
    # --- 山门（月台南缘，中央 5.8 m 门洞）
    b.append(box("shanmen_pillar_west", "building", (0.5, 33.0, -15.0), (1.2, 6.0, 1.2)))
    b.append(box("shanmen_pillar_east", "building", (7.5, 33.0, -15.0), (1.2, 6.0, 1.2)))
    b.append(box("shanmen_lintel", "building", (4.0, 35.0, -15.0), (6.4, 2.0, 1.0)))
    b.append(box("shanmen_roof", "roof", (4.0, 36.75, -15.0), (10.0, 1.5, 4.0)))
    # --- 东西廊台：柱 + 双坡瓦顶，檐下净高 4 m 可穿行
    for side, cx in (("west", -9.5), ("east", 17.5)):
        b.append(box(f"corridor_{side}_roof_eaves", "roof", (cx, 40.4, -46.0), (3.6, 0.8, 20.0)))
        b.append(box(f"corridor_{side}_roof_upper", "roof", (cx, 41.9, -46.0), (2.4, 2.2, 20.0)))
        for z in (-38.0, -42.0, -46.0, -50.0, -54.0):
            b.append(box(f"corridor_{side}_column_{abs(int(z))}", "building", (cx, 38.0, z),
                         (0.6, 4.0, 0.6)))
    # --- 宗门台石栏（南面留 6 m 门洞对台阶）
    b.append(box("rail_summit_south_west", "building", (-5.5, 36.7, -36.0), (11.0, 1.4, 0.4)))
    b.append(box("rail_summit_south_east", "building", (13.5, 36.7, -36.0), (11.0, 1.4, 0.4)))
    b.append(box("rail_summit_north", "building", (4.0, 36.7, -56.0), (30.0, 1.4, 0.4)))
    b.append(box("rail_summit_west", "building", (-11.0, 36.7, -46.0), (0.4, 1.4, 20.0)))
    b.append(box("rail_summit_east", "building", (19.0, 36.7, -46.0), (0.4, 1.4, 20.0)))
    # --- 北峰小庭院：0.4 m 台基 + 四柱亭 + 双坡顶
    b.append(box("north_plinth", "ground", (-46.0, 28.2, -56.0), (7.0, 0.4, 7.0)))
    for dx in (-2.6, 2.6):
        for dz in (-2.6, 2.6):
            b.append(box(f"north_pavilion_column_{'w' if dx < 0 else 'e'}{'n' if dz < 0 else 's'}",
                         "building", (-46.0 + dx, 30.0, -56.0 + dz), (0.4, 3.2, 0.4)))
    b.append(box("north_pavilion_roof_eaves", "roof", (-46.0, 31.9, -56.0), (8.0, 0.6, 8.0)))
    b.append(box("north_pavilion_roof_upper", "roof", (-46.0, 32.8, -56.0), (5.6, 1.2, 5.6)))
    # --- 石灯（近地灯柱实心）
    for i, (x, z, top) in enumerate([(-8.5, -42.0, 36), (16.5, -42.0, 36), (-8.5, -48.0, 36),
                                     (16.5, -48.0, 36), (0.0, -16.0, 30), (8.0, -16.0, 30)]):
        b.append(box(f"stone_lantern_{i + 1}", "prop", (x, top + 1.1, z), (0.5, 2.2, 0.5),
                     note="仅灯柱实心，灯罩不碰撞"))
    # --- 松（仅树干实心）
    for i, (x, z, top, h) in enumerate([(-41.0, 30.0, 12, 3.6), (-19.0, 30.0, 12, 4.0),
                                        (-41.0, 40.0, 12, 3.2), (-19.0, 40.0, 12, 3.8),
                                        (-5.0, -53.0, 36, 4.2), (13.0, -53.0, 36, 3.8),
                                        (-52.0, -46.0, 28, 3.6), (-40.0, -46.0, 28, 3.2),
                                        (-52.0, -58.0, 28, 3.9)]):
        b.append(box(f"pine_trunk_{i + 1}", "prop", (x, top + h / 2.0, z), (0.5, h, 0.5),
                     note="仅树干实心，树冠不碰撞"))
    # --- 竹丛（仅近地丛芯实心）
    for i, (x, z, top) in enumerate([(-74.0, -2.0, 20), (-66.0, -10.0, 20), (-34.0, 42.0, 12),
                                     (-25.0, 25.0, 12), (-46.0, -62.0, 28)]):
        b.append(box(f"bamboo_clump_{i + 1}", "prop", (x, top + 1.6, z), (0.7, 3.2, 0.7),
                     note="仅丛芯实心，竹叶不碰撞"))
    return b


def build_layout():
    boxes = build_boxes()
    layout = {
        "schema": SCHEMA,
        "generated_by": "tools/art/generate_mountain_realm.py layout",
        "units": "meters",
        "up_axis": "Y",
        "blender_to_godot": "godot = (bx, bz, -by)",
        "bounds": BOUNDS,
        "spawn": SPAWN,
        "landing_points": [
            {"name": "spawn_courtyard", "top_y": 12.0, "center": [-30.0, 34.0], "size": [20.0, 16.0],
             "peak": "front_mesa"},
            {"name": "summit_sect", "top_y": 36.0, "center": [4.0, -41.0], "size": [22.0, 9.0],
             "peak": "main_peak"},
            {"name": "north_pavilion", "top_y": 28.0, "center": [-46.0, -52.0], "size": [14.0, 12.0],
             "peak": "north_peak"},
        ],
        "collision": {
            "mode": "visual_glb + separate_trimesh_shell",
            "shell_glb": "res://levels/experiments/character_movement/mountain_realm_collision.glb",
            "ring_segments": COLLISION_RING_SEGMENTS,
            "top_surface_rule": "box.top_y 同时是视觉顶面与站立面高度；boxes 每项都是实体，场景不得按标记挖空",
            # 五峰碰撞节点与台顶真源：地形重建后由高度场按最近峰分面，
            # 节点名与关键台顶保持不变（景观与碰撞同源采样）。
            "mountains": [
                {"name": "main_peak", "node": "MainPeakCol", "top_y": 36.0,
                 "drive_boxes": ["summit_terrace", "main_plateau_30", "shanmen_terrace"],
                 "landing_point": "summit_sect"},
                {"name": "north_peak", "node": "NorthPeakCol", "top_y": 28.0,
                 "drive_boxes": ["north_peak_top"], "landing_point": "north_pavilion"},
                {"name": "west_peak", "node": "WestPeakCol", "top_y": 20.0,
                 "drive_boxes": ["west_peak_top"], "landing_point": None},
                {"name": "east_ridge", "node": "EastRidgeCol", "top_y": 16.0,
                 "drive_boxes": ["east_ridge_top"], "landing_point": None},
                {"name": "front_mesa", "node": "FrontMesaCol", "top_y": 12.0,
                 "drive_boxes": ["front_mesa_top"], "landing_point": "spawn_courtyard"},
            ],
            "wall_coverage": "高度场按最近峰分面，五节点合起来覆盖整片可走谷地与山面",
        },
        "boxes": boxes,
        "decor": [],  # 旧云层/漂浮石已退役，地形不再生成
    }
    return layout


def validate(layout):
    problems = []
    boxes = layout["boxes"]
    names = [b["name"] for b in boxes]
    if len(names) != len(set(names)):
        problems.append("boxes 名称重复")
    for b in boxes:
        cx, cy, cz = b["center"]
        sx, sy, sz = b["size"]
        if abs(b["top_y"] - (cy + sy / 2.0)) > 1e-6:
            problems.append(f"{b['name']}: top_y 与 center/size 不符")
        if b["role"] not in ROLES:
            problems.append(f"{b['name']}: role 非法 {b['role']}")
        lo, hi = layout["bounds"]["min"], layout["bounds"]["max"]
        if not (lo[0] <= cx - sx / 2 and cx + sx / 2 <= hi[0]):
            problems.append(f"{b['name']}: X 越界")
        if not (lo[2] <= cz - sz / 2 and cz + sz / 2 <= hi[2]):
            problems.append(f"{b['name']}: Z 越界")
        if cy - sy / 2 < lo[1] - 1e-6 or cy + sy / 2 > hi[1] + 1e-6:
            problems.append(f"{b['name']}: Y 越界")

    def rect(cx, cz, sx, sz):
        return (cx - sx / 2, cx + sx / 2, cz - sz / 2, cz + sz / 2)

    ground = [b for b in boxes if b["role"] == "ground"]
    for lp in layout["landing_points"]:
        cx, cz = lp["center"]
        sx, sz = lp["size"]
        r = rect(cx, cz, sx, sz)
        host = [b for b in ground
                if abs(b["top_y"] - lp["top_y"]) < 1e-6
                and rect(b["center"][0], b["center"][2], b["size"][0], b["size"][2])[0] <= r[0]
                and rect(b["center"][0], b["center"][2], b["size"][0], b["size"][2])[1] >= r[1]
                and rect(b["center"][0], b["center"][2], b["size"][0], b["size"][2])[2] <= r[2]
                and rect(b["center"][0], b["center"][2], b["size"][0], b["size"][2])[3] >= r[3]]
        if not host:
            problems.append(f"{lp['name']}: 没有同高度的 ground 盒完全承载")
    sp = layout["spawn"]
    host = next(lp for lp in layout["landing_points"] if lp["name"] == sp["landing_point"])
    if abs(host["top_y"] + 0.02 - sp["position"][1]) > 1e-6:
        problems.append("spawn.y 与落脚点顶面不符")
    if abs(sp["position"][0] - host["center"][0]) > host["size"][0] / 2 or        abs(sp["position"][2] - host["center"][1]) > host["size"][1] / 2:
        problems.append("spawn 不在落脚点净空内")

    # 台阶单调上升且单级不超过跳跃顶点
    steps = sorted([b for b in boxes if b["role"] == "stairs"], key=lambda x: x["top_y"])
    if len(steps) != 8:
        problems.append(f"台阶段数应为 8，实际 {len(steps)}")
    tops = [b["top_y"] for b in steps]
    if tops != sorted(set(tops)):
        problems.append("台阶 top_y 不单调")
    prev = 30.0
    for b in steps:
        if not 0 < b["top_y"] - prev <= 1.0:
            problems.append(f"{b['name']}: 单级抬升 {b['top_y'] - prev} 超出跳跃顶点")
        prev = b["top_y"]

    js = next((b for b in boxes if b["name"] == "jump_step"), None)
    if js is None:
        problems.append("缺少 jump_step")
    elif abs(js["top_y"] - 12.55) > 1e-6 or abs(js["top_y"] - 12.0 - 0.55) > 1e-6:
        problems.append("jump_step 顶面不是 12.55")

    # 廊台檐下净高与庭院净空不被屋顶盒覆盖
    for lp in layout["landing_points"]:
        if lp["name"] != "summit_sect":
            continue
        r = rect(lp["center"][0], lp["center"][1], lp["size"][0], lp["size"][1])
        for b in boxes:
            if b["role"] not in ("roof", "building"):
                continue
            br = rect(b["center"][0], b["center"][2], b["size"][0], b["size"][2])
            if br[0] < r[1] and r[0] < br[1] and br[2] < r[3] and r[2] < br[3] and                b["center"][1] - b["size"][1] / 2 < lp["top_y"] + 3.0:
                problems.append(f"{b['name']}: 侵入宗门庭院净空")

    # 主殿墙段留出真实门洞（南墙两段之间 4 m 缺口）与内部空腔
    south = [b for b in boxes if b["name"].startswith("main_hall_wall_south")]
    if len(south) != 2:
        problems.append("主殿南墙必须为两段（门洞）")
    else:
        gap = min(abs(b["center"][0] - 4.0) for b in south) - 3.0
        if abs(gap - 2.0) > 1e-6:
            problems.append(f"主殿门洞半宽异常：{gap}")
    nodes = [m["node"] for m in layout["collision"]["mountains"]]
    if len(nodes) != 5 or len(set(nodes)) != 5:
        problems.append("碰撞节点必须为 5 个且唯一")
    for node in nodes:
        if not (node[0].isupper() and node.endswith("Col") and "_" not in node):
            problems.append(f"碰撞节点非 PascalCase：{node}")
    return problems


def write_layout():
    SCENE_DIR.mkdir(parents=True, exist_ok=True)
    layout = build_layout()
    problems = validate(layout)
    roles = {}
    for b in layout["boxes"]:
        roles[b["role"]] = roles.get(b["role"], 0) + 1
    layout["checks"] = {
        "box_count": len(layout["boxes"]),
        "solid_count": sum(1 for b in layout["boxes"] if b["solid"]),
        "role_histogram": roles,
        "landing_point_count": len(layout["landing_points"]),
        "jump_apex_m": 1.0,
        "jump_speed_mps": 6.0,
        "gravity_mps2": 18.0,
        "max_stair_rise_m": STAIR_RISE,
        "corridor_clearance_m": 4.0,
        "player_capsule": {"radius": 0.35, "height": 1.6},
        "problems": problems,
    }
    LAYOUT_PATH.write_text(json.dumps(layout, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"LAYOUT {LAYOUT_PATH}")
    print(f"BOXES {len(layout['boxes'])} SOLID {layout['checks']['solid_count']} ROLES {roles}")
    print(f"LANDING {[lp['name'] for lp in layout['landing_points']]}")
    print(f"NODES {[m['node'] for m in layout['collision']['mountains']]}")
    if problems:
        for p in problems:
            print("PROBLEM", p)
        return 1
    print("PROBLEMS none")
    return 0


# ============================================================ Blender 阶段
def to_blender(gx, gy, gz):
    """Godot (Y-up, 北 = -Z) -> Blender (Z-up)；导出 export_yup 后回到同一世界坐标。"""
    return (gx, -gz, gy)


def make_palette(bpy):
    """纸白青绿基调的纯色 PBR 材质，与 movement_garden 同一素材语言。"""
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
        "rock_base": mat("Granite base", (0.145, 0.163, 0.158)),
        "rock_mid": mat("Granite mid", (0.215, 0.238, 0.223)),
        "rock_high": mat("Granite high", (0.318, 0.342, 0.305)),
        "rock_light": mat("Granite light", (0.435, 0.452, 0.402)),
        "moss": mat("Moss", (0.22, 0.33, 0.105)),
        "sand": mat("Raked sand", (0.54, 0.59, 0.45)),
        "ivory": mat("Ivory paving", (0.78, 0.77, 0.64)),
        "stone": mat("Warm limestone", (0.59, 0.62, 0.51)),
        "cut": mat("Cut stone edges", (0.24, 0.35, 0.28)),
        "jade": mat("Celadon ceramic", (0.075, 0.24, 0.18)),
        "roof": mat("Jade roof tiles", (0.078, 0.235, 0.185)),
        "plaster": mat("Ivory plaster wall", (0.745, 0.715, 0.625), 0.86),
        "stepstone": mat("Step stone", (0.665, 0.645, 0.555), 0.82),
        "ridge": mat("Roof ridge bronze", (0.51, 0.34, 0.09), 0.45, 0.35),
        "wall": mat("Jade hall wall", (0.30, 0.42, 0.35)),
        "timber": mat("Warm cedar", (0.22, 0.115, 0.053)),
        "bamboo": mat("Bamboo stems", (0.25, 0.38, 0.12)),
        "leaf": mat("Bamboo leaves", (0.12, 0.29, 0.09)),
        "pine": mat("Pine needles", (0.10, 0.235, 0.145)),
        "bark": mat("Pine bark", (0.26, 0.17, 0.10)),
        "iron": mat("Blade steel", (0.62, 0.66, 0.68), 0.32, 0.85),
        "gold": mat("Aged bronze", (0.51, 0.34, 0.09), 0.42, 0.35),
        "wrap": mat("Hilt wrap", (0.58, 0.52, 0.36)),
        "lantern": mat("Lantern paper", (0.98, 0.75, 0.37), 0.6, 0.0, 0.6),
        "haze": mat("Distant haze", (0.505, 0.575, 0.605), 0.9),
        # 自然地形材质：青灰岩两级、土、植被、碎石（视觉重建方向，不用大面积纸白）
        "rock_dark": mat("Cliff rock dark", (0.245, 0.262, 0.268), 0.88),
        "rock_mid": mat("Cliff rock mid", (0.372, 0.386, 0.373), 0.84),
        "soil": mat("Mountain soil", (0.352, 0.298, 0.222), 0.92),
        "grass": mat("Alpine grass", (0.146, 0.245, 0.129), 0.90),
        "scree": mat("Scree", (0.452, 0.442, 0.408), 0.86),
        "cloud": mat("Cloud band", (0.80, 0.845, 0.855), 0.95),
    }


def clear_scene(bpy):
    """factory-startup 自带 Cube/Camera/Light：每个阶段先清空，避免混入导出。"""
    for o in list(bpy.context.scene.objects):
        bpy.data.objects.remove(o, do_unlink=True)


def cbox(bpy, name, center_g, size_g, material, bevel=0.0):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=to_blender(*center_g))
    o = bpy.context.object
    o.name = name
    o.scale = (size_g[0], size_g[2], size_g[1])
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel:
        mod = o.modifiers.new("Soft crafted edges", "BEVEL")
        mod.width = bevel
        mod.segments = 2
    o.data.materials.append(material)
    return o


def ccyl(bpy, name, center_g, radius, depth, material, verts=12):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=radius, depth=depth,
                                        location=to_blender(*center_g))
    o = bpy.context.object
    o.name = name
    o.data.materials.append(material)
    return o


def ccone(bpy, name, center_g, r1, r2, depth, material, verts=10):
    bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r1, radius2=r2, depth=depth,
                                    location=to_blender(*center_g))
    o = bpy.context.object
    o.name = name
    o.data.materials.append(material)
    return o


def cblob(bpy, name, center_g, size_g, material, subdivisions=2):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdivisions, radius=1.0,
                                          location=to_blender(*center_g))
    o = bpy.context.object
    o.name = name
    o.scale = (size_g[0] / 2.0, size_g[2] / 2.0, size_g[1] / 2.0)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    o.data.materials.append(material)
    return o


def evaluated_stats(bpy):
    """用 depsgraph 求值后的网格统计（含修改器），与导出结果一致。"""
    deps = bpy.context.evaluated_depsgraph_get()
    meshes = tris = 0
    for o in bpy.context.scene.objects:
        if o.type != "MESH":
            continue
        meshes += 1
        ev = o.evaluated_get(deps)
        tris += sum(max(0, len(p.vertices) - 2) for p in ev.to_mesh().polygons)
        ev.to_mesh_clear()
    return meshes, tris


def export_selected(path, objects):
    import bpy
    bpy.ops.object.select_all(action="DESELECT")
    for o in objects:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.export_scene.gltf(filepath=str(path), export_format="GLB", use_selection=True,
                              export_apply=True, export_yup=True)
    print("EXPORTED", path)


# ============================================================ 自然地形重建（地形代理写集）
# 以 layout 的 ground 台顶为锚点，向外生成不规则坡脚/岩壁/山脊/冲沟的连续高度场；
# 平台范围内地形贴在盒顶下 0.05 m（不挡降落点、不留可走但不可见的边角）。
CACHE_DIR = Path.home() / ".cache" / "game-xiuxian-lab" / "visual-rebuild"


def _hash01(ix, iz, seed):
    """确定性 2D 哈希 -> [0,1)；不使用内置 hash()，跨进程稳定。"""
    h = (ix * 374761393 + iz * 668265263 + seed * 1013904223) & 0xFFFFFFFF
    h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
    return ((h ^ (h >> 16)) & 0xFFFFFF) / float(0x1000000)


def value_noise(x, z, seed):
    """双线性 + 五次淡化的值噪声。"""
    ix, iz = math.floor(x), math.floor(z)
    fx, fz = x - ix, z - iz
    ux = fx * fx * fx * (fx * (fx * 6.0 - 15.0) + 10.0)
    uz = fz * fz * fz * (fz * (fz * 6.0 - 15.0) + 10.0)
    return ((_hash01(ix, iz, seed) * (1 - ux) + _hash01(ix + 1, iz, seed) * ux) * (1 - uz)
            + (_hash01(ix, iz + 1, seed) * (1 - ux) + _hash01(ix + 1, iz + 1, seed) * ux) * uz)


def fbm(x, z, seed, octaves=4, lac=2.03, gain=0.5):
    total, amp, norm, fx, fz = 0.0, 1.0, 0.0, x, z
    for _ in range(octaves):
        total += amp * value_noise(fx, fz, seed)
        norm += amp
        amp *= gain
        fx *= lac
        fz *= lac
    return total / norm


def smoothstep(a, b, t):
    if b <= a:
        return 0.0 if t < a else 1.0
    u = max(0.0, min(1.0, (t - a) / (b - a)))
    return u * u * (3.0 - 2.0 * u)


def rect_distance(x, z, rect):
    """点到轴对齐矩形的欧氏距离（矩形内为 0）。"""
    x0, x1, z0, z1 = rect
    dx = max(x0 - x, x - x1, 0.0)
    dz = max(z0 - z, z - z1, 0.0)
    return math.sqrt(dx * dx + dz * dz)


# 每座山由它在 layout 中的大型 ground 盒驱动。盒坐标是唯一真源，本模块只读取。
PEAK_NODES = {
    "MainPeakCol": ("summit_terrace", "main_plateau_30", "shanmen_terrace"),
    "NorthPeakCol": ("north_peak_top",),
    "WestPeakCol": ("west_peak_top",),
    "EastRidgeCol": ("east_ridge_top",),
    "FrontMesaCol": ("front_mesa_top",),
}


# 自然峰脊：(x, z, 峰顶高度, 半径, 短长轴比, 方位)。
# 五峰方位各不相同，避免同形；全部避开三处落点、建筑、楼梯与主要通道。
PEAK_CRESTS = {
    # 主峰：峰脊中心收敛到宗门台/月台矩形内，只在台顶内部形成岩肩起伏，
    # 不越过保护区、不沿坡堆叠（薄鳍根因）。
    "MainPeakCol": [
        (10.0, -46.0, 45.0, 12.0, 0.92, 0.55),
        (-8.0, -33.0, 38.0, 11.0, 0.92, 2.30),
    ],
    # 北峰台顶 26×22 m：峰脊只能落在矩形内才不产生薄鳍，故收敛到贴近台顶的肩部。
    "NorthPeakCol": [
        (-46.0, -52.0, 34.0, 13.0, 0.90, 0.30),
    ],
    # 西峰与东岭台顶狭小：峰脊一律落在矩形之外，坡面叠加会产生薄鳍，
    # 按审计意见直接删除，保留自然圆形岩肩轮廓（无孤立石塔）。
    "WestPeakCol": [],
    "EastRidgeCol": [],
    "FrontMesaCol": [],   # 起点台需完整保留 spawn 庭院净空，不放峰脊
}


def exclusion_rects(layout, margin=2.0, landing_margin=0.5):
    """禁止地形侵入的区域：三处降落净空 + 全部 building/roof/stairs 盒。

    margin 控制建筑外扩；landing_margin 控制降落净空外扩（不宜过大，
    否则整块台顶都被占满，台面会变成无细节的平板）。
    """
    rects = []
    for lp in layout["landing_points"]:
        cx, cz = lp["center"]
        sx, sz = lp["size"]
        rects.append((cx - sx / 2.0 - landing_margin, cx + sx / 2.0 + landing_margin,
                      cz - sz / 2.0 - landing_margin, cz + sz / 2.0 + landing_margin))
    for b in layout["boxes"]:
        if b["role"] in ("building", "roof", "stairs"):
            cx, _, cz = b["center"]
            sx, _, sz = b["size"]
            rects.append((cx - sx / 2.0 - margin, cx + sx / 2.0 + margin,
                          cz - sz / 2.0 - margin, cz + sz / 2.0 + margin))
    return rects


def blocked(x, z, rects):
    for x0, x1, z0, z1 in rects:
        if x0 <= x <= x1 and z0 <= z <= z1:
            return True
    return False


def crest_height(x, z, platform, seed):
    """峰脊高度场：各向异性穹丘 + 斜向棱线，形成宽阔岩肩而非薄鳍。"""
    total = 0.0
    for (cxc, czc, crest_h, radius, aniso, azimuth) in PEAK_CRESTS.get(platform["node"], []):
        if crest_h <= 0.0:
            continue
        ca, sa = math.cos(azimuth), math.sin(azimuth)
        dx, dz = x - cxc, z - czc
        u = dx * ca + dz * sa
        v = -dx * sa + dz * ca
        d = math.sqrt(u * u + (v / max(0.2, aniso)) ** 2) / radius
        if d >= 1.0:
            continue
        # 指数 <1 使中段饱满；再乘圆钝包络，避免顶部被 1.5 m 网格切成刀尖薄片。
        ridge = (1.0 - d) ** 0.62 * (1.0 - 0.55 * smoothstep(0.55, 1.0, d))
        rib = math.exp(-((v / max(1.0, radius * 0.22)) ** 2)) * (1.0 - d)
        ridge += 0.16 * rib
        h = (crest_h - platform["top"]) * ridge
        h += (fbm(x * 0.075, z * 0.075, seed + 131, 4) - 0.5) * 3.6 * (1.0 - d) * (0.35 + 0.65 * rib)
        h += (fbm(x * 0.26, z * 0.26, seed + 137, 3) - 0.5) * 1.2 * (1.0 - d)
        total = max(total, h)
    return total


def exclusion_weight(x, z, rects, ramp):
    """到最近排除矩形边界的平滑权重：矩形内/边界处为 0，向外 ramp 米渐增到 1。

    布尔硬裁切（blocked 直接归零）会在保护区边缘留下竖直断面，渲染成"薄鳍/刀片"。
    这里用平滑衰减取代直接归零：净空内仍严格为 0，外缘自然过渡。
    """
    if not rects:
        return 1.0
    d = min(rect_distance(x, z, r) for r in rects)
    return smoothstep(0.0, ramp, d)


def massif_support(x, z, platforms):
    """峰脊必须由山体支撑：离台顶矩形越远支撑越弱，避免远处出现孤立薄石塔。"""
    if not platforms:
        return 1.0
    d = min(rect_distance(x, z, p["rect"]) for p in platforms)
    return 1.0 - smoothstep(10.0, 40.0, d)


def terrain_platforms(layout):
    """从 layout 读取可承载山体的 ground 台顶，含其碰撞盒顶面（-0.05 避免共面）。"""
    platforms = []
    boxes = {b["name"]: b for b in layout["boxes"]}
    for node, names in PEAK_NODES.items():
        for name in names:
            b = boxes.get(name)
            if b is None:
                continue
            cx, _, cz = b["center"]
            sx, _, sz = b["size"]
            platforms.append({
                "node": node, "name": name,
                "rect": (cx - sx / 2.0, cx + sx / 2.0, cz - sz / 2.0, cz + sz / 2.0),
                "top": b["top_y"] - 0.05,
                "flare": max(14.0, 0.82 * min(sx, sz) + 10.0),
                "cx": cx, "cz": cz,
            })
    return platforms


def flank_flare(p, theta):
    """坡脚宽度随方向变化：山脊外伸、沟谷收窄，轮廓不再同心。"""
    f = p["flare"] * (1.0 + 0.30 * math.cos(3.0 * theta + 1.1)
                      + 0.17 * math.cos(5.0 * theta - 0.45)
                      + 0.10 * math.cos(7.0 * theta + 2.25))
    ph = (p["cx"] * 0.11 + p["cz"] * 0.07) % (2.0 * math.pi)
    for k in range(2):
        ang = ph + k * 2.4
        d = ((theta - ang + math.pi) % (2.0 * math.pi)) - math.pi
        f += p["flare"] * 0.34 * math.exp(-(d * d) / (2.0 * 0.30 ** 2))
    d = ((theta - (ph + 1.15) + math.pi) % (2.0 * math.pi)) - math.pi
    f -= p["flare"] * 0.24 * math.exp(-(d * d) / (2.0 * 0.22 ** 2))
    return max(p["flare"] * 0.45, f)


def terrain_height(x, z, platforms, seed, exclusions=(), crest_exclusions=None):
    """谷地基面 + 各台顶坡脚与峰脊的软并集。

    exclusions：建筑/楼梯/落点/通道净空（挡土石、露岩、峰脊全部禁止）。
    crest_exclusions：峰脊专用禁止区，外扩量更大；缺省时退回 exclusions。
    """
    block_rects = exclusions
    crest_blocks = crest_exclusions if crest_exclusions is not None else exclusions
    # 谷地必须 >= 0：既有 ground_valley 碰撞盒顶面固定在 y=0，若可见面出现负高度，
    # 角色会踩在盒面而脚下地表更低，表现为悬空。可玩区内高度恒 >= 0，
    # 且碰撞网格与可见网格同源采样，两者不会分离。
    r = math.sqrt((x / 118.0) ** 2 + (z / 104.0) ** 2)
    base = (fbm(x * 0.021, z * 0.021, seed + 31, 3) - 0.5) * (0.35 + 5.5 * smoothstep(0.55, 1.15, r))
    base += (fbm(x * 0.075, z * 0.075, seed + 53, 2) - 0.5) * 0.18
    base = max(0.0, base)
    # 盆缘抬升：把矩形底板边缘藏进自然山体
    base += smoothstep(0.74, 1.22, r) * (16.0 + 12.0 * fbm(x * 0.018, z * 0.018, seed + 71, 2))
    # 平台内部为权威值：取覆盖该点台顶中的最高者，绝不叠加坡脚噪声
    inside = None
    inside_p = None
    for p in platforms:
        if rect_distance(x, z, p["rect"]) <= 0.0:
            if inside is None or p["top"] > inside:
                inside, inside_p = p["top"], p
    if inside is not None:
        if blocked(x, z, block_rects):
            return max(base, inside)
        h = (inside + platform_rim_height(x, z, inside_p)
             + outcrop_height(x, z, inside_p, seed))
        # 峰脊按到净空边界的距离平滑衰减，而非布尔归零：净空内仍为 0，
        # 避免了此前保护区边缘的竖直断面（薄鳍/刀片）。
        w_clear = exclusion_weight(x, z, crest_blocks, 9.0)
        w_support = massif_support(x, z, platforms)
        for q in platforms:
            h += crest_height(x, z, q, seed) * w_clear * w_support
        return max(base, h)
    best = 0.0
    for p in platforms:
        d = rect_distance(x, z, p["rect"])
        cx, cz = p["cx"], p["cz"]
        wx = x + 5.5 * math.sin(z * 0.052 + p["cz"] * 0.03)
        wz = z + 5.5 * math.sin(x * 0.047 + p["cx"] * 0.03)
        theta = math.atan2(wz - cz, wx - cx)
        ph = (p["cx"] * 0.11 + p["cz"] * 0.07) % (2.0 * math.pi)
        flare = flank_flare(p, theta)
        u = d / flare
        if u >= 1.0:
            continue
        prof = (1.0 - u) ** 1.45
        prof += 0.06 * math.exp(-((u - 0.55) / 0.16) ** 2)
        prof += 0.05 * math.exp(-((u - 0.22) / 0.12) ** 2)
        h = p["top"] * prof
        env = 1.0 - (1.0 - u) ** 2
        h += (fbm(x * 0.062, z * 0.062, seed + 91, 4) - 0.5) * 9.0 * env * (p["top"] / 36.0)
        h += (fbm(x * 0.155, z * 0.155, seed + 97, 4) - 0.5) * 3.2 * env
        h += (fbm(x * 0.33, z * 0.33, seed + 13, 3) - 0.5) * 1.1 * env
        gul = 0.0
        for gk in range(3):
            gang = ph + 0.9 + gk * 2.1
            dg = ((theta - gang + math.pi) % (2.0 * math.pi)) - math.pi
            gul += math.exp(-(dg * dg) / (2.0 * 0.10 ** 2))
        h -= p["top"] * 0.17 * gul * env
        rib = 0.0
        for rk in range(2):
            rang = ph + 1.9 + rk * 2.7
            dr = ((theta - rang + math.pi) % (2.0 * math.pi)) - math.pi
            rib += math.exp(-(dr * dr) / (2.0 * 0.07 ** 2))
        h += p["top"] * 0.10 * rib * env * (1.0 - u)
        best = max(best, max(0.0, h))
    # 峰脊在坡面同样隆起，但绝不压到建筑/楼梯/落点与主要通道上（审计①）：
    # 用平滑衰减而非布尔裁切，避免保护区边缘出现竖直断面（薄鳍/刀片）。
    #
    # 关键：crest_height 返回的是"相对该平台顶面"的高度，必须叠加在已有山体之上，
    # 而不能加到谷地基面上——否则峰脊中心落在台顶矩形之外时只会鼓起一个小土包
    # （上一版实测主峰脊顶仅 9~21 m，低于 36 m 台顶，正是这个原因）。
    # 因此用 weight 同时限制：越靠近山体（h_now 越高）越能长出峰脊，
    # 谷底与远处的权重为 0，不会出现悬空石塔。
    # 坡面不再叠加峰脊。任何形式的峰脊沿坡叠加都受 1.5 m 网格与噪声梯度影响，
    # 反复产生竖直薄鳍/刀片（审计明确否决：要自然岩脊，不要保护区边缘的高墙）。
    # 按审计给出的退路处理：删掉这些薄鳍，坡面保持圆润自然坡脚；
    # 台顶内部仍保留受净空约束的岩肩起伏（见上面的 platform 分支）。
    return base + best


def platform_rim_height(x, z, p):
    """平台边缘挡土石：环绕一圈、成簇而非连续墙，把方形口切成自然岩边。"""
    x0, x1, z0, z1 = p["rect"]
    inside = x0 <= x <= x1 and z0 <= z <= z1
    d = rect_distance(x, z, p["rect"])
    band = max(2.0, 0.040 * min(x1 - x0, z1 - z0) + 1.4)
    if d >= band:
        return 0.0
    if inside and min(x - x0, x1 - x, z - z0, z1 - z) > 0.8:
        return 0.0
    ang = math.atan2(z - (z0 + z1) / 2.0, x - (x0 + x1) / 2.0)
    wob = 0.55 + 0.45 * abs(math.sin(ang * 3.0 + p["cx"] * 0.2)) * abs(math.cos(ang * 2.0))
    gate = smoothstep(0.40, 0.62, value_noise(x * 0.21, z * 0.21, 1709))
    if gate <= 0.0:
        return 0.0
    return (0.7 + 1.5 * wob) * gate * (1.0 - d / band) ** 1.15


def outcrop_height(x, z, platform, seed):
    """台顶露岩：孤立低矮岩块，让承载面不是一块干净平板。"""
    field = fbm(x * 0.16, z * 0.16, seed + 211, 3)
    if field < 0.62:
        return 0.0
    t = (field - 0.62) / 0.38
    return (0.35 + 1.6 * t) * (0.6 + 0.4 * value_noise(x * 0.5, z * 0.5, seed + 223))


def nearest_peak_node(x, z, platforms):
    """把任意点归属到最近的峰节点：碰撞因此覆盖整片谷地而不只是山壳（审计③）。"""
    best, best_d = None, float("inf")
    for p in platforms:
        d = (x - p["cx"]) ** 2 + (z - p["cz"]) ** 2
        if d < best_d:
            best_d, best = d, p["node"]
    return best


def build_terrain_mesh(bpy, platforms, seed, domain, cell, exclusions=(), crest_exclusions=None):
    """高度场网格（可见与碰撞同源）；返回单个对象。"""
    x0, x1, z0, z1 = domain
    nx = int(round((x1 - x0) / cell))
    nz = int(round((z1 - z0) / cell))
    verts = []
    for j in range(nz + 1):
        gz = z0 + j * cell
        for i in range(nx + 1):
            gx = x0 + i * cell
            verts.append(to_blender(
                gx, terrain_height(gx, gz, platforms, seed, exclusions, crest_exclusions), gz))
    faces = []
    for j in range(nz):
        for i in range(nx):
            a = j * (nx + 1) + i
            # 绕序必须使法线朝上（to_blender=(x,-z,y) 会翻转手性）：
            # 写成 (a, a+1, a+nx+2, a+nx+1) 会得到 Godot -Y 法线。
            faces.append((a, a + nx + 1, a + nx + 2, a + 1))
    mesh = bpy.data.meshes.new("TerrainMesh")
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new("Terrain", mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def paint_terrain(bpy, obj, pal, seed=1709, platforms=(), exclusions=()):
    """顶点色承载岩/土/草颜色过渡（多倍频噪声，无网格块感）；材质只管表面响应。"""
    mats = [pal["rock_dark"], pal["scree"]]
    for m in mats:
        obj.data.materials.append(m)
    obj.data.polygons.foreach_set("use_smooth", [True] * len(obj.data.polygons))
    me = obj.data
    col = me.color_attributes.new(name="Col", type="FLOAT_COLOR", domain="POINT")
    for v in me.vertices:
        x, y, z = v.co.x, v.co.y, v.co.z
        fine = fbm(x * 0.085, y * 0.085, seed + 17, 4)
        coarse = fbm(x * 0.028, y * 0.028, seed + 29, 3)
        micro = value_noise(x * 0.42, y * 0.42, seed + 41)
        blend = max(0.0, min(1.0, (0.62 * fine + 0.38 * coarse - 0.40) * 2.4))
        rock = (0.215, 0.240, 0.258)
        grass = (0.088, 0.190, 0.082)
        soil = (0.300, 0.238, 0.158)
        if blend < 0.5:
            t = blend / 0.5
            base = tuple(grass[i] + (soil[i] - grass[i]) * t for i in range(3))
        else:
            t = (blend - 0.5) / 0.5
            base = tuple(soil[i] + (rock[i] - soil[i]) * t for i in range(3))
        alta = smoothstep(18.0, 34.0, z)
        base = tuple(base[i] + (rock[i] - base[i]) * alta * 0.45 for i in range(3))
        shade = 0.86 + 0.22 * micro + 0.10 * (coarse - 0.5)
        # 挡土石带与台顶露岩强制岩色：矩形边缘读作砌石岩边
        stony = 0.0
        for p in platforms:
            if not blocked(x, y, exclusions):
                stony = max(stony, platform_rim_height(x, y, p), outcrop_height(x, y, p, seed))
        if stony > 0.12:
            mix = min(1.0, stony / 1.1)
            base = tuple(base[i] + (rock[i] - base[i]) * mix for i in range(3))
        col.data[v.index].color = (base[0] * shade, base[1] * shade, base[2] * shade, 1.0)
    for poly in me.polygons:
        poly.material_index = 0
    # 顶点色已是最终颜色，直接驱动 Base Color（再乘材质本色会二次着色）
    for m in mats:
        bs = m.node_tree.nodes.get("Principled BSDF")
        if bs is None or bs.inputs["Base Color"].is_linked:
            continue
        attr = m.node_tree.nodes.new("ShaderNodeVertexColor")
        attr.layer_name = "Col"
        attr.location = (-420, 260)
        m.node_tree.links.new(attr.outputs["Color"], bs.inputs["Base Color"])
    return obj


def pine_layout(layout):
    """9 棵松的位置取自 layout 的 pine_trunk 碰撞盒：视觉与碰撞同名同位，无隐形树干。"""
    out = []
    for b in layout["boxes"]:
        if b["name"].startswith("pine_trunk"):
            out.append((b["name"], b["center"][0], b["center"][2], b["top_y"], b["size"][1]))
    return sorted(out)


def build_pines(bpy, pal, layout):
    """自然植被：松（树冠占树干上半段、三层收细）。位置由 layout 唯一确定。"""
    made = []
    for i, (name, x, z, top, h) in enumerate(pine_layout(layout), start=1):
        made.append(ccyl(bpy, f"pine_{i}_stem", (x, top - h / 2.0, z),
                         0.14 * (h / 3.6), h, pal["bark"], verts=8))
        tier_h = h * 0.34
        for tier, (scale, base_off) in enumerate(((1.0, 0.0), (0.78, 0.16), (0.55, 0.33))):
            center_z = top - h * 0.50 + h * base_off + tier_h / 2.0
            made.append(ccone(bpy, f"pine_{i}_crown_{tier + 1}", (x, center_z, z),
                              scale * 1.25 * (h / 3.6), 0.0, tier_h, pal["pine"], verts=9))
    return made


def build_undergrowth(bpy, pal, platforms, seed, exclusions):
    """坡脚灌木点缀：只用噪声布点，不进入净空与建筑区。"""
    made = []
    count = 0
    gx = -110.0
    while gx <= 110.0 and count < 220:
        gz = -100.0
        while gz <= 100.0 and count < 220:
            if not blocked(gx, gz, exclusions) and fbm(gx * 0.035, gz * 0.035, seed + 401, 3) > 0.60:
                h = terrain_height(gx, gz, platforms, seed, exclusions)
                if h > 0.6:
                    size = 0.6 + 1.4 * value_noise(gx * 0.3, gz * 0.3, seed + 409)
                    made.append(cblob(bpy, f"shrub_{count + 1}", (gx, h + size * 0.22, gz),
                                      (size, size * 0.55, size), pal["grass"], subdivisions=1))
                    count += 1
            gz += 6.0
        gx += 6.0
    return made


def channel_report(platforms, seed, exclusions, crest_exclusions=None):
    """审计①证据：建筑/楼梯/落点/通道压在平台上的点，地形不得高于该处台顶。

    只统计**真正落在平台承载面内**的点；台矩形之外是自然坡脚，其高度与台顶无关，
    若一并计入会把正常山坡误报成侵占（首版即因此报出 35.7 m 假阳性）。
    返回 (最坏差值, 检查点数)。
    """
    worst = 0.0
    count = 0
    for (x0, x1, z0, z1) in exclusions:
        gx = x0
        while gx <= x1 + 1e-6:
            gz = z0
            while gz <= z1 + 1e-6:
                ref = 0.0
                for p in platforms:
                    if rect_distance(gx, gz, p["rect"]) <= 0.0:
                        ref = max(ref, p["top"])
                if ref > 0.0:
                    count += 1
                    h = terrain_height(gx, gz, platforms, seed, exclusions, crest_exclusions)
                    worst = max(worst, h - ref)
                gz += 1.5
            gx += 1.5
    return round(worst, 4), count


def valley_report(platforms, seed, exclusions):
    """审计②证据：可玩 bounds 内谷地最低可见高度；必须 >= 0 才与 ground_valley 盒顶一致。"""
    lo = float("inf")
    x = -90.0
    while x <= 90.0:
        z = -80.0
        while z <= 80.0:
            if not any(rect_distance(x, z, p["rect"]) <= 0.0 for p in platforms):
                lo = min(lo, terrain_height(x, z, platforms, seed, exclusions))
            z += 2.0
        x += 2.0
    return round(lo, 4)


def stage_terrain(tag=""):
    """最终地形：仅自然山地谷地与植被（建筑/规则平台视觉件归庭院代理）。"""
    import bpy
    clear_scene(bpy)
    layout = json.loads(LAYOUT_PATH.read_text(encoding="utf-8"))
    platforms = terrain_platforms(layout)
    exclusions = exclusion_rects(layout)
    crest_exclusions = exclusion_rects(layout, margin=6.0, landing_margin=3.0)
    pal = make_palette(bpy)
    obj = build_terrain_mesh(bpy, platforms, 1709, (-118.0, 118.0, -108.0, 108.0), 1.5,
                             exclusions, crest_exclusions)
    paint_terrain(bpy, obj, pal, platforms=platforms, exclusions=exclusions)
    pines = build_pines(bpy, pal, layout)
    shrubs = build_undergrowth(bpy, pal, platforms, 1709, exclusions)
    meshes, tris = evaluated_stats(bpy)
    export_selected(VISUAL_GLB, [o for o in bpy.context.scene.objects if o.type == "MESH"])
    ART_DIR.mkdir(parents=True, exist_ok=True)
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(ART_DIR / "mountain_realm.blend"))
    print(f"TERRAIN meshes={meshes} tris={tris} pines={len(pines)} shrubs={len(shrubs)}")
    intrusion, checked = channel_report(platforms, 1709, exclusions, crest_exclusions)
    print(f"CHECK channel_intrusion_m={intrusion} over {checked} platform points (must be 0)")
    print(f"CHECK valley_floor_min_y={valley_report(platforms, 1709, exclusions)} (must be >= 0)")
    print("TERRAIN_DONE")
    return 0


def stage_collision(tag=""):
    """碰撞：与可见地形同源的高度场，按最近峰分网格面，五节点覆盖整片可走谷地与山面。"""
    import bpy
    clear_scene(bpy)
    layout = json.loads(LAYOUT_PATH.read_text(encoding="utf-8"))
    platforms = terrain_platforms(layout)
    exclusions = exclusion_rects(layout)
    crest_exclusions = exclusion_rects(layout, margin=6.0, landing_margin=3.0)
    x0, x1, z0, z1 = (-118.0, 118.0, -108.0, 108.0)
    cell = 1.5
    nx = int(round((x1 - x0) / cell))
    nz = int(round((z1 - z0) / cell))
    height = {}
    for j in range(nz + 1):
        gz = z0 + j * cell
        for i in range(nx + 1):
            gx = x0 + i * cell
            height[(i, j)] = terrain_height(gx, gz, platforms, 1709, exclusions, crest_exclusions)
    groups = {}
    for j in range(nz):
        for i in range(nx):
            gx = x0 + (i + 0.5) * cell
            gz = z0 + (j + 0.5) * cell
            groups.setdefault(nearest_peak_node(gx, gz, platforms), []).append((i, j))
    objects = []
    for node, cells in sorted(groups.items()):
        index, verts, faces = {}, [], []
        for (i, j) in cells:
            # 绕序必须使法线朝上：见 build_terrain_mesh 的说明。
            quad = []
            for (vi, vj) in ((i, j), (i, j + 1), (i + 1, j + 1), (i + 1, j)):
                if (vi, vj) not in index:
                    index[(vi, vj)] = len(verts)
                    verts.append(to_blender(x0 + vi * cell, height[(vi, vj)], z0 + vj * cell))
                quad.append(index[(vi, vj)])
            faces.append(tuple(quad))
        mesh = bpy.data.meshes.new(f"{node}_mesh")
        mesh.from_pydata(verts, [], faces)
        mesh.update()
        o = bpy.data.objects.new(node, mesh)
        bpy.context.collection.objects.link(o)
        objects.append(o)
    up = sum(1 for o in objects for poly in o.data.polygons if poly.normal.z > 0.0)
    bad = sum(1 for o in objects for poly in o.data.polygons if poly.normal.z <= 0.0)
    export_selected(COLLISION_GLB, objects)
    print(f"COLLISION nodes={[o.name for o in objects]}")
    print(f"COLLISION faces={sum(len(o.data.polygons) for o in objects)}")
    print(f"CHECK collision_normals_up={up} non_up={bad} (non_up must be 0)")
    print("COLLISION_DONE")
    return 0


def stage_sword():
    import bpy
    from mathutils import Vector
    pal = make_palette(bpy)
    clear_scene(bpy)
    # 局部 -Z 为剑尖；原点 = 剑身顶面（Godot y=0 即人物足底站立面）。
    # 剑尖 z=-1.12、剑柄尾 z=+0.68 -> 全长 1.80 m；最宽 = 剑格 0.26；厚 = 剑身 0.07。
    # 倒角会让顶面高出盒体 0.02：这里预留下移量，使倒角后的最高点正好落在 y=0。
    Y = -0.055
    blade = cbox(bpy, "Blade", (0.0, Y, -0.35), (0.09, 0.07, 1.30), pal["iron"], bevel=0.012)
    tip = ccone(bpy, "Tip", (0.0, Y, -1.00), 0.055, 0.0, 0.24, pal["iron"], verts=8)
    tip.rotation_euler = (-math.pi / 2.0, 0.0, 0.0)
    guard = cbox(bpy, "Guard", (0.0, Y, 0.32), (0.26, 0.06, 0.06), pal["gold"], bevel=0.015)
    grip = ccyl(bpy, "Grip", (0.0, Y, 0.49), 0.028, 0.28, pal["wrap"], verts=10)
    grip.rotation_euler = (math.pi / 2.0, 0.0, 0.0)
    pommel = cblob(bpy, "Pommel", (0.0, Y, 0.645), (0.075, 0.07, 0.07), pal["gold"], subdivisions=2)
    for k in range(5):
        ring = ccyl(bpy, f"GripWrap_{k + 1}", (0.0, Y, 0.385 + k * 0.052), 0.032, 0.02, pal["gold"], verts=8)
        ring.rotation_euler = (math.pi / 2.0, 0.0, 0.0)
    parts = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    SWORD_DIR.mkdir(parents=True, exist_ok=True)
    export_selected(SWORD_GLB, parts)
    ART_DIR.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(ART_DIR / "flying_sword.blend"))
    xs = [o.matrix_world @ Vector(c) for o in parts for c in o.bound_box]
    print("SWORD bounds x=%.3f..%.3f y=%.3f..%.3f z=%.3f..%.3f" % (
        min(v.x for v in xs), max(v.x for v in xs), min(v.y for v in xs), max(v.y for v in xs),
        min(v.z for v in xs), max(v.z for v in xs)))
    return 0


def stage_preview(tag=""):
    """最终全景预览：读最终地形 blend 渲染，非运行时素材。"""
    import bpy
    from mathutils import Vector
    clear_scene(bpy)
    layout = json.loads(LAYOUT_PATH.read_text(encoding="utf-8"))
    platforms = terrain_platforms(layout)
    exclusions = exclusion_rects(layout)
    crest_exclusions = exclusion_rects(layout, margin=6.0, landing_margin=3.0)
    pal = make_palette(bpy)
    obj = build_terrain_mesh(bpy, platforms, 1709, (-118.0, 118.0, -108.0, 108.0), 1.5,
                             exclusions, crest_exclusions)
    paint_terrain(bpy, obj, pal, platforms=platforms, exclusions=exclusions)
    build_pines(bpy, pal, layout)
    build_undergrowth(bpy, pal, platforms, 1709, exclusions)
    scene = bpy.context.scene
    world = scene.world or bpy.data.worlds.new("Sky")
    scene.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.42, 0.56, 0.70, 1.0)
    world.node_tree.nodes["Background"].inputs[1].default_value = 0.62
    scene.view_settings.view_transform = "Standard"
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 24
    scene.cycles.use_denoising = True
    scene.render.resolution_x = 1280
    scene.render.resolution_y = 720
    scene.render.image_settings.file_format = "PNG"
    bpy.ops.object.light_add(type="SUN", location=to_blender(-70.0, 120.0, -90.0))
    sun = bpy.context.object
    sun.data.energy = 3.2
    sun.data.angle = 0.12
    sun.data.color = (1.0, 0.97, 0.90)
    sun.rotation_euler = (Vector((0, 0, 0)) - sun.location).to_track_quat("-Z", "Y").to_euler()
    bpy.ops.object.camera_add(location=to_blender(10.0, 52.0, 200.0))
    cam = bpy.context.object
    cam.data.type = "PERSP"
    cam.data.lens = 32.0
    cam.rotation_euler = (Vector(to_blender(0.0, 10.0, -12.0)) - cam.location).to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam
    out = ART_DIR / "mountain_realm_preview.png"
    if tag:
        out = ART_DIR / f"mountain_realm_preview_{tag}.png"
    scene.render.filepath = str(out)
    bpy.ops.render.render(write_still=True)
    print("PREVIEW", scene.render.filepath)
    return 0


def main(argv):
    stage = argv[0] if argv else "layout"
    if stage == "layout":
        return write_layout()
    if stage == "terrain":
        return stage_terrain()
    if stage == "collision":
        return stage_collision()
    if stage == "sword":
        return stage_sword()
    if stage == "preview":
        return stage_preview(argv[1] if len(argv) > 1 else "")
    raise SystemExit(f"未知阶段 {stage!r}；可用：layout / terrain / collision / sword / preview")


if __name__ == "__main__":
    code = 0
    if "bpy" in sys.modules or "--" in sys.argv:
        code = main(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    else:
        code = main(sys.argv[1:])
    if code:
        sys.exit(code)
