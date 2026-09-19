"""Generate the jade-paper movement cultivator v2 as a polished static T-pose.

The character is authored facing Blender -Y. The previous v1 was rotated to +Y before FBX
export and Mixamo displayed its back; v2 deliberately keeps the opposite authored facing and
stores semantic vertex groups so a clean FBX re-import can prove the face and toes are on -Y.

Run:
  /Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup \
    --python tools/art/generate_cultivator_shortcoat_v2.py -- build preview audit
"""
import hashlib
import importlib.util
import json
import math
import os
import shutil
import sys

import bmesh
import bpy
from mathutils import Vector


ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DOCS = os.path.join(ROOT, "docs", "art", "cultivator_shortcoat_v2")
ITERATIONS = os.path.join(DOCS, "iterations")
BLEND = os.path.join(DOCS, "cultivator_shortcoat_v2.blend")
GLB = os.path.join(DOCS, "cultivator_shortcoat_v2.glb")
FBX = os.path.join(DOCS, "cultivator_shortcoat_v2_mixamo_tpose.fbx")
MANIFEST = os.path.join(DOCS, "build_manifest.json")


def load_helpers():
    path = os.path.join(ROOT, "tools", "art", "generate_cultivator_refined.py")
    spec = importlib.util.spec_from_file_location("cultivator_refined_helpers_v2", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


h = load_helpers()


def sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def ensure_dirs():
    os.makedirs(DOCS, exist_ok=True)
    os.makedirs(ITERATIONS, exist_ok=True)


def materials():
    h.MATS.clear()
    # Linear values tuned for a warm studio, not saturated game-blue plastic.
    h.make_mat("Indigo_Cloth", (0.0194, 0.0437, 0.1070), rough=0.84)
    h.make_mat("Indigo_Torso_QA", (0.0194, 0.0437, 0.1070), rough=0.84)
    h.make_mat("Indigo_Light", (0.0320, 0.0710, 0.1540), rough=0.82)
    h.make_mat("Indigo_Shadow", (0.0091, 0.0212, 0.0497), rough=0.87)
    h.make_mat("Moon_Ivory", (0.7758, 0.7379, 0.6445), rough=0.76)
    h.make_mat("Warm_Gold", (0.4735, 0.2874, 0.0723), rough=0.64, metallic=0.08)
    h.make_mat("Skin_Warm", (0.6724, 0.4179, 0.2747), rough=0.72)
    h.make_mat("Skin_Head_QA", (0.6724, 0.4179, 0.2747), rough=0.72)
    h.make_mat("Skin_Nose_QA", (0.6724, 0.4179, 0.2747), rough=0.72)
    h.make_mat("Hair_Ink", (0.005, 0.008, 0.015), rough=0.64)
    h.make_mat("Hair_Bun_QA", (0.005, 0.008, 0.015), rough=0.64)
    h.make_mat("Boot_Ink", (0.010, 0.014, 0.022), rough=0.78)
    h.make_mat("Boot_Heel_QA", (0.010, 0.014, 0.022), rough=0.78)
    h.make_mat("Boot_Toe_QA", (0.010, 0.014, 0.022), rough=0.78)
    h.make_mat("Face_Detail", (0.018, 0.014, 0.018), rough=0.75)
    h.make_mat("Eye_White_QA", (0.600, 0.535, 0.430), rough=0.78)
    h.make_mat("Eye_QA", (0.012, 0.010, 0.014), rough=0.75)
    h.make_mat("Mouth", (0.180, 0.050, 0.042), rough=0.72)
    for name in ("Indigo_Cloth", "Indigo_Torso_QA", "Indigo_Light", "Indigo_Shadow"):
        bsdf = h.get_mat(name).node_tree.nodes["Principled BSDF"]
        if "Specular IOR Level" in bsdf.inputs:
            bsdf.inputs["Specular IOR Level"].default_value = 0.22


def finish(bm, name, mat, smooth=True):
    return h.finish(bm, name, mat, smooth_faces=smooth)


def tag_all(obj, group_name):
    group = obj.vertex_groups.new(name=group_name)
    group.add(list(range(len(obj.data.vertices))), 1.0, "REPLACE")


def loft_object(name, mat, sections, segments=20, smooth=True):
    bm = bmesh.new()
    h.tube_z(bm, sections, segments=segments)
    h.smooth(bm)
    return finish(bm, name, mat, smooth)


def ribbon_object(name, mat, centers, half_widths, thickness=0.005):
    """A cloth ribbon on the frontal XZ plane, with explicit width and a soft solid edge."""
    bm = bmesh.new()
    strips = []
    for (x, y, z), half in zip(centers, half_widths):
        strips.append([(x - half, y, z), (x + half, y, z)])
    h.loft(bm, strips, cap_start=True, cap_end=True, closed=False)
    h.solidify(bm, thickness)
    h.bevel(bm, min(thickness * 0.45, 0.0025), 2, only_sharp=False)
    return finish(bm, name, mat, True)


def curved_band(name, mat, upper, lower, thickness=0.006):
    """Create a filled band between two authored XZ curves on the character front."""
    if len(upper) != len(lower):
        raise ValueError("curved_band curves must have matching lengths")
    bm = bmesh.new()
    sections = [[lower[i], upper[i]] for i in range(len(upper))]
    h.loft(bm, sections, cap_start=True, cap_end=True, closed=False)
    h.solidify(bm, thickness)
    h.bevel(bm, 0.002, 2, only_sharp=False)
    return finish(bm, name, mat, True)


def wedge_panel(name, mat, top_center, top_width, bottom_center, bottom_width, height, depth):
    """Three-section cloth fall: hip-hugging root, one broad fold, bias-cut hem."""
    tx, ty, tz = top_center
    bx, by, _ = bottom_center
    z0, z1 = tz, tz - height
    # Outer hem sits lower than the inner hem, producing a restrained bias cut.
    is_left = name.endswith("_L")
    hem_lift_left = 0.014 if is_left else 0.000
    hem_lift_right = 0.000 if is_left else 0.014
    xs_top = [tx - top_width / 2, tx, tx + top_width / 2]
    mid_width = top_width * 0.48 + bottom_width * 0.52
    mx = tx * 0.46 + bx * 0.54
    xs_mid = [mx - mid_width / 2, mx, mx + mid_width / 2]
    xs_bottom = [bx - bottom_width / 2, bx, bx + bottom_width / 2]
    zs_bottom = [z1 + hem_lift_left, z1 + 0.007, z1 + hem_lift_right]
    z_mid = z0 - height * 0.52
    # The root follows the hip shell, the middle rolls outward and the hem relaxes. Centre
    # vertices create one broad controlled fold instead of a flat armour plate.
    front_sign = -1.0 if ty < 0 else 1.0
    verts = []
    for front in (True, False):
        face_sign = front_sign if front else -front_sign
        for row in (0, 1, 2):
            for col in range(3):
                if row == 0:
                    x, z, base_y, fold = xs_top[col], z0 - (0.004 if col == 1 else 0.0), ty, 0.002
                elif row == 1:
                    x, z, base_y, fold = xs_mid[col], z_mid, ty * 0.42 + by * 0.58, 0.012
                else:
                    x, z, base_y, fold = xs_bottom[col], zs_bottom[col], by, 0.007
                bow = fold if col == 1 else -fold * 0.20
                y = base_y + face_sign * (depth * 0.5 + bow)
                verts.append((x, y, z))
    # Each left/right panel wraps around its hip. Front and back use opposite yaw.
    side = -1.0 if name.endswith("_L") else 1.0
    front_panel = name.startswith("Front_")
    yaw = math.radians(side * (20.0 if front_panel else -20.0))
    rotated = []
    for x, y, z in verts:
        dx, dy = x - tx, y - ty
        rotated.append((tx + dx * math.cos(yaw) - dy * math.sin(yaw),
                        ty + dx * math.sin(yaw) + dy * math.cos(yaw), z))
    verts = rotated
    # Indices: front rows 0..8, back rows 9..17.
    faces = [
        (0, 1, 4, 3), (1, 2, 5, 4), (3, 4, 7, 6), (4, 5, 8, 7),
        (9, 12, 13, 10), (10, 13, 14, 11), (12, 15, 16, 13), (13, 16, 17, 14),
        (0, 9, 10, 1), (1, 10, 11, 2),
        (6, 7, 16, 15), (7, 8, 17, 16),
        (0, 3, 12, 9), (3, 6, 15, 12),
        (2, 11, 14, 5), (5, 14, 17, 8),
    ]
    mesh = bpy.data.meshes.new(name + "_mesh")
    mesh.from_pydata(verts, [], faces)
    mesh.materials.append(h.get_mat(mat))
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    bevel = obj.modifiers.new("Soft cloth edge", "BEVEL")
    bevel.width = 0.0035
    bevel.segments = 2
    bevel.limit_method = "ANGLE"
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.modifier_apply(modifier=bevel.name)
    for poly in mesh.polygons:
        poly.use_smooth = True
    obj.select_set(False)
    return obj


def build_body():
    parts = []
    # Clothing shell follows an anatomical shoulder/chest/waist/pelvis rhythm.
    torso = loft_object("Tunic_Body", "Indigo_Torso_QA", [
        (0.0, 0.018, 0.940, 0.166, 0.114),
        (0.0, 0.016, 1.030, 0.142, 0.102),
        (0.0, 0.012, 1.140, 0.130, 0.094),
        (0.0, 0.004, 1.275, 0.148, 0.108),
        (0.0, 0.000, 1.350, 0.198, 0.116),
        (0.0, 0.000, 1.410, 0.154, 0.096),
    ], segments=24)
    tag_all(torso, "TORSO_CENTER")
    parts.append(torso)

    # Ivory under-collar is a compact V opening; it deliberately ends above the sternum.
    inner = ribbon_object("Inner_V", "Moon_Ivory", [
        (0.000, -0.111, 1.402),
        (0.000, -0.121, 1.365),
        (0.000, -0.123, 1.330),
    ], [0.032, 0.035, 0.014], 0.005)
    parts.append(inner)

    # Two diagonal lapels overlap asymmetrically like wrapped cloth, not a necktie.
    left = ribbon_object("Cross_Lapel_Over", "Moon_Ivory", [
        (-0.052, -0.121, 1.400), (-0.034, -0.128, 1.370),
        (-0.008, -0.132, 1.340), (0.021, -0.130, 1.312),
        (0.043, -0.122, 1.292),
    ], [0.014, 0.015, 0.015, 0.013, 0.008], 0.005)
    right = ribbon_object("Cross_Lapel_Under", "Indigo_Light", [
        (0.052, -0.120, 1.398), (0.034, -0.127, 1.368),
        (0.010, -0.130, 1.340), (-0.010, -0.127, 1.316),
        (-0.026, -0.120, 1.299),
    ], [0.013, 0.014, 0.013, 0.010, 0.007], 0.0045)
    parts.extend([left, right])

    # A slim sash reinforces the waist instead of becoming a bulky belt tube.
    sash = loft_object("Layered_Sash", "Indigo_Shadow", [
        (0.0, 0.015, 1.025, 0.151, 0.109),
        (0.0, 0.015, 0.987, 0.156, 0.112),
        (0.0, 0.015, 0.952, 0.153, 0.109),
    ], segments=24)
    parts.append(sash)
    bm = bmesh.new()
    h.cube(bm, (0.0, -0.111, 0.987), (0.034, 0.016, 0.026))
    h.bevel(bm, 0.005, 3, only_sharp=False)
    parts.append(finish(bm, "Sash_Clasp", "Warm_Gold", True))

    # Restrained diagonal seam and shoulder embroidery gives scale without noisy texture.
    seam = ribbon_object("Front_Seam", "Indigo_Light", [
        (0.057, -0.110, 1.230), (0.078, -0.111, 1.165),
        (0.086, -0.110, 1.095), (0.075, -0.109, 1.035),
    ], [0.006, 0.005, 0.004, 0.003], 0.003)
    parts.append(seam)
    return parts


def build_panels():
    # Four principal panels only, each tied to one leg-side; center gap remains visible.
    return [
        wedge_panel("Front_Panel_L", "Indigo_Cloth", (-0.064, -0.082, 0.970), 0.090,
                    (-0.082, -0.145, 0.0), 0.132, 0.220, 0.008),
        wedge_panel("Front_Panel_R", "Indigo_Light", (0.066, -0.082, 0.968), 0.094,
                    (0.086, -0.142, 0.0), 0.128, 0.210, 0.008),
        wedge_panel("Back_Panel_L", "Indigo_Cloth", (-0.066, 0.082, 0.965), 0.094,
                    (-0.083, 0.138, 0.0), 0.126, 0.202, 0.008),
        wedge_panel("Back_Panel_R", "Indigo_Shadow", (0.066, 0.082, 0.962), 0.092,
                    (0.081, 0.136, 0.0), 0.123, 0.196, 0.008),
    ]


def build_arms():
    parts = []
    for side, tag in ((-1.0, "L"), (1.0, "R")):
        # Cloth sleeve has a shaped shoulder cap and deliberate elbow reduction.
        bm = bmesh.new()
        h.tube_axis(bm, (side * 0.172, 0.0, 1.350), (side * 0.445, 0.0, 1.350),
                    [(0.073, 0.078), (0.071, 0.075), (0.059, 0.063), (0.051, 0.055)], segments=16)
        h.tube_axis(bm, (side * 0.442, 0.0, 1.350), (side * 0.705, 0.0, 1.350),
                    [(0.052, 0.056), (0.049, 0.052), (0.043, 0.046), (0.038, 0.041)], segments=16)
        h.sphere(bm, (side * 0.190, 0.0, 1.350), 0.076, scale=(1.08, 0.97, 1.02), subdivisions=2)
        h.smooth(bm)
        sleeve = finish(bm, "Fitted_Sleeve_" + tag, "Indigo_Cloth", True)
        parts.append(sleeve)

        bm = bmesh.new()
        h.tube_axis(bm, (side * 0.662, 0.0, 1.350), (side * 0.710, 0.0, 1.350),
                    [(0.046, 0.049), (0.041, 0.044)], segments=14)
        parts.append(finish(bm, "Moon_Cuff_" + tag, "Moon_Ivory", True))

        # Palm/fingers read as one tapered hand; thumb stays clear for Mixamo orientation.
        bm = bmesh.new()
        h.tube_axis(bm, (side * 0.702, -0.002, 1.350), (side * 0.835, -0.006, 1.350),
                    [(0.034, 0.035), (0.037, 0.038), (0.029, 0.031), (0.018, 0.022)], segments=14)
        h.tube_axis(bm, (side * 0.758, -0.014, 1.339), (side * 0.799, -0.030, 1.311),
                    [(0.016, 0.018), (0.012, 0.013), (0.008, 0.009)], segments=9)
        h.smooth(bm)
        hand = finish(bm, "Hand_" + tag, "Skin_Warm", True)
        parts.append(hand)
    return parts


def build_legs():
    parts = []
    for side, tag in ((-1.0, "L"), (1.0, "R")):
        bm = bmesh.new()
        h.tube_z(bm, [
            (side * 0.087, 0.012, 0.955, 0.082, 0.080),
            (side * 0.088, 0.008, 0.840, 0.091, 0.086),
            (side * 0.091, 0.001, 0.665, 0.080, 0.075),
            (side * 0.092, -0.004, 0.535, 0.055, 0.055),
            (side * 0.094, 0.001, 0.430, 0.072, 0.075),
            (side * 0.094, 0.008, 0.285, 0.061, 0.065),
            (side * 0.093, 0.010, 0.165, 0.043, 0.047),
        ], segments=18)
        h.smooth(bm)
        parts.append(finish(bm, "Trouser_" + tag, "Indigo_Shadow", True))

        # Boot shaft follows ankle; elongated toe points toward authored front (-Y).
        bm = bmesh.new()
        h.tube_z(bm, [
            (side * 0.093, 0.006, 0.205, 0.053, 0.058),
            (side * 0.093, 0.002, 0.125, 0.057, 0.064),
            (side * 0.093, -0.015, 0.065, 0.061, 0.082),
        ], segments=16)
        h.sphere(bm, (side * 0.093, -0.044, 0.058), 0.064,
                 scale=(0.90, 1.20, 0.64), subdivisions=3)
        h.smooth(bm)
        heel = finish(bm, "Boot_Heel_" + tag, "Boot_Heel_QA", True)
        tag_all(heel, "HEEL_MARKER")
        parts.append(heel)
        bm = bmesh.new()
        # Soft upturned toe: 0.25m overall shoe length, tip lifted 11mm.
        h.sphere(bm, (side * 0.093, -0.124, 0.060), 0.056,
                 scale=(0.95, 1.14, 0.56), subdivisions=3)
        h.sphere(bm, (side * 0.093, -0.169, 0.069), 0.037,
                 scale=(0.92, 0.94, 0.50), subdivisions=3)
        h.smooth(bm)
        toe = finish(bm, "Boot_Toe_" + tag, "Boot_Toe_QA", True)
        tag_all(toe, "TOE_FRONT_MARKER")
        parts.append(toe)
    return parts


def build_head():
    parts = []
    # Neck is visible and narrow enough to keep the collar readable.
    bm = bmesh.new()
    h.tube_z(bm, [(0.0, 0.012, 1.395, 0.053, 0.050),
                  (0.0, 0.010, 1.475, 0.058, 0.054)], segments=18)
    h.smooth(bm)
    parts.append(finish(bm, "Neck", "Skin_Warm", True))

    bm = bmesh.new()
    h.sphere(bm, (0.0, 0.008, 1.578), 0.128, scale=(0.84, 0.77, 0.98), subdivisions=4)
    # Wider cheek plane with a narrower, shorter jaw gives a youthful heroic taper.
    h.sphere(bm, (0.0, -0.013, 1.535), 0.087, scale=(0.94, 0.76, 0.62), subdivisions=3)
    h.sphere(bm, (0.0, -0.014, 1.492), 0.056, scale=(0.72, 0.68, 0.48), subdivisions=2)
    h.smooth(bm)
    face = finish(bm, "Head_Face", "Skin_Head_QA", True)
    tag_all(face, "HEAD_CENTER")
    parts.append(face)

    # Hair mass sits behind the face; brow and nose remain on the -Y/front side.
    bm = bmesh.new()
    h.sphere(bm, (0.0, 0.030, 1.612), 0.132, scale=(0.88, 0.74, 0.82), subdivisions=4)
    h.smooth(bm)
    parts.append(finish(bm, "Hair_Crown", "Hair_Ink", True))

    # One continuous, rounded hairline. It has no outward-pointing forehead wedges.
    hair_x = (-0.072, -0.058, -0.032, 0.0, 0.032, 0.058, 0.072)
    hair_upper_z = (1.650, 1.672, 1.686, 1.691, 1.686, 1.672, 1.650)
    hair_lower_z = (1.650, 1.642, 1.649, 1.654, 1.649, 1.642, 1.650)
    hair_upper = [(x, -0.040 - 0.005 * (1.0 - abs(x) / 0.072), z)
                  for x, z in zip(hair_x, hair_upper_z)]
    hair_lower = [(x, -0.043 - 0.005 * (1.0 - abs(x) / 0.072), z)
                  for x, z in zip(hair_x, hair_lower_z)]
    parts.append(curved_band("Continuous_Hairline", "Hair_Ink", hair_upper, hair_lower, 0.006))
    for side, tag in ((-1.0, "L"), (1.0, "R")):
        bm = bmesh.new()
        h.tube_z(bm, [(side * 0.099, -0.001, 1.642, 0.017, 0.019),
                      (side * 0.100, -0.012, 1.570, 0.014, 0.017),
                      (side * 0.094, -0.014, 1.500, 0.010, 0.013)], segments=12)
        h.smooth(bm)
        parts.append(finish(bm, "Temple_Lock_" + tag, "Hair_Ink", True))

    # One flattened wrapped bun over a narrow root; no stacked ball/column silhouette.
    bm = bmesh.new()
    h.sphere(bm, (0.0, 0.043, 1.710), 0.068, scale=(1.05, 0.76, 0.52), subdivisions=3)
    h.smooth(bm)
    bun = finish(bm, "Hair_Topknot", "Hair_Bun_QA", True)
    tag_all(bun, "BUN_BACK_MARKER")
    parts.append(bun)
    bm = bmesh.new()
    h.tube_z(bm, [(0.0, 0.037, 1.668, 0.036, 0.032),
                  (0.0, 0.039, 1.686, 0.043, 0.036)], segments=16)
    parts.append(finish(bm, "Topknot_Binding", "Warm_Gold", True))
    # Two converging hair gathers visually feed the crown into the bound bun.
    for side, tag in ((-1.0, "L"), (1.0, "R")):
        parts.append(ribbon_object("Bun_Gather_" + tag, "Hair_Ink", [
            (side * 0.060, -0.020, 1.655),
            (side * 0.038, -0.008, 1.675),
            (side * 0.018, 0.012, 1.690),
        ], [0.010, 0.009, 0.006], 0.004))

    # Face details are shallow geometry so they survive untextured GLB/FBX previews.
    for side, tag in ((-1.0, "L"), (1.0, "R")):
        bm = bmesh.new()
        h.sphere(bm, (side * 0.038, -0.094, 1.578), 0.014,
                 scale=(1.42, 0.24, 0.38), subdivisions=3)
        parts.append(finish(bm, "Eye_White_" + tag, "Eye_White_QA", True))
        bm = bmesh.new()
        h.sphere(bm, (side * 0.038, -0.098, 1.578), 0.008,
                 scale=(0.48, 0.22, 0.60), subdivisions=2)
        eye = finish(bm, "Eye_Pupil_" + tag, "Eye_QA", True)
        tag_all(eye, "EYE_FRONT_MARKER")
        parts.append(eye)
        bm = bmesh.new()
        h.cube(bm, (side * 0.038, -0.099, 1.584), (0.031, 0.004, 0.0035),
               rot=(0.0, side * 0.010, side * 0.006))
        h.bevel(bm, 0.0015, 2, only_sharp=False)
        parts.append(finish(bm, "Upper_Lid_" + tag, "Face_Detail", True))
        bm = bmesh.new()
        h.cube(bm, (side * 0.038, -0.090, 1.605), (0.030, 0.005, 0.005),
               rot=(0.0, side * 0.025, side * 0.012))
        h.bevel(bm, 0.002, 2, only_sharp=False)
        parts.append(finish(bm, "Brow_" + tag, "Face_Detail", True))

    bm = bmesh.new()
    h.tube_z(bm, [
        (0.0, -0.086, 1.603, 0.0040, 0.0045),
        (0.0, -0.092, 1.583, 0.0048, 0.0052),
        (0.0, -0.099, 1.561, 0.0060, 0.0068),
        (0.0, -0.106, 1.546, 0.0105, 0.0100),
        (0.0, -0.104, 1.538, 0.0090, 0.0090),
    ], segments=14)
    nose = finish(bm, "Nose", "Skin_Nose_QA", True)
    tag_all(nose, "NOSE_FRONT_MARKER")
    parts.append(nose)
    bm = bmesh.new()
    h.sphere(bm, (0.0, -0.091, 1.522), 0.014, scale=(1.15, 0.25, 0.22), subdivisions=2)
    parts.append(finish(bm, "Mouth", "Mouth", True))
    return parts


def build_all():
    return build_body() + build_panels() + build_arms() + build_legs() + build_head()


def bounds(objects):
    return h.bounds(objects)


def export_single_mesh(parts):
    bpy.ops.object.select_all(action="DESELECT")
    copies = []
    for part in parts:
        copy = part.copy()
        copy.data = part.data.copy()
        bpy.context.collection.objects.link(copy)
        copy.select_set(True)
        copies.append(copy)
    bpy.context.view_layer.objects.active = copies[0]
    bpy.ops.object.join()
    upload = bpy.context.object
    upload.name = "Cultivator_Shortcoat_V2_TPose_FRONT_NEGATIVE_Y"
    for poly in upload.data.polygons:
        poly.use_smooth = True
    bpy.ops.export_scene.fbx(
        filepath=FBX,
        use_selection=True,
        object_types={"MESH"},
        apply_unit_scale=True,
        apply_scale_options="FBX_SCALE_NONE",
        bake_space_transform=False,
        axis_forward="-Z",
        axis_up="Y",
        add_leaf_bones=False,
        bake_anim=False,
        path_mode="AUTO",
    )
    bpy.data.objects.remove(upload, do_unlink=True)


def export_godot_glb(parts):
    """GLB branch rotates source -Y front to Blender +Y, which maps to Godot -Z."""
    bpy.ops.object.select_all(action="DESELECT")
    copies = []
    for part in parts:
        copy = part.copy()
        copy.data = part.data.copy()
        bpy.context.collection.objects.link(copy)
        for vertex in copy.data.vertices:
            vertex.co.x *= -1.0
            vertex.co.y *= -1.0
        copy.data.update()
        copies.append(copy)
    h.export_glb(copies, GLB)
    for copy in copies:
        bpy.data.objects.remove(copy, do_unlink=True)


def stage_build():
    ensure_dirs()
    h.reset_scene()
    materials()
    parts = build_all()
    # Geometry is authored directly in metres. Soles are normalized exactly to z=0.
    _, _, zr = bounds(parts)
    shift = -zr[0]
    for obj in parts:
        for vertex in obj.data.vertices:
            vertex.co.z += shift
        obj.data.update()

    export_godot_glb(parts)
    export_single_mesh(parts)
    bpy.context.preferences.filepaths.save_version = 0
    h.save_blend(BLEND)

    xr, yr, zr = bounds(parts)
    head_parts = [obj for obj in parts if obj.name in {"Head_Face", "Eye_L", "Eye_R", "Nose", "Mouth"}]
    _, _, head_z = bounds(head_parts)
    head_height = head_z[1] - head_z[0]
    body_top = max(v.co.z for obj in head_parts for v in obj.data.vertices)
    stats = {
        "generator": "tools/art/generate_cultivator_shortcoat_v2.py",
        "blender": bpy.app.version_string,
        "original_geometry": True,
        "third_party_assets": False,
        "source_objects": len(parts),
        "triangles": sum(h.tri_count(obj) for obj in parts),
        "body_height_to_cranium_m": round(body_top - zr[0], 4),
        "total_height_with_bun_m": round(zr[1] - zr[0], 4),
        "head_height_m": round(head_height, 4),
        "head_units": round((body_top - zr[0]) / head_height, 3),
        "arm_span_m": round(xr[1] - xr[0], 4),
        "depth_m": round(yr[1] - yr[0], 4),
        "soles_at_zero": abs(zr[0]) < 1e-6,
        "authored_front_axis_blender": "-Y",
        "fbx_axis_forward": "-Z",
        "fbx_axis_up": "Y",
        "static_t_pose": True,
        "rigged": False,
        "animations": 0,
        "outputs": {},
    }
    for path in (BLEND, GLB, FBX):
        stats["outputs"][os.path.basename(path)] = {
            "bytes": os.path.getsize(path), "sha256": sha256(path)
        }
    with open(MANIFEST, "w", encoding="utf-8") as handle:
        json.dump(stats, handle, ensure_ascii=False, indent=2)
        handle.write("\n")
    print("STATS " + json.dumps(stats, ensure_ascii=False))


def studio_setup():
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    scene.view_settings.view_transform = "AgX"
    scene.view_settings.look = "AgX - Medium High Contrast"
    scene.view_settings.exposure = -0.55
    world = scene.world or bpy.data.worlds.new("JadePaperStudio")
    scene.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.075, 0.090, 0.105, 1.0)
    world.node_tree.nodes["Background"].inputs[1].default_value = 0.24

    # Warm key, cool fill, narrow rim: readable cloth volume without glossy plastic.
    for name, location, color, energy, size in (
        ("Warm_Key", (-2.3, -3.1, 3.4), (1.0, 0.74, 0.48), 960.0, 3.2),
        ("Jade_Fill", (2.8, -1.8, 2.2), (0.48, 0.78, 0.82), 620.0, 4.0),
        ("Rim", (0.4, 3.2, 2.7), (0.58, 0.73, 1.0), 1050.0, 2.6),
    ):
        bpy.ops.object.light_add(type="AREA", location=location)
        light = bpy.context.object
        light.name = name
        light.data.color = color
        light.data.energy = energy
        light.data.size = size
        light.rotation_euler = (Vector((0.0, 0.0, 1.0)) - light.location).to_track_quat("-Z", "Y").to_euler()

    # Soft studio floor establishes contact and scale.
    bpy.ops.mesh.primitive_plane_add(size=8.0, location=(0.0, 0.0, -0.004))
    floor = bpy.context.object
    floor.name = "Preview_Floor"
    mat = bpy.data.materials.new("Preview_Floor_Mat")
    mat.diffuse_color = (0.055, 0.065, 0.075, 1.0)
    mat.roughness = 0.92
    floor.data.materials.append(mat)


