#!/usr/bin/env python3
"""cultivator_tripo_v9 Phase 2: 从 clean.blend 派生 Mixamo 专用低面上传候选。

背景：标准上传件（599,417 tri / 22.1 MB FBX）在 Mixamo Auto-Rigger 页面长时间停在
"Processing upload" 未进入 marker 页。本轮不再原样重复，改为派生的低面候选。

用法（隔离后台进程）：
    Blender --background --factory-startup --python tools/art/build_cultivator_tripo_v9_lowpoly.py
    Blender --background --factory-startup --python tools/art/build_cultivator_tripo_v9_lowpoly.py -- audit

不覆盖 clean.blend / clean.glb / 标准上传件；全部产物使用 _lowpoly 后缀。
"""

import bmesh
import bpy
import hashlib
import json
import math
import os
import struct
import sys
import time
from mathutils import Matrix, Vector, kdtree

def _repo_root():
    return os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

ROOT = _repo_root()
ASSET = os.path.join(ROOT, "docs/art/cultivator_tripo_v9")
SOURCE_DIR = os.path.join(ASSET, "source")
EXPORT_DIR = os.path.join(ASSET, "exports")
TEXTURE_DIR = os.path.join(ASSET, "textures")
RENDER_DIR = os.path.join(ASSET, "renders")

CLEAN_BLEND = os.path.join(SOURCE_DIR, "cultivator_tripo_v9_clean.blend")
LOWPOLY_BLEND = os.path.join(SOURCE_DIR, "cultivator_tripo_v9_lowpoly.blend")
LOWPOLY_FBX = os.path.join(EXPORT_DIR, "cultivator_tripo_v9_mixamo_lowpoly.fbx")
MANIFEST = os.path.join(ASSET, "lowpoly_manifest.json")
AUDIT = os.path.join(ASSET, "lowpoly_audit.json")

TARGET_TRIS = 215000          # 目标中值（区间 180k–250k）
TARGET_HEIGHT = 1.750
S = TARGET_HEIGHT / 1.1470    # clean.blend 已在 1.75 m 尺度；此比例仅用于把"原始尺度阈值"换算过来

# --- 两级保护：只锁真正关键的结构，其余（含大部分头发与衣装）允许减面 -------------
# 一级（硬保护 weight=1.0）：Auto-Rigger 要靠它找下巴/手腕/脚踝，且人工 marker 也要看得清
CORE_FACE_Z = 0.905           # 原始尺度：下巴 0.955 以下 5 cm 起，含脸+前发
CORE_FACE_Y = -0.020          # 只保护前侧（y 更小 = 更靠脸），后脑大面积头发可减
CORE_HAND_ABSX = 0.300        # 原始尺度：只保护手掌与手指，不锁整条前臂
CORE_FOOT_Z = 0.058           # 原始尺度：只保护脚与靴筒下部，不锁整条靴筒

# 二级（软保护 weight=0.30）：保留外轮廓但不硬锁
SOFT_FACE_Z = 0.855
SOFT_FACE_Y = 0.060
SOFT_HAND_ABSX = 0.235
SOFT_HAND_Z = (0.45, 0.80)
SOFT_FOOT_Z = 0.120
SOFT_WEIGHT = 0.30

PHASE = "build"
if "--" in sys.argv:
    rest = sys.argv[sys.argv.index("--") + 1:]
    if rest:
        PHASE = rest[0]

LOG = []
def log(m):
    print(m, flush=True)
    LOG.append(m)

def sha256(path, chunk=1 << 20):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for b in iter(lambda: fh.read(chunk), b""):
            h.update(b)
    return h.hexdigest()

def tri_count(mesh):
    return sum(len(p.vertices) - 2 for p in mesh.polygons)

# ---------------------------------------------------------------- 保护分级

def tier_of(co):
    """返回 1.0(核心保护) / 0.30(软保护) / 0.0(自由)。坐标已在 1.75 m 尺度。"""
    z, y, x = co.z, co.y, co.x
    if z >= CORE_FACE_Z * S and y <= CORE_FACE_Y * S:
        return 1.0
    if abs(x) >= CORE_HAND_ABSX * S and 0.45 * S <= z <= 0.80 * S:
        return 1.0
    if z <= CORE_FOOT_Z * S:
        return 1.0
    if z >= SOFT_FACE_Z * S and y <= SOFT_FACE_Y * S:
        return SOFT_WEIGHT
    if abs(x) >= SOFT_HAND_ABSX * S and SOFT_HAND_Z[0] * S <= z <= SOFT_HAND_Z[1] * S:
        return SOFT_WEIGHT
    if z <= SOFT_FOOT_Z * S:
        return SOFT_WEIGHT
    return 0.0

