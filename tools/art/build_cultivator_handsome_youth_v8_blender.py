#!/usr/bin/env python3
"""构建 cultivator_handsome_youth_v8_blender：纯程序建模的清俊少年修仙弟子候选（18 岁视觉）。

依据 notes/proposed/art/2026-09-19-handsome-youth-cultivator-v8-blender.md。
纯原创程序建模：不下载、不购买、不调用在线生成、不复用任何旧版本网格。

坐标约定（重要）
  Blender 内 Z 为高度轴，人物正面朝 -Y。Blender glTF 导出用 export_yup=True 时
  Blender -Y -> glTF +Z，因此导出后 / Godot 内正面为局部 +Z，与现役角色共享约定一致。
  场景中的 FRONT_+Z 辅助箭头在 Blender 里指向 -Y，即导出后的 +Z。

阶段
  build  （默认）建模 -> 保存 .blend -> 渲染全部验收图 -> 写 manifest -> 触发 export
  export          独立进程重新打开最终 .blend，重新导出 GLB/FBX 并做读回审计

用法
  Blender --background --factory-startup --python <本文件> [-- --phase export]
"""

import bmesh
import bpy
import hashlib
import json
import math
import os
import subprocess
import sys
from mathutils import Matrix, Vector

TAU = math.pi * 2.0

ROOT = "/Users/yuqixian/forever-skills/projects/games/game-xiuxian-lab"
OUT = os.path.join(ROOT, "docs/art/cultivator_handsome_youth_v8_blender")
RENDERS = os.path.join(OUT, "renders")
BLEND = os.path.join(OUT, "cultivator_handsome_youth_v8_blender.blend")
GLB = os.path.join(OUT, "cultivator_handsome_youth_v8_blender.glb")
FBX = os.path.join(OUT, "cultivator_handsome_youth_v8_blender.fbx")
MANIFEST = os.path.join(OUT, "build_manifest.json")
EXPORT_MANIFEST = os.path.join(OUT, "export_audit.json")

BLENDER = "/Applications/Blender.app/Contents/MacOS/Blender"
REPORT = {"phases": {}}


# ---------------------------------------------------------------- 通用工具

def log(msg: str) -> None:
    print("[v8] " + msg, flush=True)


