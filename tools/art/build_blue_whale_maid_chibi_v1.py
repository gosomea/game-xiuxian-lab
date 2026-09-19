#!/usr/bin/env python3
"""构建 blue_whale_maid_chibi_v1：蓝鲸主题 Q 版女仆少女（独立原创程序建模）。

依据 notes/proposed/art/2026-09-19-blue-whale-maid-chibi-v1.md 与使用者提供的三视图参考
（docs/art/blue_whale_maid_chibi_v1/reference/source_character_sheet.png，外部版权未知）。

坐标约定
  Blender：Z 为高度轴，角色正面朝 **-Y**。
  导出 export_yup=True → Blender -Y 映射到 glTF/Godot **+Z**，即导出后局部 +Z 为正面。

阶段
  build （默认）建模 -> 校验 -> 保存 .blend -> 渲染全部验收图 -> 导出 -> 写 manifest
  export          独立进程重新打开最终 .blend，重新导出并回读审计

用法
  Blender --background --factory-startup --python <本文件> [-- --phase export]
"""

import bmesh
import bpy
import hashlib
import json
import math
import os
import struct
import sys
from mathutils import Matrix, Vector

TAU = math.pi * 2.0

ROOT = "/Users/yuqixian/forever-skills/projects/games/game-xiuxian-lab"
OUT = os.path.join(ROOT, "docs/art/blue_whale_maid_chibi_v1")
SOURCE_DIR = os.path.join(OUT, "source")
EXPORT_DIR = os.path.join(OUT, "exports")
RENDERS = os.path.join(OUT, "renders")
REFERENCE = os.path.join(OUT, "reference/source_character_sheet.png")
BLEND = os.path.join(SOURCE_DIR, "blue_whale_maid_chibi_v1.blend")
GLB = os.path.join(EXPORT_DIR, "blue_whale_maid_chibi_v1.glb")
FBX = os.path.join(EXPORT_DIR, "blue_whale_maid_chibi_v1_unrigged.fbx")
MANIFEST = os.path.join(OUT, "build_manifest.json")
EXPORT_MANIFEST = os.path.join(OUT, "export_audit.json")

REPORT = {}
ITERATION = "refined_01"


def log(msg):
    print("[whale] " + msg, flush=True)


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def hex_rgb(value):
    value = value.lstrip("#")
    return tuple(srgb_to_linear(int(value[i:i + 2], 16) / 255.0) for i in (0, 2, 4))


# ------------------------------------------------------------------ 场景工具

def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0
    scene.render.fps = 30


def link(obj):
    bpy.context.scene.collection.objects.link(obj)


def activate(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def new_mesh_object(name, bm, material=None):
    mesh = bpy.data.meshes.new(name + "_mesh")
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    link(obj)
    if material is not None:
        mesh.materials.append(material)
    return obj


def join_objects(objs, name):
    objs = [o for o in objs if o is not None]
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    objs[0].name = name
    objs[0].data.name = name + "_mesh"
    return objs[0]


def merge_material_slots(obj):
    unique, index_of, remap = [], {}, {}
    for slot_index, slot in enumerate(obj.material_slots):
        mat = slot.material
        key = mat.name if mat else "__none__"
        if key not in index_of:
            index_of[key] = len(unique)
            unique.append(mat)
        remap[slot_index] = index_of[key]
    if len(unique) == len(obj.material_slots):
        return
    for poly in obj.data.polygons:
        poly.material_index = remap[poly.material_index]
    obj.data.materials.clear()
    for mat in unique:
        obj.data.materials.append(mat)


def orient_outward(obj, axis_x=0.0, axis_y=0.0):
    """把朝向体内（指向竖直轴）的面翻正，避免渲染出暗色背面。"""
    me = obj.data
    bm = bmesh.new()
    bm.from_mesh(me)
    flipped = 0
    for face in bm.faces:
        centre = face.calc_center_median()
        radial = Vector((centre.x - axis_x, centre.y - axis_y, 0.0))
        if radial.length < 1e-6:
            continue
        radial.normalize()
        if face.normal.dot(radial) < 0.0:
            face.normal_flip()
            flipped += 1
    bm.to_mesh(me)
    bm.free()
    me.update()
    return flipped


def shade(obj, smooth=True, angle_deg=38.0):
    activate(obj)
    obj.data.polygons.foreach_set("use_smooth", [smooth] * len(obj.data.polygons))
    obj.data.update()
    if smooth:
        try:
            bpy.ops.object.shade_auto_smooth(angle=math.radians(angle_deg))
        except Exception:
            pass


def apply_transforms(objs):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objs:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)


# ------------------------------------------------------------ 环 / 放样 / 管

def superellipse(t, rx, ry, power=2.0):
    ct, st = math.cos(t), math.sin(t)
    ex = 2.0 / power
    return (rx * math.copysign(abs(ct) ** ex, ct),
            ry * math.copysign(abs(st) ** ex, st))


def ring(cz, rx, ry, segments, power=2.0, cx=0.0, cy=0.0):
    pts = []
    for i in range(segments):
        x, y = superellipse(TAU * i / segments, rx, ry, power)
        pts.append(Vector((cx + x, cy + y, cz)))
    return pts


def loft(name, rings, cap_start=True, cap_end=True, material=None):
    bm = bmesh.new()
    prev = None
    first = None
    for pts in rings:
        verts = [bm.verts.new(p) for p in pts]
        if prev is not None:
            n = len(verts)
            for i in range(n):
                j = (i + 1) % n
                try:
                    bm.faces.new((prev[i], prev[j], verts[j], verts[i]))
                except ValueError:
                    pass
        else:
            first = verts
        prev = verts
    if cap_start and first and len(first) > 2:
        try:
            bm.faces.new(list(reversed(first)))
        except ValueError:
            pass
    if cap_end and prev and len(prev) > 2:
        try:
            bm.faces.new(prev)
        except ValueError:
            pass
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return new_mesh_object(name, bm, material)


def frame_at(points, i):
    n = len(points)
    if i == 0:
        tangent = points[1] - points[0]
    elif i == n - 1:
        tangent = points[-1] - points[-2]
    else:
        tangent = points[i + 1] - points[i - 1]
    tangent = tangent.normalized()
    ref = Vector((1.0, 0.0, 0.0))
    if abs(tangent.dot(ref)) > 0.95:
        ref = Vector((0.0, 1.0, 0.0))
    u_axis = ref.cross(tangent).normalized()
    v_axis = tangent.cross(u_axis).normalized()
    return tangent, u_axis, v_axis


def tube_along(name, points, radii, seg=14, material=None, cap_start=True, cap_end=True,
               squash=1.0):
    rings = []
    for i, (p, r) in enumerate(zip(points, radii)):
        _, u_axis, v_axis = frame_at(points, i)
        row = []
        for k in range(seg):
            a = TAU * k / seg
            row.append(p + u_axis * (math.cos(a) * r)
                       + v_axis * (math.sin(a) * r * squash))
        rings.append(row)
    return loft(name, rings, cap_start=cap_start, cap_end=cap_end, material=material)


def sheet(name, rows, thickness, material=None):
    """开放曲面 + Solidify 加厚。

    建面前先去除重复顶点：折线端点重合时会生成零面积面（审计会报 zero_area）。
    """
    bm = bmesh.new()
    grid = [[bm.verts.new(p) for p in row] for row in rows]
    for r in range(len(grid) - 1):
        n = len(grid[r])
        for i in range(n - 1):
            quad = (grid[r][i], grid[r][i + 1], grid[r + 1][i + 1], grid[r + 1][i])
            coords = [v.co for v in quad]
            if min((a - b).length for j, a in enumerate(coords)
                   for b in coords[j + 1:]) < 1e-7:
                continue
            try:
                bm.faces.new(quad)
            except ValueError:
                pass
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    obj = new_mesh_object(name, bm, material)
    if thickness > 0.0:
        mod = obj.modifiers.new("solidify", "SOLIDIFY")
        mod.thickness = thickness
        mod.offset = 0.0
        activate(obj)
        bpy.ops.object.modifier_apply(modifier=mod.name)
    return obj