def tier_census(mesh):
    d = {1.0: 0, SOFT_WEIGHT: 0, 0.0: 0}
    for p in mesh.polygons:
        d[tier_of(p.center)] += 1
    return {"core_protected": d[1.0], "soft_protected": d[SOFT_WEIGHT], "free": d[0.0],
            "total": len(mesh.polygons)}

# ---------------------------------------------------------------- 网格卫生

def mesh_health(mesh):
    bm = bmesh.new(); bm.from_mesh(mesh)
    bm.verts.ensure_lookup_table(); bm.edges.ensure_lookup_table(); bm.faces.ensure_lookup_table()
    out = {
        "verts": len(bm.verts), "edges": len(bm.edges), "faces": len(bm.faces),
        "tris": sum(len(f.verts) - 2 for f in bm.faces),
        "loose_verts": sum(1 for v in bm.verts if not v.link_faces),
        "loose_edges": sum(1 for e in bm.edges if not e.link_faces),
        "non_manifold_edges": sum(1 for e in bm.edges if not e.is_manifold),
        "zero_area_faces": sum(1 for f in bm.faces if f.calc_area() < 1e-12),
        "non_finite_verts": sum(1 for v in bm.verts if not all(math.isfinite(c) for c in v.co)),
    }
    bm.free()
    return out

def uv_stats(mesh):
    if not mesh.uv_layers:
        return {"layers": 0}
    d = mesh.uv_layers.active.data
    us = [x.uv[0] for x in d]; vs = [x.uv[1] for x in d]
    return {"layers": len(mesh.uv_layers), "names": [l.name for l in mesh.uv_layers],
            "u_min": min(us), "u_max": max(us), "v_min": min(vs), "v_max": max(vs),
            "outside_0_1": sum(1 for x in d if not (0.0 <= x.uv[0] <= 1.0 and 0.0 <= x.uv[1] <= 1.0))}

def orientation_evidence(mesh, label, matrix_world=None, height=None):
    mw = matrix_world or Matrix.Identity(4)
    pts = [mw @ v.co for v in mesh.vertices]
    if height is None:
        height = max(p.z for p in pts) - min(p.z for p in pts)
    k = height / 1.1470
    head = [p for p in pts if p.z >= 0.955 * k and abs(p.x) < 0.025 * k]
    toe = [p for p in pts if p.z <= 0.02 * k]
    torso = [p for p in pts if 0.60 * k <= p.z <= 0.90 * k]
    ev = {"label": label, "height_m": round(height, 6),
          "head_centerline_y_min": round(min(p.y for p in head), 5) if head else None,
          "head_centerline_y_max": round(max(p.y for p in head), 5) if head else None,
          "toe_y_min": round(min(p.y for p in toe), 5) if toe else None,
          "toe_y_max": round(max(p.y for p in toe), 5) if toe else None,
          "torso_verts_front_negY": sum(1 for p in torso if p.y < -0.09 * k),
          "torso_verts_back_posY": sum(1 for p in torso if p.y > 0.09 * k)}
    if head:
        mid = 0.5 * (ev["head_centerline_y_min"] + ev["head_centerline_y_max"])
        ev["face_at_negative_y"] = bool(ev["head_centerline_y_min"] < mid and ev["head_centerline_y_min"] < 0)
    else:
        ev["face_at_negative_y"] = False
    ev["toes_at_negative_y"] = bool(toe and min(p.y for p in toe) < 0 < max(p.y for p in toe))
    ev["hair_mass_at_positive_y"] = ev["torso_verts_back_posY"] > ev["torso_verts_front_negY"]
    return ev

# ---------------------------------------------------------------- 减面（自动标定 ratio）

