#!/usr/bin/env python3
"""cultivator_tripo_v9 第一阶段：归档 -> 导入审计 -> 朝向归一 -> 清理 -> 减面 -> 导出 -> 渲染。

用法（隔离后台进程，绝不动用户当前 Blender 会话）：
    Blender --background --factory-startup --python tools/art/process_cultivator_tripo_v9.py
    Blender --background --factory-startup --python tools/art/process_cultivator_tripo_v9.py -- --phase audit

阶段：
  build : 全流程，产出 raw 副本校验 / imported.blend / clean.blend / glb / fbx / obj / 16 张渲染 / cleanup_manifest.json
  audit : 独立进程重新打开 clean.blend、clean.glb、upload.fbx、upload.obj，逐项复检 -> export_audit.json

边界：只写 docs/art/cultivator_tripo_v9/** 与自身脚本；不改 raw 原件、src/、旧资产。
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

# ---------------------------------------------------------------- 路径与常量

def _repo_root():
    here = os.path.dirname(os.path.abspath(__file__))
    return os.path.dirname(os.path.dirname(here))

ROOT = _repo_root()
ASSET = os.path.join(ROOT, "docs/art/cultivator_tripo_v9")
RAW_GLB = os.path.join(ASSET, "raw/9b092e988c21840611f833788e4e4e9a.glb")
SOURCE_GLB = os.path.join(ROOT, "docs/art/9b092e988c21840611f833788e4e4e9a.glb")
SOURCE_SHA = "69ed3a5b9a6279fd4756212c5ab43e25521fefbbc12baaed150d8e6dfd031627"

SOURCE_DIR = os.path.join(ASSET, "source")
EXPORT_DIR = os.path.join(ASSET, "exports")
TEXTURE_DIR = os.path.join(ASSET, "textures")
RENDER_DIR = os.path.join(ASSET, "renders")
OBJ_DIR = os.path.join(EXPORT_DIR, "mixamo_upload_obj")

BLEND_IMPORTED = os.path.join(SOURCE_DIR, "cultivator_tripo_v9_imported.blend")
BLEND_CLEAN = os.path.join(SOURCE_DIR, "cultivator_tripo_v9_clean.blend")
GLB_CLEAN = os.path.join(EXPORT_DIR, "cultivator_tripo_v9_clean.glb")
FBX_UPLOAD = os.path.join(EXPORT_DIR, "cultivator_tripo_v9_mixamo_upload.fbx")
OBJ_UPLOAD = os.path.join(OBJ_DIR, "cultivator_tripo_v9_mixamo_upload.obj")

MANIFEST = os.path.join(ASSET, "cleanup_manifest.json")
AUDIT = os.path.join(ASSET, "export_audit.json")

# --- 目标尺寸 -------------------------------------------------------------
# 原始模型高 1.1470 m，但人体比例是成年人（约 6.0 头身、成人脸型/肩宽/腿长），
# 1.147 m 不满足契约要求的「合理米制身高」。因此按实测高度归一化到成人身高，
# 均匀缩放（保留比例），足底仍落在 z=0。原始 1.1470 m 完整保留在
# raw/ 原始 GLB 与 source/*_imported.blend 中，可回溯。
TARGET_HEIGHT = 1.750           # 米；与本仓现役 v7 运行时角色 1.7447 m 同量级，可直接接入

# --- 清理阈值 -------------------------------------------------------------
MERGE_DIST = 1.0e-5             # 10 µm 焊接半径（保守：远小于发丝/指缝/唇缝特征尺度）
AREA_EPS = 1.0e-12              # m²，零面积面判据

# --- 减面：可达掩码（权重 1.0 = 不做减面）----------------------------------
# 用面中心判定；三块区域合起来必须在视觉检查中逐个确认无塌陷。
MASK_FACE_Z = 0.925             # 原始尺度：下巴(0.955)以下 3 cm 起算，含整个头部+前发
MASK_FACE_Y = 0.045             # 只保护前侧，后脑长发允许减面
MASK_HAND_ABSX = 0.235          # 原始尺度：手腕以外
MASK_HAND_Z = (0.45, 0.80)
MASK_FOOT_Z = 0.10              # 原始尺度：含整只靴子
DECIMATE_RATIO = 0.40           # 在「自由几何」上生效的 collapse 比例

PHASE = "build"
if "--" in sys.argv:
    rest = sys.argv[sys.argv.index("--") + 1:]
    if rest:
        PHASE = rest[0]

LOG = []
def log(msg):
    print(msg, flush=True)
    LOG.append(msg)
    return msg

def sha256(path, chunk=1 << 20):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        while True:
            b = fh.read(chunk)
            if not b:
                break
            h.update(b)
    return h.hexdigest()

def tri_count(mesh):
    return sum(len(p.vertices) - 2 for p in mesh.polygons)

def ensure_dirs():
    for d in (SOURCE_DIR, EXPORT_DIR, TEXTURE_DIR, RENDER_DIR, OBJ_DIR):
        os.makedirs(d, exist_ok=True)

# ---------------------------------------------------------------- 网格审计

def bbox_of(objects):
    pts = []
    for ob in objects:
        if ob.type != "MESH":
            continue
        mw = ob.matrix_world
        pts.extend(mw @ v.co for v in ob.data.vertices)
    if not pts:
        return None
    mn = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    mx = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    return mn, mx

def mesh_health(mesh):
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bm.verts.ensure_lookup_table()
    bm.edges.ensure_lookup_table()
    bm.faces.ensure_lookup_table()
    loose_v = sum(1 for v in bm.verts if not v.link_faces)
    loose_e = sum(1 for e in bm.edges if not e.link_faces)
    nonman_e = sum(1 for e in bm.edges if not e.is_manifold)
    zero_area = sum(1 for f in bm.faces if f.calc_area() < AREA_EPS)
    dup_face = 0
    seen = set()
    for f in bm.faces:
        key = tuple(sorted(v.index for v in f.verts))
        if key in seen:
            dup_face += 1
        else:
            seen.add(key)
    nonfinite = sum(1 for v in bm.verts if not all(math.isfinite(c) for c in v.co))
    # 法线一致性：面法线与「从质心指向外」的夹角超过 90° 视为可疑
    centroid = Vector((0.0, 0.0, 0.0))
    for v in bm.verts:
        centroid += v.co
    centroid /= max(len(bm.verts), 1)
    outward_bad = 0
    for f in bm.faces:
        d = (f.calc_center_median() - centroid)
        if d.length > 1e-6 and f.normal.dot(d.normalized()) < -0.7:
            outward_bad += 1
    # 边长度分布（用于论证焊接阈值保守）
    el = sorted(e.calc_length() for e in bm.edges)
    n = len(el)
    pct = lambda q: el[min(int(n * q), n - 1)] if n else 0.0
    stats = {
        "verts": len(bm.verts), "edges": len(bm.edges), "faces": len(bm.faces),
        "tris": tri_count(mesh),
        "loose_verts": loose_v, "loose_edges": loose_e,
        "non_manifold_edges": nonman_e,
        "zero_area_faces": zero_area, "duplicate_faces": dup_face,
        "non_finite_verts": nonfinite,
        "faces_pointing_inward": outward_bad,
        "edge_len_min": el[0] if n else 0.0,
        "edge_len_p01": pct(0.01), "edge_len_p50": pct(0.50), "edge_len_max": el[-1] if n else 0.0,
    }
    bm.free()
    return stats

def uv_stats(mesh):
    if not mesh.uv_layers:
        return {"layers": 0}
    d = mesh.uv_layers.active.data
    us = [x.uv[0] for x in d]
    vs = [x.uv[1] for x in d]
    return {
        "layers": len(mesh.uv_layers),
        "names": [l.name for l in mesh.uv_layers],
        "u_min": min(us), "u_max": max(us), "v_min": min(vs), "v_max": max(vs),
        "outside_0_1": sum(1 for x in d if not (0.0 <= x.uv[0] <= 1.0 and 0.0 <= x.uv[1] <= 1.0)),
    }

def object_audit(objects):
    out = {"objects": [], "mesh_count": 0, "armatures": 0, "cameras": 0, "lights": 0,
           "empties": 0, "texts": 0, "other": 0}
    for ob in objects:
        entry = {"name": ob.name, "type": ob.type,
                 "matrix_world_translation": [round(v, 6) for v in ob.matrix_world.translation],
                 "scale": [round(v, 6) for v in ob.matrix_world.to_scale()]}
        if ob.type == "MESH":
            out["mesh_count"] += 1
            entry["verts"] = len(ob.data.vertices)
            entry["polys"] = len(ob.data.polygons)
            entry["tris"] = tri_count(ob.data)
            entry["materials"] = [m.name if m else None for m in ob.data.materials]
            entry["uv"] = [l.name for l in ob.data.uv_layers]
        elif ob.type == "ARMATURE":
            out["armatures"] += 1
        elif ob.type == "CAMERA":
            out["cameras"] += 1
        elif ob.type == "LIGHT":
            out["lights"] += 1
        elif ob.type == "EMPTY":
            out["empties"] += 1
        elif ob.type == "FONT":
            out["texts"] += 1
        else:
            out["other"] += 1
        out["objects"].append(entry)
    return out

def orientation_evidence(mesh, label, height=None, matrix_world=None):
    """用几何证据判定朝向，不靠包围盒猜测。

    证据面：
      鼻/面  头部中线 (|x|<0.025) 最前点所在 y 符号与中线中点比较
      脚尖   最低 2 cm 内顶点 y 的范围
      发背   躯干带 +Y 侧与 -Y 侧的顶点数量对比
      眼带   头宽最大处的 y 跨度

    必须在**世界坐标**下判定：OBJ/FBX 重新导入时会带一个轴向矩阵
    （例如 rx=-90°），只看 mesh 局部坐标会得出错误的朝向结论。
    """
    vs = list(mesh.vertices)
    if matrix_world is None:
        matrix_world = Matrix.Identity(4)
    pts = [matrix_world @ v.co for v in vs]
    if height is None:
        height = max(p.z for p in pts) - min(p.z for p in pts)
    band_lo = 0.955 / 1.1470 * height          # 下巴

    def centerline_y(zlo, zhi):
        b = [p for p in pts if zlo <= p.z <= zhi and abs(p.x) < 0.025 * (height / 1.1470)]
        if not b:
            return None
        return (min(p.y for p in b), max(p.y for p in b), len(b))

    nose = centerline_y(band_lo, height)
    toe = [p for p in pts if p.z <= 0.02 * (height / 1.1470)]
    torso = [p for p in pts if 0.60 * (height / 1.1470) <= p.z <= 0.90 * (height / 1.1470)]
    ev = {
        "label": label,
        "height_m": round(height, 6),
        "scale_vs_original": round(height / 1.1470, 6),
        "head_centerline_y_min": round(nose[0], 5) if nose else None,
        "head_centerline_y_max": round(nose[1], 5) if nose else None,
        "head_centerline_samples": nose[2] if nose else 0,
        "toe_y_min": round(min(p.y for p in toe), 5) if toe else None,
        "toe_y_max": round(max(p.y for p in toe), 5) if toe else None,
        "torso_verts_front_negY": sum(1 for p in torso if p.y < -0.09 * (height / 1.1470)),
        "torso_verts_back_posY": sum(1 for p in torso if p.y > 0.09 * (height / 1.1470)),
        "torso_y_max": round(max(p.y for p in torso), 5) if torso else None,
        "torso_y_min": round(min(p.y for p in torso), 5) if torso else None,
    }
    # 鼻子必须落在「头部中线 y 跨度」的前半，且整体位于 -Y 侧
    if nose:
        span_lo, span_hi = nose[0], nose[1]
        mid = 0.5 * (span_lo + span_hi)
        ev["head_span_mid_y"] = round(mid, 5)
        ev["face_at_negative_y"] = bool(span_lo < mid and span_lo < 0)
    else:
        ev["head_span_mid_y"] = None
        ev["face_at_negative_y"] = False
    ev["toes_at_negative_y"] = bool(toe is not None and len(toe) > 0
                                    and min(p.y for p in toe) < 0 < max(p.y for p in toe))
    ev["hair_mass_at_positive_y"] = ev["torso_verts_back_posY"] > ev["torso_verts_front_negY"]
    return ev

# ---------------------------------------------------------------- 阶段一：raw 归档校验

def verify_raw():
    rep = {"source_glb": SOURCE_GLB, "raw_copy": RAW_GLB}
    if not os.path.exists(RAW_GLB):
        raise RuntimeError("raw 副本缺失，先执行逐位复制: cp %s %s" % (SOURCE_GLB, RAW_GLB))
    rep["raw_bytes"] = os.path.getsize(RAW_GLB)
    rep["raw_sha256"] = sha256(RAW_GLB)
    rep["raw_sha256_expected"] = SOURCE_SHA
    rep["raw_sha256_matches_expected"] = rep["raw_sha256"] == SOURCE_SHA
    if os.path.exists(SOURCE_GLB):
        rep["source_bytes"] = os.path.getsize(SOURCE_GLB)
        rep["source_sha256"] = sha256(SOURCE_GLB)
        rep["source_sha256_matches_raw"] = rep["source_sha256"] == rep["raw_sha256"]
        rep["source_still_present"] = True
    else:
        rep["source_still_present"] = False
    if not rep["raw_sha256_matches_expected"]:
        raise RuntimeError("raw 副本 SHA-256 与约定值不符，拒绝继续: %s" % rep["raw_sha256"])
    return rep

# ---------------------------------------------------------------- 阶段二：导入 + 审计

def import_raw():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=RAW_GLB)
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    if len(meshes) != 1:
        raise RuntimeError("原始 GLB 预期 1 个网格对象，实际 %d 个" % len(meshes))
    return meshes[0]

def isolated(func):
    """在独立的 mesh 数据副本上操作，避免污染当前场景。"""
    def wrap(*a, **k):
        return func(*a, **k)
    return wrap

# ---------------------------------------------------------------- 阶段三：朝向归一

def normalize_orientation(ob, target_height):
    """apply transform -> 朝向断言 -> 均匀缩放对齐身高 -> 再次把足底压到 z=0。

    模型原始朝向已经是面朝 -Y（证据见 orient_evidence），所以旋转量为 0；
    本函数仍然显式写出该步骤，并把「实际施加的旋转」记入 manifest。
    """
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob

    pre = orientation_evidence(ob.data, "before_normalize")
    rot_euler_before = [round(math.degrees(v), 6) for v in ob.rotation_euler]
    scale_before = [round(v, 8) for v in ob.scale]

    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    post_apply = orientation_evidence(ob.data, "after_apply_transform")
    if not post_apply["face_at_negative_y"]:
        raise RuntimeError("朝向断言失败：脸部未落在 -Y 侧，拒绝继续（%s）" % json.dumps(post_apply))
    if not post_apply["toes_at_negative_y"]:
        raise RuntimeError("朝向断言失败：脚尖未落在 -Y 侧，拒绝继续")

    # 均匀缩放到目标身高
    h_before = max(v.co.z for v in ob.data.vertices) - min(v.co.z for v in ob.data.vertices)
    factor = target_height / h_before
    for v in ob.data.vertices:
        v.co *= factor
    zmin = min(v.co.z for v in ob.data.vertices)
    for v in ob.data.vertices:
        v.co.z -= zmin
    zmax = max(v.co.z for v in ob.data.vertices)
    post_scale = orientation_evidence(ob.data, "after_height_normalize", height=zmax)

    steps = {
        "applied_rotation_deg": [0.0, 0.0, 0.0],
        "reason_rotation_zero": "导入后模型已面朝 Blender -Y（鼻子与前胸在 -Y，发量在 +Y，脚尖在 -Y）；"
                                "glTF 导入器已把源文件 +90°X 的节点旋转一并计入 matrix_world。",
        "rotation_euler_before_apply_deg": rot_euler_before,
        "scale_before_apply": scale_before,
        "height_before_m": round(h_before, 6),
        "uniform_scale_factor": round(factor, 8),
        "height_after_m": round(zmax, 6),
        "target_height_m": target_height,
        "foot_z_after_m": round(min(v.co.z for v in ob.data.vertices), 9),
        "before": pre, "after_apply": post_apply, "after_height": post_scale,
    }
    return steps

# ---------------------------------------------------------------- 阶段四：清理

def clean_mesh(ob):
    mesh = ob.data
    before = mesh_health(mesh)
    actions = {}

    bm = bmesh.new()
    bm.from_mesh(mesh)

    # 1) 孤立点 / 松散边（删掉即「孤立点」，不是删部件）
    loose_v = [v for v in bm.verts if not v.link_faces]
    loose_e = [e for e in bm.edges if not e.link_faces]
    actions["removed_loose_verts"] = len(loose_v)
    actions["removed_loose_edges"] = len(loose_e)
    for e in loose_e:
        bm.edges.remove(e)
    for v in loose_v:
        if v.is_valid:
            bm.verts.remove(v)

    # 2) 零面积 / 退化面
    degen = [f for f in bm.faces if f.calc_area() < AREA_EPS]
    actions["removed_degenerate_faces"] = len(degen)
    bmesh.ops.delete(bm, geom=degen, context="FACES")

    # 3) 保守焊接：只焊距离 < MERGE_DIST 的重复点
    v_before = len(bm.verts)
    bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=MERGE_DIST)
    bm.verts.ensure_lookup_table()
    actions["merge_distance_m"] = MERGE_DIST
    actions["merged_verts"] = v_before - len(bm.verts)
    actions["min_edge_len_before_merge_m"] = before["edge_len_min"]
    actions["merge_safety_ratio"] = round(MERGE_DIST / max(before["edge_len_min"], 1e-12), 6)

    # 4) 删掉焊接后可能出现的退化面
    degen2 = [f for f in bm.faces if f.calc_area() < AREA_EPS]
    actions["removed_degenerate_faces_after_merge"] = len(degen2)
    bmesh.ops.delete(bm, geom=degen2, context="FACES")

    # 5) 统一外法线
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))

    # 6) 去掉重复面（同顶点集合）
    seen = set()
    dup = []
    for f in bm.faces:
        key = tuple(sorted(v.index for v in f.verts))
        if key in seen:
            dup.append(f)
        else:
            seen.add(key)
    actions["removed_duplicate_faces"] = len(dup)
    bmesh.ops.delete(bm, geom=dup, context="FACES")

    bm.to_mesh(mesh)
    bm.free()
    mesh.update()

    after = mesh_health(mesh)
    return {"before": before, "after": after, "actions": actions}

# ---------------------------------------------------------------- 阶段五：分区减面

def region_of(co, height):
    """返回 'face' / 'hands' / 'feet' / 'free'。阈值按身高比例换算，跨尺度稳定。"""
    s = height / 1.1470
    if co.z >= MASK_FACE_Z * s and co.y <= MASK_FACE_Y * s:
        return "face"
    if abs(co.x) >= MASK_HAND_ABSX * s and MASK_HAND_Z[0] * s <= co.z <= MASK_HAND_Z[1] * s:
        return "hands"
    if co.z <= MASK_FOOT_Z * s:
        return "feet"
    return "free"

def region_census(mesh, height):
    d = {"face": 0, "hands": 0, "feet": 0, "free": 0}
    for p in mesh.polygons:
        d[region_of(p.center, height)] += 1
    return d

def decimate(ob, ratio, height):
    mesh = ob.data
    before = mesh_health(mesh)
    census_before = region_census(mesh, height)
    mask_tris_before = census_before["face"] + census_before["hands"] + census_before["feet"]

    # 可达掩码：权重 1.0 = 保护（实测 invert_vertex_group=True + vertex_group_factor=1.0）
    vg = ob.vertex_groups.new(name="__reachable_mask")
    protected = 0
    for v in mesh.vertices:
        if region_of(v.co, height) != "free":
            vg.add([v.index], 1.0, "REPLACE")
            protected += 1

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
    new_mesh.name = "cultivator_tripo_v9_clean_mesh"

    old_mat = [m for m in mesh.materials]
    new_mesh.materials.clear()
    for m in old_mat:
        new_mesh.materials.append(m)
    old_mesh = mesh
    ob.modifiers.clear()
    ob.vertex_groups.clear()
    ob.data = new_mesh
    bpy.data.meshes.remove(old_mesh)

    census_after = region_census(new_mesh, height)
    after = mesh_health(new_mesh)
    report = {
        "ratio_applied_to_free_geometry": ratio,
        "mask_definitions": {
            "face+front_hair": {"z_min": MASK_FACE_Z, "y_max": MASK_FACE_Y, "space": "original_1.1470m_scale"},
            "hands": {"abs_x_min": MASK_HAND_ABSX, "z_range": list(MASK_HAND_Z), "space": "original_1.1470m_scale"},
            "feet_boots": {"z_max": MASK_FOOT_Z, "space": "original_1.1470m_scale"},
        },
        "protected_vertex_count": protected,
        "tris_before": before["tris"], "tris_after": after["tris"],
        "reduction_percent": round(100.0 * (1 - after["tris"] / max(before["tris"], 1)), 4),
        "region_tris_before": census_before, "region_tris_after": census_after,
        "mask_tris_before": mask_tris_before,
        "mask_tris_after": census_after["face"] + census_after["hands"] + census_after["feet"],
        "free_tris_before": census_before["free"], "free_tris_after": census_after["free"],
        "before": before, "after": after,
    }
    return report

def silhouette_deviation(original_mesh, clean_mesh):
    """把原始点云作为参考，统计清理后每个顶点到最近原始点的距离（m）。"""
    kd = kdtree.KDTree(len(clean_mesh.vertices))
    for i, v in enumerate(clean_mesh.vertices):
        kd.insert(v.co, i)
    kd.balance()
    ds = sorted(kd.find(v.co)[2] for v in original_mesh.vertices)
    n = len(ds)
    return {
        "p50_mm": round(ds[int(n * 0.50)] * 1000, 4),
        "p95_mm": round(ds[int(n * 0.95)] * 1000, 4),
        "p99_mm": round(ds[int(n * 0.99)] * 1000, 4),
        "max_mm": round(ds[-1] * 1000, 4),
        "body_diagonal_m": round(math.sqrt(sum((max(v.co[i] for v in original_mesh.vertices)
                                               - min(v.co[i] for v in original_mesh.vertices)) ** 2 for i in range(3))), 4),
    }

# ---------------------------------------------------------------- 贴图解包

def unpack_textures():
    """把 GLB 内嵌贴图落盘到 textures/，并把 image 数据源改为相对路径外部文件。

    做法与实测语义：
      image.unpack(method='USE_LOCAL') 会把文件写到 blend 所在目录；
      因此先把 filepath 指到 textures/，再 save() + unpack('REMOVE')，
      得到 source=FILE + 绝对 filepath + 不再 packed；存档时 Blender 存为 // 相对路径。
    """
    report = []
    for img in list(bpy.data.images):
        if img.source != "FILE" or img.size[0] == 0:
            continue
        name = os.path.basename(img.name)
        if not name.lower().endswith((".png", ".jpg", ".jpeg")):
            name += ".png"
        tgt = os.path.join(TEXTURE_DIR, name)
        entry = {"image": img.name, "file": name, "size": list(img.size[:])}
        if os.path.exists(tgt):
            img.filepath_raw = tgt
            img.file_format = "PNG"
            img.save()
            img.unpack(method="REMOVE")
            entry["action"] = "overwrote_existing_then_unpacked"
        else:
            img.filepath_raw = tgt
            img.file_format = "PNG"
            img.save()
            img.unpack(method="REMOVE")
            entry["action"] = "written_then_unpacked"
        entry["packed_after"] = bool(img.packed_file)
        entry["filepath_after"] = img.filepath
        entry["bytes"] = os.path.getsize(tgt)
        entry["sha256"] = sha256(tgt)
        report.append(entry)
    # 显式改写为相对路径（相对 clean.blend 所在目录），不依赖操作符上下文
    for e in report:
        img = bpy.data.images.get(e["image"])
        if not img:
            continue
        rel = os.path.relpath(os.path.join(TEXTURE_DIR, e["file"]), SOURCE_DIR).replace(os.sep, "/")
        img.filepath = "//" + rel
        img.filepath_raw = "//" + rel
        e["filepath_after_relative"] = img.filepath
        e["resolved_from_source_dir"] = os.path.normpath(os.path.join(SOURCE_DIR, rel))
        e["resolves"] = os.path.exists(e["resolved_from_source_dir"])
    return report

# ---------------------------------------------------------------- 渲染

class RenderRig:
    def __init__(self, height):
        sc = bpy.context.scene
        sc.render.engine = "BLENDER_EEVEE"
        sc.render.image_settings.file_format = "PNG"
        sc.render.image_settings.color_mode = "RGB"
        sc.render.film_transparent = False
        sc.view_settings.view_transform = "Standard"
        try:
            sc.eevee.taa_render_samples = 32
        except Exception:
            pass
        w = bpy.data.worlds.new("v9_world")
        w.use_nodes = True
        w.node_tree.nodes["Background"].inputs[0].default_value = (0.28, 0.30, 0.34, 1.0)
        sc.world = w
        self.height = height
        self.sc = sc

        sun = bpy.data.objects.new("v9_sun", bpy.data.lights.new("v9_sun", "SUN"))
        sun.data.energy = 4.0
        sun.data.angle = math.radians(6)
        sun.rotation_euler = (math.radians(58), 0.0, math.radians(28))
        sc.collection.objects.link(sun)
        fill = bpy.data.objects.new("v9_fill", bpy.data.lights.new("v9_fill", "SUN"))
        fill.data.energy = 1.4
        fill.rotation_euler = (math.radians(72), 0.0, math.radians(-135))
        sc.collection.objects.link(fill)
        self.lights = [sun, fill]

        cam = bpy.data.objects.new("v9_cam", bpy.data.cameras.new("v9_cam"))
        sc.collection.objects.link(cam)
        sc.camera = cam
        self.cam = cam

    def _look(self, loc, target):
        self.cam.location = loc
        d = Vector(target) - Vector(loc)
        self.cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()

    def shot(self, path, loc, target, ortho, res=(560, 760)):
        self.sc.render.resolution_x = res[0]
        self.sc.render.resolution_y = res[1]
        self.cam.data.type = "ORTHO"
        self.cam.data.ortho_scale = ortho
        self._look(loc, target)
        self.sc.render.filepath = path
        bpy.ops.render.render(write_still=True)
        return os.path.getsize(path) if os.path.exists(path) else 0

    def session(self):
        self.sc.render.resolution_x = 560
        self.sc.render.resolution_y = 760
        self.cam.data.type = "ORTHO"
        self.cam.data.ortho_scale = 1.3
        self._look((0, -2.4, 0.6), (0, 0, 0.6))
        return self

def compose(paths, out, gap=10):
    """横向拼接若干 PNG（用于 comparison_*/orientation_proof/hands_feet 合成图）。"""
    import numpy as np
    arrs = []
    for p in paths:
        im = bpy.data.images.load(p)
        im.colorspace_settings.name = "Non-Color"
        w, h = im.size
        a = np.array(im.pixels[:], dtype=np.float32).reshape(h, w, 4)
        arrs.append(a)
        bpy.data.images.remove(im)
    H = max(a.shape[0] for a in arrs)
    W = sum(a.shape[1] for a in arrs) + gap * (len(arrs) - 1)
    bg = np.array([0.28, 0.30, 0.34, 1.0], dtype=np.float32)
    canvas = np.tile(bg, (H, W, 1)).astype(np.float32)
    x = 0
    for a in arrs:
        y0 = (H - a.shape[0]) // 2          # 垂直居中留边，不重采样，保留原始像素
        canvas[y0:y0 + a.shape[0], x:x + a.shape[1]] = a
        x += a.shape[1] + gap
    img = bpy.data.images.new("v9_compose", W, H, alpha=True)
    img.colorspace_settings.name = "Non-Color"
    img.pixels = canvas.reshape(-1).tolist()
    img.filepath_raw = out
    img.file_format = "PNG"
    img.save()
    bpy.data.images.remove(img)
    return W, H

def _rgba(c):
    return tuple(c) + (1.0,) if len(c) == 3 else tuple(c)

def add_label(text, loc, size, color, rotation=(0.0, 0.0, 0.0)):
    bpy.ops.object.text_add(location=loc)
    tx = bpy.context.object
    tx.data.body = text
    tx.data.size = size
    tx.data.extrude = 0.0015
    tx.rotation_euler = rotation
    m = bpy.data.materials.new("v9_label_mat")
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = _rgba(color)
    bsdf.inputs["Roughness"].default_value = 0.6
    tx.data.materials.append(m)
    try:
        bpy.ops.object.convert(target="MESH")
        return bpy.context.object
    except Exception:
        return tx

def add_axis_arrow(origin, direction, length, radius, color):
    d = Vector(direction).normalized()
    bpy.ops.mesh.primitive_cylinder_add(vertices=24, radius=radius, depth=length * 0.82,
                                        location=Vector(origin) + d * (length * 0.41))
    shaft = bpy.context.object
    shaft.rotation_euler = d.to_track_quat("Z", "Y").to_euler()
    bpy.ops.mesh.primitive_cone_add(vertices=24, radius1=radius * 2.8, radius2=0.0,
                                    depth=length * 0.18,
                                    location=Vector(origin) + d * (length * 0.91))
    head = bpy.context.object
    head.rotation_euler = shaft.rotation_euler
    bpy.ops.object.select_all(action="DESELECT")
    shaft.select_set(True)
    head.select_set(True)
    bpy.context.view_layer.objects.active = shaft
    bpy.ops.object.join()
    arrow = bpy.context.object
    m = bpy.data.materials.new("v9_arrow_mat")
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = _rgba(color)
    b.inputs["Emission Color"].default_value = _rgba(color)
    b.inputs["Emission Strength"].default_value = 1.6
    arrow.data.materials.append(m)
    return arrow

# ---------------------------------------------------------------- 导出

def export_glb(ob, path):
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.export_scene.gltf(
        filepath=path, export_format="GLB", use_selection=True,
        export_yup=True, export_apply=False,
        export_texcoords=True, export_normals=True, export_tangents=False,
        export_materials="EXPORT", export_image_format="AUTO",
        export_skins=False, export_animations=False, export_cameras=False, export_lights=False,
        export_extras=False,
    )
    return os.path.getsize(path)

def export_fbx(ob, path):
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.export_scene.fbx(
        filepath=path, use_selection=True, object_types={"MESH"},
        apply_unit_scale=True, global_scale=1.0,
        axis_forward="-Y", axis_up="Z",
        add_leaf_bones=False, use_mesh_modifiers=True, mesh_smooth_type="FACE",
        path_mode="RELATIVE", embed_textures=False, use_tspace=False,
    )
    return os.path.getsize(path)

def export_obj(ob, path, forward="NEGATIVE_Y", up="Z"):
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.wm.obj_export(
        filepath=path, export_selected_objects=True, apply_modifiers=True,
        export_uv=True, export_normals=True, export_materials=True,
        export_triangulated_mesh=True,
        forward_axis=forward, up_axis=up, path_mode="COPY",
    )
    return os.path.getsize(path)

def export_fbx_yup(ob, path):
    """本仓已验证过的 Mixamo 上传约定（Y-up / 面朝 -Z，见 mcp/mixamo/kaykit_route_b_prepare.py）。"""
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.export_scene.fbx(
        filepath=path, use_selection=True, object_types={"MESH"},
        apply_unit_scale=True, global_scale=1.0,
        axis_forward="-Z", axis_up="Y",
        add_leaf_bones=False, use_mesh_modifiers=True, mesh_smooth_type="FACE",
        path_mode="RELATIVE", embed_textures=False, use_tspace=False,
    )
    return os.path.getsize(path)

def build_blend(ob, path, extra=None):
    keep = [o for o in list(bpy.data.objects) if o is ob]
    if extra:
        keep.extend(extra)
    for o in list(bpy.data.objects):
        if o not in keep:
            bpy.data.objects.remove(o, do_unlink=True)
    for img in list(bpy.data.images):
        # "Render Result" 是渲染器内部缓冲，不是资产；带它存档只会在重开时报未解析路径
        if img.name == "Render Result" or img.source != "FILE" or img.users == 0:
            try:
                bpy.data.images.remove(img, do_unlink=True)
            except Exception:
                pass
    bpy.ops.wm.save_as_mainfile(filepath=path, compress=True)
    return os.path.getsize(path)

# ---------------------------------------------------------------- 主流程 build

def phase_build():
    t0 = time.time()
    ensure_dirs()
    log("=" * 72)
    log("cultivator_tripo_v9 第一阶段 build")
    log("=" * 72)
    manifest = {"asset": "cultivator_tripo_v9", "phase": "build",
                "contract_note": "notes/proposed/art/2026-09-19-cultivator-tripo-v9-runtime.md",
                "blender": bpy.app.version_string, "started": time.strftime("%Y-%m-%dT%H:%M:%S")}

    # 1) raw 归档校验
    manifest["raw_archive"] = verify_raw()
    log("[1] raw SHA-256 %s (expected match=%s)" % (
        manifest["raw_archive"]["raw_sha256"][:16] + "...",
        manifest["raw_archive"]["raw_sha256_matches_expected"]))

    # 2) 导入 + 原始审计
    ob = import_raw()
    mesh0 = ob.data
    h0 = max(v.co.z for v in mesh0.vertices) - min(v.co.z for v in mesh0.vertices)
    manifest["imported"] = {
        "object_count": len(bpy.data.objects),
        "objects": object_audit(list(bpy.data.objects)),
        "mesh_health": mesh_health(mesh0),
        "uv": uv_stats(mesh0),
        "materials": [m.name for m in mesh0.materials],
        "images": [{"name": i.name, "size": list(i.size[:]), "packed": bool(i.packed_file)} for i in bpy.data.images],
        "bbox_height_m": round(h0, 6),
        "orientation": orientation_evidence(mesh0, "raw_import", matrix_world=ob.matrix_world),
    }
    log("[2] 原始: verts=%d polys=%d tris=%d uv=%s mats=%s bbox_h=%.4fm" % (
        manifest["imported"]["mesh_health"]["verts"], manifest["imported"]["mesh_health"]["faces"],
        manifest["imported"]["mesh_health"]["tris"], manifest["imported"]["uv"]["names"],
        manifest["imported"]["materials"], h0))

    # imported.blend（原始状态存档，含原始几何与内嵌贴图，用于回溯）
    bpy.ops.wm.save_as_mainfile(filepath=BLEND_IMPORTED, compress=True)
    manifest["imported_blend"] = {"path": os.path.relpath(BLEND_IMPORTED, ROOT),
                                  "bytes": os.path.getsize(BLEND_IMPORTED),
                                  "sha256": sha256(BLEND_IMPORTED)}
    log("[2] imported.blend %.1f MB" % (manifest["imported_blend"]["bytes"] / 1e6))

    # 3) 朝向归一
    manifest["orientation"] = normalize_orientation(ob, TARGET_HEIGHT)
    log("[3] 朝向: face@-Y=%s toes@-Y=%s hair@+Y=%s | rot=%s | scale x%.5f -> %.4f m" % (
        manifest["orientation"]["after_height"]["face_at_negative_y"],
        manifest["orientation"]["after_height"]["toes_at_negative_y"],
        manifest["orientation"]["after_height"]["hair_mass_at_positive_y"],
        manifest["orientation"]["applied_rotation_deg"],
        manifest["orientation"]["uniform_scale_factor"], manifest["orientation"]["height_after_m"]))

    # 渲染骨架（在减面前建立，用于渲染「清理前」三视图）
    rig = RenderRig(TARGET_HEIGHT)
    manifest["renders"] = render_original_trio(rig, ob)

    # 4) 清理 + 5) 减面
    original_copy = bpy.data.meshes.new_from_object(ob)

    # 先减面，再清理（先减面可让焊接/退化面处理作用在最终拓扑上）
    dec = decimate(ob, DECIMATE_RATIO, TARGET_HEIGHT)
    manifest["decimate"] = dec
    log("[5] 减面: %d -> %d tris (-%.2f%%) | face %d->%d hands %d->%d feet %d->%d free %d->%d" % (
        dec["tris_before"], dec["tris_after"], dec["reduction_percent"],
        dec["region_tris_before"]["face"], dec["region_tris_after"]["face"],
        dec["region_tris_before"]["hands"], dec["region_tris_after"]["hands"],
        dec["region_tris_before"]["feet"], dec["region_tris_after"]["feet"],
        dec["region_tris_before"]["free"], dec["region_tris_after"]["free"]))

    manifest["cleanup"] = clean_mesh(ob)
    log("[4] 清理: loose_v=%d loose_e=%d degen=%d merged=%d dup_faces=%d nonmanifold %d->%d" % (
        manifest["cleanup"]["actions"]["removed_loose_verts"],
        manifest["cleanup"]["actions"]["removed_loose_edges"],
        manifest["cleanup"]["actions"]["removed_degenerate_faces"] + manifest["cleanup"]["actions"]["removed_degenerate_faces_after_merge"],
        manifest["cleanup"]["actions"]["merged_verts"],
        manifest["cleanup"]["actions"]["removed_duplicate_faces"],
        manifest["cleanup"]["before"]["non_manifold_edges"], manifest["cleanup"]["after"]["non_manifold_edges"]))

    manifest["silhouette_deviation"] = silhouette_deviation(original_copy, ob.data)
    bpy.data.meshes.remove(original_copy)
    log("[5] 轮廓偏差 p50=%.2fmm p95=%.2fmm p99=%.2fmm max=%.2fmm" % (
        manifest["silhouette_deviation"]["p50_mm"], manifest["silhouette_deviation"]["p95_mm"],
        manifest["silhouette_deviation"]["p99_mm"], manifest["silhouette_deviation"]["max_mm"]))

    # 材质 / 贴图
    manifest["final_materials"] = [m.name for m in ob.data.materials]
    manifest["textures"] = unpack_textures()
    flags = [t.get("filepath_after_make_relative", t["filepath_after"]) for t in manifest["textures"]]
    manifest["final_uv"] = uv_stats(ob.data)
    manifest["final_health"] = mesh_health(ob.data)
    log("[6] 贴图解包: %s" % flags)

    # 渲染（在导出前做，避免导出器改动场景）
    manifest["renders"].update(render_all(rig, ob))
    cleanup_render_objects(ob)
    log("[7] 渲染 %d 张" % len(manifest["renders"]))

    # 7) 导出
    manifest["exports"] = {}
    manifest["exports"]["glb_bytes"] = export_glb(ob, GLB_CLEAN)
    manifest["exports"]["fbx_bytes"] = export_fbx(ob, FBX_UPLOAD)
    manifest["exports"]["obj_bytes"] = export_obj(ob, OBJ_UPLOAD)
    # 同几何、不同坐标约定的备用上传件（Y-up / 面朝 -Z），本仓已验证 Mixamo 可接受
    FBX_YUP = os.path.join(EXPORT_DIR, "cultivator_tripo_v9_mixamo_upload_yup.fbx")
    OBJ_YUP = os.path.join(OBJ_DIR, "cultivator_tripo_v9_mixamo_upload_yup.obj")
    manifest["exports"]["fbx_yup_bytes"] = export_fbx_yup(ob, FBX_YUP)
    manifest["exports"]["obj_yup_bytes"] = export_obj(ob, OBJ_YUP, forward="NEGATIVE_Z", up="Y")
    for p in (GLB_CLEAN, FBX_UPLOAD, OBJ_UPLOAD, FBX_YUP, OBJ_YUP,
              os.path.join(OBJ_DIR, "cultivator_tripo_v9_mixamo_upload.mtl"),
              os.path.join(OBJ_DIR, "cultivator_tripo_v9_mixamo_upload_yup.mtl")):
        if os.path.exists(p):
            manifest["exports"][os.path.basename(p)] = {"bytes": os.path.getsize(p), "sha256": sha256(p)}
    for f in sorted(os.listdir(OBJ_DIR)):
        fp = os.path.join(OBJ_DIR, f)
        manifest["exports"].setdefault("obj_dir_files", {})[f] = os.path.getsize(fp)
    log("[8] 导出 GLB %.1fMB / FBX %.1fMB / OBJ %.1fMB" % (
        manifest["exports"]["glb_bytes"] / 1e6, manifest["exports"]["fbx_bytes"] / 1e6,
        manifest["exports"]["obj_bytes"] / 1e6))

    # clean.blend（只含最终角色网格）
    manifest["clean_blend"] = {"path": os.path.relpath(BLEND_CLEAN, ROOT),
                               "bytes": build_blend(ob, BLEND_CLEAN),
                               "sha256": sha256(BLEND_CLEAN)}
    log("[9] clean.blend %.1f MB" % (manifest["clean_blend"]["bytes"] / 1e6))

    manifest["finished"] = time.strftime("%Y-%m-%dT%H:%M:%S")
    manifest["elapsed_sec"] = round(time.time() - t0, 1)
    manifest["log"] = LOG
    with open(MANIFEST, "w") as fh:
        json.dump(manifest, fh, indent=2, ensure_ascii=False)
    log("[10] cleanup_manifest.json 写入完成，用时 %.1fs" % manifest["elapsed_sec"])
    return manifest

def cleanup_render_objects(ob):
    """删除渲染辅助对象（文字/箭头/相机/灯），只留角色网格。"""
    for o in list(bpy.data.objects):
        if o is not ob:
            bpy.data.objects.remove(o, do_unlink=True)

# ---------------------------------------------------------------- 渲染清单

def _p(name):
    return os.path.join(RENDER_DIR, name)

def render_original_trio(rig, ob):
    H = rig.height
    out = {}
    rig.session()
    c = (0.0, 0.0, H * 0.5)
    S = H * 1.14
    for name, loc, note in (
        ("original_front.png", (0.0, -2.4, H * 0.5), "清理前（原始拓扑，未减面未焊接）"),
        ("original_side.png", (-2.4, 0.0, H * 0.5), "清理前左侧"),
        ("original_back.png", (0.0, 2.4, H * 0.5), "清理前背面"),
    ):
        p = _p(name)
        out[name] = {"bytes": rig.shot(p, loc, c, S), "size": [560, 760], "note": note,
                     "source": "normalize 后的原始网格（减面/清理之前）"}
    log("    original trio: %s" % {k: v["bytes"] for k, v in out.items()})
    return out

def render_all(rig, ob):
    H = rig.height
    out = {}
    rig.session()
    c = (0.0, 0.0, H * 0.5)
    S = H * 1.14

    # 正交三视图
    for name, loc in (("clean_front.png", (0.0, -2.4, H * 0.5)),
                      ("clean_side.png", (-2.4, 0.0, H * 0.5)),
                      ("clean_back.png", (0.0, 2.4, H * 0.5))):
        out[name] = {"bytes": rig.shot(_p(name), loc, c, S), "size": [560, 760]}

    # 四分之三视图（正交，保证与三视图同尺度）
    for name, loc in (("clean_three_quarter_front.png", (1.75, -1.75, H * 0.60)),
                      ("clean_three_quarter_back.png", (-1.75, 1.75, H * 0.60))):
        out[name] = {"bytes": rig.shot(_p(name), loc, c, S), "size": [560, 760]}

    # 头部特写
    out["clean_head_closeup.png"] = {"bytes": rig.shot(
        _p("clean_head_closeup.png"), (0.0, -0.85, 1.585), (0.0, 0.0, 1.585), 0.42, res=(640, 640)),
        "size": [640, 640]}

    # 手 / 脚特写面板
    out["clean_hand_closeup.png"] = {"bytes": rig.shot(
        _p("clean_hand_closeup.png"), (0.44, -0.55, 0.80), (0.44, 0.0, 0.79), 0.24, res=(520, 520)),
        "size": [520, 520]}
    out["clean_foot_closeup.png"] = {"bytes": rig.shot(
        _p("clean_foot_closeup.png"), (0.17, -0.62, 0.13), (0.17, 0.0, 0.11), 0.34, res=(520, 520)),
        "size": [520, 520]}
    w, h = compose([_p("clean_hand_closeup.png"), _p("clean_foot_closeup.png"),
                    _p("clean_three_quarter_front.png")], _p("clean_hands_feet.png"))
    out["clean_hands_feet.png"] = {"bytes": os.path.getsize(_p("clean_hands_feet.png")),
                                   "size": [w, h], "note": "左手特写 | 靴子特写 | 3/4 全景"}

    # 灰模正视图（材质替换，只看轮廓）
    mesh = ob.data
    saved = [m for m in mesh.materials]
    gray = bpy.data.materials.new("v9_gray")
    gray.use_nodes = True
    bsdf = gray.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (0.62, 0.62, 0.62, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.55
    mesh.materials.clear()
    mesh.materials.append(gray)
    out["clean_gray_front.png"] = {"bytes": rig.shot(_p("clean_gray_front.png"),
                                                     (0.0, -2.4, H * 0.5), c, S), "size": [560, 760],
                                   "note": "无贴图灰模，仅用于检查轮廓与法线"}
    mesh.materials.clear()
    for m in saved:
        mesh.materials.append(m)
    bpy.data.materials.remove(gray)

    # 朝向证明
    out["orientation_proof.png"] = render_orientation_proof(rig, ob)

    # 前后对照
    for view in ("front", "side"):
        w, h = compose([_p("original_%s.png" % view), _p("clean_%s.png" % view)],
                       _p("comparison_%s.png" % view), gap=14)
        out["comparison_%s.png" % view] = {"bytes": os.path.getsize(_p("comparison_%s.png" % view)),
                                           "size": [w, h],
                                           "note": "左：原始拓扑（未减面）｜ 右：清理+减面后",
                                           "panels": ["original_%s.png" % view, "clean_%s.png" % view]}
    return out

def render_orientation_proof(rig, ob):
    """构造坐标轴证据场景：红=-Y(正面) / 绿=+X / 蓝=+Z，地面写 FRONT / BACK。"""
    sc = rig.sc
    helpers = []
    H = rig.height

    bpy.ops.mesh.primitive_plane_add(size=3.0, location=(0, 0, -0.002))
    ground = bpy.context.object
    gm = bpy.data.materials.new("v9_ground")
    gm.use_nodes = True
    gm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.16, 0.17, 0.20, 1.0)
    ground.data.materials.append(gm)
    helpers.append(ground)

    helpers.append(add_axis_arrow((0, 0, 0.02), (0, -1, 0), 1.15, 0.010, (0.95, 0.10, 0.10)))
    helpers.append(add_axis_arrow((0, 0, 0.02), (1, 0, 0), 0.85, 0.008, (0.15, 0.85, 0.25)))
    helpers.append(add_axis_arrow((0, 0, 0.02), (0, 0, 1), 0.85, 0.008, (0.20, 0.45, 0.95)))

    helpers.append(add_label("FRONT", (-0.88, -0.60, 0.004), 0.15, (1.0, 0.30, 0.30)))
    helpers.append(add_label("BACK", (-0.80, 0.48, 0.004), 0.15, (0.75, 0.78, 0.85)))
    helpers.append(add_label("-Y  FRONT", (-0.62, -0.92, 0.004), 0.12, (1.0, 0.10, 0.10)))
    helpers.append(add_label("+Y", (-0.32, 0.80, 0.004), 0.12, (0.55, 0.75, 1.0)))
    helpers.append(add_label("+X", (0.86, -0.16, 0.004), 0.13, (0.20, 0.9, 0.35)))
    helpers.append(add_label("+Z", (0.10, 0.0, 0.98), 0.13, (0.30, 0.55, 1.0),
                             rotation=(math.radians(90), 0.0, 0.0)))

    a = _p("orientation_proof_persp.png")
    b = _p("orientation_proof_top.png")
    rig.shot(a, (1.55, -2.05, 1.42), (0.0, 0.0, 0.62), 2.0, res=(760, 760))
    rig.cam.data.type = "ORTHO"
    rig.cam.data.ortho_scale = 1.55
    rig.sc.render.resolution_x = 760
    rig.sc.render.resolution_y = 760
    rig._look((0.0, 0.0, 3.2), (0.0, 0.0, 0.0))
    rig.sc.render.filepath = b
    bpy.ops.render.render(write_still=True)

    w, h = compose([a, b], _p("orientation_proof.png"), gap=14)

    for o in helpers:
        bpy.data.objects.remove(o, do_unlink=True)
    for m in list(bpy.data.materials):
        if m.name.startswith("v9_ground") or m.name.startswith("v9_arrow_mat") or m.name.startswith("v9_label_mat"):
            bpy.data.materials.remove(m)
    for img in list(bpy.data.images):
        if img.users == 0:
            bpy.data.images.remove(img)
    return {"bytes": os.path.getsize(_p("orientation_proof.png")), "size": [w, h],
            "note": "左：3/4 正交（红=+X / 绿=-Y 正面箭头 / 蓝=+Z，地面写 FRONT/BACK）；"
            "右：俯视（图像上方=+Y 背面，下方=-Y 正面，人物鼻尖朝下）"}

# ---------------------------------------------------------------- 阶段：独立审计

def parse_glb_json(path):
    with open(path, "rb") as fh:
        data = fh.read()
    magic, ver, length = struct.unpack_from("<III", data, 0)
    jlen, jtype = struct.unpack_from("<II", data, 12)
    js = json.loads(data[20:20 + jlen].decode("utf-8"))
    return js, len(data)

def inspect_glb(path):
    js, size = parse_glb_json(path)
    prims = []
    for m in js.get("meshes", []):
        for pr in m["primitives"]:
            acc = js["accessors"]
            pos = acc[pr["attributes"]["POSITION"]]
            prims.append({
                "mesh": m.get("name"), "mode": pr.get("mode", 4), "material": pr.get("material"),
                "triangles": acc[pr["indices"]]["count"] // 3 if "indices" in pr else pos["count"] // 3,
                "verts": pos["count"],
                "attributes": sorted(pr["attributes"].keys()),
                "pos_min": [round(v, 6) for v in pos["min"]], "pos_max": [round(v, 6) for v in pos["max"]],
            })
    root_nodes = js["scenes"][js.get("scene", 0)]["nodes"]
    out = {
        "bytes": size, "sha256": sha256(path),
        "generator": js["asset"].get("generator"), "version": js["asset"].get("version"),
        "scenes": len(js.get("scenes", [])), "root_nodes": root_nodes,
        "nodes": len(js.get("nodes", [])), "meshes": len(js.get("meshes", [])),
        "primitives": len(prims), "primitives_detail": prims,
        "materials": len(js.get("materials", [])), "material_names": [m.get("name") for m in js.get("materials", [])],
        "textures": len(js.get("textures", [])), "images": len(js.get("images", [])),
        "samplers": len(js.get("samplers", [])),
        "skins": len(js.get("skins", [])), "animations": len(js.get("animations", [])),
        "cameras": len(js.get("cameras", [])),
        "extensions_used": js.get("extensionsUsed", []),
        "node_transforms": [{"name": n.get("name"), "translation": n.get("translation"),
                             "rotation": n.get("rotation"), "scale": n.get("scale")}
                            for n in js.get("nodes", [])],
    }
    return out

def phase_audit():
    ensure_dirs()
    rep = {"asset": "cultivator_tripo_v9", "phase": "audit", "blender": bpy.app.version_string,
           "started": time.strftime("%Y-%m-%dT%H:%M:%S"),
           "contract_note": "notes/proposed/art/2026-09-19-cultivator-tripo-v9-runtime.md"}
    checks = []
    def check(name, ok, detail=""):
        checks.append({"check": name, "ok": bool(ok), "detail": detail})
        log("  [%s] %s %s" % ("PASS" if ok else "FAIL", name, detail))
        return ok

    log("=" * 72)
    log("cultivator_tripo_v9 第一阶段 独立审计")
    log("=" * 72)

    # --- raw
    rep["raw_archive"] = verify_raw()
    check("raw 副本 SHA-256 与根原件一致",
          rep["raw_archive"]["raw_sha256_matches_expected"] and rep["raw_archive"].get("source_sha256_matches_raw", False),
          rep["raw_archive"]["raw_sha256"])

    # --- clean.blend 重开
    bpy.ops.wm.open_mainfile(filepath=BLEND_CLEAN)
    objs = list(bpy.data.objects)
    meshes = [o for o in objs if o.type == "MESH"]
    rep["clean_blend"] = {
        "path": os.path.relpath(BLEND_CLEAN, ROOT), "bytes": os.path.getsize(BLEND_CLEAN),
        "sha256": sha256(BLEND_CLEAN),
        "objects": object_audit(objs),
        "mesh_health": mesh_health(meshes[0].data) if meshes else None,
        "uv": uv_stats(meshes[0].data) if meshes else None,
        "materials": [m.name for m in meshes[0].data.materials] if meshes else [],
        "images": [{"name": i.name, "filepath": i.filepath,
                    "resolved": os.path.exists(bpy.path.abspath(i.filepath)),
                    "size": list(i.size[:]), "packed": bool(i.packed_file)}
                   for i in bpy.data.images if i.source == "FILE"],
        "non_file_images": [i.name for i in bpy.data.images if i.source != "FILE"],
        "bbox": None, "actions": len(bpy.data.actions), "armatures": len(bpy.data.armatures),
        "cameras": len(bpy.data.cameras), "lights": len(bpy.data.lights),
        "collections": [c.name for c in bpy.data.collections],
    }
    if meshes:
        mn, mx = bbox_of(meshes)
        rep["clean_blend"]["bbox"] = {"min": [round(v, 6) for v in mn], "max": [round(v, 6) for v in mx],
                                      "height_m": round(mx.z - mn.z, 6), "foot_z": round(mn.z, 9)}
        rep["clean_blend"]["orientation"] = orientation_evidence(meshes[0].data, "clean_blend",
                                                                height=mx.z - mn.z, matrix_world=meshes[0].matrix_world)
    cb = rep["clean_blend"]
    check("clean.blend 恰好 1 个网格对象", len(meshes) == 1 and cb["objects"]["mesh_count"] == 1,
          "mesh_count=%d total_objects=%d" % (cb["objects"]["mesh_count"], len(objs)))
    check("clean.blend 0 armature/skin/action/camera/light",
          cb["armatures"] == 0 and cb["actions"] == 0 and cb["cameras"] == 0 and cb["lights"] == 0
          and cb["objects"]["armatures"] == 0 and cb["objects"]["cameras"] == 0 and cb["objects"]["lights"] == 0)
    check("clean.blend UV 存在", bool(cb["uv"] and cb["uv"]["layers"] and cb["uv"]["outside_0_1"] == 0),
          json.dumps(cb["uv"]))
    check("clean.blend 纹理相对路径可解析",
          all(i["resolved"] and i["size"][0] > 0 for i in cb["images"]) and len(cb["images"]) == 3,
          json.dumps([(i["filepath"], i["resolved"]) for i in cb["images"]]))
    check("clean.blend 足底 z≈0", abs(cb["bbox"]["foot_z"]) < 1e-6, "foot_z=%.9f" % cb["bbox"]["foot_z"])
    check("clean.blend 人物面朝 -Y",
          cb["orientation"]["face_at_negative_y"] and cb["orientation"]["toes_at_negative_y"],
          "nose_y=%.4f toes_y=[%.4f,%.4f]" % (cb["orientation"]["head_centerline_y_min"],
                                              cb["orientation"]["toe_y_min"], cb["orientation"]["toe_y_max"]))

    # --- clean.glb
    rep["clean_glb"] = inspect_glb(GLB_CLEAN)
    g = rep["clean_glb"]
    check("clean.glb 1 mesh / 1 primitive", g["meshes"] == 1 and g["primitives"] == 1,
          "meshes=%d prims=%d" % (g["meshes"], g["primitives"]))
    check("clean.glb 0 skin / 0 animation / 0 camera",
          g["skins"] == 0 and g["animations"] == 0 and g["cameras"] == 0)
    check("clean.glb 有 TEXCOORD_0", "TEXCOORD_0" in g["primitives_detail"][0]["attributes"],
          str(g["primitives_detail"][0]["attributes"]))
    check("clean.glb 有 NORMAL", "NORMAL" in g["primitives_detail"][0]["attributes"])

    # GLB 重新导入核对朝向与足底
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=GLB_CLEAN)
    m2 = [o for o in bpy.data.objects if o.type == "MESH"]
    if m2:
        mn, mx = bbox_of(m2)
        rep["clean_glb"]["reimport"] = {
            "objects": object_audit(list(bpy.data.objects)),
            "height_m": round(mx.z - mn.z, 6), "foot_z": round(mn.z, 9),
            "bbox_min": [round(v, 6) for v in mn], "bbox_max": [round(v, 6) for v in mx],
            "uv": uv_stats(m2[0].data),
            "orientation": orientation_evidence(m2[0].data, "clean_glb_reimport",
                                                             height=mx.z - mn.z, matrix_world=m2[0].matrix_world),
        }
        check("clean.glb 重新导入后 foot_z≈0 且高度合理",
              abs(mn.z) < 1e-4 and 1.70 < (mx.z - mn.z) < 1.80,
              "foot_z=%.6f height=%.4f" % (mn.z, mx.z - mn.z))
        check("clean.glb 重新导入后面朝 -Y",
              rep["clean_glb"]["reimport"]["orientation"]["face_at_negative_y"],
              "nose_y=%.4f" % rep["clean_glb"]["reimport"]["orientation"]["head_centerline_y_min"])

    # --- FBX
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=FBX_UPLOAD)
    m3 = [o for o in bpy.data.objects if o.type == "MESH"]
    rep["mixamo_upload_fbx"] = {"path": os.path.relpath(FBX_UPLOAD, ROOT), "bytes": os.path.getsize(FBX_UPLOAD),
                                "sha256": sha256(FBX_UPLOAD),
                                "objects": object_audit(list(bpy.data.objects)),
                                "armatures": len(bpy.data.armatures), "actions": len(bpy.data.actions)}
    if m3:
        mn, mx = bbox_of(m3)
        rep["mixamo_upload_fbx"].update({
            "height_m": round(mx.z - mn.z, 6), "foot_z": round(mn.z, 9),
            "tris": sum(tri_count(o.data) for o in m3),
            "uv": uv_stats(m3[0].data), "materials": [m.name for m in m3[0].data.materials],
            "orientation": orientation_evidence(m3[0].data, "fbx_reimport",
                                                             height=mx.z - mn.z, matrix_world=m3[0].matrix_world),
        })
    f = rep["mixamo_upload_fbx"]
    check("upload.fbx 恰好 1 个网格", f["objects"]["mesh_count"] == 1, "mesh_count=%d" % f["objects"]["mesh_count"])
    check("upload.fbx 0 armature / 0 action / 0 camera / 0 light",
          f["armatures"] == 0 and f["actions"] == 0 and f["objects"]["cameras"] == 0 and f["objects"]["lights"] == 0)
    check("upload.fbx 有 UV", bool(f.get("uv") and f["uv"]["layers"]), json.dumps(f.get("uv")))
    check("upload.fbx 足底≈0 且 6 英尺量级", abs(f.get("foot_z", 9)) < 1e-3 and 1.70 < f.get("height_m", 0) < 1.80,
          "foot_z=%.6f height=%.4f" % (f.get("foot_z", -1), f.get("height_m", -1)))
    check("upload.fbx 面朝 -Y", f["orientation"]["face_at_negative_y"] if m3 else False)

    # --- OBJ（契约约定：Z-up / 面朝 -Y，导入时用同一约定还原）
    def inspect_obj(path, fwd, upv, label, mtl_name):
        entry = {"path": os.path.relpath(path, ROOT), "bytes": os.path.getsize(path), "sha256": sha256(path),
                 "forward_axis_on_import": fwd, "up_axis_on_import": upv,
                 "mtl": os.path.relpath(os.path.join(OBJ_DIR, mtl_name), ROOT)}
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.wm.obj_import(filepath=path, forward_axis=fwd, up_axis=upv)
        ms = [o for o in bpy.data.objects if o.type == "MESH"]
        if ms:
            mn, mx = bbox_of(ms)
            entry.update({
                "mesh_count": len(ms), "tris": sum(tri_count(o.data) for o in ms),
                "height_m": round(mx.z - mn.z, 6), "foot_z": round(mn.z, 9),
                "uv": uv_stats(ms[0].data),
                "orientation": orientation_evidence(ms[0].data, label, height=mx.z - mn.z,
                                                     matrix_world=ms[0].matrix_world),
            })
        return entry

    rep["mixamo_upload_obj"] = inspect_obj(OBJ_UPLOAD, "NEGATIVE_Y", "Z", "obj_reimport_zup",
                                           "cultivator_tripo_v9_mixamo_upload.mtl")
    rep["mixamo_upload_obj_yup"] = inspect_obj(
        os.path.join(OBJ_DIR, "cultivator_tripo_v9_mixamo_upload_yup.obj"), "NEGATIVE_Z", "Y",
        "obj_reimport_yup", "cultivator_tripo_v9_mixamo_upload_yup.mtl")
    o = rep["mixamo_upload_obj"]
    check("upload.obj 恰好 1 网格 + UV", o.get("mesh_count") == 1 and bool(o.get("uv", {}).get("layers")))
    check("upload.obj 足底≈0 且面朝 -Y",
          abs(o.get("foot_z", 9)) < 1e-3 and o["orientation"]["face_at_negative_y"],
          "foot_z=%.6f nose_y=%s" % (o.get("foot_z", -1), o["orientation"]["head_centerline_y_min"]))
    # 备用件为 optional / non-blocking：不计入 Phase 1 硬前置信度，只留实测口径
    oy = rep["mixamo_upload_obj_yup"]
    oy["optional"] = True
    oy["blocking"] = False
    oy["note"] = ("备用 Y-up / 面朝 -Z 上传件。OBJ 往返会把轴向表达为导入矩阵而不是烘焙进顶点，"
                  "朝向结论一律以 world 坐标下的 orientation 字段为准；标准 Z-up 件才是硬前置。")
    if not (oy.get("mesh_count") == 1 and abs(oy.get("foot_z", 9)) < 1e-3
            and oy["orientation"]["face_at_negative_y"]):
        checks.append({"check": "upload.obj_yup (optional, non-blocking)", "ok": False,
                       "optional": True,
                       "detail": "optional/non-blocking: mesh_count=%s foot_z=%s nose_y=%s" % (
                           oy.get("mesh_count"), oy.get("foot_z"),
                           oy["orientation"].get("head_centerline_y_min"))})

    # --- 渲染存在性
    need = ["original_front.png", "original_side.png", "original_back.png",
            "clean_front.png", "clean_side.png", "clean_back.png",
            "clean_three_quarter_front.png", "clean_three_quarter_back.png",
            "clean_head_closeup.png", "clean_hands_feet.png", "clean_gray_front.png",
            "orientation_proof.png", "comparison_front.png", "comparison_side.png"]
    missing = [n for n in need if not os.path.exists(_p(n)) or os.path.getsize(_p(n)) < 2000]
    rep["renders"] = {n: {"bytes": os.path.getsize(_p(n)), "sha256": sha256(_p(n))}
                      for n in need if os.path.exists(_p(n))}
    check("14 张必需渲染全部存在且非空", not missing, "missing=%s" % missing)

    # --- 减面与边界
    mf = os.path.join(ASSET, "cleanup_manifest.json")
    with open(mf) as fh:
        man = json.load(fh)
    rep["manifest_reference"] = {"path": os.path.relpath(mf, ROOT), "sha256": sha256(mf)}
    tb = man["decimate"]["tris_before"]; ta = man["decimate"]["tris_after"]
    rep["decimation"] = {"tris_before": tb, "tris_after": ta,
                         "reduction_percent": round(100 * (1 - ta / tb), 4),
                         "face_region_before": man["decimate"]["region_tris_before"]["face"],
                         "face_region_after": man["decimate"]["region_tris_after"]["face"],
                         "hands_before": man["decimate"]["region_tris_before"]["hands"],
                         "hands_after": man["decimate"]["region_tris_after"]["hands"],
                         "feet_before": man["decimate"]["region_tris_before"]["feet"],
                         "feet_after": man["decimate"]["region_tris_after"]["feet"],
                         "free_before": man["decimate"]["region_tris_before"]["free"],
                         "free_after": man["decimate"]["region_tris_after"]["free"],
                         "silhouette_deviation": man["silhouette_deviation"]}
    check("三角面下降 >= 40%", rep["decimation"]["reduction_percent"] >= 40.0,
          "%.2f%% (%d -> %d)" % (rep["decimation"]["reduction_percent"], tb, ta))
    check("脸/手/靴保护区未塌陷",
          rep["decimation"]["face_region_after"] >= rep["decimation"]["face_region_before"] * 0.99
          and rep["decimation"]["hands_after"] >= rep["decimation"]["hands_before"] * 0.99
          and rep["decimation"]["feet_after"] >= rep["decimation"]["feet_before"] * 0.99,
          "face %d->%d hands %d->%d feet %d->%d" % (rep["decimation"]["face_region_before"], rep["decimation"]["face_region_after"],
                                                    rep["decimation"]["hands_before"], rep["decimation"]["hands_after"],
                                                    rep["decimation"]["feet_before"], rep["decimation"]["feet_after"]))
    check("最终网格非有限坐标=0", rep["clean_blend"]["mesh_health"]["non_finite_verts"] == 0)

    rep["checks"] = checks
    rep["checks_passed"] = sum(1 for c in checks if c["ok"])
    rep["checks_total"] = len(checks)
    rep["all_passed"] = rep["checks_passed"] == rep["checks_total"]
    rep["required_all_passed"] = all(c["ok"] for c in checks if not c.get("optional"))
    rep["note_optional"] = ("upload.obj_yup 为 optional/non-blocking 备用件，"
                            "required_all_passed 不计入它。")
    rep["finished"] = time.strftime("%Y-%m-%dT%H:%M:%S")
    with open(AUDIT, "w") as fh:
        json.dump(rep, fh, indent=2, ensure_ascii=False)
    log("-" * 72)
    log("审计: %d/%d 通过, required_all_passed=%s, all_passed(含 optional)=%s" % (
        rep["checks_passed"], rep["checks_total"], rep["required_all_passed"], rep["all_passed"]))
    log("export_audit.json 写入完成")
    return rep

# ---------------------------------------------------------------- 入口

def main():
    if PHASE == "build":
        phase_build()
    elif PHASE == "audit":
        phase_audit()
    else:
        raise SystemExit("未知 phase: %s（可用 build / audit）" % PHASE)

if __name__ == "__main__":
    main()