def sha256(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def srgb_to_linear(c: float) -> float:
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def hex_rgb(value: str):
    value = value.lstrip("#")
    return tuple(srgb_to_linear(int(value[i:i + 2], 16) / 255.0) for i in (0, 2, 4))


def reset_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0
    scene.render.fps = 30


def link(obj) -> None:
    bpy.context.scene.collection.objects.link(obj)


def activate(obj) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def new_mesh_object(name: str, bm: bmesh.types.BMesh, material=None):
    mesh = bpy.data.meshes.new(name + "_mesh")
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    link(obj)
    if material is not None:
        mesh.materials.append(material)
    return obj


# ------------------------------------------------------------ 环 / 放样核心

def superellipse_xy(t: float, rx: float, ry_front: float, ry_back: float, power: float):
    """超椭圆截面：power=2 为椭圆，power=4 更接近圆角矩形。front 为 -Y。"""
    ct, st = math.cos(t), math.sin(t)
    ex = 2.0 / power
    sx = math.copysign(abs(ct) ** ex, ct)
    sy = math.copysign(abs(st) ** ex, st)
    ry = ry_back if sy >= 0.0 else ry_front
    return rx * sx, ry * sy


def ring(cz: float, rx: float, ry_front: float, ry_back: float, segments: int,
         power: float = 2.0, cx: float = 0.0, cy: float = 0.0, rot_z: float = 0.0):
    pts = []
    for i in range(segments):
        t = TAU * i / segments
        x, y = superellipse_xy(t, rx, ry_front, ry_back, power)
        if rot_z:
            ct, st = math.cos(rot_z), math.sin(rot_z)
            x, y = x * ct - y * st, x * st + y * ct
        pts.append(Vector((cx + x, cy + y, cz)))
    return pts


def loft(name: str, rings, cap_start=True, cap_end=True, material=None):
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


def sheet(name: str, rows, thickness: float, material=None, offset: float = 0.0):
    """由若干行点构成开放曲面，再沿法线加厚（Solidify）。"""
    bm = bmesh.new()
    grid = []
    for row in rows:
        verts = []
        for p in row:
            verts.append(bm.verts.new(p if not offset else p + Vector((0, 0, 0)) * offset))
        grid.append(verts)
    for r in range(len(grid) - 1):
        n = len(grid[r])
        for i in range(n - 1):
            try:
                bm.faces.new((grid[r][i], grid[r][i + 1], grid[r + 1][i + 1], grid[r + 1][i]))
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


def box(name: str, center, size, material=None):
    cx, cy, cz = center
    sx, sy, sz = (s * 0.5 for s in size)
    bm = bmesh.new()
    verts = [bm.verts.new((cx + dx * sx, cy + dy * sy, cz + dz * sz))
             for dx, dy, dz in ((-1, -1, -1), (1, -1, -1), (1, 1, -1), (-1, 1, -1),
                                (-1, -1, 1), (1, -1, 1), (1, 1, 1), (-1, 1, 1))]
    for face in ((0, 1, 2, 3), (7, 6, 5, 4), (0, 4, 5, 1), (1, 5, 6, 2),
                 (2, 6, 7, 3), (3, 7, 4, 0)):
        bm.faces.new([verts[i] for i in face])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return new_mesh_object(name, bm, material)


def sphere(name: str, center, radii, material=None, segments: int = 16, rings_n: int = 10):
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


def join_objects(objs, name: str):
    objs = [o for o in objs if o is not None]
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    objs[0].name = name
    objs[0].data.name = name + "_mesh"
    return objs[0]


def orient_outward(obj, axis_x: float = 0.0, axis_y: float = 0.0) -> None:
    """把网格中朝向体内（指向竖直轴）的面翻正。

    Solidify 会从源面法向生成厚度，源面法向若朝内，外壳就成了背面 —— 渲染时
    被背面光照亮成暗色三角（短摆与后披发上实测到）。这里按面心到轴的径向
    方向判定，逐面翻转。
    """
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


def shade(obj, smooth: bool = True, angle_deg: float = 42.0) -> None:
    activate(obj)
    obj.data.polygons.foreach_set("use_smooth", [smooth] * len(obj.data.polygons))
    obj.data.update()
    if smooth:
        try:
            bpy.ops.object.shade_auto_smooth(angle=math.radians(angle_deg))
        except Exception:
            pass


# ------------------------------------------------------------------ 材质

def make_material(name, hex_color, roughness=0.85, metallic=0.0, specular=0.3):
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
        bsdf.inputs["Sheen Weight"].default_value = 0.0
    mat.diffuse_color = (r, g, b, 1.0)
    return mat


# 外层短衣下摆（米）：前短、侧面居中、后摆只比前摆长 10 cm
COAT_HEM_FRONT = 0.870
COAT_HEM_SIDE = 0.842
COAT_HEM_BACK = 0.770

MAT = {}


def build_materials() -> None:
    # 12 个材质：皮肤 / 发 / 青玉 / 月白内衫（兼眼白高光）/ 青蓝外层 /
    # 腰封 / 长裤 / 靴 / 哑金滚边 / 眉瞳黑 / 深棕虹膜 / 唇
    MAT["skin"] = make_material("V8_Skin", "#F2DECC", 0.72, 0.0, 0.34)
    MAT["hair"] = make_material("V8_Hair", "#1A1E2E", 0.40, 0.0, 0.52)
    MAT["jade"] = make_material("V8_Jade", "#7FB8A0", 0.42, 0.0, 0.55)
    MAT["inner"] = make_material("V8_Inner", "#E6ECEF", 0.86, 0.0, 0.25)
    MAT["outer"] = make_material("V8_Outer", "#46708A", 0.84, 0.0, 0.25)
    MAT["sash"] = make_material("V8_Sash", "#2C4A5E", 0.82, 0.0, 0.26)
    MAT["pants"] = make_material("V8_Pants", "#3A4650", 0.88, 0.0, 0.2)
    MAT["boots"] = make_material("V8_Boots", "#232A33", 0.6, 0.0, 0.36)
    MAT["trim"] = make_material("V8_Trim", "#B9985A", 0.5, 0.35, 0.5)
    MAT["dark"] = make_material("V8_Dark", "#101216", 0.5, 0.0, 0.45)
    MAT["iris"] = make_material("V8_Iris", "#4A3428", 0.35, 0.0, 0.6)
    MAT["lips"] = make_material("V8_Lips", "#C08878", 0.66, 0.0, 0.35)


# ---------------------------------------------------------------- 身体比例

HEIGHT = 1.752
HEAD_COUNT = 7.55
HEAD_H = HEIGHT / HEAD_COUNT
HEAD_TOP = HEIGHT
CHIN_Z = HEIGHT - HEAD_H

ANKLE_Z = 0.075
KNEE_Z = 0.470
CROTCH_Z = 0.830
HIP_Z = 0.950
WAIST_Z = 1.060
CHEST_Z = 1.300
SHOULDER_Z = 1.440
NECK_BASE_Z = 1.470

HEAD_HALF_W = 0.0775
SHOULDER_HALF_W = 0.180
TORSO_SEG = 24
LIMB_SEG = 16

HIP_JOINT = Vector((0.082, 0.0, 0.930))
KNEE = Vector((0.088, 0.0, KNEE_Z))
ANKLE = Vector((0.088, -0.004, ANKLE_Z))

SHOULDER_JOINT = Vector((0.155, 0.0, 1.415))
ARM_ABDUCTION = math.radians(80.0)
UPPER_ARM_LEN = 0.300
FORE_ARM_LEN = 0.265


def arm_frame(sign: int):
    """返回 (肩, 肘, 腕, 上臂方向, 前臂方向)。sign=+1 为角色左臂（+X）。

    上臂外展 80°（在 75–90° 硬约束内），肘几乎伸直；前臂相对上臂向前（-Y）
    偏 3.5°，方向明确但远未反关节。
    """
    # 外展角从身体竖直轴量起：90° = 完全水平 T pose，75–90° 为硬约束区间。
    d_up = Vector((math.sin(ARM_ABDUCTION) * sign, 0.0, -math.cos(ARM_ABDUCTION))).normalized()
    bend = math.radians(3.5)
    a = Vector((0.0, -1.0, 0.0))
    d_fore = (d_up * math.cos(bend) + a * (math.sin(bend))).normalized()
    shoulder = Vector((SHOULDER_JOINT.x * sign, SHOULDER_JOINT.y, SHOULDER_JOINT.z))
    elbow = shoulder + d_up * UPPER_ARM_LEN
    wrist = elbow + d_fore * FORE_ARM_LEN
    return shoulder, elbow, wrist, d_up, d_fore


# ---------------------------------------------------------------- 躯干

TORSO_PROFILE = [
    (CROTCH_Z - 0.035, 0.118, 0.079, 0.081, 3.0),
    (CROTCH_Z + 0.020, 0.132, 0.084, 0.086, 3.0),
    (HIP_Z, 0.138, 0.086, 0.089, 3.0),
    (WAIST_Z, 0.117, 0.074, 0.075, 2.8),
    (WAIST_Z + 0.075, 0.127, 0.079, 0.080, 2.7),
    (CHEST_Z - 0.075, 0.139, 0.086, 0.083, 2.6),
    (CHEST_Z, 0.148, 0.089, 0.084, 2.6),
    (CHEST_Z + 0.070, 0.152, 0.088, 0.083, 2.6),
    (SHOULDER_Z, 0.150, 0.084, 0.081, 2.5),
    (SHOULDER_Z + 0.028, 0.126, 0.073, 0.072, 2.4),
    (NECK_BASE_Z, 0.062, 0.058, 0.058, 2.2),
    (NECK_BASE_Z + 0.048, 0.048, 0.049, 0.050, 2.1),
    (NECK_BASE_Z + 0.086, 0.046, 0.048, 0.049, 2.1),
]


def torso_rings(expand: float = 0.0, seg: int = TORSO_SEG):
    out = []
    for z, rx, ryf, ryb, pw in TORSO_PROFILE:
        out.append(ring(z, rx + expand, ryf + expand, ryb + expand, seg, pw))
    return out


def build_torso():
    return loft("V8_Torso", torso_rings(), material=MAT["skin"])


# ---------------------------------------------------------------- 四肢

def frame_at(points, i: int):
    """路径第 i 点的正交标架。切向取相邻点差分 —— 手臂接近水平时，
    按 Z 轴堆水平环会得到扁平"缎带"而不是圆管（本轮实测踩坑）。"""
    n = len(points)
    if i == 0:
        tangent = points[1] - points[0]
    elif i == n - 1:
        tangent = points[-1] - points[-2]
    else:
        tangent = points[i + 1] - points[i - 1]
    tangent = tangent.normalized()
    ref = Vector((0.0, 1.0, 0.0))
    if abs(tangent.dot(ref)) > 0.95:
        ref = Vector((0.0, 0.0, 1.0))
    u_axis = ref.cross(tangent).normalized()
    v_axis = tangent.cross(u_axis).normalized()
    return tangent, u_axis, v_axis


def tube_along(name, points, radii, seg=LIMB_SEG, power=2.0, material=None,
               cap_start=True, cap_end=True):
    """沿任意折线生成圆管（环垂直于路径切向）。"""
    rings = []
    for i, (p, r) in enumerate(zip(points, radii)):
        _, u_axis, v_axis = frame_at(points, i)
        row = []
        for k in range(seg):
            a = TAU * k / seg
            cu = math.copysign(abs(math.cos(a)) ** (2.0 / power), math.cos(a))
            cv = math.copysign(abs(math.sin(a)) ** (2.0 / power), math.sin(a))
            row.append(p + u_axis * (cu * r) + v_axis * (cv * r))
        rings.append(row)
    return loft(name, rings, cap_start=cap_start, cap_end=cap_end, material=material)


def build_arm(sign: int):
    shoulder, elbow, wrist, d_up, d_fore = arm_frame(sign)
    up_pts = [shoulder + d_up * t for t in (0.0, 0.075, 0.150, 0.225, UPPER_ARM_LEN)]
    up_r = [0.055, 0.050, 0.045, 0.040, 0.0375]
    fore_pts = [elbow + d_fore * t for t in (0.0, 0.070, 0.140, 0.205, FORE_ARM_LEN)]
    fore_r = [0.0375, 0.0345, 0.0315, 0.028, 0.0255]
    return tube_along("V8_Arm_" + ("L" if sign > 0 else "R"),
                      up_pts + fore_pts[1:], up_r + fore_r[1:], LIMB_SEG, 2.0, MAT["skin"])


def hand_frame(sign: int):
    _, _, wrist, _, d_fore = arm_frame(sign)
    d = d_fore.normalized()
    n = Vector((0.0, 0.0, 1.0))
    s = d.cross(n).normalized()
    if sign > 0:
        s = -s
    return wrist, d, n, s


def build_hand(sign: int):
    tag = "L" if sign > 0 else "R"
    wrist, d, n, s = hand_frame(sign)
    parts = []
    # 手掌
    palm_rows = []
    # 掌：用 8 边超椭圆环放样 -> 掌缘收圆，不再是方盒
    palm_pts = [wrist + d * t for t in (0.008, 0.038, 0.068, 0.092)]
    palm_rows = []
    for idx, (c, w, th) in enumerate(zip(palm_pts,
                                         (0.0345, 0.0410, 0.0405, 0.0360),
                                         (0.0100, 0.0112, 0.0104, 0.0086))):
        row = []
        for k in range(12):
            a = TAU * k / 12
            cu = math.copysign(abs(math.cos(a)) ** (2.0 / 2.6), math.cos(a))
            cv = math.copysign(abs(math.sin(a)) ** (2.0 / 2.6), math.sin(a))
            row.append(c + s * (cu * w) + n * (cv * th))
        palm_rows.append(row)
    parts.append(loft("V8_Palm_" + tag, palm_rows, material=MAT["skin"]))

    base = wrist + d * 0.088
    # 指间净空 = 间距 - 2*半径：取 18 mm 间距 + 5.5 mm 半径 = 7 mm 净空，
    # 手指才在轮廓上分开（半径 7.4 mm 时净空仅 3.4 mm，渲染成一整块桨）。
    # 指：加粗到 8 mm 级、缩短，并铺满掌宽 —— 初版 5.6–6.9 mm 半径 + 0.086 m 长度
    # 在俯视图里读成一把梳齿（实测）。掌宽 0.081，四指总占宽取 0.072。
    fingers = (
        ("index", 0.0298, 0.074, 0.0082, -0.070),
        ("middle", 0.0100, 0.080, 0.0085, -0.016),
        ("ring", -0.0098, 0.073, 0.0082, 0.024),
        ("pinky", -0.0286, 0.060, 0.0074, 0.086),
    )
    for fname, offset_x, flen, frad, fan in fingers:
        origin = base + s * offset_x - n * 0.0004
        dirv = (d + s * fan).normalized()
        pts = [origin + dirv * (flen * u) for u in (0.0, 0.28, 0.56, 0.80, 1.0)]
        rad = [frad, frad * 1.00, frad * 0.94, frad * 0.82, frad * 0.56]
        rings = []
        for p, r in zip(pts, rad):
            rings.append([p + s * (math.cos(TAU * k / 12) * r)
                          + n * (math.sin(TAU * k / 12) * r) for k in range(12)])
        parts.append(loft("V8_Finger_%s_%s" % (tag, fname), rings, material=MAT["skin"]))

    # 拇指：偏离掌面并朝向角色前方
    # 拇指：根部必须**埋进掌体**（起点落在掌宽之内 6 mm），否则在俯视图里
    # 读成一根游离的尖刺（本轮实测）。根部半径加大到 10.5 mm 与掌缘相接。
    thumb_origin = wrist + d * 0.030 - s * 0.0300 - n * 0.0020
    tdir = (-s * 0.66 + d * 0.72 - n * 0.16).normalized()
    tpts = [thumb_origin + tdir * (0.058 * u) for u in (0.0, 0.30, 0.60, 0.85, 1.0)]
    trad = [0.0112, 0.0104, 0.0094, 0.0080, 0.0056]
    t_rings = []
    for p, r in zip(tpts, trad):
        t_rings.append([p + s * (math.cos(TAU * k / 12) * r) + n * (math.sin(TAU * k / 12) * r)
                        for k in range(12)])
    parts.append(loft("V8_Finger_%s_thumb" % tag, t_rings, material=MAT["skin"]))
    return parts


def build_leg(sign: int):
    tag = "L" if sign > 0 else "R"
    hip = Vector((HIP_JOINT.x * sign, HIP_JOINT.y, HIP_JOINT.z))
    knee = Vector((KNEE.x * sign, KNEE.y, KNEE.z))
    ankle = Vector((ANKLE.x * sign, ANKLE.y, ANKLE.z))
    thigh_pts = [hip + (knee - hip) * u for u in (0.0, 0.25, 0.5, 0.75, 1.0)]
    thigh_r = [0.089, 0.082, 0.073, 0.063, 0.056]
    calf_pts = [knee + (ankle - knee) * u for u in (0.0, 0.22, 0.45, 0.72, 1.0)]
    calf_r = [0.056, 0.060, 0.055, 0.043, 0.033]
    return tube_along("V8_Leg_" + tag, thigh_pts + calf_pts[1:],
                      thigh_r + calf_r[1:], LIMB_SEG, 2.0, MAT["skin"])


def build_foot(sign: int):
    """赤足（大部分被靴子覆盖，提供脚底与脚趾的完整轮廓）。"""
    tag = "L" if sign > 0 else "R"
    x = ANKLE.x * sign
    rows = [
        (ANKLE.y + 0.052, x - 0.034, x + 0.034, 0.000, 0.062),
        (ANKLE.y + 0.020, x - 0.038, x + 0.038, 0.000, 0.070),
        (ANKLE.y - 0.030, x - 0.041, x + 0.041, 0.000, 0.052),
        (ANKLE.y - 0.095, x - 0.044, x + 0.044, 0.000, 0.036),
        (ANKLE.y - 0.145, x - 0.042, x + 0.042, 0.000, 0.026),
        (ANKLE.y - 0.175, x - 0.036, x + 0.036, 0.000, 0.018),
    ]
    rings = []
    for y, x0, x1, z0, z1 in rows:
        rings.append([
            Vector((x0, y, z0)), Vector((x1, y, z0)),
            Vector((x1, y, z1)), Vector((x0, y, z1)),
        ])
    return loft("V8_Foot_" + tag, rings, material=MAT["skin"])


# ---------------------------------------------------------------- 头部

HEAD_PROFILE = [
    # 下巴收窄但保持圆钝：初版 CHIN 半径 0.030 太尖，读成刀下巴
    (CHIN_Z - 0.004, 0.0355, 0.0730, 0.0360, 2.15),
    (CHIN_Z + 0.016, 0.0465, 0.0840, 0.0555, 2.30),
    (CHIN_Z + 0.036, 0.0570, 0.0905, 0.0710, 2.45),
    (CHIN_Z + 0.062, 0.0655, 0.0940, 0.0830, 2.55),
    (CHIN_Z + 0.090, 0.0725, 0.0955, 0.0935, 2.65),
    (CHIN_Z + 0.120, 0.0775, 0.0965, 0.1005, 2.7),
    (CHIN_Z + 0.150, 0.0770, 0.0935, 0.1015, 2.6),
    (CHIN_Z + 0.178, 0.0725, 0.0875, 0.0985, 2.5),
    (CHIN_Z + 0.202, 0.0625, 0.0755, 0.0875, 2.4),
    (CHIN_Z + 0.220, 0.0455, 0.0545, 0.0625, 2.3),
    (CHIN_Z + 0.231, 0.0205, 0.0245, 0.0285, 2.2),
]


def head_profile_at(z: float):
    prof = HEAD_PROFILE
    if z <= prof[0][0]:
        return prof[0][1:]
    if z >= prof[-1][0]:
        return prof[-1][1:]
    for i in range(len(prof) - 1):
        z0, z1 = prof[i][0], prof[i + 1][0]
        if z0 <= z <= z1:
            u = (z - z0) / max(z1 - z0, 1e-9)
            return tuple(prof[i][k] + (prof[i + 1][k] - prof[i][k]) * u for k in range(1, 5))
    return prof[-1][1:]


def head_surface_y(x: float, z: float, front: bool = True) -> float:
    """给定 (x, z) 求头部表面 y；front=True 取 -Y 一侧。"""
    rx, ryf, ryb, pw = head_profile_at(z)
    ratio = min(abs(x) / max(rx, 1e-6), 1.0)
    inner = max(1.0 - ratio ** pw, 0.0)
    y = (ryf if front else ryb) * inner ** (1.0 / pw)
    return -y if front else y


def build_head():
    rings = [ring(z, rx, ryf, ryb, 24, pw) for z, rx, ryf, ryb, pw in HEAD_PROFILE]
    head = loft("V8_Head", rings, material=MAT["skin"])
    ears = []
    for sign in (1, -1):
        tag = "L" if sign > 0 else "R"
        c = Vector((sign * 0.0755, 0.014, CHIN_Z + 0.108))
        ear = sphere("V8_Ear_" + tag, c, (0.010, 0.026, 0.033), MAT["skin"], 12, 8)
        activate(ear)
        ear.scale = (1.0, 0.42, 1.0)
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        ears.append(ear)
    return [head] + ears


# ---------------------------------------------------------------- 面部

def head_normal(x: float, z: float) -> Vector:
    def F(px, py, pz):
        rx, ryf, ryb, pw = head_profile_at(pz)
        ry = ryf if py <= 0.0 else ryb
        return (abs(px) / max(rx, 1e-6)) ** pw + (abs(py) / max(ry, 1e-6)) ** pw - 1.0
    e = 0.0012
    y = head_surface_y(x, z)
    g = Vector(((F(x + e, y, z) - F(x - e, y, z)) / (2 * e),
                (F(x, y + e, z) - F(x, y - e, z)) / (2 * e),
                (F(x, y, z + e) - F(x, y, z - e)) / (2 * e)))
    return g.normalized() if g.length > 1e-9 else Vector((0.0, -1.0, 0.0))


def head_point(x: float, z: float, offset: float = 0.0) -> Vector:
    p = Vector((x, head_surface_y(x, z), z))
    return p + head_normal(x, z) * offset


def patch_from_outline(name: str, outline, material, offset: float, rings: int = 3):
    """把 (x,z) 平面轮廓贴到头部前表面并沿法线抬起 offset。"""
    cx = sum(p[0] for p in outline) / len(outline)
    cz = sum(p[1] for p in outline) / len(outline)
    bm = bmesh.new()
    grid = []
    for r in range(rings):
        t = 1.0 - r / float(rings)
        grid.append([bm.verts.new(head_point(cx + (x - cx) * t, cz + (z - cz) * t, offset))
                     for (x, z) in outline])
    for r in range(len(grid) - 1):
        n = len(grid[r])
        for i in range(n):
            j = (i + 1) % n
            try:
                bm.faces.new((grid[r][i], grid[r][j], grid[r + 1][j], grid[r + 1][i]))
            except ValueError:
                pass
    centre = bm.verts.new(head_point(cx, cz, offset))
    last = grid[-1]
    for i in range(len(last)):
        j = (i + 1) % len(last)
        try:
            bm.faces.new((last[i], last[j], centre))
        except ValueError:
            pass
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return new_mesh_object(name, bm, material)


def almond_outline(cx, cz, half_len, upper_h, lower_h, tilt_deg, n=14, skew=0.16, sign=1.0):
    """杏眼/凤眼轮廓：上睑弧高、外眼角上挑、上睑峰略偏外。"""
    pts = []
    for i in range(n + 1):
        u = -1.0 + 2.0 * i / n
        h = upper_h * math.sqrt(max(1.0 - u * u, 0.0)) * (1.0 + skew * u)
        pts.append((u * half_len, h))
    for i in range(n - 1, 0, -1):
        u = -1.0 + 2.0 * i / n
        h = -lower_h * math.sqrt(max(1.0 - u * u, 0.0)) * (1.0 - 0.10 * u)
        pts.append((u * half_len, h))
    ct, st = math.cos(math.radians(tilt_deg)), math.sin(math.radians(tilt_deg))
    out = []
    for x, z in pts:
        out.append((cx + sign * (x * ct - z * st), cz + (x * st + z * ct)))
    return out


EYE_Z = CHIN_Z + 0.0985
EYE_X = 0.0355


# --- 五官尺寸（少年感关键：眼裂小、眼线细、眉薄）---------------------------
# 相对初版：眼裂半长 0.0268 -> 0.0212（-21%），上睑高 0.0132 -> 0.0094（-29%）。
# 初版过大的眼裂与厚重的上眼线会在 2.5D 尺度直接读成严厉成年人。
EYE_HALF_LEN = 0.0212
EYE_UPPER_H = 0.0094
EYE_LOWER_H = 0.0066
EYE_TILT_DEG = 4.0
# 虹膜半径小于眼裂高度，保证上下都留出眼白（初版虹膜几乎占满，读成瞪视）
IRIS_R = 0.0068
IRIS_CORE_R = 0.0032
# 上眼线厚度：初版 0.0029 -> 0.0011（-62%）
LASH_THICK = 0.00110
# 眉：厚度由 0.0022-0.0064 收到 0.0014-0.0030（-55%/-53%），走向改为平缓外扬
BROW_HALF_LEN = 0.0262
BROW_H_HEAD = 0.0158
BROW_H_TAIL = 0.0196
BROW_THICK_MIN = 0.00140
BROW_THICK_MAX = 0.00300


def brow_center_z(u: float) -> float:
    """眉毛中心线：眉头低、中段平、眉尾微扬（不是愤怒的倒八）。"""
    rise = BROW_H_HEAD + (BROW_H_TAIL - BROW_H_HEAD) * (u ** 1.35)
    arch = 0.00185 * math.sin(math.pi * min(max((u - 0.10) / 0.80, 0.0), 1.0))
    return EYE_Z + rise + arch


def build_face():
    parts = []
    for sign in (1, -1):
        tag = "L" if sign > 0 else "R"
        cx = EYE_X * sign
        tilt = EYE_TILT_DEG
        sclera = almond_outline(cx, EYE_Z, EYE_HALF_LEN, EYE_UPPER_H, EYE_LOWER_H,
                                tilt, n=16, skew=0.14, sign=sign)
        parts.append(patch_from_outline("V8_EyeWhite_" + tag, sclera, MAT["inner"], 0.0008))
        # 虹膜：圆而小，四边留眼白
        iris = almond_outline(cx + 0.0009 * sign, EYE_Z - 0.0002, IRIS_R, IRIS_R * 1.02,
                              IRIS_R * 1.02, tilt, n=14, skew=0.0, sign=sign)
        parts.append(patch_from_outline("V8_Iris_" + tag, iris, MAT["iris"], 0.0013))
        pupil = almond_outline(cx + 0.0010 * sign, EYE_Z - 0.0002, IRIS_CORE_R,
                               IRIS_CORE_R, IRIS_CORE_R, tilt, n=12, skew=0.0, sign=sign)
        parts.append(patch_from_outline("V8_Pupil_" + tag, pupil, MAT["dark"], 0.0018))
        spark = almond_outline(cx - 0.0028 * sign, EYE_Z + 0.0030, 0.0016, 0.0016, 0.0016,
                               0, n=10, sign=sign)
        parts.append(patch_from_outline("V8_Glint_" + tag, spark, MAT["inner"], 0.0022))

        # 上眼线：只覆上睑外缘的细线，宽度沿睑缘略变
        lash = []
        n = 16
        for i in range(n + 1):
            u = -1.0 + 2.0 * i / n
            h = EYE_UPPER_H * math.sqrt(max(1.0 - u * u, 0.0)) * (1.0 + 0.14 * u)
            lash.append((u * EYE_HALF_LEN, h))
        for i in range(n, -1, -1):
            u = -1.0 + 2.0 * i / n
            h = EYE_UPPER_H * math.sqrt(max(1.0 - u * u, 0.0)) * (1.0 + 0.14 * u)
            t = LASH_THICK * (0.70 + 0.30 * (1.0 - abs(u)))
            lash.append((u * EYE_HALF_LEN, h - t))
        ct, st = math.cos(math.radians(tilt)), math.sin(math.radians(tilt))
        lash = [(cx + sign * (x * ct - z * st), EYE_Z + (x * st + z * ct)) for x, z in lash]
        parts.append(patch_from_outline("V8_Lash_" + tag, lash, MAT["dark"], 0.0019, rings=2))

        # 眉：薄、平缓、眉尾微扬；中段略厚、两端收细
        brow = []
        n = 14
        for i in range(n + 1):
            u = i / n
            brow.append(((-1.0 + 2.0 * u) * BROW_HALF_LEN, brow_center_z(u)))
        for i in range(n, -1, -1):
            u = i / n
            t = BROW_THICK_MIN + (BROW_THICK_MAX - BROW_THICK_MIN) * math.sin(
                math.pi * min(max((u - 0.02) / 0.96, 0.0), 1.0)) ** 0.7
            brow.append(((-1.0 + 2.0 * u) * BROW_HALF_LEN, brow_center_z(u) - t))
        brow = [(cx + sign * x, z) for x, z in brow]
        parts.append(patch_from_outline("V8_Brow_" + tag, brow, MAT["dark"], 0.0014, rings=2))

    # 鼻：窄直鼻梁 + 克制的鼻头与鼻翼
    nose_rows = []
    for z, w, off in ((EYE_Z + 0.0040, 0.0062, 0.0055), (EYE_Z - 0.0175, 0.0072, 0.0092),
                      (EYE_Z - 0.0345, 0.0086, 0.0118), (EYE_Z - 0.0450, 0.0128, 0.0126),
                      (EYE_Z - 0.0510, 0.0112, 0.0072), (EYE_Z - 0.0535, 0.0072, 0.0030)):
        row = []
        for k in range(5):
            u = -1.0 + 2.0 * k / 4.0
            row.append(head_point(u * w, z, off))
        nose_rows.append(row)
    bm = bmesh.new()
    grid = [[bm.verts.new(p) for p in row] for row in nose_rows]
    for r in range(len(grid) - 1):
        for i in range(4):
            bm.faces.new((grid[r][i], grid[r][i + 1], grid[r + 1][i + 1], grid[r + 1][i]))
    for edge in (list(reversed(grid[0])), grid[-1]):
        try:
            bm.faces.new(edge)
        except ValueError:
            pass
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    parts.append(new_mesh_object("V8_Nose", bm, MAT["skin"]))

    # 嘴：薄而有形，自然闭合
    mouth_z = EYE_Z - 0.0790
    upper = []
    n = 12
    for i in range(n + 1):
        u = -1.0 + 2.0 * i / n
        upper.append((u * 0.0175, 0.0026 * math.sqrt(max(1.0 - u * u, 0.0)) + 0.0004))
    lower = []
    for i in range(n, -1, -1):
        u = -1.0 + 2.0 * i / n
        lower.append((u * 0.0175, -0.0038 * math.sqrt(max(1.0 - u * u, 0.0))))
    outline = [(x, mouth_z + z) for x, z in upper + lower]
    parts.append(patch_from_outline("V8_Mouth", outline, MAT["lips"], 0.0011, rings=2))
    line = [(x, mouth_z + 0.0002 + 0.0006 * math.sqrt(max(1.0 - (x / 0.0175) ** 2, 0.0)))
            for x in [(-1.0 + 2.0 * i / 10) * 0.0168 for i in range(11)]]
    line += [(x, mouth_z - 0.0008 + 0.0006 * math.sqrt(max(1.0 - (x / 0.0175) ** 2, 0.0)))
             for x in [(-1.0 + 2.0 * i / 10) * 0.0168 for i in range(10, -1, -1)]]
    parts.append(patch_from_outline("V8_MouthLine", line, MAT["dark"], 0.0015, rings=2))
    return parts


# ---------------------------------------------------------------- 头发

# 发际线相对下巴的高度（米）。必须落在头部最宽环（CHIN_Z+0.120）之下，
# 否则发帽会在颅骨最宽处外翻出一条"帽檐"（本轮实测）。
# 前中抬高到 0.158 形成发际露额，两侧降到耳上，后颈降到 0.006 盖住后颈。
HAIRLINE_TABLE = [(0.0, 0.158), (26.0, 0.154), (52.0, 0.140), (78.0, 0.120),
                  (110.0, 0.070), (145.0, 0.026), (180.0, 0.006)]


def hairline_offset(angle_from_front_deg: float) -> float:
    a = abs(angle_from_front_deg)
    tbl = HAIRLINE_TABLE
    if a >= tbl[-1][0]:
        return tbl[-1][1]
    for i in range(len(tbl) - 1):
        a0, v0 = tbl[i]
        a1, v1 = tbl[i + 1]
        if a0 <= a <= a1:
            u = (a - a0) / (a1 - a0)
            return v0 + (v1 - v0) * u
    return tbl[-1][1]


# 中分缝半宽（度）：分缝处抬高，露出眉间上方的额头
PART_HALF_DEG = 9.0
PART_LIFT = 0.0060


def part_lift(ang_front_deg: float) -> float:
    """发际在分缝附近抬高，形成一条可读的中分缝。"""
    a = abs(ang_front_deg)
    if a >= 34.0:
        return 0.0
    t = 1.0 - (a / 34.0)
    return PART_LIFT * (t ** 2.0)


def build_hair():
    seg = 40
    rows_u = 9
    # 不得高于颅顶（CHIN_Z+0.2310）：高出颅顶会在正面形成一个小jiu凸起（本轮实测）
    # 必须高于颅顶（CHIN_Z+0.2310），否则头顶露出发帽外的一小块肤色
    top_z = CHIN_Z + 0.2335
    grid_rows = []
    for r in range(rows_u + 1):
        u = r / float(rows_u)
        ease = u ** 0.72
        row = []
        for i in range(seg):
            t = TAU * i / seg
            ang_front = math.degrees(abs(((t - TAU * 0.75 + math.pi) % TAU) - math.pi))
            base = CHIN_Z + hairline_offset(ang_front) + part_lift(ang_front)
            z = base + (top_z - base) * ease
            rx, ryf, ryb, pw = head_profile_at(z)
            # 发帽只做贴头底层（3–7 mm），外观交给前发/鬓发/披发分件；
            # 初版 4–13.5 mm 的厚壳正面读成一顶完整头盔。
            thick = 0.0030 + 0.0042 * (0.35 + 0.65 * (1.0 - ang_front / 180.0)) * (0.40 + 0.60 * u)
            x, y = superellipse_xy(t, rx + thick, ryf + thick, ryb + thick, pw)
            row.append(Vector((x, y, z)))
        grid_rows.append(row)
    # 顶部收口：单圈向一个顶点收敛，形成平缓穹顶，正面不产生小凸起
    rx0, ryf0, ryb0, pw0 = head_profile_at(top_z)
    last = grid_rows[-1]
    apex = Vector((0.0, (ryf0 - ryb0) * 0.5 - 0.0025, top_z + 0.0022))
    cap_row = [apex + (p - apex) * 0.42 for p in last]
    grid_rows.append(cap_row)

    bm = bmesh.new()
    grid = [[bm.verts.new(p) for p in row] for row in grid_rows]
    for r in range(len(grid) - 1):
        for i in range(seg):
            j = (i + 1) % seg
            bm.faces.new((grid[r][i], grid[r][j], grid[r + 1][j], grid[r + 1][i]))
    bm.faces.new(grid[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    cap = new_mesh_object("V8_HairCap", bm, MAT["hair"])

    parts = [cap]

    # 1) 前发（分缝）：左右两块独立前发，中分缝在 x≈0 处露出额头。
    #    初版是一条平切的黑色发际弧，正面读成头盔；这里改成有分缝的两块。
    for sign in (1, -1):
        tag = "L" if sign > 0 else "R"
        rows = []
        steps = 7
        for zi in range(steps + 1):
            u = zi / steps
            # 自内（分缝处，高）向外（太阳穴，低）扫过前额
            ang_front = PART_HALF_DEG + 1.5 + 44.0 * u
            z = CHIN_Z + hairline_offset(ang_front) + 0.0200 * (1.0 - u) ** 1.2
            pts = []
            for k in range(5):
                v = -1.0 + 2.0 * k / 4.0
                # 沿宽度方向下探更多，形成有厚度、外缘更低的前发块
                zz = z + v * (0.0155 + 0.0060 * u) - 0.0075 * (1.0 - abs(v))
                aa = ang_front + v * 4.6
                rx, ryf, ryb, pw = head_profile_at(zz)
                t = TAU * 0.75 + math.radians(aa)
                x, y = superellipse_xy(t, rx + 0.0088, ryf + 0.0088, ryb + 0.0088, pw)
                # 同领片：必须镜像，否则左右前发落在同一侧（本轮实测）
                pts.append(Vector((x * sign, y, zz)))
            rows.append(pts)
        parts.append(sheet("V8_FrontBang_" + tag, rows, 0.0105, MAT["hair"]))

    # 2) 鬓发：太阳穴到颧骨上缘，窄而贴脸（终到 CHIN_Z+0.089，不遮下颌）
    for sign in (1, -1):
        tag = "L" if sign > 0 else "R"
        rows = []
        for zi in range(6):
            u = zi / 5.0
            z = CHIN_Z + 0.1180 - 0.0290 * u
            w = 0.0082 + 0.0026 * math.sin(math.pi * u)
            pts = []
            for k in range(4):
                v = -1.0 + 2.0 * k / 3.0
                px = sign * (0.0738 + 0.0006 * u)
                pz = z + v * w * 0.55
                surface = Vector((px, head_surface_y(min(abs(px), 0.0775), pz, front=False), pz))
                pts.append(surface + Vector((0.0, 0.0088, 0.0)))
            rows.append(pts)
        parts.append(sheet("V8_SideLock_" + tag, rows, 0.0100, MAT["hair"]))

    # 3) 后脑束点：束起的一小股，位于颅顶之下、后脑偏高处
    bundle_rows = []
    for i in range(7):
        u = i / 6.0
        z = CHIN_Z + 0.100 + 0.0480 * u
        rad = 0.0455 - 0.0200 * (u ** 1.35)
        y = 0.0500 + 0.0170 * u
        row = []
        for k in range(12):
            a = TAU * k / 12
            row.append(Vector((math.cos(a) * rad, y + math.sin(a) * rad * 0.80, z)))
        bundle_rows.append(row)
    parts.append(loft("V8_HairBundle", bundle_rows, material=MAT["hair"]))

    # 4) 素净青玉发带
    band_z = CHIN_Z + 0.1285
    parts.append(band_ring("V8_HairBand", band_z, band_z + 0.0110, 0.0425, 0.0470,
                           0.0500 + 0.0170 * 0.60, MAT["jade"], seg=18))

    # 5) 下披发：三片有间隙、有层次的厚片（不是一整块矩形板）。
    #    中央最宽最长，左右两片稍短并向前包，片间留缝，末端渐窄错落。
    # 三片之间必须留出可见缝隙，否则会糊成一块板（初版失败点）。
    # 中央片最宽最长；左右片收窄、前包、缩短，形成错落层次。
    fall_strands = (
        ("Center", 0.0, 0.0620, 0.0920, 0.0, 0.000),
        ("Left", 0.62, 0.0540, 0.0840, -0.038, 0.030),
        ("Right", -0.62, 0.0540, 0.0840, 0.038, 0.030),
    )
    for name, centre_rad_ratio, hw0, depth0, x_off, shorten in fall_strands:
        centre = math.pi * centre_rad_ratio
        rows = []
        spec = [
            (CHIN_Z + 0.140, 0.94, 0.92),
            (CHIN_Z + 0.075, 1.00, 1.00),
            (CHIN_Z + 0.010, 1.02, 1.02),
            (CHIN_Z - 0.055, 0.99, 1.00),
            (CHIN_Z - 0.120, 0.92, 0.94),
            (CHIN_Z - 0.180, 0.82, 0.85),
            (CHIN_Z - 0.220 + shorten, 0.60, 0.62),
            (CHIN_Z - 0.245 + shorten, 0.26, 0.28),
        ]
        for z, sw, sd in spec:
            row = []
            span = math.radians(31.0)
            for k in range(13):
                phi = centre + (-span + 2.0 * span * k / 12.0)
                hw = hw0 * sw
                depth = depth0 * sd
                x = math.sin(phi) * hw + x_off
                y = 0.0200 + math.cos(phi) * depth
                row.append(Vector((x, max(y, 0.0135), z)))
            rows.append(row)
        strand = sheet("V8_HairFall_" + name, rows, 0.0155, MAT["hair"])
        orient_outward(strand, 0.0, 0.020)
        parts.append(strand)
    return parts


def band_ring(name, z0, z1, r_in, r_out, cy, material, seg=20, cx=0.0):
    """扁平环带（发带 / 束带）：内径外径接近，高度小。"""
    bm = bmesh.new()
    def rr(z, r):
        return [bm.verts.new((cx + r * math.cos(TAU * i / seg), cy + r * math.sin(TAU * i / seg), z))
                for i in range(seg)]
    ob0, ob1 = rr(z0, r_out), rr(z1, r_out)
    ib0, ib1 = rr(z0, r_in), rr(z1, r_in)
    for i in range(seg):
        j = (i + 1) % seg
        bm.faces.new((ob0[i], ob0[j], ob1[j], ob1[i]))
        bm.faces.new((ib1[i], ib1[j], ib0[j], ib0[i]))
        bm.faces.new((ob1[i], ob1[j], ib1[j], ib1[i]))
        bm.faces.new((ib0[i], ib0[j], ob0[j], ob0[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return new_mesh_object(name, bm, material)


# ---------------------------------------------------------------- 服装

# 内衫下缘塞进腰封以下、藏在外层（前摆 0.870）之内；骨盆由长裤覆盖。
# 下缘若低于外层下摆，会在开叉处露出一块白色内衣角（本轮实测）。
SHIRT_HEM_Z = 0.930


def coat_gap_half_deg() -> float:
    return COAT_GAP_DEG * 0.5


def neckline_top_z(ang_front_deg: float) -> float:
    """内衫领口上缘：一条平缓的高圆领，前中略下凹成 V。

    这是本轮最稳的构造（前两版都失败）：
    - 只要内衫上缘是**单值连续曲线**，就不可能与自身交叠成尖片；
    - 只要它整体高于外层前领口、低于外层侧领口，月白就只会从外层正面的
      V 形缺口里露出一块 V 形，两侧被外层自然遮住 —— 这正是交领该有的读法。
    失败版本：把上缘追着外层开口曲线走，会得到横贯胸口的白板或整条白带。
    """
    a = min(abs(ang_front_deg), 180.0)
    dip = math.exp(-((a / 26.0) ** 2))
    return SHIRT_NECK_HIGH - SHIRT_NECK_DIP * dip


def shirt_surface(ang_front_deg: float, z: float, expand: float):
    t = TAU * 0.75 + math.radians(ang_front_deg)
    zc = max(z, CROTCH_Z - 0.01)
    rx, ryf, ryb, pw = torso_profile_at(zc)
    return superellipse_xy(t, rx + expand, ryf + expand, ryb + expand, pw)


def build_inner_shirt():
    """月白交领内衫：上缘按方位角定义 V 领。

    初版领口用两条"压边带子"叠在 V 上，产生了多片穿插与尖片爆炸。
    这里改为单一连续壳体 + 出口在 V 尖端的一对**等厚平领片**（见 build_collar_bands）。
    """
    rows = []
    steps = 16
    seg = 44
    for r in range(steps + 1):
        u = r / steps
        row = []
        for i in range(seg):
            t = TAU * i / seg
            ang_front = math.degrees(abs(((t - TAU * 0.75 + math.pi) % TAU) - math.pi))
            top = neckline_top_z(ang_front)
            z = SHIRT_HEM_Z + (top - SHIRT_HEM_Z) * u
            x, y = shirt_surface(ang_front, z, 0.0058)
            row.append(Vector((x, y, z)))
        rows.append(row)

    # 翻领：只把**领口那一圈**的外缘向下延长成一条外翻窄带。
    # 初版把整圈所有列都向下延，等于让整圈面料沿自身切向"斜切"，
    # 在 x≈0 附近形成一条横贯胸口的斜折片（本轮实测的白色尖块来源）。
    # 这里改成：内层壳体照旧，紧贴其外再套一个"外翻 V 领壳"，
    # 两者同心同列序，因此不会互相穿插。
    bm = bmesh.new()
    grid = [[bm.verts.new(p) for p in row] for row in rows]
    for r in range(len(grid) - 1):
        for i in range(seg):
            j = (i + 1) % seg
            bm.faces.new((grid[r][i], grid[r][j], grid[r + 1][j], grid[r + 1][i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    obj = new_mesh_object("V8_InnerShirt", bm, MAT["inner"])
    mod = obj.modifiers.new("solidify", "SOLIDIFY")
    mod.thickness = 0.0042
    mod.offset = 1.0
    activate(obj)
    bpy.ops.object.modifier_apply(modifier=mod.name)

    # 不再叠"外翻领壳"：任何额外的环形领片都会在领口曲率最大处自交成白色尖片
    # （初版与外翻壳各失败一次）。月白 V 区直接由内衫本体在青蓝外层 62° 开口中读出，
    # 两层关系由「外层开口边缘 + 内衫白色表面」构成，无需第三层几何。
    return obj


# 领口层次（三条边界必须按此顺序，否则外层开口里露出的是胸口皮肤）：
#   内衫 V 底 1.4280  <  外层前领口 1.4420  <  内衫颈侧上缘 1.5060
# 内衫领口：高处 1.4700（低于外层侧领 1.4840，高于外层前领 1.4180），
# 前中下凹 0.0520 形成 V，于是月白只在正面的 V 缺口里可见。
SHIRT_NECK_HIGH = 1.4700
SHIRT_NECK_DIP = 0.0605
V_BOTTOM_Z = 1.3860
V_TOP_Z = 1.4720
SHIRT_TOP_OUTER = 1.4760
V_HALF_W = 0.0445


def collar_point(u: float, half_w: float, expand: float, lift: float) -> Vector:
    """V 领口参数点：u=0 在领口最低点，u=1 在颈侧最高点。"""
    z = V_BOTTOM_Z + (V_TOP_Z - V_BOTTOM_Z) * u
    x = -half_w * u
    rx, ryf, ryb, pw = torso_profile_at(z)
    y = -(ryf + expand + lift) * max(1.0 - (abs(x) / max(rx + expand + lift, 1e-6)) ** pw,
                                     0.0) ** (1.0 / pw)
    return Vector((x, y, z))


def collar_band(sign: int, lift: float, width: float = 0.0230):
    """一条交领领片：贴着胸廓表面、沿 V 边的一整条等宽带。

    构造方式刻意只用 sheet()（连续两行四边形）再 Solidify：
    - 不再手搭 4 行"环管"，因此不会因切向翻转产生翻面或尖片爆炸（初版实测）；
    - 带宽方向由「领口中心线切向 × 表面法向」给出，并统一朝 V 外侧，
      因此左右两条带宽一致、厚度一致。
    """
    steps = 16
    # u 从 -0.16（越过 V 尖，形成交叠）到 1.0（颈侧）
    centre_line = []
    for i in range(steps + 1):
        # u 自 V 尖稍上方起（-0.06）到颈侧；两端都不越过彼此，避免自交
        u = -0.06 + 1.06 * i / steps
        ang = (56.0 * u) * (1.0 if sign > 0 else -1.0)
        z = neckline_top_z(abs(ang)) + 0.0030 + lift
        x, y = shirt_surface(abs(ang), z, 0.0058)
        centre_line.append(Vector((x, y, z)))

    # 只用两行点构成带宽（外缘行 + 内缘行），再 Solidify 出等厚：
    # 三行（含中轴）会在 V 尖处自交，产生尖片堆叠（初版实测）。
    band_rows = []
    for i, c in enumerate(centre_line):
        nxt = centre_line[min(i + 1, len(centre_line) - 1)]
        prv = centre_line[max(i - 1, 0)]
        tangent = nxt - prv
        if tangent.length < 1e-9:
            tangent = Vector((0.0, 0.0, 1.0))
        tangent.normalize()
        normal = Vector((c.x, c.y - 0.006, 0.0))
        normal = normal.normalized() if normal.length > 1e-9 else Vector((0.0, -1.0, 0.0))
        across = tangent.cross(normal)
        across = across.normalized() if across.length > 1e-9 else Vector((1.0, 0.0, 0.0))
        outward = Vector((c.x, c.y + 0.02, 0.0))
        if outward.length < 1e-9:
            outward = Vector((0.0, -1.0, 0.0))
        if across.dot(outward) < 0.0:
            across = -across
        band_rows.append([c, c + across * width])

    # 必须镜像：shirt_surface() 只返回 +X 一侧的点。初版漏了这一步，
    # 两条领片被建在同一侧并共面，渲染成一片尖叫的白色碎块（本轮主因）。
    if sign < 0:
        band_rows = [[Vector((-p.x, p.y, p.z)) for p in row] for row in band_rows]

    return sheet("V8_Collar_" + ("L" if sign > 0 else "R"), band_rows, 0.0060, MAT["inner"])


def build_collar_bands():
    """交领：右片压在左片之上（lift 差 4 mm），两条带宽与厚度一致。"""
    return [collar_band(1, 0.0), collar_band(-1, 0.0040)]


def build_sash():
    parts = []
    z0, z1 = 1.0180, 1.0920
    rows = []
    # 腰封束在外层之上：外层在该高度的膨胀约 2.3 cm，这里取 3.4 cm
    for r in range(9):
        u = r / 8.0
        z = z0 + (z1 - z0) * u
        # 上下边缘略收，中段最厚：束腰弧面，避免直筒与衣身同半径打架
        bulge = 0.0068 * math.sin(math.pi * min(max(u, 0.0), 1.0)) ** 0.65
        rx, ryf, ryb, pw = torso_profile_at(z)
        row = []
        seg = 34
        for i in range(seg):
            t = TAU * i / seg
            e = 0.0345 + bulge
            x, y = superellipse_xy(t, rx + e, ryf + e, ryb + e, pw)
            row.append(Vector((x, y, z)))
        rows.append(row)
    bm = bmesh.new()
    grid = [[bm.verts.new(p) for p in row] for row in rows]
    seg_n = len(rows[0])
    for r in range(len(grid) - 1):
        for i in range(seg_n):
            j = (i + 1) % seg_n
            bm.faces.new((grid[r][i], grid[r][j], grid[r + 1][j], grid[r + 1][i]))
    bm.faces.new(list(reversed(grid[0])))
    bm.faces.new(grid[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    parts.append(new_mesh_object("V8_Sash", bm, MAT["sash"]))

    rx, ryf, ryb, pw = torso_profile_at(1.0555)
    y = -(ryf + 0.0413)
    parts.append(box("V8_SashRim", (0.0, y - 0.0035, 1.0555), (0.0468, 0.0090, 0.0425), MAT["trim"]))
    parts.append(box("V8_SashJade", (0.0, y - 0.0075, 1.0555), (0.0368, 0.0125, 0.0325), MAT["jade"]))
    return parts


def coat_hem_z(ang_front_deg: float) -> float:
    """外层下摆高度：前片最高，侧面居中，后摆只比前摆长 10 cm。"""
    a = min(abs(ang_front_deg), 180.0)
    if a <= 90.0:
        u = a / 90.0
        return COAT_HEM_FRONT + (COAT_HEM_SIDE - COAT_HEM_FRONT) * (u ** 1.25)
    u = (a - 90.0) / 90.0
    return COAT_HEM_SIDE + (COAT_HEM_BACK - COAT_HEM_SIDE) * (u ** 1.05)


# 外层前中开口半角（度）×2。30° 时肩胸仍被外层覆盖，只在领口留出 V 形缺口；
# 过宽（62°）会让内衫摊成横贯胸口的白板（实测）。
COAT_GAP_DEG = 30.0
NECK_OPEN_SCALE = 0.430
# 领口收拢区高度（米）：内衫与外层共用同一条收拢曲线，内衫才不会从外层肩部穿出
COLLAR_TOP_Z = SHOULDER_Z + 0.038
COLLAR_TAPER_SPAN = 0.150


def collar_taper(z: float) -> float:
    u = (z - (COLLAR_TOP_Z - COLLAR_TAPER_SPAN)) / COLLAR_TAPER_SPAN
    return 1.0 - (1.0 - NECK_OPEN_SCALE) * smoothstep01(u)


def smoothstep01(u: float) -> float:
    u = max(0.0, min(1.0, u))
    return u * u * (3.0 - 2.0 * u)


def torso_shell(name, top_fn, hem_fn, expand_fn, material, thickness, seg=44,
                gap_deg: float = 0.0):
    """以躯干截面为基准生成的衣壳。

    hem_fn(ang)=下摆高度；top_fn(ang)=该方位的领口上缘高度。
    关键 1：环半径**不做整体缩放**。用统一系数收领口会让衣壳在胸口缩到躯干以内，
            把皮肤挤成一条横带（实测）。
    关键 2：gap_deg>0 时前中留出开口（不闭合），使内层月白 V 领连续可见；
            初版是整圈闭合壳，正面读成现代圆领长袖衫。
    """
    rows = []
    steps = 28
    for r in range(steps + 1):
        u = r / steps
        row = []
        if gap_deg > 0.0:
            half = math.radians(gap_deg) * 0.5
            count = seg
            angles = [TAU * 0.75 + half + (TAU - 2.0 * half) * i / (count - 1)
                      for i in range(count)]
        else:
            angles = [TAU * i / seg for i in range(seg)]
        for t in angles:
            ang_front = math.degrees(abs(((t - TAU * 0.75 + math.pi) % TAU) - math.pi))
            hem = hem_fn(ang_front)
            top = top_fn(ang_front)
            z = hem + (top - hem) * u
            zc = max(z, CROTCH_Z - 0.01)
            rx, ryf, ryb, pw = torso_profile_at(zc)
            expand = expand_fn(u, ang_front)
            x, y = superellipse_xy(t, rx + expand, ryf + expand, ryb + expand, pw)
            row.append(Vector((x, y, z)))
        rows.append(row)
    bm = bmesh.new()
    grid = [[bm.verts.new(p) for p in row] for row in rows]
    cols = len(rows[0])
    for r in range(len(grid) - 1):
        for i in range(cols):
            j = (i + 1) % cols
            bm.faces.new((grid[r][i], grid[r][j], grid[r + 1][j], grid[r + 1][i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    obj = new_mesh_object(name, bm, material)
    if thickness > 0.0:
        mod = obj.modifiers.new("solidify", "SOLIDIFY")
        mod.thickness = thickness
        mod.offset = 1.0
        activate(obj)
        bpy.ops.object.modifier_apply(modifier=mod.name)
    return obj


# 外层前领口必须低于内衫 V 底（1.4280），否则内层 V 会被外层切掉一半
COAT_NECK_FRONT = 1.4180
COAT_NECK_SIDE = 1.4840
COAT_NECK_BACK = 1.4990


def coat_neck_z(ang_front_deg: float) -> float:
    """外层领口：前中最低（露出内衫交领 V），肩侧抬到肩线，后中最高。"""
    a = min(abs(ang_front_deg), 180.0)
    if a <= 90.0:
        u = a / 90.0
        return COAT_NECK_FRONT + (COAT_NECK_SIDE - COAT_NECK_FRONT) * (u ** 1.45)
    u = (a - 90.0) / 90.0
    return COAT_NECK_SIDE + (COAT_NECK_BACK - COAT_NECK_SIDE) * (u ** 1.2)


def build_short_coat():
    """青蓝短外层：前中开口、贴合肩胸、腰部略收、下摆前短后稍长。

    初版是整圈闭合圆领筒，正面读成现代长袖针织衫。这里前中留 34° 开口，
    使内层月白 V 连续可见，形成明确的「内外两层」关系。
    """
    def expand(u, ang_front):
        # 肩胸贴（6.5 mm），腰部收（10 mm），下摆最松（26 mm）
        waist = math.exp(-((u - 0.46) / 0.26) ** 2)
        return 0.0260 - 0.0195 * u + 0.0055 * waist

    # 开口 30°：外层正常覆盖肩胸，只在领口留出一道 V 形缺口露出月白内衫。
    # 开口过宽（62°）时内衫会露成横贯胸口的白板（实测）。
    shell = torso_shell("V8_ShortCoat", coat_neck_z, coat_hem_z,
                        expand, MAT["outer"], 0.0100, gap_deg=COAT_GAP_DEG)
    return [shell]


def Math_lerp(u):
    return max(0.0, min(1.0, u))


def torso_profile_at(z):
    prof = TORSO_PROFILE
    if z <= prof[0][0]:
        return prof[0][1:]
    if z >= prof[-1][0]:
        return prof[-1][1:]
    for i in range(len(prof) - 1):
        z0, z1 = prof[i][0], prof[i + 1][0]
        if z0 <= z <= z1:
            u = (z - z0) / max(z1 - z0, 1e-9)
            return tuple(prof[i][k] + (prof[i + 1][k] - prof[i][k]) * u for k in range(1, 5))
    return prof[-1][1:]


def build_sleeve(sign: int):
    """窄袖：自肩到腕逐渐收窄，末端束口；腕与整只手必须完全露出。"""
    tag = "L" if sign > 0 else "R"
    shoulder, elbow, wrist, d_up, d_fore = arm_frame(sign)
    fore_t = FORE_ARM_LEN * 0.86
    # 起点回到躯干内部（肩关节前 0.055 m），否则三角肌与衣身之间会露出皮肤缝
    pts = ([shoulder + d_up * t for t in (-0.068, -0.020, 0.045, 0.130, 0.225, UPPER_ARM_LEN)]
           + [elbow + d_fore * t for t in (0.020, 0.070, 0.130, fore_t)])
    # 每站都比上臂/前臂皮肤半径大 8 mm 以上，避免手臂顶穿袖管
    rad = [0.0705, 0.0690, 0.0640, 0.0580, 0.0535, 0.0505, 0.0515, 0.0470, 0.0425, 0.0375]
    tube = tube_along("V8_Sleeve_" + tag, pts, rad, 18, 2.0, MAT["outer"],
                      cap_start=True, cap_end=True)
    cuff_pts = [elbow + d_fore * (fore_t + t) for t in (0.0, 0.010, 0.019)]
    cuff = tube_along("V8_Cuff_" + tag, cuff_pts, [0.0392, 0.0388, 0.0350], 18, 2.0,
                      MAT["sash"])
    return [tube, cuff]


def build_skirt():
    """短摆：四片明确分离的布片，前片左右分开留中央开口，侧开叉自髋下开始。

    初版是"按角度连续、近水平"的整圈壳，正面读成短裙/围裙，开叉不清楚。
    这里每片是独立 sheet：片宽固定、片与片之间留 16–22° 净空，
    下缘沿片宽做斜线（外侧更低），最高点止于大腿上 1/3。
    """
    parts = []
    seg = 16
    panels = (
        ("FrontLeft", 26.0), ("FrontRight", -26.0),
        ("BackLeft", 152.0), ("BackRight", -152.0),
        ("LeftSide", 92.0), ("RightSide", -92.0),
    )
    z_top = 1.0300
    for name, centre_deg in panels:
        rows = []
        steps = 11
        hem_centre = z_panel_hem(centre_deg)
        half = math.radians(21.5)
        for r in range(steps + 1):
            u = r / steps
            row = []
            for i in range(seg):
                frac = -1.0 + 2.0 * i / (seg - 1)
                a = math.radians(centre_deg) + frac * half
                # 下缘斜线：片的外侧更低（形成折线感，不是水平盒盖）
                hem = hem_centre - 0.0240 * frac
                z = z_top - (z_top - hem) * u
                # 开叉：髋下（z<0.868）之后片宽收窄
                spread = 1.0 if z >= 0.8680 else 0.70
                aa = math.radians(centre_deg) + frac * half * spread
                t = TAU * 0.75 + aa
                zc = max(z, CROTCH_Z - 0.02)
                rx, ryf, ryb, pw = torso_profile_at(zc)
                flare = 0.0345 + 0.0150 * u
                x, y = superellipse_xy(t, rx + flare, ryf + flare, ryb + flare, pw)
                row.append(Vector((x, y, z)))
            rows.append(row)
        bm = bmesh.new()
        grid = [[bm.verts.new(p) for p in row] for row in rows]
        cols = len(rows[0])
        for r in range(len(grid) - 1):
            for i in range(cols - 1):
                bm.faces.new((grid[r][i], grid[r][i + 1], grid[r + 1][i + 1], grid[r + 1][i]))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        obj = new_mesh_object("V8_SkirtPanel_" + name, bm, MAT["outer"])
        mod = obj.modifiers.new("solidify", "SOLIDIFY")
        mod.thickness = 0.0115
        mod.offset = 1.0
        activate(obj)
        bpy.ops.object.modifier_apply(modifier=mod.name)
        orient_outward(obj)
        parts.append(obj)
    return parts


def z_panel_hem(centre_deg: float) -> float:
    """片下缘基准高度。前片保持在大腿上 1/3（髋 0.950 / 膝 0.470），
    后片比前片长 10.2 cm，仍远高于大腿中部。"""
    a = abs(centre_deg)
    if a <= 30.0:
        return 0.8760            # 前片：大腿上 1/3
    if a >= 150.0:
        return 0.7740            # 后片：比前片长 10.2 cm
    return 0.8260                # 侧片


def build_pants(sign: int):
    tag = "L" if sign > 0 else "R"
    hip = Vector((HIP_JOINT.x * sign, HIP_JOINT.y, HIP_JOINT.z + 0.062))
    knee = Vector((KNEE.x * sign, KNEE.y, KNEE.z))
    ankle = Vector((ANKLE.x * sign, ANKLE.y, 0.135))
    thigh_pts = [hip + (knee - hip) * u for u in (0.0, 0.3, 0.6, 1.0)]
    thigh_r = [0.1055, 0.0880, 0.0735, 0.0640]
    calf_pts = [knee + (ankle - knee) * u for u in (0.0, 0.3, 0.65, 1.0)]
    # 必须比小腿网格（0.056/0.060/0.055/0.043/0.033）每站都大 6 mm 以上，
    # 否则小腿会在裤管中段顶穿出来，形成裸腿色环（本轮实测）。
    calf_r = [0.0665, 0.0685, 0.0625, 0.0505]
    return tube_along("V8_Pants_" + tag, thigh_pts + calf_pts[1:],
                      thigh_r + calf_r[1:], LIMB_SEG, 2.0, MAT["pants"])


def build_pelvis():
    """长裤裆部/臀部壳体：补上两条裤腿之间的区域。

    只做左右两条裤腿管时，裆部（x≈0、外层前摆 0.870 以下）会露出一块躯干皮肤。
    这里用躯干截面加放松量补一层从裤腰到裆下的裤子壳体，裤腿管再从它下面分叉。
    """
    rows = []
    steps = 12
    top_z, hem_z = 1.0980, 0.7860
    for r in range(steps + 1):
        u = r / steps
        z = top_z - (top_z - hem_z) * u
        zc = max(z, CROTCH_Z - 0.02)
        rx, ryf, ryb, pw = torso_profile_at(zc)
        # 裤腰略紧，向下向大腿自然放松
        expand = 0.0060 if u < 0.12 else 0.0195 + 0.0075 * u
        # 不做径向收缩：收缩系数会把下缘拉进躯干内侧，反而把皮肤露出来（本轮实测）。
        # 裆部造型改由下缘高度（0.790，低于躯干底 0.795）与裤腿管衔接。
        shrink = 1.0
        row = []
        seg = 28
        for i in range(seg):
            t = TAU * i / seg
            x, y = superellipse_xy(t, (rx + expand) * shrink, (ryf + expand) * shrink,
                                   (ryb + expand) * shrink, pw)
            row.append(Vector((x, y, z)))
        rows.append(row)
    bm = bmesh.new()
    grid = [[bm.verts.new(p) for p in row] for row in rows]
    for r in range(len(grid) - 1):
        for i in range(len(grid[0])):
            j = (i + 1) % len(grid[0])
            bm.faces.new((grid[r][i], grid[r][j], grid[r + 1][j], grid[r + 1][i]))
    bm.faces.new(list(reversed(grid[0])))
    bm.faces.new(grid[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return new_mesh_object("V8_Pelvis", bm, MAT["pants"])


def build_boot(sign: int):
    tag = "L" if sign > 0 else "R"
    x = ANKLE.x * sign
    # 鞋楦：8 边截面 + 由后跟到鞋尖持续收窄 + 脚背坡度（前面低平、后跟高），
    # 不再是长方砖（初版）。
    rows = [
        (ANKLE.y + 0.058, 0.0430, 0.0900, 0.0000),
        (ANKLE.y + 0.020, 0.0480, 0.0930, 0.0000),
        (ANKLE.y - 0.030, 0.0505, 0.0760, 0.0000),
        (ANKLE.y - 0.100, 0.0520, 0.0570, 0.0000),
        (ANKLE.y - 0.158, 0.0492, 0.0450, 0.0000),
        (ANKLE.y - 0.198, 0.0400, 0.0338, 0.0000),
        (ANKLE.y - 0.222, 0.0252, 0.0242, 0.0000),
    ]
    rings = []
    for y, half_w, z_top, z_bot in rows:
        row = []
        for k in range(10):
            a = TAU * k / 10
            cu = math.copysign(abs(math.cos(a)) ** (2.0 / 3.4), math.cos(a))
            cv = math.copysign(abs(math.sin(a)) ** (2.0 / 3.4), math.sin(a))
            cz = z_bot + (z_top - z_bot) * 0.5
            rz = (z_top - z_bot) * 0.5
            row.append(Vector((x + cu * half_w, y, cz + cv * rz)))
        rings.append(row)
    foot = loft("V8_Boot_" + tag, rings, material=MAT["boots"])
    # 靴筒：顶点 0.1280，低于裤脚（0.1350）约 7 mm，裤脚自然盖住靴口
    shaft_rows = []
    for i in range(5):
        u = i / 4.0
        z = 0.0760 + 0.0520 * u
        r = 0.0560 - 0.0090 * u
        shaft_rows.append([Vector((x + math.cos(TAU * k / 16) * r,
                                   ANKLE.y + 0.004 + math.sin(TAU * k / 16) * r * 0.94, z))
                           for k in range(16)])
    shaft = loft("V8_BootShaft_" + tag, shaft_rows, material=MAT["boots"])
    return [foot, shaft]


# ---------------------------------------------------------------- 装配

def assemble():
    parts_body = []
    parts_body.append(build_torso())
    for sign in (1, -1):
        parts_body.append(build_arm(sign))
        parts_body += build_hand(sign)
        parts_body.append(build_leg(sign))
        parts_body.append(build_foot(sign))
    parts_head = build_head() + build_face()
    parts_hair = build_hair()
    # 交领翻领已并入内衫网格（见 build_inner_shirt 的 lapel 行）；
    # build_collar_bands() 保留但不再使用，避免独立领片再次产生穿插尖片。
    parts_cloth = [build_inner_shirt()] + build_sash()
    parts_cloth += build_short_coat() + build_skirt()
    parts_cloth.append(build_pelvis())
    for sign in (1, -1):
        parts_cloth += build_sleeve(sign)
        parts_cloth.append(build_pants(sign))
        parts_cloth += build_boot(sign)

    body = join_objects(parts_body, "V8_Body")
    head = join_objects(parts_head, "V8_Head_Face")
    hair = join_objects(parts_hair, "V8_Hair")
    outfit = join_objects(parts_cloth, "V8_Outfit")

    # 合并多余材质槽（各对象合并后槽位重复）
    for obj in (body, head, hair, outfit):
        merge_material_slots(obj)
    return {"body": body, "head": head, "hair": hair, "outfit": outfit}


def merge_material_slots(obj) -> None:
    """按材质去重并重映射面索引，避免合并后出现几十个重复槽。"""
    unique = []
    index_of = {}
    remap = {}
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


# ---------------------------------------------------------------- 校验

def mesh_stats(obj):
    me = obj.data
    me.calc_loop_triangles()
    tris = len(me.loop_triangles)
    verts = len(me.vertices)
    non_manifold = 0
    zero_area = 0
    bad_coord = 0
    bm = bmesh.new()
    bm.from_mesh(me)
    for edge in bm.edges:
        if not edge.is_manifold:
            non_manifold += 1
    for face in bm.faces:
        if face.calc_area() < 1e-12:
            zero_area += 1
    for v in bm.verts:
        if not all(math.isfinite(c) for c in v.co):
            bad_coord += 1
    bm.free()
    return {"name": obj.name, "vertices": verts, "triangles": tris,
            "polygons": len(me.polygons), "materials": len(obj.data.materials),
            "non_manifold_edges": non_manifold, "zero_area_faces": zero_area,
            "non_finite_verts": bad_coord}


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
    total_tris = sum(s["triangles"] for s in stats)
    materials = set()
    for obj in parts.values():
        for slot in obj.material_slots:
            if slot.material:
                materials.add(slot.material.name)
    mn, mx = world_bounds(list(parts.values()))
    checks = {
        "triangles_total": total_tris,
        "triangles_in_range_15k_45k": 15000 <= total_tris <= 45000,
        "material_count": len(materials),
        "materials_in_range_6_12": 6 <= len(materials) <= 12,
        "object_count": len(parts),
        "bbox_min": [round(v, 5) for v in mn],
        "bbox_max": [round(v, 5) for v in mx],
        "height_m": round(mx.z - mn.z, 4),
        "height_ok": 1.74 <= (mx.z - mn.z) <= 1.78,
        "feet_on_ground": abs(mn.z) < 0.002,
        "origin_between_feet": abs((mn.x + mx.x) * 0.5) < 0.004,
        "non_manifold_total": sum(s["non_manifold_edges"] for s in stats),
        "zero_area_total": sum(s["zero_area_faces"] for s in stats),
        "non_finite_total": sum(s["non_finite_verts"] for s in stats),
    }
    report["meshes"] = stats
    report["checks"] = checks
    return checks


def unapplied_transforms(objs):
    bad = []
    for obj in objs:
        if (obj.location - Vector((0, 0, 0))).length > 1e-6 or obj.scale != Vector((1, 1, 1)):
            bad.append({"name": obj.name, "location": list(obj.location), "scale": list(obj.scale)})
    return bad


def apply_transforms(objs) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objs:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)


def symmetry_report(parts) -> dict:
    """左右对称数值检查：以 X 镜像后顶点集合应可重合并回自身。"""
    out = {}
    for key in ("body", "head", "hair", "outfit"):
        obj = parts.get(key)
        if obj is None:
            continue
        pts = [obj.matrix_world @ v.co for v in obj.data.vertices]
        grid = {}
        for p in pts:
            grid[(round(p.x, 4), round(p.y, 4), round(p.z, 4))] = True
        missing = 0
        for p in pts:
            key2 = (round(-p.x, 4), round(p.y, 4), round(p.z, 4))
            if key2 not in grid:
                missing += 1
        out[key] = {"vertices": len(pts), "mirror_unmatched": missing,
                    "ratio": round(missing / max(len(pts), 1), 4)}
    return out


# ---------------------------------------------------------------- 轴向辅助

def build_axis_helper():
    """FRONT_+Z 指示：Blender 中指向 -Y（导出后为 +Z）。不导出。

    由「粗杆 + 圆锥箭头 + 文字」三部分组成，确保在 128/256 px 下仍可读；
    初版只有一个贴地小方块，脚前方几乎看不见。
    """
    mat = make_material("V8_AxisHelper", "#D8483C", 0.6, 0.0, 0.2)
    arrow = bpy.data.meshes.new("FRONT_axis_mesh")
    bm = bmesh.new()
    shaft_r = 0.030
    y0, y1 = 0.34, -0.58
    a = [bm.verts.new(p) for p in (
        (-shaft_r, y0, -0.014), (shaft_r, y0, -0.014), (shaft_r, y0, 0.014), (-shaft_r, y0, 0.014),
        (-shaft_r, y1, -0.014), (shaft_r, y1, -0.014), (shaft_r, y1, 0.014), (-shaft_r, y1, 0.014))]
    for face in ((0, 1, 2, 3), (7, 6, 5, 4), (0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)):
        bm.faces.new([a[i] for i in face])
    tip_y = y1 - 0.16
    base = [bm.verts.new(p) for p in (
        (-0.045, y1, -0.045), (0.045, y1, -0.045), (0.045, y1, 0.045), (-0.045, y1, 0.045))]
    tipp = bm.verts.new((0.0, tip_y, 0.0))
    bm.faces.new(list(reversed(base)))
    for i in range(4):
        j = (i + 1) % 4
        bm.faces.new((base[i], base[j], tipp))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(arrow)
    bm.free()
    obj = bpy.data.objects.new("FRONT_+Z", arrow)
    link(obj)
    obj.location = Vector((0.62, 0.0, 0.0))
    arrow.materials.append(mat)

    # 箭头：圆锥，起于杆端，指向 -Y
    cone = bpy.data.meshes.new("FRONT_axis_head")
    bmc = bmesh.new()
    bmesh.ops.create_cone(bmc, cap_ends=True, cap_tris=False, segments=20,
                          radius1=0.085, radius2=0.0, depth=0.26,
                          matrix=Matrix.Rotation(math.radians(-90), 4, "X")
                          @ Matrix.Translation((0.0, 0.0, 0.0)))
    bmesh.ops.translate(bmc, verts=bmc.verts, vec=Vector((0.0, y1 - 0.06, 0.0)))
    bmesh.ops.recalc_face_normals(bmc, faces=bmc.faces)
    bmc.to_mesh(cone)
    bmc.free()
    head = bpy.data.objects.new("FRONT_arrow_head", cone)
    link(head)
    head.location = Vector((0.62, 0.0, 0.0))
    cone.materials.append(mat)

    # 文字：Blender 内置字体，转成网格后随场景一起渲染
    labels = []
    for text, loc, size in (("FRONT +Z", (0.62, 0.42, 0.30), 0.170),
                            ("FRONT", (0.62, -0.98, 0.30), 0.130),
                            ("BACK", (0.62, 0.98, 0.30), 0.110)):
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
            tobj.name = "FRONT_label_" + text.replace(" ", "_").replace("+", "plus")
            tobj.data.materials.clear()
            tobj.data.materials.append(mat)
            labels.append(tobj)
        except Exception as exc:
            log("轴向文字生成失败（改用纯箭头）：%s" % exc)
    return join_objects([obj, head] + labels, "FRONT_+Z")


# ---------------------------------------------------------------- 渲染

def setup_render():
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 900
    scene.render.resolution_y = 1350
    scene.render.image_settings.file_format = "PNG"
    scene.view_settings.view_transform = "Standard"
    scene.render.film_transparent = False
    world = bpy.data.worlds.new("V8_World")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (0.70, 0.71, 0.72, 1.0)
    bg.inputs[1].default_value = 0.85

    cam_data = bpy.data.cameras.new("V8_Camera")
    cam_data.type = "ORTHO"
    cam = bpy.data.objects.new("V8_Camera", cam_data)
    link(cam)
    scene.camera = cam

    def sun(name, energy, rot):
        d = bpy.data.lights.new(name, "SUN")
        d.energy = energy
        d.angle = math.radians(14.0)
        o = bpy.data.objects.new(name, d)
        link(o)
        o.rotation_euler = rot
        return o

    sun("V8_Key", 2.6, (math.radians(56), 0.0, math.radians(-38)))
    sun("V8_Fill", 1.15, (math.radians(68), 0.0, math.radians(126)))
    sun("V8_Rim", 1.35, (math.radians(112), 0.0, math.radians(196)))
    return cam, cam_data


def render_view(cam, cam_data, name, azimuth_deg, elevation_deg, ortho, focus_z,
                height_px=None, width_px=None, focus_x: float = 0.0, focus_y: float = 0.0,
                aspect: float = 2.0 / 3.0):
    """ortho 参数的语义统一为「构图高度」。Blender 的 ortho_scale 作用于**较长的一边**，
    因此横构图时若直接把它当高度用，画面高度会缩成 ortho*H/W，角色头顶被裁掉
    （初版 2.5D 两张图就是这样被裁的）。这里按当前分辨率换算。"""
    scene = bpy.context.scene
    if height_px:
        scene.render.resolution_y = height_px
        scene.render.resolution_x = width_px or int(height_px * aspect)
    res_x = scene.render.resolution_x
    res_y = scene.render.resolution_y
    # ortho 的语义是「构图高度」；Blender 的 ortho_scale 作用于较长边，故横构图要放大
    cam_data.ortho_scale = ortho * (res_x / res_y) if res_x >= res_y else ortho
    a = math.radians(azimuth_deg)
    e = math.radians(elevation_deg)
    d = Vector((math.sin(a) * math.cos(e), -math.cos(a) * math.cos(e), math.sin(e)))
    cam.location = Vector((focus_x, focus_y, focus_z)) + d * 8.0
    cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
    scene.render.filepath = os.path.join(RENDERS, name + ".png")
    bpy.ops.render.render(write_still=True)
    return name


def image_margin_report(path: str) -> dict:
    """非背景像素 bbox 相对画面四边的留白比例。用于 2.5D 构图断言。

    背景色**从图像四角实测**，不写死常量：渲染结果经 sRGB 编码后与 World 的
    线性值不同（0.70 线性 ≈ 202/255 显示），写死线性值会把整幅背景误判成角色
    （本轮实测，导致 top 留白被报成 0）。
    """
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
    # Blender 图像第 0 行是画面**底部**，因此 ys_min 对应底边留白、ys_max 对应顶边
    return {
        "width": w, "height": h,
        "left": round(xs_min / w, 4),
        "right": round((w - 1 - xs_max) / w, 4),
        "bottom": round(ys_min / h, 4),
        "top": round((h - 1 - ys_max) / h, 4),
    }


def render_all(cam, cam_data, axis_helper):
    os.makedirs(RENDERS, exist_ok=True)
    H = HEIGHT
    shots = [
        ("v8_front", 0.0, 0.0, H * 1.10, H * 0.5),
        ("v8_back", 180.0, 0.0, H * 1.10, H * 0.5),
        ("v8_side_left", 90.0, 0.0, H * 1.10, H * 0.5),
        ("v8_side_right", -90.0, 0.0, H * 1.10, H * 0.5),
        ("v8_three_quarter_front", 38.0, 2.0, H * 1.10, H * 0.5),
        ("v8_three_quarter_back", 142.0, 2.0, H * 1.10, H * 0.5),
        ("v8_head_closeup", 0.0, 0.0, H * 0.30, H - H * 0.105),
        ("v8_head_three_quarter", 34.0, 0.0, H * 0.30, H - H * 0.105),
        ("v8_hands_closeup", 0.0, 30.0, H * 0.40, SHOULDER_Z - 0.020,
         None, None, 0.700, 0.0, 2.0 / 3.0),
        ("v8_hand_left_three_quarter", 32.0, 26.0, H * 0.40, SHOULDER_Z - 0.020,
         None, None, 0.700, 0.0, 2.0 / 3.0),
        ("v8_hand_left_top", 0.0, 78.0, H * 0.34, SHOULDER_Z - 0.020,
         None, None, 0.700, 0.0, 2.0 / 3.0),
        ("v8_feet_closeup", 0.0, 18.0, H * 0.30, 0.085),
    ]
    names = []
    axis_helper.hide_render = True
    for spec in shots:
        names.append(render_view(cam, cam_data, spec[0], spec[1], spec[2], spec[3], spec[4],
                                 *(spec[5:8] if len(spec) > 5 else ())))
    # 轴向证明用俯视 3/4：正面正交下「指向镜头」的箭头会被压缩成一个圆盘（实测不可读）
    axis_helper.hide_render = False
    names.append(render_view(cam, cam_data, "v8_front_with_axis", 26.0, 34.0, H * 1.35,
                             H * 0.46, focus_x=0.34))
    names.append(render_view(cam, cam_data, "v8_axis_topdown", 22.0, 62.0, H * 1.45,
                             H * 0.44, focus_x=0.34))
    axis_helper.hide_render = True
    names.append(render_view(cam, cam_data, "v8_front_with_axis_ortho", 0.0, 0.0, H * 1.10, H * 0.5))
    axis_helper.hide_render = True
    names.append(render_view(cam, cam_data, "v8_front_no_axis", 0.0, 0.0, H * 1.10, H * 0.5))

    # 2.5D：构图必须完整包含头顶、脚底与 T pose 全展（±0.89 m），并留 >=5% 边距。
    # 竖构图会裁掉手臂（实测：left/right 留白 0），因此按实际包围盒算宽高比。
    pose_half_w = 0.8905
    pad = 1.16                      # 上下左右各留约 7%（断言要求 >=4%）
    need_w = pose_half_w * 2.0 * pad
    need_h = H * pad
    for label, px in (("2p5d_128", 128), ("2p5d_256", 256)):
        width_px = max(8, int(round(px * (need_w / need_h))))
        names.append(render_view(cam, cam_data, "v8_" + label, 0.0, 0.0, need_h,
                                 H * 0.5, height_px=px, width_px=width_px,
                                 aspect=need_w / need_h))
    bpy.context.scene.render.resolution_x = 900
    bpy.context.scene.render.resolution_y = 1350

    # 灰模：整体覆盖为中性灰
    clay = make_material("V8_Clay", "#B8B8B8", 0.92, 0.0, 0.1)
    saved = {}
    for obj in bpy.data.objects:
        if obj.type == "MESH" and obj.name != "FRONT_+Z":
            saved[obj.name] = [s.material for s in obj.material_slots]
            for s in obj.material_slots:
                s.material = clay
    for spec in (("v8_grey_front", 0.0), ("v8_grey_back", 180.0),
                 ("v8_grey_side", 90.0), ("v8_grey_three_quarter", 38.0)):
        names.append(render_view(cam, cam_data, spec[0], spec[1], 0.0, H * 1.10, H * 0.5))
    for obj in bpy.data.objects:
        if obj.name in saved:
            for slot, mat in zip(obj.material_slots, saved[obj.name]):
                slot.material = mat
    return names


# ---------------------------------------------------------------- 导出

def export_all(shade_before: bool = False):
    bpy.ops.object.select_all(action="DESELECT")
    meshes = [o for o in bpy.data.objects if o.type == "MESH" and o.name != "FRONT_+Z"]
    for obj in meshes:
        obj.select_set(True)
        if shade_before:
            shade(obj, True, 42.0)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.export_scene.gltf(
        filepath=GLB, export_format="GLB", use_selection=True,
        export_yup=True, export_apply=True, export_animations=False,
        export_skins=False, export_morph=False, export_cameras=False, export_lights=False,
    )
    try:
        bpy.ops.export_scene.fbx(
            filepath=FBX, use_selection=True, apply_scale_options="FBX_SCALE_ALL",
            object_types={"MESH"}, use_mesh_modifiers=True,
            add_leaf_bones=False, bake_space_transform=False, axis_forward="-Z", axis_up="Y",
        )
        fbx_ok = os.path.exists(FBX)
    except Exception as exc:
        log("FBX 导出失败：%s" % exc)
        fbx_ok = False
    return fbx_ok


def glb_audit():
    import struct
    data = open(GLB, "rb").read()
    magic, version, total = struct.unpack("<III", data[:12])
    cursor, payload, binary = 12, None, None
    while cursor < total:
        length, ctype = struct.unpack("<II", data[cursor:cursor + 8])
        chunk = data[cursor + 8:cursor + 8 + length]
        if ctype == 0x4E4F534A:
            payload = json.loads(chunk)
        elif ctype == 0x004E4942:
            binary = chunk
        cursor += 8 + length
    tri = 0
    for mesh in payload.get("meshes", []):
        for prim in mesh["primitives"]:
            idx = prim.get("indices")
            if idx is not None:
                tri += payload["accessors"][idx]["count"] // 3
    mn = [1e9] * 3
    mx = [-1e9] * 3
    for mesh in payload.get("meshes", []):
        for prim in mesh["primitives"]:
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


# ---------------------------------------------------------------- 主流程

def phase_build():
    reset_scene()
    build_materials()
    parts = assemble()
    apply_transforms(list(parts.values()))
    for obj in parts.values():
        shade(obj, True, 42.0)

    axis_helper = build_axis_helper()
    report = {}
    report["blender_version"] = bpy.app.version_string
    report["units"] = "metric, 1.0 m"
    checks = validate(parts, report)
    report["symmetry"] = symmetry_report(parts)
    report["unapplied_transforms"] = unapplied_transforms(list(parts.values()) + [axis_helper])
    report["orientation"] = {
        "blender_front": "-Y",
        "export_yup": True,
        "gltf_front_after_export": "+Z",
        "axis_helper": "FRONT_+Z 为空物体，Blender 中箭头指向 -Y（导出后 +Z），不导出",
    }

    bpy.ops.wm.save_as_mainfile(filepath=BLEND)
    report["blend_sha256"] = sha256(BLEND)

    cam, cam_data = setup_render()
    report["renders"] = render_all(cam, cam_data, axis_helper)
    report["iteration"] = "refined_01"
    margins = {}
    for label in ("2p5d_128", "2p5d_256"):
        path = os.path.join(RENDERS, "v8_" + label + ".png")
        m = image_margin_report(path)
        margins[label] = m
        if not m.get("empty"):
            for side in ("top", "bottom", "left", "right"):
                assert m[side] >= 0.04, (
                    "2.5D %s 的 %s 留白 %.4f < 0.04，构图被裁切" % (label, side, m[side]))
    report["framing_check"] = margins
    log("2.5D 留白检查：%s" % margins)

    fbx_ok = export_all()
    report["export"] = {
        "glb": os.path.relpath(GLB, ROOT), "glb_sha256": sha256(GLB),
        "fbx": os.path.relpath(FBX, ROOT) if fbx_ok else None,
        "fbx_sha256": sha256(FBX) if fbx_ok else None,
        "fbx_note": "静态无骨骼；unrigged 供后续自动绑骨" if fbx_ok else "FBX 导出失败",
    }
    report["glb_audit"] = glb_audit()

    REPORT["phases"]["build"] = report
    with open(MANIFEST, "w") as fh:
        json.dump(REPORT, fh, indent=1, ensure_ascii=False, sort_keys=True)

    log("建模完成：三角面 %d，材质 %d，对象 %d" % (
        checks["triangles_total"], checks["material_count"], checks["object_count"]))
    log("包围盒 %s .. %s，身高 %.4f m" % (checks["bbox_min"], checks["bbox_max"], checks["height_m"]))
    log("对称镜像未匹配顶点：%s" % {k: v["mirror_unmatched"] for k, v in report["symmetry"].items()})
    log("GLB: %s" % report["glb_audit"])
    log("渲染：%d 张" % len(report["renders"]))
    return checks


def phase_export():
    """独立进程：重新打开最终 .blend，重新导出并回读审计。"""
    bpy.ops.wm.open_mainfile(filepath=BLEND)
    objs = [o for o in bpy.data.objects if o.type == "MESH"]
    report = {
        "reopened_blend": os.path.relpath(BLEND, ROOT),
        "blender_version": bpy.app.version_string,
        "objects": [{"name": o.name, "materials": [s.material.name for s in o.material_slots if s.material],
                     "vertices": len(o.data.vertices)} for o in objs],
        "axis_helper_present": any(o.name == "FRONT_+Z" for o in bpy.data.objects),
        "cameras_in_file": len([o for o in bpy.data.objects if o.type == "CAMERA"]),
        "lights_in_file": len([o for o in bpy.data.objects if o.type == "LIGHT"]),
        "armatures": len([o for o in bpy.data.objects if o.type == "ARMATURE"]),
        "constraints": sum(len(o.constraints) for o in bpy.data.objects),
        "actions": len(bpy.data.actions),
    }
    fbx_ok = export_all()
    report["fbx_ok"] = fbx_ok
    report["glb_audit"] = glb_audit()
    REPORT["phases"]["export"] = report
    with open(EXPORT_MANIFEST, "w") as fh:
        json.dump(REPORT, fh, indent=1, ensure_ascii=False, sort_keys=True)
    log("导出阶段回读：%s" % json.dumps(report["glb_audit"], ensure_ascii=False))
    return report


def main():
    argv = sys.argv
    phase = "build"
    if "--phase" in argv:
        phase = argv[argv.index("--phase") + 1]
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(RENDERS, exist_ok=True)
    if phase == "export":
        phase_export()
    else:
        phase_build()


main()