def apply_decimate(ob, ratio):
    """按保护分级减面；返回新的 mesh（调用方负责替换）。"""
    mesh = ob.data
    vg = ob.vertex_groups.new(name="__keep")
    for v in mesh.vertices:
        t = tier_of(v.co)
        if t > 0.0:
            vg.add([v.index], t, "REPLACE")
    ob.vertex_groups.active_index = vg.index
    mod = ob.modifiers.new("Decimate", "DECIMATE")
    mod.decimate_type = "COLLAPSE"
    mod.ratio = ratio
    mod.vertex_group = vg.name
    mod.vertex_group_factor = 1.0
    mod.invert_vertex_group = True
    mod.use_collapse_triangulate = True
    dg = bpy.context.evaluated_depsgraph_get()
    new_mesh = bpy.data.meshes.new_from_object(ob.evaluated_get(dg))
    new_mesh.name = "cultivator_tripo_v9_lowpoly_mesh"
    mats = [m for m in mesh.materials]
    new_mesh.materials.clear()
    for m in mats:
        new_mesh.materials.append(m)
    ob.modifiers.clear()
    ob.vertex_groups.clear()
    old_mesh = mesh
    ob.data = new_mesh            # 必须先换上新 mesh，再释放旧的（否则 Object 引用失效）
    bpy.data.meshes.remove(old_mesh)
    return new_mesh

def calibrate_ratio(ob, target, tol=4000, lo=0.05, hi=1.0, max_iter=12):
    """二分 ratio，使最终三角面落到 target 附近。

    每次迭代都在**重新打开 clean.blend** 的副本上做，避免累减面。
    """
    print("  二分标定 ratio（目标 %d tri）：" % target, flush=True)
    best = None
    for i in range(max_iter):
        mid = 0.5 * (lo + hi)
        bpy.ops.wm.open_mainfile(filepath=CLEAN_BLEND)
        o = [x for x in bpy.data.objects if x.type == "MESH"][0]
        bpy.ops.object.select_all(action="DESELECT")
        o.select_set(True)
        bpy.context.view_layer.objects.active = o
        m = apply_decimate(o, mid)
        n = len(m.polygons)
        print("    iter %2d ratio=%.4f -> %7d tri (diff %+7d)" % (i, mid, n, n - target), flush=True)
        if best is None or abs(n - target) < abs(best[2] - target):
            best = (mid, o, n)
        if abs(n - target) <= tol:
            return mid, n
        if n > target:
            hi = mid          # 面太多 -> 需要更强的减面 -> ratio 更小
        else:
            lo = mid
    print("    未在 %d 次内收敛，采用最接近的 ratio=%.4f (%d tri)" % (max_iter, best[0], best[2]), flush=True)
    return best[0], best[2]

def region_census(mesh, height):
    k = height / 1.1470
    d = {"face": 0, "hands": 0, "feet": 0, "hair_soft": 0, "free": 0}
    for p in mesh.polygons:
        c = p.center
        if c.z >= CORE_FACE_Z * k and c.y <= CORE_FACE_Y * k:
            d["face"] += 1
        elif abs(c.x) >= CORE_HAND_ABSX * k and 0.45 * k <= c.z <= 0.80 * k:
            d["hands"] += 1
        elif c.z <= CORE_FOOT_Z * k:
            d["feet"] += 1
        elif c.z >= SOFT_FACE_Z * k and c.y <= SOFT_FACE_Y * k:
            d["hair_soft"] += 1
        else:
            d["free"] += 1
    return d

def silhouette_deviation(reference_mesh, mesh):
    kd = kdtree.KDTree(len(mesh.vertices))
    for i, v in enumerate(mesh.vertices):
        kd.insert(v.co, i)
    kd.balance()
    ds = sorted(kd.find(v.co)[2] for v in reference_mesh.vertices)
    n = len(ds)
    return {"p50_mm": round(ds[int(n * .50)] * 1000, 4), "p95_mm": round(ds[int(n * .95)] * 1000, 4),
            "p99_mm": round(ds[int(n * .99)] * 1000, 4), "max_mm": round(ds[-1] * 1000, 4)}

# ---------------------------------------------------------------- 渲染

def make_rig():
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE"
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGB"
    sc.view_settings.view_transform = "Standard"
    try:
        sc.eevee.taa_render_samples = 24
    except Exception:
        pass
    w = bpy.data.worlds.new("v9lp_world"); w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[0].default_value = (0.28, 0.30, 0.34, 1.0)
    sc.world = w
    sun = bpy.data.objects.new("v9lp_sun", bpy.data.lights.new("v9lp_sun", "SUN"))
    sun.data.energy = 4.0
    sun.rotation_euler = (math.radians(58), 0.0, math.radians(28))
    sc.collection.objects.link(sun)
    fill = bpy.data.objects.new("v9lp_fill", bpy.data.lights.new("v9lp_fill", "SUN"))
    fill.data.energy = 1.4
    fill.rotation_euler = (math.radians(72), 0.0, math.radians(-135))
    sc.collection.objects.link(fill)
    cam = bpy.data.objects.new("v9lp_cam", bpy.data.cameras.new("v9lp_cam"))
    sc.collection.objects.link(cam)
    sc.camera = cam
    return sc, cam