SHOTS = {
    "front": ((0.0, -3.65, 1.05), (0.0, 0.0, 0.91), 2.05, (1100, 1200)),
    "three_quarter": ((-2.55, -3.05, 1.18), (0.0, 0.0, 0.94), 2.05, (1100, 1200)),
    "side": ((-3.65, 0.0, 1.05), (0.0, 0.0, 0.91), 2.05, (1100, 1200)),
    "back": ((0.0, 3.65, 1.05), (0.0, 0.0, 0.91), 2.05, (1100, 1200)),
}


def stage_preview():
    bpy.ops.wm.open_mainfile(filepath=BLEND, load_ui=False)
    studio_setup()
    scene = bpy.context.scene
    bpy.ops.object.camera_add()
    camera = bpy.context.object
    scene.camera = camera
    camera.data.type = "ORTHO"
    scene.render.resolution_percentage = 100
    written = []
    for name, (location, target, ortho_scale, resolution) in SHOTS.items():
        camera.location = location
        camera.data.ortho_scale = ortho_scale
        camera.rotation_euler = (Vector(target) - camera.location).to_track_quat("-Z", "Y").to_euler()
        scene.render.resolution_x, scene.render.resolution_y = resolution
        path = os.path.join(DOCS, "cultivator_shortcoat_v2_%s.png" % name)
        scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
        written.append(path)

    # A dedicated front-proof image has an in-frame, non-mirrored FRONT label and axis note.
    bpy.ops.object.text_add(location=(-0.72, -0.030, 1.770), rotation=(math.pi / 2, 0.0, 0.0))
    label = bpy.context.object
    label.name = "FRONT_Label"
    label.data.body = "FRONT  /  FACE = -Y"
    label.data.align_x = "LEFT"
    label.data.size = 0.075
    label.data.extrude = 0.0015
    label.data.materials.append(bpy.data.materials["Warm_Gold"])
    camera.location = (0.0, -3.65, 1.05)
    camera.data.ortho_scale = 2.05
    camera.rotation_euler = (Vector((0.0, 0.0, 0.91)) - camera.location).to_track_quat("-Z", "Y").to_euler()
    scene.render.resolution_x, scene.render.resolution_y = (1100, 1200)
    proof = os.path.join(DOCS, "cultivator_shortcoat_v2_FRONT_axis_proof.png")
    scene.render.filepath = proof
    bpy.ops.render.render(write_still=True)
    written.append(proof)

    # Two 2.5D readability distances, exactly matching the art review rubric.
    label.hide_render = True
    camera.location = (-4.5, -6.0, 4.0)
    camera.rotation_euler = (Vector((0.0, 0.0, 0.90)) - camera.location).to_track_quat("-Z", "Y").to_euler()
    scene.render.resolution_x, scene.render.resolution_y = (1280, 720)
    for size in (18.0, 6.0):
        camera.data.ortho_scale = size
        game = os.path.join(DOCS, "cultivator_shortcoat_v2_2p5d_size%d.png" % int(size))
        scene.render.filepath = game
        bpy.ops.render.render(write_still=True)
        written.append(game)

    # Neutral grey orthographic turntable isolates silhouette and cloth cut from palette appeal.
    grey = bpy.data.materials.new("Greybox_Review")
    grey.diffuse_color = (0.34, 0.36, 0.39, 1.0)
    grey.roughness = 0.82
    scene.view_layers[0].material_override = grey
    scene.render.resolution_x, scene.render.resolution_y = (1100, 1200)
    for name, (location, target, ortho_scale, _) in SHOTS.items():
        camera.location = location
        camera.data.ortho_scale = ortho_scale
        camera.rotation_euler = (Vector(target) - camera.location).to_track_quat("-Z", "Y").to_euler()
        grey_path = os.path.join(DOCS, "cultivator_shortcoat_v2_grey_%s.png" % name)
        scene.render.filepath = grey_path
        bpy.ops.render.render(write_still=True)
        written.append(grey_path)
    scene.view_layers[0].material_override = None

    with open(MANIFEST, "r", encoding="utf-8") as handle:
        manifest = json.load(handle)
    manifest["previews"] = {
        os.path.basename(path): {"bytes": os.path.getsize(path), "sha256": sha256(path)}
        for path in written
    }
    with open(MANIFEST, "w", encoding="utf-8") as handle:
        json.dump(manifest, handle, ensure_ascii=False, indent=2)
        handle.write("\n")
    print("PREVIEWS " + json.dumps(written, ensure_ascii=False))