def sphere(name, center, radii, material=None, segments=20, rings_n=12):
    cx, cy, cz = center
    rx, ry, rz = radii
    rows = []
    for j in range(1, rings_n):
        phi = math.pi * j / rings_n
        z = cz + rz * math.cos(phi)
        s = math.sin(phi)
        rows.append([Vector((cx + rx * s * math.cos(TAU * i / segments),
                             cy + ry * s * math.sin(TAU * i / segments), z))
                     for i in range(segments)])
    bm = bmesh.new()
    top = bm.verts.new((cx, cy, cz + rz))
    bottom = bm.verts.new((cx, cy, cz - rz))
    grid = [[bm.verts.new(p) for p in row] for row in rows]
    for r in range(len(grid) - 1):
        for i in range(segments):
            j = (i + 1) % segments
            bm.faces.new((grid[r][i], grid[r][j], grid[r + 1][j], grid[r + 1][i]))
    for i in range(segments):
        j = (i + 1) % segments
        bm.faces.new((top, grid[0][j], grid[0][i]))
        bm.faces.new((bottom, grid[-1][i], grid[-1][j]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return new_mesh_object(name, bm, material)


def flat_patch(name, outline_xz, base_fn, material, offset, rings_n=3):
    """把 (x,z) 平面轮廓贴到曲面上并沿法线抬起 offset。"""
    cx = sum(p[0] for p in outline_xz) / len(outline_xz)
    cz = sum(p[1] for p in outline_xz) / len(outline_xz)
    bm = bmesh.new()
    grid = []
    for r in range(rings_n):
        t = 1.0 - r / float(rings_n)
        grid.append([bm.verts.new(base_fn(cx + (x - cx) * t, cz + (z - cz) * t, offset))
                     for (x, z) in outline_xz])
    for r in range(len(grid) - 1):
        n = len(grid[r])
        for i in range(n):
            j = (i + 1) % n
            try:
                bm.faces.new((grid[r][i], grid[r][j], grid[r + 1][j], grid[r + 1][i]))
            except ValueError:
                pass
    centre = bm.verts.new(base_fn(cx, cz, offset))
    last = grid[-1]
    for i in range(len(last)):
        j = (i + 1) % len(last)
        try:
            bm.faces.new((last[i], last[j], centre))
        except ValueError:
            pass
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return new_mesh_object(name, bm, material)


def ruffle(name, centre, radius, count, wave_amp, depth, material, thickness=0.006,
           a0=0.0, a1=TAU, closed=True, tilt=0.0, z_wave=0.0):
    """荷叶边：沿圆周的波浪褶皱环（女仆装关键轮廓元素）。"""
    steps = max(count * 6, 36)
    rows = []
    for band in range(3):
        t = band / 2.0
        row = []
        for i in range(steps + 1):
            u = i / steps
            a = a0 + (a1 - a0) * u
            wave = math.sin(a * count) * wave_amp
            r = radius + wave + depth * t
            x = centre[0] + math.cos(a) * r
            y = centre[1] + math.sin(a) * r
            z = centre[2] + tilt * r + z_wave * math.sin(a * count * 0.5) - depth * 0.55 * t
            row.append(Vector((x, y, z)))
        rows.append(row)
    obj = sheet(name, rows, thickness, material)
    return obj


# ------------------------------------------------------------------ 材质

MAT = {}


def make_material(name, hex_color, roughness=0.85, metallic=0.0, specular=0.3,
                  sheen=0.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    r, g, b = hex_rgb(hex_color)
    bsdf.inputs["Base Color"].default_value = (r, g, b, 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    if "Specular IOR Level" in bsdf.inputs:
        bsdf.inputs["Specular IOR Level"].default_value = specular
    if "Sheen Weight" in bsdf.inputs:
        bsdf.inputs["Sheen Weight"].default_value = sheen
    mat.diffuse_color = (r, g, b, 1.0)
    return mat


def build_materials():
    MAT["skin"] = make_material("BW_Skin", "#F7E2D4", 0.72, 0.0, 0.30)
    MAT["hair_dark"] = make_material("BW_HairDeep", "#1E2860", 0.42, 0.0, 0.50, 0.15)
    MAT["hair_mid"] = make_material("BW_HairMid", "#2C3F8C", 0.42, 0.0, 0.50, 0.15)
    MAT["hair_tip"] = make_material("BW_HairTip", "#4E7FD0", 0.42, 0.0, 0.50, 0.15)
    MAT["eye_white"] = make_material("BW_EyeWhite", "#FBFBFE", 0.45, 0.0, 0.40)
    MAT["eye_deep"] = make_material("BW_IrisDeep", "#1B2C6B", 0.35, 0.0, 0.55)
    MAT["eye_mid"] = make_material("BW_IrisMid", "#3E6DBE", 0.35, 0.0, 0.55)
    MAT["eye_light"] = make_material("BW_IrisLight", "#8CC5EA", 0.35, 0.0, 0.55)
    MAT["eye_line"] = make_material("BW_EyeLine", "#141A38", 0.45, 0.0, 0.45)
    MAT["mouth"] = make_material("BW_Mouth", "#C4707A", 0.60, 0.0, 0.35)
    MAT["blush"] = make_material("BW_Blush", "#F2A9AE", 0.70, 0.0, 0.30)
    MAT["navy"] = make_material("BW_Navy", "#1C2A5E", 0.86, 0.0, 0.22)
    MAT["navy_deep"] = make_material("BW_NavyDeep", "#141F49", 0.86, 0.0, 0.22)
    MAT["white"] = make_material("BW_White", "#F6F8FC", 0.88, 0.0, 0.20)
    MAT["white_soft"] = make_material("BW_WhiteSoft", "#E9EFF8", 0.90, 0.0, 0.18)
    MAT["gold"] = make_material("BW_Gold", "#C9A54E", 0.45, 0.35, 0.50)
    MAT["whale_blue"] = make_material("BW_WhaleBlue", "#2E5FA8", 0.55, 0.0, 0.35)
    MAT["tail_deep"] = make_material("BW_TailDeep", "#1E3C7A", 0.50, 0.0, 0.40)
    MAT["tail_tip"] = make_material("BW_TailTip", "#5A93D8", 0.50, 0.0, 0.40)
    MAT["pink"] = make_material("BW_Pink", "#F0879C", 0.60, 0.0, 0.35)
    MAT["shoe"] = make_material("BW_Shoe", "#1A2452", 0.38, 0.0, 0.50)


# ------------------------------------------------------------------ 比例
#
# 参考图三视图实测（刻度线：头顶/眼睛/肩膀/腰部/膝盖/脚底）：
#   总高 H，眼睛在 0.62H，肩 0.52H，腰 0.40H，膝盖 0.23H，脚底 0
#   头部（含发）高度约 0.36H，即约 2.8 头身。
H = 1.00                       # 归一化身高；导出前按 2.9–3.2 头身不放大，保持 1 m 级
HEAD_TOP = 0.995
# 头身比：契约要求 2.9–3.2 头。头部在「以 CHIN_Z 为轴心」的局部坐标里建模
# （沿用初版手感），组装阶段整体缩放 HEAD_SCALE 并抬升 HEAD_LIFT，使下巴落到
# HEAD_CHIN_FINAL，从而得到 2.9 头身。身体常量按最终高度独立给出。
HEAD_SCALE = 0.680
HEAD_LIFT = 0.155
HEAD_CHIN_FINAL = 0.660

# --- 头部局部坐标（缩放前）---
CHIN_Z = 0.505                 # 局部下巴高度（缩放轴心）
HEAD_TOP = 0.995               # 局部颅顶
EYE_Z = 0.655
HEAD_CY = -0.012
HEAD_RX = 0.252
HEAD_RY = 0.238
HEAD_RZ = 0.250

# --- 身体最终坐标（缩放后，总高约 1.0）---
SHOULDER_Z = 0.638
WAIST_Z = 0.498
HIP_Z = 0.408
KNEE_Z = 0.232
ANKLE_Z = 0.056

SHOULDER_X = 0.104
HIP_X = 0.043   # 双腿靠近但各自可读（0.034 时两条腿在正面糊成一根柱子）

# 头部块高度（下巴 -> 发顶，缩放后）：用于头身比断言
HEAD_BLOCK_H = (HEAD_TOP + 0.030 - CHIN_Z) * HEAD_SCALE


def local_z(z_final):
    """把「身体最终坐标」的高度换算回头部局部坐标（scale_about_chin 之前）。

    头发部件与头/脸一起被整体缩放；若其中某个部件直接按最终坐标写入，
    就会被缩放第二次而浮到错误高度（本轮实测：侧发与后波浪整体偏高）。
    """
    return CHIN_Z + (z_final - HEAD_CHIN_FINAL) / HEAD_SCALE


def head_profile(z):
    """头部椭球截面：返回 (rx, ry, power)。Q 版：下半张脸收窄成圆钝小下巴。"""
    t = (z - (CHIN_Z - 0.02)) / max((HEAD_TOP + 0.015) - (CHIN_Z - 0.02), 1e-6)
    t = min(max(t, 0.0), 1.0)
    # 圆润娃娃脸：整段保持饱满，只在最下方快速收成小圆下巴。
    # 初版用 sin(0.16+0.78t) 造成楔形平削感，这里改为更饱满的 cos 包络。
    base = math.cos(math.pi * (t - 0.46) * 0.92)
    base = max(base, 0.0) ** 0.72
    taper = 1.0
    if t < 0.22:
        taper = 0.58 + 0.42 * (t / 0.22) ** 0.62
    elif t > 0.88:
        taper = 1.0 - 0.20 * ((t - 0.88) / 0.12) ** 1.4
    return HEAD_RX * base * taper, HEAD_RY * base * taper, 2.05


def head_surface_y(x, z, front=True):
    """头部前/后表面 y。**必须包含 HEAD_CY** —— 头部网格是以 cy=HEAD_CY 放样的，
    初版这里漏掉偏移，导致所有面部贴片被放进颅骨内侧 10 mm，渲染成一张空脸。"""
    rx, ry, power = head_profile(z)
    ratio = min(abs(x) / max(rx, 1e-6), 1.0)
    inner = max(1.0 - ratio ** power, 0.0)
    y = ry * inner ** (1.0 / power)
    y = -y if front else y
    return y + HEAD_CY


def head_point(x, z, offset=0.0, front=True):
    """面部贴片落点：沿椭球面外推 offset，保证浮在皮肤之上。"""
    rx, ry, power = head_profile(z)
    ratio = min(abs(x) / max(rx, 1e-6), 1.0)
    inner = max(1.0 - ratio ** power, 0.0)
    y = (ry + offset) * inner ** (1.0 / power)
    y = -y if front else y
    return Vector((x, y + HEAD_CY, z))


def head_normal(x, z, front=True):
    e = 0.0015
    y = head_surface_y(x, z, front)

    def F(px, pz):
        rx, ry, power = head_profile(pz)
        return (abs(px) / max(rx, 1e-6)) ** power + (abs(y) / max(ry, 1e-6)) ** power - 1.0

    g = Vector(((F(x + e, z) - F(x - e, z)) / (2 * e), 0.0,
                (F(x, z + e) - F(x, z - e)) / (2 * e)))
    g.y = -1.0 if front else 1.0
    return g.normalized() if g.length > 1e-9 else Vector((0.0, -1.0, 0.0))


# ------------------------------------------------------------------ 头部

def build_head():
    rows = []
    steps = 18
    for i in range(steps + 1):
        t = i / steps
        z = (CHIN_Z - 0.030) + (HEAD_TOP + 0.012 - (CHIN_Z - 0.030)) * t
        rx, ry, power = head_profile(z)
        rows.append(ring(z, rx, ry, 26, power, cy=HEAD_CY))
    head = loft("BW_Head", rows, material=MAT["skin"])

    ears = []
    for sign in (1, -1):
        tag = "L" if sign > 0 else "R"
        ear = sphere("BW_Ear_" + tag, (sign * HEAD_RX * 0.94, HEAD_CY + 0.012, EYE_Z - 0.012),
                     (0.016, 0.030, 0.040), MAT["skin"], 12, 8)
        activate(ear)
        ear.scale = (1.0, 0.40, 1.0)
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        ears.append(ear)
    # 脖子：从肩到（缩放后的）下巴；Q 版极短颈
    neck_top = HEAD_CHIN_FINAL - 0.004
    neck = loft("BW_Neck", [
        ring(SHOULDER_Z - 0.014, 0.045, 0.042, 18, 2.1, cy=HEAD_CY * 0.6),
        ring(SHOULDER_Z + (neck_top - SHOULDER_Z) * 0.45, 0.043, 0.040, 18, 2.1,
             cy=HEAD_CY * 0.7),
        ring(neck_top, 0.042, 0.039, 18, 2.1, cy=HEAD_CY * 0.9),
    ], material=MAT["skin"])
    return [head] + ears + [neck]


# ------------------------------------------------------------------ 面部

# 参考图：单眼宽度约为脸宽的 1/3，眼高约为脸高的 1/4 —— Q 版大头必须大眼
EYE_X = 0.097
EYE_HALF_W = 0.074
EYE_HALF_H = 0.090
IRIS_RX = 0.0470
IRIS_RZ = 0.0560


def eye_outline(cx, cz, hw, hh, n=20, top_bias=1.0):
    """大眼轮廓：上睑圆拱、下睑略平。"""
    pts = []
    for i in range(n + 1):
        u = -1.0 + 2.0 * i / n
        h = hh * math.sqrt(max(1.0 - u * u, 0.0)) * top_bias
        pts.append((u * hw, h))
    for i in range(n - 1, 0, -1):
        u = -1.0 + 2.0 * i / n
        h = -hh * 0.86 * math.sqrt(max(1.0 - u * u, 0.0))
        pts.append((u * hw, h))
    return [(cx + x, cz + z) for x, z in pts]


def build_face():
    parts = []
    for sign in (1, -1):
        tag = "L" if sign > 0 else "R"
        cx = EYE_X * sign

        def base(px, pz, off):
            return head_point(px, pz, off, True)

        # --- 眼：白眼球 -> 蓝虹膜（三段渐变）-> 瞳孔 -> 双高光；黑色只留细上眼线 ---
        # 初版把深靛虹膜画满整个眼白、又叠了粗上眼线与下眼线，正面读成一圈熊猫眼。
        # 现在虹膜只占眼白的 0.62 宽 / 0.66 高，四周留白；下眼线整条去掉。
        parts.append(flat_patch("BW_EyeWhite_" + tag,
                                eye_outline(cx, EYE_Z, EYE_HALF_W, EYE_HALF_H),
                                base, MAT["eye_white"], 0.0026, rings_n=3))
        parts.append(flat_patch("BW_IrisDeep_" + tag,
                                eye_outline(cx, EYE_Z + 0.009, IRIS_RX, IRIS_RZ, n=18),
                                base, MAT["eye_deep"], 0.0032, rings_n=2))
        parts.append(flat_patch("BW_IrisMid_" + tag,
                                eye_outline(cx, EYE_Z - 0.011, IRIS_RX * 0.80, IRIS_RZ * 0.50, n=16),
                                base, MAT["eye_mid"], 0.0038, rings_n=2))
        parts.append(flat_patch("BW_IrisLight_" + tag,
                                eye_outline(cx, EYE_Z - 0.030, IRIS_RX * 0.52, IRIS_RZ * 0.24, n=14),
                                base, MAT["eye_light"], 0.0043, rings_n=2))
        parts.append(flat_patch("BW_Pupil_" + tag,
                                eye_outline(cx, EYE_Z + 0.004, 0.0155, 0.0215, n=12),
                                base, MAT["eye_line"], 0.0050, rings_n=2))
        parts.append(flat_patch("BW_GlintBig_" + tag,
                                eye_outline(cx - 0.021 * sign, EYE_Z + 0.032, 0.0150, 0.0165, n=10),
                                base, MAT["eye_white"], 0.0057, rings_n=2))
        parts.append(flat_patch("BW_GlintSmall_" + tag,
                                eye_outline(cx + 0.023 * sign, EYE_Z - 0.022, 0.0086, 0.0094, n=8),
                                base, MAT["eye_white"], 0.0057, rings_n=2))
        # 上眼线：细带 + 外眼角加厚的睫毛尖（不再是一整圈黑框）
        lash = []
        n = 22
        for i in range(n + 1):
            u = -1.0 + 2.0 * i / n
            h = EYE_HALF_H * math.sqrt(max(1.0 - u * u, 0.0))
            lash.append((u * (EYE_HALF_W + 0.002), h + 0.0042 * (0.55 + 0.45 * (1.0 + u) * 0.5)))
        for i in range(n, -1, -1):
            u = -1.0 + 2.0 * i / n
            h = EYE_HALF_H * math.sqrt(max(1.0 - u * u, 0.0))
            lash.append((u * (EYE_HALF_W + 0.002), h - 0.0026))
        lash = [(cx + x, EYE_Z + z) for x, z in lash]
        parts.append(flat_patch("BW_Lash_" + tag, lash, base, MAT["eye_line"], 0.0064, rings_n=2))
        # 外眼角睫毛：一小撮上扬三角
        lash_tip = [(-0.002, -0.0035), (0.0165, 0.0055), (0.0245, 0.0135),
                    (0.0125, 0.0075), (-0.002, 0.0015)]
        lash_tip = [(cx + sign * x, EYE_Z + z) for x, z in lash_tip]
        parts.append(flat_patch("BW_LashTip_" + tag, lash_tip, base, MAT["eye_line"],
                                0.0066, rings_n=2))
        # 眉毛（细短、平缓）
        brow = []
        m = 12
        for i in range(m + 1):
            u = i / m
            brow.append(((-1.0 + 2.0 * u) * 0.058, EYE_Z + 0.118 + 0.012 * (u ** 1.6)))
        for i in range(m, -1, -1):
            u = i / m
            t = 0.006 + 0.008 * math.sin(math.pi * min(max(u / 0.9, 0.0), 1.0))
            brow.append(((-1.0 + 2.0 * u) * 0.058, EYE_Z + 0.118 + 0.012 * (u ** 1.6) - t))
        brow = [(cx + x, z) for x, z in brow]
        parts.append(flat_patch("BW_Brow_" + tag, brow, base, MAT["hair_dark"], 0.0050, rings_n=2))
        # 腮红
        blush = eye_outline(cx * 1.06, EYE_Z - 0.098, 0.042, 0.026, n=14)
        parts.append(flat_patch("BW_Blush_" + tag, blush, base, MAT["blush"], 0.0030, rings_n=2))

    # 嘴：很小、平静的微笑
    mouth = []
    m = 12
    for i in range(m + 1):
        u = -1.0 + 2.0 * i / m
        mouth.append((u * 0.019, 0.0055 * math.sqrt(max(1.0 - u * u, 0.0))))
    for i in range(m, -1, -1):
        u = -1.0 + 2.0 * i / m
        mouth.append((u * 0.019, -0.0075 * math.sqrt(max(1.0 - u * u, 0.0))))
    mouth = [(x, EYE_Z - 0.118 + z) for x, z in mouth]
    parts.append(flat_patch("BW_Mouth", mouth,
                            lambda px, pz, off: head_point(px, pz, off, True),
                            MAT["mouth"], 0.0036, rings_n=2))
    # 鼻：几乎不做，只留极小一点
    parts.append(flat_patch("BW_Nose", eye_outline(0.0, EYE_Z - 0.062, 0.011, 0.008, n=10),
                            lambda px, pz, off: head_point(px, pz, off, True),
                            MAT["skin"], 0.0055, rings_n=2))
    return parts


# ------------------------------------------------------------------ 头发
#
# 参考图：深靛蓝发根 → 亮蓝发梢；刘海分大束（中心轻微 V）；两侧长鬓发外翻卷；
# 后发为蓬松钟形，落至大腿，至少 4–6 个可读大波浪；头顶一根弧形呆毛。

HAIR_TOP = HEAD_TOP + 0.030
HAIR_OUT = 0.026          # 发壳相对头皮的厚度


def hair_gradient_material(z, z_top, z_bot):
    """按高度选深/中/浅三档发色，模拟参考图的渐变。"""
    t = (z - z_bot) / max(z_top - z_bot, 1e-6)
    if t > 0.62:
        return MAT["hair_dark"]
    if t > 0.30:
        return MAT["hair_mid"]
    return MAT["hair_tip"]


# 发际高度（米）。参考图：额头露出较多，眼睛上方约 0.09 处是发际中心。
# 初版把发壳从眼睛高度整个罩住，导致头发包住整张脸（本轮最大失败点）。
HAIRLINE_FRONT_Z = EYE_Z + 0.120
HAIRLINE_SIDE_Z = EYE_Z + 0.056
HAIRLINE_BACK_Z = EYE_Z - 0.016


def hairline_z(angle_from_front_deg):
    """发际线高度随方位角变化：前中最高（露额），两侧下降，后颈最低。"""
    a = abs(angle_from_front_deg)
    if a <= 90.0:
        u = a / 90.0
        return HAIRLINE_FRONT_Z + (HAIRLINE_SIDE_Z - HAIRLINE_FRONT_Z) * (u ** 1.35)
    u = (a - 90.0) / 90.0
    return HAIRLINE_SIDE_Z + (HAIRLINE_BACK_Z - HAIRLINE_SIDE_Z) * (u ** 0.85)


def hair_point(x, z, ang_front, grow):
    """发壳外表面点：在头型截面基础上按方位角向后加厚。"""
    rx, ry, power = head_profile(z)
    back = max(0.0, math.cos(math.radians(180.0 - ang_front))) if ang_front > 90 else 0.0
    gx = rx + grow * (1.0 + 0.34 * back)
    gy = ry + grow * (1.0 + 1.05 * back)
    ratio = min(abs(x) / max(gx, 1e-6), 1.0)
    inner = max(1.0 - ratio ** power, 0.0)
    y = gy * inner ** (1.0 / power)
    sx = math.copysign(1.0, x) if abs(x) > 1e-9 else 1.0
    y = y if (x * sx) < gx else y
    # 前侧取 -Y，后侧取 +Y
    if abs(ang_front) <= 90.0:
        y = -abs(y)
    else:
        y = abs(y)
    return Vector((x, y + HEAD_CY, z))


def build_hair_shell():
    """发帽：只做**贴头底层**，上缘由发际线决定；再加后脑独立钟形发量。"""
    parts = []
    seg = 34
    rings = []
    steps = 12
    for r_i in range(steps + 1):
        t = r_i / steps
        row = []
        for k in range(seg):
            ang = TAU * k / seg
            ang_front = math.degrees(abs(((ang - TAU * 0.75 + math.pi) % TAU) - math.pi))
            z0 = hairline_z(ang_front)
            z = z0 + (HAIR_TOP - z0) * (t ** 0.78)
            rx, ry, power = head_profile(z)
            # 顶端收敛：接近颅顶时半径快速收小 -> 连续穹顶，不再截平成"瓶盖"
            cap = 1.0
            if t > 0.80:
                cap = max(0.18, 1.0 - 0.92 * ((t - 0.80) / 0.20) ** 1.25)
            grow = HAIR_OUT * (0.70 + 0.42 * t) * cap
            x, y = superellipse(ang, (rx + grow) * (0.55 + 0.45 * cap),
                                (ry + grow) * (0.55 + 0.45 * cap), power)
            row.append(Vector((x, y + HEAD_CY, z)))
        rings.append(row)
    # 穹顶封口
    apex_z = HAIR_TOP + 0.014
    rings.append([Vector((0.016 * math.cos(TAU * k / seg), 0.016 * math.sin(TAU * k / seg),
                          apex_z)) for k in range(seg)])
    parts.append(loft("BW_HairCap", rings, material=MAT["hair_dark"]))

    # 后发：**层叠长发瀑布**（不是一颗球）。
    # 内层 = 贴背扁弧板（遮住后颈与发壳接缝、提供发量底色）；
    # 外层 = 7 条外露长发束，中央最长、两侧渐短，末端 S/C 外翻卷 + 亮蓝发梢。
    back_rows = []
    steps = 14
    z_start = EYE_Z + 0.060
    z_end = local_z(HIP_Z + 0.015)
    for i in range(steps + 1):
        t = i / steps
        z = z_start + (z_end - z_start) * t
        width = 0.168 + 0.040 * math.sin(math.pi * min(t * 0.95, 1.0)) - 0.058 * (t ** 2.8)
        depth = 0.048 + 0.020 * math.sin(math.pi * min(t * 0.90, 1.0))
        cy = HEAD_CY + 0.086 + 0.016 * t
        row = []
        span = math.radians(96.0)
        seg_n = 22
        for k in range(seg_n):
            a = math.radians(90.0) + (-span + 2.0 * span * k / (seg_n - 1))
            row.append(Vector((math.cos(a) * width, cy + math.sin(a) * depth, z)))
        back_rows.append(row)
    # 内层背板用最深的发色，只做"遮缝 + 发量底色"，不能抢外露发束的轮廓
    parts.append(sheet("BW_HairBackBase", back_rows, 0.026, MAT["hair_dark"]))

    # 每束的粗细/卷向/弯曲幅度都不同，避免读成 7 根等粗"面条"
    locks = (
        ("L1", -0.178, 0.096, 0.044, 0.70, 0.056, 1.35),
        ("L2", -0.128, 0.128, 0.056, 0.84, -0.046, 0.85),
        ("L3", -0.072, 0.148, 0.050, 0.94, 0.034, 1.15),
        ("L4", 0.000, 0.158, 0.060, 1.00, -0.028, 0.75),
        ("L5", 0.072, 0.148, 0.050, 0.94, 0.034, 1.15),
        ("L6", 0.128, 0.128, 0.056, 0.84, -0.046, 0.85),
        ("L7", 0.178, 0.096, 0.044, 0.70, 0.056, 1.35),
    )
    top = local_z(HEAD_CHIN_FINAL + 0.150)
    bottom = CHIN_Z - 0.320
    for name, x0, y0, rad, length_f, curl, wig in locks:
        pts, radii = [], []
        seg = 10
        bot = bottom + (1.0 - length_f) * 0.130
        for i in range(seg + 1):
            t = i / seg
            z = top + (bot - top) * t
            # S 形纵向摆动（wig 放大/收窄），让发束有波浪而不是直线下垂
            sway = math.sin(t * math.pi * 1.05 * wig) * 0.026
            wave_z = 0.014 * math.sin(t * math.pi * 2.1 * wig)
            flare = 0.028 * (t ** 1.8)
            sgn = 1.0 if x0 >= 0 else -1.0
            x = x0 * (1.0 + 0.26 * t) + sgn * (sway + flare)
            y = HEAD_CY + y0 + 0.028 * math.sin(t * math.pi * 0.85) + curl * (t ** 3.0) * 1.4
            pts.append(Vector((x, y, z + wave_z)))
            radii.append(rad * (1.0 - 0.28 * (t ** 2.2)))
        parts.append(tube_along("BW_BackLock_" + name, pts, radii, 14, MAT["hair_mid"],
                                squash=0.58))
        # 发梢：亮蓝外翻 C 卷
        tip_pts, tip_r = [], []
        tseg = 5
        for i in range(tseg + 1):
            t = i / tseg
            ang = math.radians(155.0 * t)
            r = rad * 0.80
            sgn = 1.0 if x0 >= 0 else -1.0
            tip_pts.append(Vector((pts[-1].x + sgn * r * math.sin(ang) * 0.85,
                                   pts[-1].y + curl * 0.9 + r * (1.0 - math.cos(ang)) * 0.70,
                                   pts[-1].z - r * math.sin(ang) * 0.60)))
            tip_r.append(rad * 0.62 * (1.0 - 0.40 * t))
        parts.append(tube_along("BW_BackTip_" + name, tip_pts, tip_r, 10,
                                MAT["hair_tip"], squash=0.52))
    return parts


def build_hair_waves():
    """后发 5 个可读大波浪发束：末端外卷。"""
    parts = []
    # 5 条大波浪：位置与相位错开，末端外卷，落在裙摆之上
    specs = (
        ("W1", -0.190, 0.070, 0.046, local_z(KNEE_Z + 0.120), 0.034),
        ("W2", -0.120, 0.128, 0.040, local_z(KNEE_Z + 0.090), -0.030),
        ("W3", 0.000, 0.150, 0.044, local_z(KNEE_Z + 0.072), 0.026),
        ("W4", 0.120, 0.128, 0.040, local_z(KNEE_Z + 0.090), -0.030),
        ("W5", 0.190, 0.070, 0.046, local_z(KNEE_Z + 0.120), 0.034),
    )
    for name, x0, y0, rad, z_end, curl in specs:
        pts = []
        radii = []
        seg = 9
        for i in range(seg + 1):
            t = i / seg
            # 沿 z 下落，x 向外鼓，末端外卷
            z = (CHIN_Z - 0.010) + (z_end - (CHIN_Z - 0.010)) * t
            sway = math.sin(t * math.pi * 1.15) * 0.030
            x = x0 * (1.0 + 0.42 * t) + sway * (1.0 if x0 >= 0 else -1.0)
            y = y0 + 0.030 * math.sin(t * math.pi) + curl * (t ** 3.2) * 2.2
            pts.append(Vector((x, y, z)))
            radii.append(rad * (1.0 - 0.34 * (t ** 2.2)))
        wave = tube_along("BW_Wave_" + name, pts, radii, 14,
                          hair_gradient_material(z_end, HAIR_TOP, CHIN_Z - 0.15), squash=0.80)
        parts.append(wave)
    return parts


def build_bangs():
    """刘海：分成清晰大束，中心轻微 V 形。"""
    parts = []
    # 7 束厚实刘海：用管状体块而不是贴壳薄片，正面外轮廓才读得出来。
    # 中束最短形成轻微 V 分缝，向两侧逐渐加长。
    # 刘海长度必须停在眼睛上方：初版长到遮住眼睛，读成"面条挂在脸上"。
    # 中束最短形成轻微 V 分缝，向两侧略加长；宽度大、厚度扁，才有发束轮廓。
    # 长度按「发际线到眼睛上缘」的实际间距给足余量：
    # 直接给短长度，而不是把长束夹到 eye_top（夹取会把发束压成一排平齐的短桩）。
    # 每束更宽、更扁（squash 0.30），贴额平铺；避免读成"额头上插的一排小旗"
    specs = (
        ("C1", 0.000, 0.060, 0.030, 0.062),
        ("L1", -0.070, 0.058, 0.034, 0.060),
        ("R1", 0.070, 0.058, 0.034, 0.060),
        ("L2", -0.132, 0.056, 0.044, 0.056),
        ("R2", 0.132, 0.056, 0.044, 0.056),
        ("L3", -0.180, 0.050, 0.054, 0.052),
        ("R3", 0.180, 0.050, 0.054, 0.052),
    )
    for name, x0, half_w, length, thick in specs:
        # 沿该束的方位角方向，自发际线向下的一段弧线
        pts, radii = [], []
        seg = 7
        ang = x0 / max(HEAD_RX, 1e-6)
        ang = max(-1.0, min(1.0, ang))
        z_top = hairline_z(abs(ang) * 90.0)
        for i in range(seg + 1):
            t = i / seg
            # 先贴额向下，末端略向外翘（发梢外翻）
            z = z_top + 0.010 - length * t
            swing = 0.012 * (t ** 2.4)
            x = x0 * (1.0 + 0.14 * t) + swing * (1.0 if x0 >= 0 else -1.0)
            rx, ry, power = head_profile(z)
            ratio = min(abs(x) / max(rx, 1e-6), 1.0)
            inner = max(1.0 - ratio ** power, 0.0)
            # 紧贴发帽外表面（发帽厚度 0.014–0.029），只往外让 4–8 mm
            yy = -(ry + 0.026 + 0.006 * t) * inner ** (1.0 / power) + HEAD_CY
            pts.append(Vector((x, yy, z)))
            radii.append(thick * (1.0 - 0.14 * (t ** 2.0)))
        clump = tube_along("BW_Bang_" + name, pts, radii, 12,
                           MAT["hair_dark"] if abs(x0) < 0.09 else MAT["hair_mid"],
                           squash=0.30)
        parts.append(clump)
    return parts


def build_side_locks():
    """两侧长鬓发：外翻卷，落至肩下。"""
    parts = []
    for sign in (1, -1):
        tag = "L" if sign > 0 else "R"
        pts, radii = [], []
        seg = 10
        for i in range(seg + 1):
            t = i / seg
            z = (CHIN_Z + 0.010) + (local_z(SHOULDER_Z - 0.115) - (CHIN_Z + 0.010)) * t
            bulge = math.sin(t * math.pi * 0.85) * 0.036
            flip = 0.055 * (t ** 3.0)          # 末端外翻
            x = sign * (HEAD_RX * 0.96 + bulge + flip)
            y = HEAD_CY - 0.030 + 0.060 * t + 0.034 * (t ** 2.4)
            pts.append(Vector((x, y, z)))
            radii.append(0.055 * (1.0 - 0.44 * (t ** 2.0)))
        lock = tube_along("BW_SideLock_" + tag, pts, radii, 12,
                          hair_gradient_material(CHIN_Z - 0.10, HAIR_TOP, CHIN_Z - 0.22),
                          squash=0.72)
        parts.append(lock)
    return parts


def build_ahoge():
    """头顶弧形呆毛。"""
    pts, radii = [], []
    seg = 8
    for i in range(seg + 1):
        t = i / seg
        z = HAIR_TOP - 0.010 + 0.075 * math.sin(t * math.pi * 0.72)
        x = 0.012 * math.sin(t * math.pi * 1.6)
        y = HEAD_CY + 0.010 + 0.055 * t - 0.028 * (t ** 2.2)
        pts.append(Vector((x, y, z)))
        radii.append(0.017 * (1.0 - 0.62 * (t ** 1.7)))
    return [tube_along("BW_Ahoge", pts, radii, 10, MAT["hair_dark"])]


def build_headdress():
    """白色扇贝/荷叶边蕾丝发箍 + 左右蓝蝴蝶结 + 耳侧鲸鳍。"""
    parts = []
    # 发箍：贴着发壳上缘的一圈荷叶边（后半圈）
    # 女仆发箍：横跨头顶的**拱形**扇贝蕾丝带（正面必须看到白色冠部）。
    # 初版做成 XY 平面水平环 -> 正面只看到一条水平白杠（主代理验收失败点）。
    crown = []
    band_rows = []
    steps = 40
    for i in range(steps + 1):
        t = i / steps
        # 从左侧耳上经头顶到右侧耳上：方位角 -78° -> +78°（以正面为 0）
        # 头箍从左侧耳上经头顶到右侧耳上；必须**贴着发冠**，不能浮在头顶上方。
        # 初版半径过大 + 高度过高，读成一道漂在头上的白色波浪拱（主代理验收失败点）。
        ang = math.radians(-84.0 + 168.0 * t)
        cap_r = HEAD_RX + HAIR_OUT + 0.014
        z = EYE_Z + 0.166 + 0.104 * math.cos(ang * 0.94)
        rr = 0.150 + 0.050 * abs(math.sin(ang))
        x = math.sin(ang) * cap_r * 0.96
        y = -rr * 0.30 * math.cos(ang) + HEAD_CY + 0.006
        scallop = 0.013 * math.sin(t * math.pi * 9.0)
        crown.append(Vector((x, y, z + scallop)))
        band_rows.append([Vector((x, y, z + scallop - 0.020)),
                          Vector((x, y, z + scallop + 0.020))])
    parts.append(sheet("BW_HeaddressBand", band_rows, 0.013, MAT["white_soft"]))
    parts.append(sheet("BW_HeaddressRuffle",
                       [[Vector((p.x * 1.01, p.y, p.z - 0.024)),
                         Vector((p.x * 1.08, p.y, p.z - 0.002))] for p in crown],
                       0.009, MAT["white"]))
    # 额前中央的连续扇贝荷叶边（女仆头箍的正面特征）：沿弧线的一整条波浪带，
    # 而不是几个孤立的白色圆点（主代理验收失败点）
    scallop_rows = []
    n = 26
    for i in range(n + 1):
        t = i / n
        ang = math.radians(-66.0 + 132.0 * t)
        cap_r = HEAD_RX + HAIR_OUT + 0.016
        z = EYE_Z + 0.162 + 0.100 * math.cos(ang * 0.94)
        wave = 0.011 * math.sin(t * math.pi * 11.0)
        x = math.sin(ang) * cap_r * 0.98
        y = -(HEAD_RY + HAIR_OUT + 0.012) * math.cos(ang) * 0.92 + HEAD_CY
        scallop_rows.append([Vector((x * 1.00, y + 0.004, z + wave - 0.022)),
                             Vector((x * 1.05, y - 0.006, z + wave + 0.006))])
    parts.append(sheet("BW_HeadScallops", scallop_rows, 0.008, MAT["white"]))
    # 左右蓝蝴蝶结
    for sign in (1, -1):
        tag = "L" if sign > 0 else "R"
        bx = sign * 0.196
        by = HEAD_CY + 0.004
        bz = EYE_Z + 0.196
        for side in (1, -1):
            wing_pts, wing_r = [], []
            for i in range(6):
                t = i / 5.0
                wing_pts.append(Vector((bx + sign * side * 0.052 * math.sin(t * 1.3),
                                        by - 0.010 + 0.030 * t,
                                        bz + 0.030 * math.sin(t * math.pi) - 0.010 * t)))
                wing_r.append(0.034 * (1.0 - 0.40 * abs(t - 0.5) * 2.0) + 0.006)
            parts.append(tube_along("BW_BowWing_%s_%d" % (tag, side), wing_pts, wing_r,
                                    8, MAT["whale_blue"], squash=0.45))
        parts.append(sphere("BW_BowKnot_" + tag, (bx, by - 0.006, bz), (0.020, 0.018, 0.018),
                            MAT["navy"], 10, 8))
    # 耳侧鲸鳍：每侧 3 层短小羽鳍（白 -> 淡蓝 -> 蓝），读成鳍而不是插在太阳穴的纸片
    fin_mats = (MAT["white"], MAT["eye_light"], MAT["whale_blue"])
    for sign in (1, -1):
        tag = "L" if sign > 0 else "R"
        for layer, mat in enumerate(fin_mats):
            rows = []
            size = 0.042 - 0.008 * layer
            for i in range(4):
                t = i / 3.0
                row = []
                for k in range(5):
                    u = -1.0 + 2.0 * k / 4.0
                    x = sign * (HEAD_RX + 0.016 + 0.024 * t + 0.007 * (1.0 - abs(u))
                                + 0.005 * layer)
                    z = (EYE_Z - 0.026 + 0.030 * t + size * u * (1.0 - 0.30 * t)
                         - 0.019 * layer)
                    y = HEAD_CY + 0.004 + 0.036 * t + 0.012 * abs(u) + 0.013 * layer
                    row.append(Vector((x, y, z)))
                rows.append(row)
            parts.append(sheet("BW_EarFin_%s_%d" % (tag, layer), rows, 0.007, mat))
    return parts


# ------------------------------------------------------------------ 身体 / 服装

TORSO_PROFILE = [
    (HIP_Z - 0.040, 0.116, 0.086),
    (HIP_Z, 0.118, 0.088),
    (WAIST_Z, 0.100, 0.076),
    (WAIST_Z + 0.055, 0.106, 0.080),
    (SHOULDER_Z - 0.012, 0.116, 0.086),
    (SHOULDER_Z + 0.016, 0.106, 0.080),
    (SHOULDER_Z + 0.034, 0.082, 0.066),
]


def torso_profile_at(z):
    prof = TORSO_PROFILE
    if z <= prof[0][0]:
        return prof[0][1], prof[0][2]
    if z >= prof[-1][0]:
        return prof[-1][1], prof[-1][2]
    for i in range(len(prof) - 1):
        z0, rx0, ry0 = prof[i]
        z1, rx1, ry1 = prof[i + 1]
        if z0 <= z <= z1:
            u = (z - z0) / max(z1 - z0, 1e-9)
            return rx0 + (rx1 - rx0) * u, ry0 + (ry1 - ry0) * u
    return prof[-1][1], prof[-1][2]


def build_body():
    """躯干 + 手臂 + 腿（皮肤层，大部被衣物覆盖，提供绑骨所需的连续环线）。"""
    parts = []
    rows = []
    steps = 12
    for i in range(steps + 1):
        t = i / steps
        z = (HIP_Z - 0.055) + (SHOULDER_Z + 0.030 - (HIP_Z - 0.055)) * t
        rx, ry = torso_profile_at(z)
        rows.append(ring(z, rx * 0.94, ry * 0.94, 22, 2.15))
    parts.append(loft("BW_TorsoSkin", rows, material=MAT["skin"]))

    # 手臂：轻 A pose（外展约 55°），动作友好
    for sign in (1, -1):
        tag = "L" if sign > 0 else "R"
        sh = Vector((SHOULDER_X * sign, 0.0, SHOULDER_Z + 0.004))
        abd = math.radians(52.0)
        d1 = Vector((math.sin(abd) * sign, 0.0, -math.cos(abd))).normalized()
        d2 = (d1 + Vector((0.0, -0.16, 0.0))).normalized()
        elbow = sh + d1 * 0.112
        wrist = elbow + d2 * 0.104
        pts = [sh + d1 * u for u in (-0.026, 0.026, 0.078, 0.112)] + \
              [elbow + d2 * u for u in (0.034, 0.074, 0.104)]
        rad = [0.046, 0.041, 0.037, 0.034, 0.032, 0.030, 0.028]
        parts.append(tube_along("BW_Arm_" + tag, pts, rad, 12, MAT["skin"]))

        # 手：简化 Q 版手套式圆手 + 分指轮廓（与袖口区分）
        hand_dir = d2
        palm = wrist + hand_dir * 0.030
        hand_rows = []
        for i in range(4):
            t = i / 3.0
            c = wrist + hand_dir * (0.014 + 0.052 * t)
            r = 0.036 * (1.0 - 0.16 * t)
            row = []
            for k in range(12):
                a = TAU * k / 12
                row.append(c + Vector((math.cos(a) * r * 1.06, math.sin(a) * r * 0.62,
                                       math.sin(a) * 0.0))
                           + Vector((0.0, 0.0, 0.0)))
            hand_rows.append(row)
            # 用垂直于 hand_dir 的平面
        # 重建：垂直于 hand_dir 的环
        u_axis = Vector((0.0, 1.0, 0.0))
        v_axis = hand_dir.cross(u_axis).normalized()
        hand_rings = []
        for i in range(5):
            t = i / 4.0
            c = wrist + hand_dir * (0.009 + 0.050 * t)
            r = 0.034 * (1.0 - 0.20 * t)
            ring_pts = []
            for k in range(14):
                a = TAU * k / 14
                ring_pts.append(c + u_axis * (math.cos(a) * r * 0.95)
                                + v_axis * (math.sin(a) * r * 0.70))
            hand_rings.append(ring_pts)
        parts.append(loft("BW_Hand_" + tag, hand_rings, material=MAT["skin"]))
        # 拇指
        thumb_dir = (hand_dir * 0.55 - u_axis * 0.80).normalized()
        tp = [wrist + hand_dir * 0.021 + u_axis * (-0.018) + thumb_dir * (0.023 * u)
              for u in (0.0, 0.5, 1.0)]
        parts.append(tube_along("BW_Thumb_" + tag, tp, [0.0140, 0.0122, 0.0090], 8,
                                MAT["skin"]))

    # 腿：短肢，膝/踝处留独立环线
    for sign in (1, -1):
        tag = "L" if sign > 0 else "R"
        hip = Vector((HIP_X * sign, 0.0, HIP_Z - 0.015))
        knee = Vector((HIP_X * sign * 1.06, -0.004, KNEE_Z))
        ankle = Vector((HIP_X * sign * 1.06, -0.002, ANKLE_Z + 0.020))
        pts = [hip + (knee - hip) * u for u in (0.0, 0.34, 0.68, 1.0)] + \
              [knee + (ankle - knee) * u for u in (0.30, 0.62, 1.0)]
        rad = [0.060, 0.056, 0.052, 0.050, 0.048, 0.046, 0.044]
        parts.append(tube_along("BW_Leg_" + tag, pts, rad, 12, MAT["skin"]))
    return parts


def build_dress():
    """深海军蓝女仆连衣裙：主裙体 + 泡泡袖 + 领子 + 领结。"""
    parts = []
    # 主裙体：胸腰贴合，裙摆向下外扩
    rows = []
    steps = 16
    for i in range(steps + 1):
        t = i / steps
        z = (SHOULDER_Z + 0.020) - (SHOULDER_Z + 0.020 - (KNEE_Z + 0.052)) * t
        rx, ry = torso_profile_at(max(z, HIP_Z - 0.030))
        # 裙摆外扩
        flare = 1.0
        if z < HIP_Z:
            u = (HIP_Z - z) / max(HIP_Z - (KNEE_Z + 0.052), 1e-6)
            flare = 1.0 + 0.72 * (u ** 1.25)
        expand = 0.016 + 0.010 * (1.0 - t)
        rows.append(ring(z, (rx + expand) * flare, (ry + expand) * flare, 30, 2.1))
    parts.append(loft("BW_DressBody", rows, material=MAT["navy"]))

    # 裙摆下缘：荷叶边两层
    hem_z = KNEE_Z + 0.052
    parts.append(ruffle("BW_DressRuffle1", (0.0, 0.0, hem_z + 0.030), 0.312, 20, 0.013, 0.034,
                        MAT["navy_deep"], 0.008))
    parts.append(ruffle("BW_DressRuffle2", (0.0, 0.0, hem_z - 0.004), 0.330, 24, 0.015, 0.030,
                        MAT["white"], 0.008))
    # 金色细边
    # 金色细边：必须贴在外层裙壳表面。初版用一个固定半径的独立环，渲染成悬空的
    # 金色呼啦圈（主代理验收失败点）。这里按裙体同一套"下摆外扩"公式取半径。
    def skirt_radius_at(z):
        rx, ry = torso_profile_at(max(z, HIP_Z - 0.030))
        u = max(0.0, (HIP_Z - z) / max(HIP_Z - (KNEE_Z + 0.052), 1e-6))
        flare = 1.0 + 0.72 * (u ** 1.25)
        return (rx + 0.016) * flare, (ry + 0.016) * flare

    trim_z = hem_z + 0.086
    trx, _try = skirt_radius_at(trim_z)
    trim_rows = []
    n = 44
    for i in range(n + 1):
        a = TAU * i / n
        row = []
        for k in range(2):
            rr = trx + 0.0016 * k
            row.append(Vector((math.cos(a) * rr, math.sin(a) * rr, trim_z - 0.0035 * k)))
        trim_rows.append(row)
    parts.append(sheet("BW_GoldTrim", trim_rows, 0.0055, MAT["gold"]))

    # 泡泡袖
    for sign in (1, -1):
        tag = "L" if sign > 0 else "R"
        sh = Vector((SHOULDER_X * sign * 0.94, 0.0, SHOULDER_Z + 0.008))
        abd = math.radians(52.0)
        d1 = Vector((math.sin(abd) * sign, 0.0, -math.cos(abd))).normalized()
        puff_pts = [sh + d1 * u for u in (-0.020, 0.008, 0.036, 0.062, 0.080)]
        puff_r = [0.046, 0.062, 0.066, 0.054, 0.040]
        parts.append(tube_along("BW_PuffSleeve_" + tag, puff_pts, puff_r, 16,
                                MAT["navy"], squash=0.94))
        # 白色花边袖口
        cuff_c = sh + d1 * 0.086
        parts.append(ruffle("BW_SleeveRuffle_" + tag, (cuff_c.x, cuff_c.y, cuff_c.z),
                            0.046, 12, 0.007, 0.016, MAT["white"], 0.006,
                            tilt=-0.40 * sign))
    # 领子（白色折领）
    # 白色折领：小一圈、薄一层，避免在下巴下面读成一整块白砖
    parts.append(loft("BW_Collar", [
        ring(SHOULDER_Z + 0.030, 0.098, 0.080, 22, 2.1),
        ring(SHOULDER_Z + 0.046, 0.090, 0.074, 22, 2.1),
        ring(SHOULDER_Z + 0.058, 0.078, 0.066, 22, 2.1),
    ], material=MAT["white"]))
    # 胸前领结：必须清楚可读（初版只是两个小球，正面几乎看不见）
    knot_c = Vector((0.0, -0.084, SHOULDER_Z - 0.022))
    for sign in (1, -1):
        wing = []
        for i in range(7):
            t = i / 6.0
            ang = math.radians(110.0 * t)
            r = 0.040
            wing.append(Vector((knot_c.x + sign * r * math.sin(ang) * 0.92,
                                knot_c.y - 0.012 * math.sin(ang),
                                knot_c.z + 0.030 * (1.0 - math.cos(ang)) * 0.55 - 0.006 * t)))
        parts.append(tube_along("BW_NeckBow_%d" % sign, wing,
                                [0.015, 0.021, 0.024, 0.024, 0.021, 0.016, 0.010], 10,
                                MAT["navy_deep"], squash=0.60))
    parts.append(sphere("BW_NeckKnot", (knot_c.x, knot_c.y - 0.010, knot_c.z),
                        (0.018, 0.014, 0.018), MAT["navy"], 12, 8))
    parts.append(sphere("BW_NeckGem", (knot_c.x, knot_c.y - 0.020, knot_c.z),
                        (0.010, 0.008, 0.010), MAT["whale_blue"], 12, 8))
    return parts


def build_apron():
    """白色围裙：覆盖正面，带花边 + 鲸鱼图案 + 粉色小爱心 + 系带。"""
    parts = []
    # 围裙主体：贴合躯干前侧的一片
    rows = []
    steps = 12
    for i in range(steps + 1):
        t = i / steps
        z = (SHOULDER_Z - 0.030) - (SHOULDER_Z - 0.030 - (KNEE_Z + 0.075)) * t
        rx, ry = torso_profile_at(max(z, HIP_Z - 0.030))
        flare = 1.0
        if z < HIP_Z:
            u = (HIP_Z - z) / max(HIP_Z - (KNEE_Z + 0.075), 1e-6)
            flare = 1.0 + 0.72 * (u ** 1.25)
        # 上窄下宽的梯形
        half_w = (0.070 + 0.150 * min(t * 1.35, 1.0)) * flare
        row = []
        for k in range(13):
            u = -1.0 + 2.0 * k / 12.0
            x = u * half_w
            depth = (ry + 0.026) * flare
            yy = -depth * max(1.0 - (abs(x) / max((rx + 0.026) * flare, 1e-6)) ** 2.1,
                              0.0) ** (1.0 / 2.1)
            row.append(Vector((x, yy, z)))
        rows.append(row)
    parts.append(sheet("BW_Apron", rows, 0.010, MAT["white"]))
    # 围裙花边
    hem_z = KNEE_Z + 0.075
    parts.append(ruffle("BW_ApronRuffle", (0.0, 0.0, hem_z + 0.020), 0.288, 24, 0.011, 0.026,
                        MAT["white_soft"], 0.007))
    # 鲸鱼图案：明确的侧身小鲸剪影（头吻 + 身体 + 尾鳍 + 喷水）
    # 初版只是两个蓝圆点，读不成鲸鱼（主代理验收失败点）。
    whale_cx = -0.004
    whale_cz = HIP_Z + 0.020
    whale_y = -0.212
    place = lambda px, pz, off: Vector((px, whale_y + off, pz))

    def whale_silhouette_outline(scale=1.0):
        """侧身鲸剪影：从吻端顺时针描一圈（x 右为头，左为尾）。"""
        pts = []
        # 背部（吻 -> 背脊 -> 尾柄）
        for i in range(11):
            t = i / 10.0
            x = (0.052 - 0.112 * t) * scale
            z = (0.020 * math.sin(math.pi * min(t * 1.05, 1.0)) ** 0.52
                 + 0.008 * math.sin(math.pi * t)) * scale
            pts.append((x, z))
        # 尾鳍上叶
        pts.append(((-0.074) * scale, (0.030) * scale))
        pts.append(((-0.090) * scale, (0.012) * scale))
        pts.append(((-0.066) * scale, (0.002) * scale))
        # 腹线（尾柄 -> 吻）
        for i in range(9, -1, -1):
            t = i / 10.0
            x = (0.052 - 0.112 * t) * scale
            z = (-0.016 * math.sin(math.pi * min(t * 1.02, 1.0)) ** 0.60) * scale
            pts.append((x, z))
        return [(whale_cx + x, whale_cz + z) for x, z in pts]

    parts.append(flat_patch("BW_WhaleMark", whale_silhouette_outline(1.0),
                            place, MAT["whale_blue"], 0.0042, rings_n=2))
    # 喷水（三滴小水珠）
    for i, (dx, dz, r) in enumerate(((-0.004, 0.042, 0.006), (-0.014, 0.052, 0.0045),
                                     (0.007, 0.054, 0.0040))):
        parts.append(flat_patch("BW_WhaleSpout_%d" % i,
                                eye_outline(whale_cx + dx, whale_cz + dz, r, r, n=8),
                                place, MAT["whale_blue"], 0.0046, rings_n=2))
    # 粉色小爱心：单个心形（两瓣 + 下尖），不是三个圆
    heart_cz = whale_cz + 0.078
    heart_pts = []
    n = 16
    for i in range(n + 1):
        u = -1.0 + 2.0 * i / n
        x = u * 0.016
        z = 0.008 * math.sqrt(max(1.0 - u * u, 0.0)) ** 0.7
        heart_pts.append((u * 0.016, z + 0.004))
    for i in range(n - 1, -1, -1):
        u = -1.0 + 2.0 * i / n
        z = -0.019 * (1.0 - abs(u)) ** 0.85
        heart_pts.append((u * 0.016, z + 0.004))
    parts.append(flat_patch("BW_Heart",
                            [(whale_cx + 0.020 + x, heart_cz + z) for x, z in heart_pts],
                            place, MAT["pink"], 0.0054, rings_n=2))
    # 腰带 + 背部蝴蝶结
    parts.append(loft("BW_Belt", [
        ring(WAIST_Z - 0.012, 0.150, 0.114, 28, 2.1),
        ring(WAIST_Z + 0.012, 0.150, 0.114, 28, 2.1),
    ], material=MAT["white_soft"]))
    for sign in (1, -1):
        kp = [Vector((sign * 0.014 * t, 0.128 + 0.012 * t, WAIST_Z - 0.006 + 0.034 * t))
              for t in (0.0, 0.5, 1.0)]
        parts.append(tube_along("BW_BackBow_%d" % sign, kp, [0.022, 0.028, 0.014], 8,
                                MAT["navy_deep"], squash=0.55))
    parts.append(sphere("BW_BackBowKnot", (0.0, 0.126, WAIST_Z - 0.006),
                        (0.017, 0.015, 0.017), MAT["navy"], 10, 8))
    return parts


# ------------------------------------------------------------------ 鲸尾
#
# 侧视优先：根部从裙后下方出发，向后下方形成柔和 J/S 弧，再略抬起；
# 尾鳍落在小腿到脚踝高度。参考后视把尾巴画成垂直下落，与侧视不一致 ——
# 本版明确优先侧视曲线，取舍记录在 asset_ledger.md。

TAIL_SEGMENTS = 6


def build_tail():
    parts = []
    # 尾根必须**先向后**快速离开裙摆钟形（裙摆最大半径约 0.23–0.33），
    # 否则从正面会从两腿之间看到一条竖条（本轮实测）。之后再走 J/S 弧向下再抬起。
    # 尾根再向后、向下一点：侧面/三分之四要能看到完整 S/J 弧
    root = Vector((0.0, 0.146, HIP_Z - 0.028))
    ctrl = [
        root,
        Vector((0.0, 0.268, HIP_Z - 0.070)),
        Vector((0.0, 0.368, KNEE_Z + 0.052)),
        Vector((0.0, 0.432, KNEE_Z - 0.010)),
        Vector((0.0, 0.470, ANKLE_Z + 0.052)),
        Vector((0.0, 0.494, ANKLE_Z + 0.024)),
    ]
    # 每段 10 环：段间半径变化足够小，不会出现"竹节"横向棱（初版 6 环时像竹节）
    pts, radii = [], []
    res = 10
    for i in range(TAIL_SEGMENTS):
        for k in range(res):
            t = (i + k / res) / TAIL_SEGMENTS
            idx = t * (len(ctrl) - 1)
            j = min(int(idx), len(ctrl) - 2)
            u = idx - j
            p = ctrl[j] * (1 - u) + ctrl[j + 1] * u
            pts.append(p)
            # 尾根粗、向尾鳍渐细；起始半径与裙后开口协调，避免管状硬插
            radii.append(0.052 * (1.0 - 0.56 * t) + 0.010)
    pts.append(ctrl[-1])
    radii.append(0.022)
    tail = tube_along("BW_TailBody", pts, radii, 20, MAT["tail_deep"], squash=0.88)
    parts.append(tail)
    # 尾鳍：明确的左右双叶 + 中间 V 缺口（初版是一块单叶铲子）
    tip = pts[-1]
    for sign in (1, -1):
        rows = []
        seg = 8
        for i in range(6):
            t = i / 5.0
            row = []
            for k in range(seg):
                u = -1.0 + 2.0 * k / (seg - 1)
                # 叶形：外缘后掠张开，内缘向中缝回收 -> 形成 V 缺口
                spread = 0.135 * math.sin(t * 1.15)
                x = sign * (0.012 + spread) * (0.35 + 0.65 * (1.0 - abs(u) ** 1.4))
                y = tip.y + 0.018 + 0.090 * t + 0.034 * (1.0 - abs(u) ** 1.5)
                z = tip.z + 0.052 - 0.105 * t * (0.45 + 0.55 * abs(u)) + 0.026 * (1.0 - abs(u))
                row.append(Vector((x, y, z)))
            rows.append(row)
        parts.append(sheet("BW_TailFluke_%d" % sign, rows, 0.016, MAT["tail_tip"]))
    # 尾巴按 TAIL_SEGMENTS 段独立环线放样（每段 6 环），保留后续绑定所需的分段拓扑；
    # 初版额外加了 5 个独立"过渡环"对象，渲染成 5 道横向条纹，已移除。
    # 尾鳍条纹（简化：两条浅色带）
    for sign in (1, -1):
        for i, off in enumerate((0.030, 0.052)):
            stripe = [Vector((sign * 0.070 * (0.4 + 0.6 * u), tip.y + 0.034 + off * 1.0,
                              tip.z + 0.024 - 0.038 * u)) for u in (0.0, 0.5, 1.0)]
            parts.append(tube_along("BW_TailStripe_%d_%d" % (sign, i), stripe,
                                    [0.006, 0.005, 0.003], 6, MAT["eye_light"], squash=0.5))
    return parts


# ------------------------------------------------------------------ 腿脚

def build_socks():
    parts = []
    for sign in (1, -1):
        tag = "L" if sign > 0 else "R"
        x = HIP_X * sign * 1.06
        pts = [Vector((x, -0.002, ANKLE_Z + 0.062)),
               Vector((x, -0.002, ANKLE_Z + 0.038)),
               Vector((x, -0.002, ANKLE_Z + 0.010)),
               Vector((x, -0.004, 0.004))]
        rad = [0.050, 0.048, 0.046, 0.044]
        parts.append(tube_along("BW_Sock_" + tag, pts, rad, 14, MAT["white"]))
        parts.append(ruffle("BW_SockRuffle_" + tag, (x, -0.002, ANKLE_Z + 0.062),
                            0.052, 12, 0.007, 0.016, MAT["white_soft"], 0.006))
    return parts


def build_shoes():
    """深蓝圆头 Mary Jane 鞋 + 横带 + 小金扣。"""
    parts = []
    for sign in (1, -1):
        tag = "L" if sign > 0 else "R"
        x = HIP_X * sign * 1.06
        rows = [
            (0.052, 0.040, 0.062),
            (0.020, 0.045, 0.066),
            (-0.030, 0.048, 0.052),
            (-0.072, 0.046, 0.038),
            (-0.098, 0.038, 0.028),
            (-0.114, 0.024, 0.020),
        ]
        rings = []
        for yy, hw, zt in rows:
            ring_pts = []
            for k in range(12):
                a = TAU * k / 12
                cu = math.copysign(abs(math.cos(a)) ** (2.0 / 3.2), math.cos(a))
                cv = math.copysign(abs(math.sin(a)) ** (2.0 / 3.2), math.sin(a))
                cz = (zt) * 0.5 + 0.002
                rz = (zt) * 0.5
                ring_pts.append(Vector((x + cu * hw, yy, cz + cv * rz)))
            rings.append(ring_pts)
        parts.append(loft("BW_Shoe_" + tag, rings, material=MAT["shoe"]))
        # 横带
        strap = [Vector((x + math.cos(TAU * k / 16) * 0.049,
                         -0.012 + math.sin(TAU * k / 16) * 0.050,
                         ANKLE_Z + 0.006)) for k in range(17)]
        strap_rows = [[strap[k], strap[k] + Vector((0.0, 0.0, 0.011))] for k in range(17)]
        parts.append(sheet("BW_ShoeStrap_" + tag, [strap, [p + Vector((0, 0, 0.010)) for p in strap]],
                           0.008, MAT["navy_deep"]))
        parts.append(sphere("BW_ShoeBuckle_" + tag, (x, -0.062, ANKLE_Z + 0.010),
                            (0.011, 0.009, 0.008), MAT["gold"], 10, 6))
    return parts


# ------------------------------------------------------------------ 装配

def scale_about_chin(objs):
    """把头部相关对象以局部 CHIN_Z 为轴心缩放 HEAD_SCALE 并抬到 HEAD_CHIN_FINAL。

    头部内部所有相对比例（眼距、刘海、发壳厚度）保持不变，只调整整体大小；
    比逐个改数百个坐标更可靠。
    """
    pivot = Vector((0.0, 0.0, CHIN_Z))
    target = Vector((0.0, 0.0, HEAD_CHIN_FINAL))
    for obj in objs:
        for v in obj.data.vertices:
            v.co = pivot + (v.co - pivot) * HEAD_SCALE + (target - pivot)
        obj.data.update()


def assemble():
    parts_body = build_body()
    parts_head = build_head() + build_face()
    # 旧 build_hair_waves() 的 5 条短波浪已被 build_hair_shell() 里的 7 条层叠长发束取代
    # （旧版被内层球体吞掉，背面读成一颗气球 —— 主代理验收失败点）
    parts_hair = build_hair_shell() + build_bangs() + \
        build_side_locks() + build_ahoge()
    parts_wear = build_headdress()
    # 头部相关（头/脸/发/发箍）整体以局部下巴为轴心缩小并抬升 -> 目标头身比
    scale_about_chin(parts_head + parts_hair + parts_wear)
    parts_wear = parts_wear + build_dress() + build_apron()
    parts_tail = build_tail()
    parts_feet = build_socks() + build_shoes()

    body = join_objects(parts_body, "BW_Body")
    head = join_objects(parts_head, "BW_Head")
    hair = join_objects(parts_hair, "BW_Hair")
    dress = join_objects(parts_wear, "BW_Dress")
    tail = join_objects(parts_tail, "BW_Tail")
    feet = join_objects(parts_feet, "BW_Feet")
    objs = [body, head, hair, dress, tail, feet]
    for obj in objs:
        merge_material_slots(obj)
    return {"body": body, "head": head, "hair": hair, "dress": dress,
            "tail": tail, "feet": feet}


# ------------------------------------------------------------------ 校验

def mesh_stats(obj):
    me = obj.data
    me.calc_loop_triangles()
    bm = bmesh.new()
    bm.from_mesh(me)
    non_manifold = sum(1 for e in bm.edges if not e.is_manifold)
    zero_area = sum(1 for f in bm.faces if f.calc_area() < 1e-12)
    bad = sum(1 for v in bm.verts if not all(math.isfinite(c) for c in v.co))
    bm.free()
    return {"name": obj.name, "vertices": len(me.vertices),
            "triangles": len(me.loop_triangles), "polygons": len(me.polygons),
            "materials": len(obj.data.materials), "non_manifold_edges": non_manifold,
            "zero_area_faces": zero_area, "non_finite_verts": bad}


def world_bounds(objs):
    mn = Vector((1e9, 1e9, 1e9))
    mx = Vector((-1e9, -1e9, -1e9))
    for obj in objs:
        for corner in obj.bound_box:
            p = obj.matrix_world @ Vector(corner)
            for i in range(3):
                mn[i] = min(mn[i], p[i])
                mx[i] = max(mx[i], p[i])
    return mn, mx


def validate(parts, report):
    stats = [mesh_stats(o) for o in parts.values()]
    materials = set()
    for obj in parts.values():
        for slot in obj.material_slots:
            if slot.material:
                materials.add(slot.material.name)
    mn, mx = world_bounds(list(parts.values()))
    tri = sum(s["triangles"] for s in stats)
    checks = {
        "triangles_total": tri,
        "triangles_in_range_20k_80k": 20000 <= tri <= 80000,
        "material_count": len(materials),
        "object_count": len(parts),
        "bbox_min": [round(v, 5) for v in mn],
        "bbox_max": [round(v, 5) for v in mx],
        "height_m": round(mx.z - mn.z, 4),
        "feet_on_ground": abs(mn.z) < 0.004,
        "head_ratio": round((mx.z - mn.z) / max(HEAD_BLOCK_H, 1e-6), 3),
        "non_manifold_total": sum(s["non_manifold_edges"] for s in stats),
        "zero_area_total": sum(s["zero_area_faces"] for s in stats),
        "non_finite_total": sum(s["non_finite_verts"] for s in stats),
    }
    report["meshes"] = stats
    report["checks"] = checks
    return checks


# ------------------------------------------------------------------ 渲染

def build_axis_helper():
    """FRONT +Z 轴向证明：粗杆 + 圆锥箭头 + FRONT/BACK 文字。不导出。"""
    mat = make_material("BW_AxisHelper", "#D8483C", 0.6, 0.0, 0.2)
    bm = bmesh.new()
    r0 = 0.020
    y0, y1 = 0.10, -0.46
    verts = [bm.verts.new(p) for p in (
        (-r0, y0, -0.010), (r0, y0, -0.010), (r0, y0, 0.010), (-r0, y0, 0.010),
        (-r0, y1, -0.010), (r0, y1, -0.010), (r0, y1, 0.010), (-r0, y1, 0.010))]
    for face in ((0, 1, 2, 3), (7, 6, 5, 4), (0, 4, 5, 1), (1, 5, 6, 2),
                 (2, 6, 7, 3), (3, 7, 4, 0)):
        bm.faces.new([verts[i] for i in face])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new("axis_shaft")
    bm.to_mesh(mesh)
    bm.free()
    shaft = bpy.data.objects.new("BW_AxisShaft", mesh)
    link(shaft)
    mesh.materials.append(mat)

    cone = bpy.data.meshes.new("axis_head")
    bmc = bmesh.new()
    bmesh.ops.create_cone(bmc, cap_ends=True, cap_tris=False, segments=20,
                          radius1=0.052, radius2=0.0, depth=0.16,
                          matrix=Matrix.Rotation(math.radians(-90), 4, "X"))
    bmesh.ops.translate(bmc, verts=bmc.verts, vec=Vector((0.0, y1 - 0.04, 0.0)))
    bmesh.ops.recalc_face_normals(bmc, faces=bmc.faces)
    bmc.to_mesh(cone)
    bmc.free()
    head = bpy.data.objects.new("BW_AxisHead", cone)
    link(head)
    cone.materials.append(mat)

    labels = []
    for text, loc, size in (("FRONT +Z", (0.0, 0.30, 0.20), 0.115),
                            ("FRONT", (0.0, -0.70, 0.20), 0.085),
                            ("BACK", (0.0, 0.72, 0.20), 0.075)):
        try:
            bpy.ops.object.text_add(location=loc)
            tobj = bpy.context.object
            tobj.data.body = text
            tobj.data.size = size
            tobj.data.align_x = "CENTER"
            tobj.rotation_euler = (math.radians(90), 0.0, 0.0)
            bpy.context.view_layer.objects.active = tobj
            tobj.select_set(True)
            bpy.ops.object.convert(target="MESH")
            tobj = bpy.context.object
            tobj.name = "BW_AxisLabel_" + text.replace(" ", "_").replace("+", "plus")
            tobj.data.materials.clear()
            tobj.data.materials.append(mat)
            labels.append(tobj)
        except Exception as exc:
            log("轴向文字失败（保留纯箭头）：%s" % exc)
    obj = join_objects([shaft, head] + labels, "FRONT_+Z")
    # 放在角色侧面且更靠外：初版与角色重叠，文字被挡住（可读性不达标）
    obj.location = Vector((0.66, 0.0, 0.06))
    return obj


def setup_render():
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 1200
    scene.render.resolution_y = 1200
    scene.render.image_settings.file_format = "PNG"
    scene.view_settings.view_transform = "Standard"
    scene.render.film_transparent = False
    world = bpy.data.worlds.new("BW_World")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (0.66, 0.68, 0.72, 1.0)
    bg.inputs[1].default_value = 0.80

    cam_data = bpy.data.cameras.new("BW_Camera")
    cam_data.type = "ORTHO"
    cam = bpy.data.objects.new("BW_Camera", cam_data)
    link(cam)
    scene.camera = cam

    def sun(name, energy, rot):
        d = bpy.data.lights.new(name, "SUN")
        d.energy = energy
        d.angle = math.radians(16.0)
        o = bpy.data.objects.new(name, d)
        link(o)
        o.rotation_euler = rot
        return o

    sun("BW_Key", 2.5, (math.radians(58), 0.0, math.radians(-36)))
    sun("BW_Fill", 1.25, (math.radians(70), 0.0, math.radians(128)))
    sun("BW_Rim", 1.5, (math.radians(108), 0.0, math.radians(196)))
    return cam, cam_data


def render_view(cam, cam_data, name, azimuth_deg, elevation_deg, frame_h, focus_z,
                height_px=None, width_px=None, focus_x=0.0, focus_y=0.0,
                aspect=1.0):
    scene = bpy.context.scene
    if height_px:
        scene.render.resolution_y = height_px
        scene.render.resolution_x = width_px or int(height_px * aspect)
    res_x = scene.render.resolution_x
    res_y = scene.render.resolution_y
    cam_data.ortho_scale = frame_h * (res_x / res_y) if res_x >= res_y else frame_h
    a = math.radians(azimuth_deg)
    e = math.radians(elevation_deg)
    d = Vector((math.sin(a) * math.cos(e), -math.cos(a) * math.cos(e), math.sin(e)))
    cam.location = Vector((focus_x, focus_y, focus_z)) + d * 3.0
    cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
    scene.render.filepath = os.path.join(RENDERS, name + ".png")
    bpy.ops.render.render(write_still=True)
    return name


def image_margin_report(path):
    """非背景像素 bbox 相对四边的留白比例；背景色自校准（sRGB 编码后与线性值不同）。"""
    img = bpy.data.images.load(path, check_existing=False)
    w, h = img.size
    px = list(img.pixels)
    row_len = w * 4

    def pixel(x, y):
        i = y * row_len + x * 4
        return (px[i], px[i + 1], px[i + 2])

    corners = [pixel(0, 0), pixel(w - 1, 0), pixel(0, h - 1), pixel(w - 1, h - 1)]
    bg = tuple(sum(c[k] for c in corners) / 4.0 for k in range(3))
    tol = 0.02
    xs_min, xs_max, ys_min, ys_max = w, -1, h, -1
    for y in range(h):
        base = y * row_len
        for x in range(w):
            i = base + x * 4
            if (abs(px[i] - bg[0]) > tol or abs(px[i + 1] - bg[1]) > tol
                    or abs(px[i + 2] - bg[2]) > tol):
                if x < xs_min:
                    xs_min = x
                if x > xs_max:
                    xs_max = x
                if y < ys_min:
                    ys_min = y
                if y > ys_max:
                    ys_max = y
    bpy.data.images.remove(img)
    if xs_max < 0:
        return {"empty": True}
    return {"width": w, "height": h,
            "left": round(xs_min / w, 4), "right": round((w - 1 - xs_max) / w, 4),
            "bottom": round(ys_min / h, 4), "top": round((h - 1 - ys_max) / h, 4)}


def render_all(cam, cam_data, axis_helper, height):
    os.makedirs(RENDERS, exist_ok=True)
    # 角色应占画面高度约 85%（主代理：初版只占约 60%，大片空白）
    frame_h = height / 0.85
    focus = height * 0.5
    axis_helper.hide_render = True
    names = []
    shots = [
        ("front", 0.0, 0.0, frame_h, focus, None, None, 0.0, 0.0, 1.0),
        ("side", -90.0, 0.0, frame_h, focus, None, None, 0.0, 0.02, 1.0),
        ("back", 180.0, 0.0, frame_h, focus, None, None, 0.0, 0.01, 1.0),
        ("three_quarter_front", -38.0, 4.0, frame_h, focus, None, None, 0.0, 0.02, 1.0),
        ("three_quarter_back", 142.0, 4.0, frame_h, focus, None, None, 0.0, 0.02, 1.0),
        ("head_closeup", -20.0, 2.0, height * 0.42, EYE_Z + 0.010, None, None, 0.0, -0.01, 1.0),
        ("hair_back_closeup", 176.0, 6.0, height * 0.52, EYE_Z - 0.060, None, None, 0.0, 0.06, 1.0),
        ("apron_skirt_closeup", -18.0, 8.0, height * 0.46, WAIST_Z - 0.045, None, None, 0.0, 0.0, 1.0),
        ("tail_side_closeup", -90.0, 8.0, height * 0.62, HIP_Z - 0.075, None, None, 0.0, 0.26, 1.0),
        ("hands_feet_closeup", -36.0, 10.0, height * 0.50, height * 0.185, None, None,
         0.130, 0.0, 1.0),
    ]
    for spec in shots:
        names.append(render_view(cam, cam_data, spec[0], spec[1], spec[2], spec[3], spec[4],
                                 spec[5], spec[6], spec[7], spec[8], spec[9]))

    # 正交三视图同图（接近参考排版）：横图放三格
    scene = bpy.context.scene
    scene.render.resolution_x = 1500
    scene.render.resolution_y = 900
    grid_h = height / 0.90
    for idx, (tag, az) in enumerate((("front", 0.0), ("side", -90.0), ("back", 180.0))):
        render_view(cam, cam_data, "_turnaround_%d" % idx, az, 0.0, grid_h, focus,
                    None, None, 0.0, 0.0, 1.0)
    names.append("orthographic_turnaround")
    scene.render.resolution_x = 1200
    scene.render.resolution_y = 1200

    # 灰模
    clay = make_material("BW_Clay", "#B9BCC2", 0.92, 0.0, 0.10)
    saved = {}
    for obj in bpy.data.objects:
        if obj.type == "MESH" and obj.name != "FRONT_+Z":
            saved[obj.name] = [s.material for s in obj.material_slots]
            for s in obj.material_slots:
                s.material = clay
    for tag, az in (("gray_front", 0.0), ("gray_side", -90.0)):
        names.append(render_view(cam, cam_data, tag, az, 2.0, frame_h, focus))
    for obj in bpy.data.objects:
        if obj.name in saved:
            for slot, mat in zip(obj.material_slots, saved[obj.name]):
                slot.material = mat

    # 轴向证明（俯视 3/4，正面正交会把箭头压成圆盘）
    axis_helper.hide_render = False
    names.append(render_view(cam, cam_data, "axis_proof", -26.0, 28.0, height * 1.55,
                             height * 0.46, focus_x=0.34, focus_y=0.06))
    axis_helper.hide_render = True

    # 游戏尺度：完整包含头顶、尾鳍、鞋底，留白 >= 4%
    # 包含正面轮廓 + 向后伸出的鲸尾；留白由断言保证
    tail_back = 0.62
    need_w = (0.32 + tail_back) * 1.20
    need_h = height * 1.20
    for label, px in (("game_scale_128", 128), ("game_scale_256", 256)):
        width_px = max(8, int(round(px * (need_w / need_h))))
        names.append(render_view(cam, cam_data, label, -34.0, 6.0, need_h, height * 0.5,
                                 height_px=px, width_px=width_px, focus_y=0.20,
                                 aspect=need_w / need_h))
    scene.render.resolution_x = 1200
    scene.render.resolution_y = 1200
    return names


# ------------------------------------------------------------------ 导出 / 审计

def export_all():
    bpy.ops.object.select_all(action="DESELECT")
    meshes = [o for o in bpy.data.objects if o.type == "MESH" and o.name != "FRONT_+Z"]
    for obj in meshes:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.export_scene.gltf(
        filepath=GLB, export_format="GLB", use_selection=True, export_yup=True,
        export_apply=True, export_animations=False, export_skins=False,
        export_morph=False, export_cameras=False, export_lights=False)
    fbx_ok = False
    try:
        bpy.ops.export_scene.fbx(
            filepath=FBX, use_selection=True, apply_scale_options="FBX_SCALE_ALL",
            object_types={"MESH"}, use_mesh_modifiers=True, add_leaf_bones=False,
            bake_space_transform=False, axis_forward="-Z", axis_up="Y")
        fbx_ok = os.path.exists(FBX)
    except Exception as exc:
        log("FBX 导出失败：%s" % exc)
    return fbx_ok


def read_glb():
    data = open(GLB, "rb").read()
    magic, version, total = struct.unpack("<III", data[:12])
    cursor, payload = 12, None
    while cursor < total:
        length, ctype = struct.unpack("<II", data[cursor:cursor + 8])
        chunk = data[cursor + 8:cursor + 8 + length]
        if ctype == 0x4E4F534A:
            payload = json.loads(chunk)
        cursor += 8 + length
    return payload, data


def glb_audit():
    payload, data = read_glb()
    tri = 0
    mn = [1e9] * 3
    mx = [-1e9] * 3
    for mesh in payload.get("meshes", []):
        for prim in mesh["primitives"]:
            idx = prim.get("indices")
            if idx is not None:
                tri += payload["accessors"][idx]["count"] // 3
            acc = payload["accessors"][prim["attributes"]["POSITION"]]
            for i in range(3):
                mn[i] = min(mn[i], acc["min"][i])
                mx[i] = max(mx[i], acc["max"][i])
    return {
        "bytes": len(data), "sha256": sha256(GLB),
        "meshes": len(payload.get("meshes", [])),
        "materials": [m.get("name") for m in payload.get("materials", [])],
        "material_count": len(payload.get("materials", [])),
        "nodes": len(payload.get("nodes", [])),
        "triangles": tri,
        "animations": len(payload.get("animations", [])),
        "skins": len(payload.get("skins", [])),
        "cameras": len(payload.get("cameras", [])),
        "images": len(payload.get("images", [])),
        "bounds_min": [round(v, 5) for v in mn],
        "bounds_max": [round(v, 5) for v in mx],
        "attributes": sorted({k for m in payload.get("meshes", [])
                              for p in m["primitives"] for k in p["attributes"]}),
    }


# ------------------------------------------------------------------ 主流程

def phase_build():
    reset_scene()
    build_materials()
    parts = assemble()
    apply_transforms(list(parts.values()))
    for obj in parts.values():
        shade(obj, True, 38.0)

    axis_helper = build_axis_helper()
    report = {"blender_version": bpy.app.version_string, "iteration": ITERATION}
    check = validate(parts, report)
    mn, mx = world_bounds(list(parts.values()))
    report["orientation"] = {
        "blender_front": "-Y", "export_yup": True,
        "gltf_front_after_export": "+Z",
        "axis_helper": "FRONT_+Z 由粗杆+圆锥箭头+文字组成，Blender 中指向 -Y（导出后 +Z），不导出",
    }
    report["reference"] = {
        "path": os.path.relpath(REFERENCE, ROOT),
        "sha256": sha256(REFERENCE),
        "note": "使用者提供的三视图设定图；外部版权与商用授权状态未知，仅作建模依据，"
                "本资产不就该图主张原创设定或可商用。",
    }

    bpy.ops.wm.save_as_mainfile(filepath=BLEND)
    report["blend_sha256"] = sha256(BLEND)

    cam, cam_data = setup_render()
    names = render_all(cam, cam_data, axis_helper, mx.z - mn.z)
    report["renders"] = names
    margins = {}
    for label in ("game_scale_128", "game_scale_256"):
        m = image_margin_report(os.path.join(RENDERS, label + ".png"))
        margins[label] = m
        for side in ("top", "bottom", "left", "right"):
            assert m[side] >= 0.04, "%s 的 %s 留白 %.4f < 0.04" % (label, side, m[side])
    report["framing_check"] = margins
    # 头身比必须落在契约区间 2.9–3.2（Q 版大头，绝不能长腿成人比例）
    assert 2.9 <= check["head_ratio"] <= 3.2, (
        "头身比 %.3f 超出契约区间 2.9–3.2" % check["head_ratio"])
    report["pose"] = {
        "type": "light A pose", "arm_abduction_deg": 52.0,
        "note": "双臂外展 52°，不贴身；腋下/胯下/膝部留净空以便后续绑骨",
    }

    # 三视图拼图
    try:
        compose_turnaround()
    except Exception as exc:
        log("三视图拼图失败：%s" % exc)

    fbx_ok = export_all()
    report["export"] = {
        "glb": os.path.relpath(GLB, ROOT), "glb_sha256": sha256(GLB),
        "fbx": os.path.relpath(FBX, ROOT) if fbx_ok else None,
        "fbx_sha256": sha256(FBX) if fbx_ok else None,
        "fbx_note": "unrigged：静态无骨骼、无动画、无约束" if fbx_ok else "FBX 导出失败",
    }
    report["glb_audit"] = glb_audit()
    REPORT["build"] = report
    with open(MANIFEST, "w") as fh:
        json.dump(REPORT, fh, indent=1, ensure_ascii=False, sort_keys=True)

    log("三角面 %d 材质 %d 对象 %d" % (check["triangles_total"], check["material_count"],
                                       check["object_count"]))
    log("高 %.4f m 头身比 %.3f 包围盒 %s..%s" % (check["height_m"], check["head_ratio"],
                                              check["bbox_min"], check["bbox_max"]))
    log("GLB %s" % json.dumps(report["glb_audit"], ensure_ascii=False)[:300])
    log("渲染 %d 张；留白 %s" % (len(names), margins))


def compose_turnaround():
    """把三张分格渲染横向拼成一张对比图（接近参考排版）。"""
    tiles = []
    for idx in range(3):
        p = os.path.join(RENDERS, "_turnaround_%d.png" % idx)
        img = bpy.data.images.load(p, check_existing=False)
        tiles.append((img, img.size[0], img.size[1]))
    w = sum(t[1] for t in tiles)
    h = tiles[0][2]
    out = bpy.data.images.new("turnaround", width=w, height=h, alpha=False)
    buf = [0.0] * (w * h * 4)
    x_off = 0
    for img, iw, ih in tiles:
        px = list(img.pixels)
        for y in range(ih):
            src = y * iw * 4
            dst = (y * w + x_off) * 4
            buf[dst:dst + iw * 4] = px[src:src + iw * 4]
        x_off += iw
    out.pixels.foreach_set(buf)
    out.filepath_raw = os.path.join(RENDERS, "orthographic_turnaround.png")
    out.file_format = "PNG"
    out.save()
    for img, _, _ in tiles:
        bpy.data.images.remove(img)
    bpy.data.images.remove(out)
    for idx in range(3):
        p = os.path.join(RENDERS, "_turnaround_%d.png" % idx)
        if os.path.exists(p):
            os.remove(p)


def phase_export():
    bpy.ops.wm.open_mainfile(filepath=BLEND)
    objs = [o for o in bpy.data.objects if o.type == "MESH"]
    report = {
        "reopened_blend": os.path.relpath(BLEND, ROOT),
        "blender_version": bpy.app.version_string,
        "objects": [{"name": o.name,
                     "materials": [s.material.name for s in o.material_slots if s.material],
                     "vertices": len(o.data.vertices)} for o in objs],
        "axis_helper_present": any(o.name == "FRONT_+Z" for o in bpy.data.objects),
        "cameras_in_file": len([o for o in bpy.data.objects if o.type == "CAMERA"]),
        "lights_in_file": len([o for o in bpy.data.objects if o.type == "LIGHT"]),
        "armatures": len([o for o in bpy.data.objects if o.type == "ARMATURE"]),
        "constraints": sum(len(o.constraints) for o in bpy.data.objects),
        "actions": len(bpy.data.actions),
    }
    stats = [mesh_stats(o) for o in objs if o.name != "FRONT_+Z"]
    report["totals"] = {
        "vertices": sum(s["vertices"] for s in stats),
        "triangles": sum(s["triangles"] for s in stats),
        "polygons": sum(s["polygons"] for s in stats),
        "non_manifold": sum(s["non_manifold_edges"] for s in stats),
        "zero_area": sum(s["zero_area_faces"] for s in stats),
        "non_finite": sum(s["non_finite_verts"] for s in stats),
    }
    real = [o for o in objs if o.name != "FRONT_+Z"]
    mn, mx = world_bounds(real)
    report["bounds_min"] = [round(v, 5) for v in mn]
    report["bounds_max"] = [round(v, 5) for v in mx]
    report["height_m"] = round(mx.z - mn.z, 4)
    report["fbx_ok"] = export_all()
    report["glb_audit"] = glb_audit()
    REPORT["export"] = report
    with open(EXPORT_MANIFEST, "w") as fh:
        json.dump(REPORT, fh, indent=1, ensure_ascii=False, sort_keys=True)
    log("导出阶段回读：%s" % json.dumps(report["glb_audit"], ensure_ascii=False))


def main():
    argv = sys.argv
    phase = "build"
    if "--phase" in argv:
        phase = argv[argv.index("--phase") + 1]
    for d in (OUT, SOURCE_DIR, EXPORT_DIR, RENDERS):
        os.makedirs(d, exist_ok=True)
    if phase == "export":
        phase_export()
    else:
        phase_build()


main()