def shot(sc, cam, path, loc, target, ortho, res=(560, 760)):
    sc.render.resolution_x, sc.render.resolution_y = res
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = ortho
    cam.location = loc
    cam.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)
    return os.path.getsize(path) if os.path.exists(path) else 0

def compose(paths, out, gap=12):
    import numpy as np
    arrs = []
    for p in paths:
        im = bpy.data.images.load(p)
        im.colorspace_settings.name = "Non-Color"
        w, h = im.size
        arrs.append(np.array(im.pixels[:], dtype=np.float32).reshape(h, w, 4))
        bpy.data.images.remove(im)
    H = max(a.shape[0] for a in arrs)
    W = sum(a.shape[1] for a in arrs) + gap * (len(arrs) - 1)
    canvas = np.tile(np.array([0.28, 0.30, 0.34, 1.0], dtype=np.float32), (H, W, 1)).astype(np.float32)
    x = 0
    for a in arrs:
        y0 = (H - a.shape[0]) // 2
        canvas[y0:y0 + a.shape[0], x:x + a.shape[1]] = a
        x += a.shape[1] + gap
    img = bpy.data.images.new("v9lp_compose", W, H, alpha=True)
    img.colorspace_settings.name = "Non-Color"
    img.pixels = canvas.reshape(-1).tolist()
    img.filepath_raw = out
    img.file_format = "PNG"
    img.save()
    bpy.data.images.remove(img)
    return W, H

# ---------------------------------------------------------------- build