def material_center(obj, material_name):
    slot_indices = {index for index, slot in enumerate(obj.material_slots)
                    if slot.material and slot.material.name == material_name}
    if not slot_indices:
        raise AssertionError("missing FBX semantic material " + material_name)
    vertex_indices = set()
    for polygon in obj.data.polygons:
        if polygon.material_index in slot_indices:
            vertex_indices.update(polygon.vertices)
    if not vertex_indices:
        raise AssertionError("empty FBX semantic material " + material_name)
    coords = [obj.matrix_world @ obj.data.vertices[index].co for index in vertex_indices]
    return sum(coords, Vector()) / len(coords)


def stage_audit():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=FBX)
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    armatures = [obj for obj in bpy.context.scene.objects if obj.type == "ARMATURE"]
    if len(meshes) != 1:
        raise AssertionError("Mixamo FBX must re-import as exactly one Mesh, got %d" % len(meshes))
    if armatures:
        raise AssertionError("Mixamo input must contain no Armature")
    obj = meshes[0]
    nose = material_center(obj, "Skin_Nose_QA")
    eyes = material_center(obj, "Eye_QA")
    toes = material_center(obj, "Boot_Toe_QA")
    heels = material_center(obj, "Boot_Heel_QA")
    torso = material_center(obj, "Indigo_Torso_QA")
    head = material_center(obj, "Skin_Head_QA")
    bun = material_center(obj, "Hair_Bun_QA")
    # Actual v1 upload faced away when its semantic face was +Y. v2 uses the opposite half-space.
    if not (nose.y < head.y - 0.015):
        raise AssertionError("nose marker is not on authored -Y front: %s vs %s" % (nose, head))
    if not (eyes.y < head.y - 0.005):
        raise AssertionError("eye marker is not on authored -Y front: %s vs %s" % (eyes, head))
    if not (toes.y < heels.y - 0.030):
        raise AssertionError("toe marker is not forward of heel: %s vs %s" % (toes, heels))
    if not (bun.y > head.y + 0.015):
        raise AssertionError("bun marker is not behind head: %s vs %s" % (bun, head))
    xr, yr, zr = h.bounds([obj])
    if not (1.65 <= zr[1] - zr[0] <= 1.90):
        raise AssertionError("FBX character height is invalid: %.4f" % (zr[1] - zr[0]))
    if abs(zr[0]) > 0.005 or abs((xr[0] + xr[1]) * 0.5) > 0.01:
        raise AssertionError("FBX ground/x-center contract failed")
    location, rotation, scale = obj.matrix_world.decompose()
    if location.length > 1e-5 or abs(rotation.angle) > 1e-5 or (scale - Vector((1, 1, 1))).length > 1e-5:
        raise AssertionError("FBX re-import matrix is not identity")
    if bpy.data.actions:
        raise AssertionError("Mixamo input FBX unexpectedly contains Actions")
    audit = {
        "fbx_reimport_meshes": 1,
        "fbx_reimport_armatures": 0,
        "vertices": len(obj.data.vertices),
        "polygons": len(obj.data.polygons),
        "materials": len(obj.data.materials),
        "actions": 0,
        "matrix_identity": True,
        "semantic_centers_blender_m": {
            "nose_front_marker": [round(v, 6) for v in nose],
            "eye_front_marker": [round(v, 6) for v in eyes],
            "toe_front_marker": [round(v, 6) for v in toes],
            "heel_marker": [round(v, 6) for v in heels],
            "torso_center": [round(v, 6) for v in torso],
            "head_center": [round(v, 6) for v in head],
            "bun_back_marker": [round(v, 6) for v in bun],
        },
        "front_axis_assertion": "PASS: nose/eyes are in front of head, toes in front of heels, bun behind head; authored front is Blender -Y",
        "mixamo_reasoning": "v1 was authored/exported facing +Y and Mixamo showed its back; v2 uses the opposite semantic facing (-Y)",
    }
    with open(MANIFEST, "r", encoding="utf-8") as handle:
        manifest = json.load(handle)
    manifest["fbx_reimport_audit"] = audit
    with open(MANIFEST, "w", encoding="utf-8") as handle:
        json.dump(manifest, handle, ensure_ascii=False, indent=2)
        handle.write("\n")
    print("AUDIT " + json.dumps(audit, ensure_ascii=False))

    # The upload check is rendered from the re-imported FBX, never from the GLB or source blend.
    materials()
    studio_setup()
    scene = bpy.context.scene
    bpy.ops.object.camera_add(location=(0.0, -3.65, 1.05))
    camera = bpy.context.object
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = 2.05
    camera.rotation_euler = (Vector((0.0, 0.0, 0.92)) - camera.location).to_track_quat("-Z", "Y").to_euler()
    scene.camera = camera
    scene.render.resolution_x, scene.render.resolution_y = (1100, 1200)
    path = os.path.join(DOCS, "cultivator_shortcoat_v2_upload_front_check.png")
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    with open(MANIFEST, "r", encoding="utf-8") as handle:
        manifest = json.load(handle)
    manifest["fbx_reimport_audit"]["upload_front_check"] = {
        "file": os.path.basename(path), "bytes": os.path.getsize(path), "sha256": sha256(path),
        "source": "clean FBX re-import"
    }
    with open(MANIFEST, "w", encoding="utf-8") as handle:
        json.dump(manifest, handle, ensure_ascii=False, indent=2)
        handle.write("\n")


STAGES = {"build": stage_build, "preview": stage_preview, "audit": stage_audit}


def main(argv):
    stages = [arg for arg in argv if arg in STAGES] or ["build"]
    for stage in stages:
        STAGES[stage]()


if __name__ == "__main__":
    main(sys.argv[1:])