def phase_build():
    t0 = time.time()
    man = {"asset": "cultivator_tripo_v9", "phase": "phase2_lowpoly_build",
           "derived_from": os.path.relpath(CLEAN_BLEND, ROOT),
           "reason": "标准上传件（599,417 tri / 22.1 MB FBX）在 Mixamo Auto-Rigger 长时间停在 "
                     "'Processing upload'，未进入 marker 页；改为派生的低面上传候选。",
           "blender": bpy.app.version_string, "started": time.strftime("%Y-%m-%dT%H:%M:%S"),
           "target_tris": TARGET_TRIS}
    log("=" * 70); log("v9 Phase 2 低面候选 build"); log("=" * 70)

    # 只读打开源 blend，核对基线
    bpy.ops.wm.open_mainfile(filepath=CLEAN_BLEND)
    src = [o for o in bpy.data.objects if o.type == "MESH"][0]
    man["source"] = {"blend": os.path.relpath(CLEAN_BLEND, ROOT), "sha256": sha256(CLEAN_BLEND),
                     "tris": tri_count(src.data), "verts": len(src.data.vertices),
                     "uv": [l.name for l in src.data.uv_layers],
                     "materials": [m.name for m in src.data.materials],
                     "textures": [i.name for i in bpy.data.images if i.source == "FILE"]}
    man["source_tier_census"] = tier_census(src.data)
    log("[1] 源 clean.blend: %d tri, UV=%s, 分级 %s" % (
        man["source"]["tris"], man["source"]["uv"], man["source_tier_census"]))

    man["calibration"] = {"target": TARGET_TRIS, "tol": 4000}
    ratio, got = calibrate_ratio(src, TARGET_TRIS)
    man["calibration"]["ratio"] = round(ratio, 6)
    man["calibration"]["achieved_tris"] = got
    log("[2] 标定 ratio=%.4f -> %d tri" % (ratio, got))

    # 用标定 ratio 重建最终结果
    bpy.ops.wm.open_mainfile(filepath=CLEAN_BLEND)
    ob = [o for o in bpy.data.objects if o.type == "MESH"][0]
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True); bpy.context.view_layer.objects.active = ob
    reference = bpy.data.meshes.new_from_object(ob)
    man["pre_tier_census"] = tier_census(ob.data)
    mesh = apply_decimate(ob, ratio)

    # 网格卫生：清孤立点/退化面/保守焊接/统一外法线
    before = mesh_health(mesh)
    bm = bmesh.new(); bm.from_mesh(mesh)
    loose_v = [v for v in bm.verts if not v.link_faces]
    loose_e = [e for e in bm.edges if not e.link_faces]
    for e in loose_e:
        bm.edges.remove(e)
    for v in loose_v:
        if v.is_valid:
            bm.verts.remove(v)
    degen = [f for f in bm.faces if f.calc_area() < 1e-12]
    bmesh.ops.delete(bm, geom=degen, context="FACES")
    v0 = len(bm.verts)
    bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=1e-5)
    bm.verts.ensure_lookup_table()
    merged = v0 - len(bm.verts)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(mesh); bm.free(); mesh.update()
    after = mesh_health(mesh)
    man["hygiene"] = {"before": before, "after": after,
                      "removed_loose_verts": len(loose_v), "removed_loose_edges": len(loose_e),
                      "removed_degenerate_faces": len(degen), "merged_verts": merged,
                      "merge_distance_m": 1e-5}
    log("[3] 卫生: %d -> %d tri, 孤立点 %d, 焊接 %d, 非流形 %d" % (
        before["tris"], after["tris"], len(loose_v), merged, after["non_manifold_edges"]))

    # 高度/落地精确归位：减面会轻微移动顶点，导致身高偏离 1.75 m（实测差 0.13 mm）。
    # 不用放宽断言掩盖，而是把 Z 轴线性映射回 [0, 1.75]，并逐轴只缩放 Z（保持比例不受影响）。
    zmin0 = min(v.co.z for v in mesh.vertices); zmax0 = max(v.co.z for v in mesh.vertices)
    kz = TARGET_HEIGHT / (zmax0 - zmin0)
    for v in mesh.vertices:
        v.co.z = (v.co.z - zmin0) * kz
    mesh.update()
    zmin1 = min(v.co.z for v in mesh.vertices); zmax1 = max(v.co.z for v in mesh.vertices)
    man["height_snap"] = {"z_scale": round(kz, 9), "before_height_m": round(zmax0 - zmin0, 6),
                          "after_height_m": round(zmax1 - zmin1, 6),
                          "reason": "减面后身高 1.749870 m，线性归位到 1.750000 m（仅缩放 Z）"}

    man["result"] = {"tris": after["tris"], "verts": after["verts"],
                     "reduction_vs_clean_percent": round(100 * (1 - after["tris"] / man["source"]["tris"]), 4),
                     "uv": uv_stats(mesh), "materials": [m.name for m in mesh.materials]}
    man["region_census"] = region_census(mesh, TARGET_HEIGHT)
    man["silhouette_deviation"] = silhouette_deviation(reference, mesh)
    bpy.data.meshes.remove(reference)
    zmin = min(v.co.z for v in mesh.vertices); zmax = max(v.co.z for v in mesh.vertices)
    man["dimensions"] = {"height_m": round(zmax - zmin, 6), "foot_z": round(zmin, 9)}
    man["orientation"] = orientation_evidence(mesh, "lowpoly", matrix_world=ob.matrix_world)
    log("[4] 结果: %d tri (较 clean -%.1f%%), %.4f m, foot_z=%.9f, 偏差 p95=%.2fmm" % (
        after["tris"], man["result"]["reduction_vs_clean_percent"], man["dimensions"]["height_m"],
        man["dimensions"]["foot_z"], man["silhouette_deviation"]["p95_mm"]))

    # 渲染：前后对比 + 头/手/衣摆证据
    sc, cam = make_rig()
    c = (0.0, 0.0, 0.875); SZ = 2.0
    man["renders"] = {}
    def R(name, loc, tgt, ortho, res=(560, 760)):
        p = os.path.join(RENDER_DIR, name)
        man["renders"][name] = {"bytes": shot(sc, cam, p, loc, tgt, ortho, res),
                                "sha256": sha256(p)}
    # 低面三视图
    R("lowpoly_front.png", (0, -2.4, 0.875), c, SZ)
    R("lowpoly_side.png", (-2.4, 0, 0.875), c, SZ)
    R("lowpoly_back.png", (0, 2.4, 0.875), c, SZ)
    # 局部证据
    R("lowpoly_head_closeup.png", (0, -0.85, 1.585), (0, 0, 1.585), 0.42, (640, 640))
    R("lowpoly_hand_closeup.png", (0.44, -0.55, 0.80), (0.44, 0, 0.79), 0.24, (520, 520))
    R("lowpoly_hem_closeup.png", (-0.55, -0.75, 0.72), (0, 0, 0.70), 0.62, (620, 620))
    # 前后同框对比（左 clean / 右 lowpoly）——clean 图沿用 Phase 1 已有渲染
    for view, f in (("front", "clean_front.png"), ("side", "clean_side.png")):
        pass
    w, h = compose([os.path.join(RENDER_DIR, "clean_front.png"),
                    os.path.join(RENDER_DIR, "lowpoly_front.png")],
                   os.path.join(RENDER_DIR, "lowpoly_comparison_front.png"), 14)
    man["renders"]["lowpoly_comparison_front.png"] = {
        "bytes": os.path.getsize(os.path.join(RENDER_DIR, "lowpoly_comparison_front.png")), "size": [w, h],
        "panels": ["clean_front.png", "lowpoly_front.png"], "note": "左：clean 599,417 tri ｜ 右：低面候选"}
    w, h = compose([os.path.join(RENDER_DIR, "clean_head_closeup.png"),
                    os.path.join(RENDER_DIR, "lowpoly_head_closeup.png")],
                   os.path.join(RENDER_DIR, "lowpoly_comparison_head.png"), 14)
    man["renders"]["lowpoly_comparison_head.png"] = {
        "bytes": os.path.getsize(os.path.join(RENDER_DIR, "lowpoly_comparison_head.png")), "size": [w, h],
        "panels": ["clean_head_closeup.png", "lowpoly_head_closeup.png"]}
    log("[5] 渲染 %d 张" % len(man["renders"]))

    # 导出 FBX（标准 Mixamo 约定：Z-up / 面朝 -Y），纹理相对路径
    for o in list(bpy.data.objects):
        if o is not ob:
            bpy.data.objects.remove(o, do_unlink=True)
    for img in list(bpy.data.images):
        if img.name == "Render Result" or img.source != "FILE" or img.users == 0:
            try:
                bpy.data.images.remove(img, do_unlink=True)
            except Exception:
                pass
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True); bpy.context.view_layer.objects.active = ob
    bpy.ops.export_scene.fbx(filepath=LOWPOLY_FBX, use_selection=True, object_types={"MESH"},
                             apply_unit_scale=True, global_scale=1.0, axis_forward="-Y", axis_up="Z",
                             add_leaf_bones=False, use_mesh_modifiers=True, mesh_smooth_type="FACE",
                             path_mode="RELATIVE", embed_textures=False, use_tspace=False)
    man["exports"] = {"fbx": {"path": os.path.relpath(LOWPOLY_FBX, ROOT),
                              "bytes": os.path.getsize(LOWPOLY_FBX), "sha256": sha256(LOWPOLY_FBX)}}
    log("[6] FBX %.2f MB" % (os.path.getsize(LOWPOLY_FBX) / 1e6))

    bpy.ops.wm.save_as_mainfile(filepath=LOWPOLY_BLEND, compress=True)
    man["blend"] = {"path": os.path.relpath(LOWPOLY_BLEND, ROOT),
                    "bytes": os.path.getsize(LOWPOLY_BLEND), "sha256": sha256(LOWPOLY_BLEND)}
    man["finished"] = time.strftime("%Y-%m-%dT%H:%M:%S")
    man["elapsed_sec"] = round(time.time() - t0, 1)
    man["log"] = LOG
    with open(MANIFEST, "w") as fh:
        json.dump(man, fh, indent=2, ensure_ascii=False)
    log("[7] lowpoly_manifest.json 写入完成，用时 %.1fs" % man["elapsed_sec"])
    return man

# ---------------------------------------------------------------- audit

def parse_glb(path):
    with open(path, "rb") as fh:
        d = fh.read()
    jlen = struct.unpack_from("<I", d, 12)[0]
    return json.loads(d[20:20 + jlen].decode("utf-8")), len(d)

def phase_audit():
    rep = {"asset": "cultivator_tripo_v9", "phase": "phase2_lowpoly_audit",
           "blender": bpy.app.version_string, "started": time.strftime("%Y-%m-%dT%H:%M:%S")}
    checks = []
    def check(name, ok, detail="", optional=False):
        checks.append({"check": name, "ok": bool(ok), "detail": detail, "optional": optional})
        log("  [%s] %s %s" % ("PASS" if ok else "FAIL", name, detail))
    log("=" * 70); log("v9 Phase 2 低面候选 独立审计"); log("=" * 70)

    # --- 复核 clean.blend / clean.glb / 标准上传件未被覆盖
    with open(os.path.join(ASSET, "cleanup_manifest.json")) as fh:
        p1 = json.load(fh)
    rep["phase1_intact"] = {
        "clean_blend_sha256": sha256(CLEAN_BLEND),
        "clean_blend_expected": p1["clean_blend"]["sha256"],
        "clean_blend_unchanged": sha256(CLEAN_BLEND) == p1["clean_blend"]["sha256"],
        "clean_glb_sha256": sha256(os.path.join(EXPORT_DIR, "cultivator_tripo_v9_clean.glb")),
        "clean_glb_expected": p1["exports"]["cultivator_tripo_v9_clean.glb"]["sha256"],
        "standard_fbx_sha256": sha256(os.path.join(EXPORT_DIR, "cultivator_tripo_v9_mixamo_upload.fbx")),
        "standard_fbx_expected": p1["exports"]["cultivator_tripo_v9_mixamo_upload.fbx"]["sha256"],
    }
    p = rep["phase1_intact"]
    p["clean_glb_unchanged"] = p["clean_glb_sha256"] == p["clean_glb_expected"]
    p["standard_fbx_unchanged"] = p["standard_fbx_sha256"] == p["standard_fbx_expected"]
    check("Phase 1 clean.blend 未被覆盖", p["clean_blend_unchanged"], p["clean_blend_sha256"][:16])
    check("Phase 1 clean.glb 未被覆盖", p["clean_glb_unchanged"], p["clean_glb_sha256"][:16])
    check("Phase 1 标准上传 FBX 未被覆盖", p["standard_fbx_unchanged"], p["standard_fbx_sha256"][:16])

    # --- 低面 blend 重开
    bpy.ops.wm.open_mainfile(filepath=LOWPOLY_BLEND)
    objs = list(bpy.data.objects)
    ms = [o for o in objs if o.type == "MESH"]
    rep["lowpoly_blend"] = {
        "path": os.path.relpath(LOWPOLY_BLEND, ROOT), "bytes": os.path.getsize(LOWPOLY_BLEND),
        "sha256": sha256(LOWPOLY_BLEND),
        "object_count": len(objs), "mesh_count": len(ms),
        "armatures": sum(1 for o in objs if o.type == "ARMATURE"),
        "cameras": sum(1 for o in objs if o.type == "CAMERA"),
        "lights": sum(1 for o in objs if o.type == "LIGHT"),
        "actions": len(bpy.data.actions),
        "health": mesh_health(ms[0].data) if ms else None,
        "uv": uv_stats(ms[0].data) if ms else None,
        "materials": [m.name for m in ms[0].data.materials] if ms else [],
        "textures": [{"name": i.name, "filepath": i.filepath, "packed": bool(i.packed_file),
                      "resolved": os.path.exists(bpy.path.abspath(i.filepath)), "size": list(i.size[:])}
                     for i in bpy.data.images if i.source == "FILE"],
    }
    lb = rep["lowpoly_blend"]
    if ms:
        mw = ms[0].matrix_world
        pts = [mw @ v.co for v in ms[0].data.vertices]
        mn = Vector((min(q.x for q in pts), min(q.y for q in pts), min(q.z for q in pts)))
        mx = Vector((max(q.x for q in pts), max(q.y for q in pts), max(q.z for q in pts)))
        lb["height_m"] = round(mx.z - mn.z, 6); lb["foot_z"] = round(mn.z, 9)
        lb["orientation"] = orientation_evidence(ms[0].data, "lowpoly_blend",
                                                 matrix_world=mw, height=mx.z - mn.z)
    check("低面 blend 恰好 1 网格", len(ms) == 1 and len(objs) == 1, "mesh=%d objs=%d" % (len(ms), len(objs)))
    check("低面 blend 0 armature/action/camera/light",
          lb["armatures"] == 0 and lb["actions"] == 0 and lb["cameras"] == 0 and lb["lights"] == 0)
    check("低面 blend UV 存在且未越界",
          bool(lb["uv"] and lb["uv"]["layers"] and lb["uv"]["outside_0_1"] == 0), json.dumps(lb["uv"]))
    check("低面 blend 纹理相对路径可解析",
          len(lb["textures"]) >= 1 and all(t["resolved"] for t in lb["textures"]),
          json.dumps([(t["filepath"], t["resolved"]) for t in lb["textures"]]))
    check("低面 blend 身高≈1.75m 且足底 z≈0",
          abs(lb["height_m"] - 1.75) < 1e-4 and abs(lb["foot_z"]) < 1e-6,
          "h=%.6f foot_z=%.9f" % (lb["height_m"], lb["foot_z"]))
    check("低面 blend 面朝 -Y",
          lb["orientation"]["face_at_negative_y"] and lb["orientation"]["toes_at_negative_y"],
          "nose_y=%s toes_y=[%s,%s]" % (lb["orientation"]["head_centerline_y_min"],
                                        lb["orientation"]["toe_y_min"], lb["orientation"]["toe_y_max"]))

    # --- FBX 重开
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=LOWPOLY_FBX)
    f_objs = list(bpy.data.objects)
    f_ms = [o for o in f_objs if o.type == "MESH"]
    rep["lowpoly_fbx"] = {"path": os.path.relpath(LOWPOLY_FBX, ROOT),
                          "bytes": os.path.getsize(LOWPOLY_FBX), "sha256": sha256(LOWPOLY_FBX),
                          "mesh_count": len(f_ms),
                          "armatures": len(bpy.data.armatures), "actions": len(bpy.data.actions),
                          "cameras": sum(1 for o in f_objs if o.type == "CAMERA"),
                          "lights": sum(1 for o in f_objs if o.type == "LIGHT")}
    if f_ms:
        mw = f_ms[0].matrix_world
        pts = [mw @ v.co for v in f_ms[0].data.vertices]
        zs = [q.z for q in pts]
        rep["lowpoly_fbx"].update({
            "tris": tri_count(f_ms[0].data), "verts": len(f_ms[0].data.vertices),
            "height_m": round(max(zs) - min(zs), 6), "foot_z": round(min(zs), 9),
            "uv": uv_stats(f_ms[0].data),
            "materials": [m.name for m in f_ms[0].data.materials],
            "orientation": orientation_evidence(f_ms[0].data, "lowpoly_fbx",
                                                matrix_world=mw, height=max(zs) - min(zs)),
        })
    f = rep["lowpoly_fbx"]
    check("低面 FBX 恰好 1 网格 / 0 armature / 0 action / 0 camera / 0 light",
          f["mesh_count"] == 1 and f["armatures"] == 0 and f["actions"] == 0
          and f["cameras"] == 0 and f["lights"] == 0,
          "mesh=%d arm=%d act=%d cam=%d light=%d" % (f["mesh_count"], f["armatures"], f["actions"],
                                                     f["cameras"], f["lights"]))
    check("低面 FBX 有 UV", bool(f.get("uv", {}).get("layers")), json.dumps(f.get("uv")))
    check("低面 FBX 身高≈1.75m / 足底≈0 / 面朝 -Y",
          abs(f.get("height_m", 0) - 1.75) < 1e-3 and abs(f.get("foot_z", 9)) < 1e-4
          and f["orientation"]["face_at_negative_y"],
          "h=%.4f foot_z=%.6f nose_y=%s" % (f.get("height_m", -1), f.get("foot_z", -1),
                                            f["orientation"]["head_centerline_y_min"]))

    with open(MANIFEST) as fh:
        man = json.load(fh)
    rep["manifest_reference"] = {"path": os.path.relpath(MANIFEST, ROOT), "sha256": sha256(MANIFEST)}
    rep["tris"] = {"clean": man["source"]["tris"], "lowpoly": man["result"]["tris"],
                   "reduction_percent": man["result"]["reduction_vs_clean_percent"],
                   "in_target_band": 180000 <= man["result"]["tris"] <= 250000}
    check("低面三角面落在 180k–250k 目标区间", rep["tris"]["in_target_band"],
          "%d tri" % rep["tris"]["lowpoly"])
    check("低面 FBX < 15 MB", f["bytes"] < 15 * 1024 * 1024, "%.2f MB" % (f["bytes"] / 1e6))
    check("保护分级未锁死全部面（free > 0）", man["pre_tier_census"]["free"] > 0,
          json.dumps(man["pre_tier_census"]))

    rep["checks"] = checks
    rep["checks_passed"] = sum(1 for c in checks if c["ok"])
    rep["checks_total"] = len(checks)
    rep["required_all_passed"] = all(c["ok"] for c in checks if not c["optional"])
    rep["all_passed"] = rep["checks_passed"] == rep["checks_total"]
    rep["finished"] = time.strftime("%Y-%m-%dT%H:%M:%S")
    with open(AUDIT, "w") as fh:
        json.dump(rep, fh, indent=2, ensure_ascii=False)
    log("-" * 70)
    log("审计: %d/%d, required_all_passed=%s" % (rep["checks_passed"], rep["checks_total"],
                                                 rep["required_all_passed"]))
    return rep

def main():
    if PHASE == "build":
        phase_build()
    elif PHASE == "audit":
        phase_audit()
    else:
        raise SystemExit("未知 phase: %s（build / audit）" % PHASE)

if __name__ == "__main__":
    main()
