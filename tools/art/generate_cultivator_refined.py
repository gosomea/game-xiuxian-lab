"""Cultivator visual rebuild: natural-proportion stylized cultivator (Blender 5.2.1 LTS).

Deterministic background build from original procedural geometry. No downloads, no external
assets, no textures, no armature, no runtime animation data. Replaces the blocky cube body with
lofted torso, tapered limbs, an open-front layered robe, a visible face (front and profile) and
a hair cap that never covers the face. Same output path as before, so the old garden also benefits.

Run:
  /Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup \
      --python tools/art/generate_cultivator_refined.py -- build preview

Produces:
  docs/art/cultivator_refined/cultivator_refined.blend
  src/game/actors/swordsman/models/cultivator.glb
  docs/art/cultivator_refined/cultivator_front.png / _side.png / _three_quarter.png / _closeup.png
Prints one "STATS {...}" JSON line per stage to stdout.

Axes: Blender Z-up. Parts are authored facing Blender -Y, then normalize_orientation() rotates
every mesh 180 degrees about Z. glTF export_yup=True maps Blender (bx, by, bz) to glTF/Godot
(bx, bz, -by), so after that rotation the exported front is Blender +Y -> Godot -Z, matching
Swordsman._face_aim(). The render is deterministic but not identical to the Godot render. Soles
rest at Blender z=0 and every part keeps an identity matrix at the world origin. Target height
1.70 m, about 6.8 heads. stage_build() asserts the resulting axis contract and prints it.
"""
import json
import math
import os
import sys

import bmesh
import bpy
import mathutils
from mathutils import Vector

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DOCS = os.path.join(ROOT, "docs", "art", "cultivator_refined")
CHAR_GLB = os.path.join(ROOT, "src", "game", "actors", "swordsman", "models", "cultivator.glb")

TARGET_HEIGHT = 1.70

MATS = {}

# Ring angle convention (radians): 0 = +X (character left), pi/2 = +Y (back), -pi/2 = -Y (face).
FRONT = -math.pi / 2.0


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.unit_settings.system = "METRIC"
    bpy.context.scene.unit_settings.scale_length = 1.0


def ensure_dirs():
    for path in (DOCS, os.path.dirname(CHAR_GLB)):
        os.makedirs(path, exist_ok=True)


def make_mat(name, color, rough=0.62, metallic=0.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (color[0], color[1], color[2], 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metallic
    mat.diffuse_color = (color[0], color[1], color[2], 1.0)
    mat.roughness = rough
    mat.metallic = metallic
    MATS[name] = mat
    return mat


def get_mat(name):
    return MATS[name]


def build_materials():
    make_mat("Robe_Indigo", (0.086, 0.146, 0.246), rough=0.78)
    make_mat("Robe_Indigo_Dark", (0.050, 0.092, 0.160), rough=0.82)
    make_mat("Inner_Ivory", (0.760, 0.732, 0.664), rough=0.74)
    make_mat("Trim_Ivory", (0.700, 0.676, 0.600), rough=0.66)
    # Wood-gold: low metallic + high roughness keeps the sash from blowing out to pure white.
    make_mat("Sash_Wood_Gold", (0.430, 0.312, 0.126), rough=0.52, metallic=0.45)
    make_mat("Skin", (0.706, 0.542, 0.420), rough=0.66)
    make_mat("Hair_Black", (0.038, 0.038, 0.052), rough=0.55)
    make_mat("Shoe_Dark", (0.078, 0.074, 0.082), rough=0.68)


def _merge(bm, sub):
    mesh = bpy.data.meshes.new("_merge")
    sub.to_mesh(mesh)
    sub.free()
    bm.from_mesh(mesh)
    bpy.data.meshes.remove(mesh)


def _rot_matrix(rot):
    return (
        mathutils.Matrix.Rotation(rot[2], 4, "Z")
        @ mathutils.Matrix.Rotation(rot[1], 4, "Y")
        @ mathutils.Matrix.Rotation(rot[0], 4, "X")
    )


def loft(bm, sections, cap_start=True, cap_end=True, closed=True):
    """Bridge vertex rings into a tube; closed=False keeps an open shell (slit, hair cap)."""
    rings = [[bm.verts.new(co) for co in section] for section in sections]
    bm.verts.index_update()
    spans = len(rings[0]) if closed else len(rings[0]) - 1
    for a, b in zip(rings, rings[1:]):
        for i in range(spans):
            j = (i + 1) % len(a)
            bm.faces.new((a[i], a[j], b[j], b[i]))
    if closed:
        if cap_start:
            bm.faces.new(tuple(reversed(rings[0])))
        if cap_end:
            bm.faces.new(tuple(rings[-1]))
    return rings


def ellipse_ring(cx, cy, cz, rx, ry, segments=12, ripple=0.0, lobes=4):
    ring = []
    for i in range(segments):
        angle = 2.0 * math.pi * i / segments
        scale = 1.0 + ripple * math.cos(lobes * angle)
        ring.append((cx + math.cos(angle) * rx * scale, cy + math.sin(angle) * ry * scale, cz))
    return ring


def arc_ring(cx, cy, cz, rx, ry, segments, gap, ripple=0.0, lobes=4):
    """Ring open over a half-angle gap centred on the face (-Y)."""
    start = FRONT + gap
    end = FRONT + 2.0 * math.pi - gap
    ring = []
    for i in range(segments + 1):
        angle = start + (end - start) * i / segments
        scale = 1.0 + ripple * math.cos(lobes * angle)
        ring.append((cx + math.cos(angle) * rx * scale, cy + math.sin(angle) * ry * scale, cz))
    return ring


def normalize_orientation(objects, scale):
    """Scale to the target height and rotate 180 degrees about Z.

    Parts are authored facing Blender -Y. Rotating about Z turns them face Blender +Y, which
    glTF export_yup maps to Godot -Z (Swordsman._face_aim assumes the model's local front is
    -Z). This is the step that keeps nose and shoe toes on Godot -Z; dropping it silently
    mirrors the character, so stage_build() asserts the exported signs afterwards.
    """
    matrix = mathutils.Matrix.Rotation(math.pi, 4, "Z") @ mathutils.Matrix.Scale(scale, 4)
    for obj in objects:
        obj.data.transform(matrix)
        obj.data.update()


def tube_z(bm, sections, segments=12, cap_start=True, cap_end=True, closed=True, ripple=0.0,
           lobes=4, gap=0.0):
    rings = []
    for section in sections:
        cx, cy, cz, rx, ry = section
        if gap > 0.0:
            rings.append(arc_ring(cx, cy, cz, rx, ry, segments, gap, ripple=ripple, lobes=lobes))
        else:
            rings.append(ellipse_ring(cx, cy, cz, rx, ry, segments, ripple=ripple, lobes=lobes))
    return loft(bm, rings, cap_start, cap_end, closed=closed)


def tube_axis(bm, start, end, radii, segments=10, cap_start=True, cap_end=True):
    a = Vector(start)
    b = Vector(end)
    axis = (b - a).normalized()
    quat = Vector((0.0, 0.0, 1.0)).rotation_difference(axis)
    sections = []
    count = len(radii)
    for index, radius in enumerate(radii):
        t = index / max(count - 1, 1)
        center = a.lerp(b, t)
        ring = ellipse_ring(0.0, 0.0, 0.0, radius[0], radius[1], segments=segments)
        ring = [tuple(quat @ Vector(co)) for co in ring]
        sections.append([(co[0] + center.x, co[1] + center.y, co[2] + center.z) for co in ring])
    return loft(bm, sections, cap_start, cap_end)


def cylinder(bm, center, radius, depth, segments=12, rot=(0.0, 0.0, 0.0)):
    sub = bmesh.new()
    bmesh.ops.create_cone(sub, cap_ends=True, cap_tris=False, segments=segments,
                          radius1=radius, radius2=radius, depth=depth)
    if any(rot):
        bmesh.ops.transform(sub, matrix=_rot_matrix(rot), verts=sub.verts)
    bmesh.ops.translate(sub, vec=Vector(center), verts=sub.verts)
    _merge(bm, sub)


def cone(bm, center, r1, r2, depth, segments=12, rot=(0.0, 0.0, 0.0), cap=True):
    sub = bmesh.new()
    bmesh.ops.create_cone(sub, cap_ends=cap, cap_tris=False, segments=segments,
                          radius1=r1, radius2=r2, depth=depth)
    if any(rot):
        bmesh.ops.transform(sub, matrix=_rot_matrix(rot), verts=sub.verts)
    bmesh.ops.translate(sub, vec=Vector(center), verts=sub.verts)
    _merge(bm, sub)


def sphere(bm, center, radius, scale=(1.0, 1.0, 1.0), subdivisions=2):
    sub = bmesh.new()
    bmesh.ops.create_icosphere(sub, subdivisions=subdivisions, radius=radius)
    bmesh.ops.scale(sub, vec=Vector(scale), verts=sub.verts)
    bmesh.ops.translate(sub, vec=Vector(center), verts=sub.verts)
    _merge(bm, sub)


def cube(bm, center, size, rot=(0.0, 0.0, 0.0)):
    sub = bmesh.new()
    bmesh.ops.create_cube(sub, size=1.0)
    bmesh.ops.scale(sub, vec=Vector(size), verts=sub.verts)
    if any(rot):
        bmesh.ops.transform(sub, matrix=_rot_matrix(rot), verts=sub.verts)
    bmesh.ops.translate(sub, vec=Vector(center), verts=sub.verts)
    _merge(bm, sub)


def bevel(bm, offset=0.010, segments=2, only_sharp=True, angle=math.radians(38.0)):
    if only_sharp:
        edges = [e for e in bm.edges if e.is_manifold and e.calc_face_angle(0.0) > angle]
    else:
        edges = [e for e in bm.edges if e.is_manifold]
    if edges:
        bmesh.ops.bevel(bm, geom=edges, offset=offset, offset_type="OFFSET",
                        segments=segments, profile=0.5, affect="EDGES", clamp_overlap=True)


def solidify(bm, thickness):
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bmesh.ops.solidify(bm, geom=list(bm.faces), thickness=thickness)


def smooth(bm):
    for face in bm.faces:
        face.smooth = True


def mark_sharp(bm, angle=math.radians(46.0)):
    """Mark creased edges sharp so smooth shading gives curved surfaces with crisp folds.

    glTF exports the resulting split normals, so Godot sees the same shading as the preview.
    """
    for edge in bm.edges:
        if len(edge.link_faces) == 2 and edge.calc_face_angle(0.0) > angle:
            edge.smooth = False


def finish(bm, name, mat_name, smooth_faces=False):
    if smooth_faces:
        mark_sharp(bm)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new(name + "_mesh")
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    obj.data.materials.append(get_mat(mat_name))
    bpy.context.collection.objects.link(obj)
    if smooth_faces:
        for polygon in mesh.polygons:
            polygon.use_smooth = True
    return obj

# ---------------------------------------------------------------- body landmarks
# Metres; front is -Y, soles at z=0. Head unit ~0.25 m => about 6.8 heads at 1.70 m.
HIP_Z = 0.96
CHEST_Z = 1.26
SHOULDER_Z = 1.40
NECK_Z = 1.46
HEAD_CENTER_Z = 1.575


# Torso profile shared by the robe body and the collar bands, so the collar lies ON the chest.
TORSO_SECTIONS = [
    (0.0, 0.0, SHOULDER_Z + 0.030, 0.118, 0.092),
    (0.0, 0.0, SHOULDER_Z + 0.006, 0.146, 0.108),
    (0.0, 0.002, SHOULDER_Z - 0.050, 0.158, 0.118),
    (0.0, 0.006, CHEST_Z, 0.150, 0.116),
    (0.0, 0.008, HIP_Z + 0.090, 0.130, 0.106),
    (0.0, 0.008, HIP_Z + 0.010, 0.138, 0.114),
]


def interp_profile(sections, z):
    """Interpolate a (cx, cy, z, rx, ry) section table at height z.

    The table is sorted here rather than assumed sorted: TORSO_SECTIONS is authored top-down
    while HEAD_SECTIONS is authored bottom-up. An order assumption previously made this return
    the shoulder profile for every height, which buried the collar inside the chest.
    """
    ordered = sorted(sections, key=lambda section: section[2])
    if z <= ordered[0][2]:
        return ordered[0][:2] + (ordered[0][3], ordered[0][4])
    if z >= ordered[-1][2]:
        return ordered[-1][:2] + (ordered[-1][3], ordered[-1][4])
    for lower, upper in zip(ordered, ordered[1:]):
        if lower[2] <= z <= upper[2]:
            span = upper[2] - lower[2]
            t = 0.0 if abs(span) < 1e-9 else (z - lower[2]) / span
            return (
                lower[0] + (upper[0] - lower[0]) * t,
                lower[1] + (upper[1] - lower[1]) * t,
                lower[3] + (upper[3] - lower[3]) * t,
                lower[4] + (upper[4] - lower[4]) * t,
            )
    return ordered[-1][:2] + (ordered[-1][3], ordered[-1][4])


def torso_radii(z):
    """Interpolated torso profile at height z: returns (cx, cy, rx, ry)."""
    return interp_profile(TORSO_SECTIONS, z)


def torso_surface_point(z, angle, outward=0.0):
    """Point on the torso ellipse at height z and ring angle (radians), lifted outward."""
    cx, cy, rx, ry = torso_radii(z)
    return (cx + math.cos(angle) * (rx + outward), cy + math.sin(angle) * (ry + outward), z)


def build_upper_robe():
    """Closed loft shoulders -> hips: chest, waist taper; no cube silhouette."""
    bm = bmesh.new()
    tube_z(bm, TORSO_SECTIONS, segments=20)
    smooth(bm)
    return finish(bm, "Robe_Upper", "Robe_Indigo", smooth_faces=True)


def build_skirt():
    """Open-front A-line skirt: two front panels, never a closed cone bucket.

    Open over FRONT_GAP around -Y and solidified for cloth thickness; the hem radius ripples so
    the silhouette reads as folds. The slit exposes the ivory inner skirt and both legs.
    """
    bm = bmesh.new()
    tube_z(bm, SKIRT_SECTIONS, segments=22, closed=False, ripple=0.018, lobes=6, gap=0.30)
    solidify(bm, 0.014)
    smooth(bm)
    return finish(bm, "Robe_Skirt", "Robe_Indigo", smooth_faces=True)


# Skirt profile shared by the skirt shell and its panel ridges, so nothing floats.
SKIRT_SECTIONS = [
    (0.0, 0.006, HIP_Z + 0.020, 0.138, 0.118),
    (0.0, 0.006, HIP_Z - 0.120, 0.150, 0.136),
    (0.0, 0.004, HIP_Z - 0.280, 0.168, 0.158),
    (0.0, 0.002, 0.520, 0.188, 0.180),
    (0.0, 0.000, 0.400, 0.204, 0.196),
    (0.0, -0.002, 0.300, 0.214, 0.206),
    (0.0, -0.004, 0.235, 0.216, 0.208),
]


def build_robe_panels():
    """Two narrow dark ridges down the robe front, lofted along the skirt surface.

    Each ridge rides the skirt ellipse at a fixed angle offset with a small radial lift, so it
    reads as fabric panelling (衣襟分片) at every height instead of a floating slab.
    """
    bm = bmesh.new()
    for side in (-1.0, 1.0):
        strip = []
        for (cx, cy, cz, rx, ry) in SKIRT_SECTIONS:
            lift = 1.035
            angle = FRONT + side * 0.34
            strip.append([(cx + math.cos(angle) * rx * lift, cy + math.sin(angle) * ry * lift, cz),
                          (cx + math.cos(angle) * (rx * lift + 0.012), cy + math.sin(angle) * (ry * lift + 0.012), cz)])
        loft(bm, strip, cap_start=True, cap_end=True, closed=False)
        bm.faces.ensure_lookup_table()
    solidify(bm, 0.008)
    smooth(bm)
    return finish(bm, "Robe_Panel", "Robe_Indigo_Dark", smooth_faces=True)


def build_hem_band():
    """Dark band along the hem lip: layered cloth instead of a flat plate edge."""
    bm = bmesh.new()
    sections = [
        (0.0, -0.001, 0.318, 0.215, 0.207),
        (0.0, -0.004, 0.268, 0.216, 0.208),
        (0.0, -0.005, 0.235, 0.216, 0.208),
    ]
    tube_z(bm, sections, segments=22, closed=False, ripple=0.018, lobes=6, gap=0.30)
    solidify(bm, 0.010)
    return finish(bm, "Robe_HemBand", "Robe_Indigo_Dark", smooth_faces=True)


def build_inner_robe():
    """Ivory chest panel plus inner skirt: visible through the slit, covers the legs."""
    bm = bmesh.new()
    # Chest filler under the outer-robe slit: a narrow strip riding the torso surface.
    panel = []
    for index in range(7):
        t = index / 6.0
        z = 1.386 - t * 0.156
        y = torso_surface_point(z, FRONT, 0.014)[1]
        panel.append([(-0.018, y, z), (0.018, y, z)])
    loft(bm, panel, cap_start=True, cap_end=True, closed=False)
    tube_z(bm, [
        (0.0, 0.0, HIP_Z + 0.040, 0.128, 0.118),
        (0.0, -0.002, 0.700, 0.140, 0.134),
        (0.0, -0.004, 0.480, 0.144, 0.142),
        (0.0, -0.006, 0.340, 0.138, 0.140),
        (0.0, -0.008, 0.245, 0.130, 0.134),
    ], segments=16)
    smooth(bm)
    return finish(bm, "Robe_Inner", "Inner_Ivory", smooth_faces=True)


def build_collar():
    """Cross collar (交领): two ivory bands lofted ON the torso surface, crossing at the sternum.

    Each band is a narrow strip that walks the torso ellipse from the shoulder down to the
    centre front, so it curves with the chest instead of jutting out as a flat white slab.
    """
    bm = bmesh.new()
    for side in (-1.0, 1.0):
        strip = []
        for index in range(10):
            t = index / 9.0
            # Short V from the collarbone to the sternum: a collar, not a chest bib.
            z = 1.392 - t * 0.150
            angle_span = 0.60 - t * 0.50
            angle = FRONT + side * angle_span
            half_width = 0.036 - t * 0.018
            cx, cy, rx, ry = torso_radii(z)
            inner_angle = angle - side * half_width / max(rx, 1e-6)
            outer_angle = angle + side * half_width / max(rx, 1e-6)
            # Lift is generous: measured on the exported GLB (assert_collar_proud) the band
            # must clear the robe shell, or it renders buried inside the chest.
            strip.append([
                (cx + math.cos(inner_angle) * (rx + 0.019), cy + math.sin(inner_angle) * (ry + 0.019), z),
                (cx + math.cos(outer_angle) * (rx + 0.027), cy + math.sin(outer_angle) * (ry + 0.027), z),
            ])
        loft(bm, strip, cap_start=True, cap_end=True, closed=False)
    # Back collar band: same lofted treatment, hugging the nape.
    back_strip = []
    for index in range(9):
        t = index / 8.0
        angle = FRONT + math.pi + (t - 0.5) * 1.10
        z = 1.362
        cx, cy, rx, ry = torso_radii(z)
        back_strip.append([
            (cx + math.cos(angle) * (rx + 0.016), cy + math.sin(angle) * (ry + 0.016), z - 0.034),
            (cx + math.cos(angle) * (rx + 0.024), cy + math.sin(angle) * (ry + 0.024), z + 0.034),
        ])
    loft(bm, back_strip, cap_start=True, cap_end=True, closed=False)
    solidify(bm, 0.004)
    smooth(bm)
    return finish(bm, "Robe_Collar", "Trim_Ivory", smooth_faces=True)


def build_sash():
    """Wood-gold belt fitted to the waist ellipse, with a knot and a hanging tail."""
    bm = bmesh.new()
    tube_z(bm, [
        (0.0, 0.007, HIP_Z + 0.070, 0.148, 0.126),
        (0.0, 0.007, HIP_Z + 0.020, 0.158, 0.134),
        (0.0, 0.006, HIP_Z - 0.045, 0.154, 0.132),
    ], segments=18)
    cube(bm, (0.0, -0.124, HIP_Z - 0.010), (0.076, 0.030, 0.066))
    cube(bm, (0.0, -0.122, HIP_Z - 0.130), (0.042, 0.020, 0.190))
    bevel(bm, 0.004, 1, only_sharp=False)
    return finish(bm, "Robe_Sash", "Sash_Wood_Gold", smooth_faces=True)


def build_arms_and_sleeves():
    """Upper arm, forearm, wide hanging sleeve with a real opening, cuff and hand."""
    parts = []
    for side, tag in ((-1.0, "L"), (1.0, "R")):
        shoulder = (side * 0.140, 0.0, SHOULDER_Z)
        elbow = (side * 0.184, -0.012, 1.090)
        wrist = (side * 0.198, -0.032, 0.885)

        # One continuous arm+sleeve loft: shoulder dome, upper arm, forearm and hanging
        # sleeve are the same surface. Separate pieces only overlapped and left seams/notches
        # where their caps met; the single shell has no interior boundary to break.
        bm = bmesh.new()
        arm = [
            (side * 0.112, 0.002, SHOULDER_Z + 0.030, 0.026, 0.032),
            (side * 0.130, 0.001, SHOULDER_Z + 0.006, 0.050, 0.058),
            (side * 0.146, 0.0, SHOULDER_Z - 0.036, 0.060, 0.068),
            (side * 0.154, -0.008, 1.248, 0.068, 0.078),
            (side * 0.162, -0.018, 1.068, 0.080, 0.094),
            (side * 0.170, -0.026, 0.908, 0.085, 0.099),
            (side * 0.174, -0.032, 0.842, 0.080, 0.094),
        ]
        tube_z(bm, arm, segments=18)
        smooth(bm)
        parts.append(finish(bm, "Arm_Sleeve_" + tag, "Robe_Indigo", smooth_faces=True))

        bm = bmesh.new()
        tube_z(bm, [
            (side * 0.174, -0.032, 0.852, 0.046, 0.052),
            (side * 0.176, -0.034, 0.826, 0.044, 0.050),
        ], segments=12)
        parts.append(finish(bm, "Cuff_" + tag, "Sash_Wood_Gold", smooth_faces=True))

        bm = bmesh.new()
        sphere(bm, (side * 0.176, -0.038, 0.788), 0.044, scale=(0.92, 0.72, 1.15), subdivisions=2)
        smooth(bm)
        parts.append(finish(bm, "Hand_" + tag, "Skin", smooth_faces=True))
    return parts


def build_legs_and_feet():
    """Tapered legs in ivory trousers; shoes with rounded toes, both soles on z=0."""
    parts = []
    for side, tag in ((-1.0, "L"), (1.0, "R")):
        bm = bmesh.new()
        tube_axis(bm, (side * 0.074, 0.004, 0.024), (side * 0.084, 0.0, 0.700),
                  [(0.068, 0.064), (0.060, 0.060), (0.052, 0.055)], segments=10)
        smooth(bm)
        parts.append(finish(bm, "Leg_" + tag, "Inner_Ivory", smooth_faces=True))

        bm = bmesh.new()
        cube(bm, (side * 0.084, -0.030, 0.032), (0.112, 0.224, 0.064))
        sphere(bm, (side * 0.084, -0.112, 0.034), 0.058, scale=(0.96, 0.62, 0.55), subdivisions=2)
        bevel(bm, 0.010, 2)
        parts.append(finish(bm, "Foot_" + tag, "Shoe_Dark", smooth_faces=True))
    return parts


# Head profile (rx, ry per height) shared by the skull and by feature placement, so the
# eyes/brows/nose/ears sit on the real surface instead of floating in front of it.
HEAD_SECTIONS = [
    (0.0, 0.010, HEAD_CENTER_Z - 0.166, 0.042, 0.056),
    (0.0, 0.012, HEAD_CENTER_Z - 0.130, 0.056, 0.076),
    (0.0, 0.010, HEAD_CENTER_Z - 0.084, 0.068, 0.090),
    (0.0, 0.004, HEAD_CENTER_Z - 0.022, 0.078, 0.098),
    (0.0, 0.0, HEAD_CENTER_Z + 0.044, 0.081, 0.098),
    (0.0, -0.002, HEAD_CENTER_Z + 0.096, 0.074, 0.089),
    (0.0, -0.002, HEAD_CENTER_Z + 0.120, 0.036, 0.050),
]


def head_radii(z):
    """Interpolated head profile at height z: returns (cx, cy, rx, ry)."""
    return interp_profile(HEAD_SECTIONS, z)


def face_surface_y(x, z, outward=0.0):
    """Front (-Y) surface of the head at (x, z); outward > 0 lifts a feature off the face."""
    _, cy, rx, ry = head_radii(z)
    ratio = min(1.0, abs(x) / max(rx, 1e-6))
    return cy - ry * math.sqrt(max(0.0, 1.0 - ratio * ratio)) - outward


def build_head():
    """Neck + skull + nose + ears + brow ridge + eyes: readable front and profile."""
    parts = []
    bm = bmesh.new()
    tube_z(bm, [
        (0.0, 0.006, NECK_Z - 0.055, 0.046, 0.048),
        (0.0, 0.006, NECK_Z + 0.020, 0.044, 0.046),
    ], segments=12)
    sections = HEAD_SECTIONS
    tube_z(bm, sections, segments=20)
    # Nose lives in its own object: the axis contract is asserted on Face_Nose vs Head.
    nose = bmesh.new()
    cone(nose, (0.0, face_surface_y(0.0, HEAD_CENTER_Z - 0.036, 0.004), HEAD_CENTER_Z - 0.036),
         0.016, 0.004, 0.034, segments=6, rot=(math.radians(90.0), 0.0, 0.0))
    smooth(nose)
    for side in (-1.0, 1.0):
        _, _, ear_rx, _ = head_radii(HEAD_CENTER_Z - 0.028)
        sphere(bm, (side * (ear_rx - 0.004), 0.010, HEAD_CENTER_Z - 0.028), 0.014,
               scale=(0.42, 0.72, 1.0), subdivisions=1)
    smooth(bm)
    parts.append(finish(nose, "Face_Nose", "Skin", smooth_faces=True))
    parts.append(finish(bm, "Head", "Skin", smooth_faces=True))

    # Eye: flat lens sitting on the face surface (never a floating bead).
    bm = bmesh.new()
    eye_z = HEAD_CENTER_Z - 0.018
    for side in (-1.0, 1.0):
        eye_x = side * 0.028
        sphere(bm, (eye_x, face_surface_y(eye_x, eye_z, 0.0015), eye_z), 0.011,
               scale=(1.35, 0.34, 0.55), subdivisions=1)
    parts.append(finish(bm, "Face_Eyes", "Hair_Black", smooth_faces=True))

    # Brow: thin slab resting on the surface just above each eye.
    bm = bmesh.new()
    brow_z = HEAD_CENTER_Z + 0.022
    for side in (-1.0, 1.0):
        brow_x = side * 0.030
        cube(bm, (brow_x, face_surface_y(brow_x, brow_z, 0.001), brow_z), (0.038, 0.007, 0.007),
             rot=(0.0, side * math.radians(-10.0), 0.0))
    parts.append(finish(bm, "Face_Brows", "Hair_Black", smooth_faces=True))
    return parts


def build_hair():
    """Hair as an open cap: covers top/back/sides, stops at the hairline, never the face.

    FRONT_GAP is far wider than the robe slit, so front shows forehead, brows, eyes and nose
    and the profile shows the hairline; the topknot sits on the crown, slightly back.
    """
    parts = []
    bm = bmesh.new()
    # Shell offset off the real head profile; the front gap shrinks with height so the
    # hairline rises from the temples to a covered crown instead of a flat cap edge.
    cap_bottom = HEAD_CENTER_Z - 0.116
    cap_top = HEAD_CENTER_Z + 0.136
    rings = 10
    segments = 26
    sections = []
    for index in range(rings):
        t = index / (rings - 1)
        z = cap_bottom + (cap_top - cap_bottom) * t
        sample = min(z, HEAD_CENTER_Z + 0.118)
        cx, cy, rx, ry = head_radii(sample)
        if z > HEAD_CENTER_Z + 0.118:
            shrink = 1.0 - (z - (HEAD_CENTER_Z + 0.118)) / 0.026
            rx *= max(0.30, shrink)
            ry *= max(0.30, shrink)
        gap = 0.98 * (1.0 - t) ** 0.55 + 0.07
        sections.append((cx, cy + 0.006, z, rx + 0.008, ry + 0.008, gap))
    rings_built = []
    for (cx, cy, cz, rx, ry, gap) in sections:
        rings_built.append(arc_ring(cx, cy, cz, rx, ry, segments, gap))
    loft(bm, rings_built, cap_start=False, cap_end=False, closed=False)
    solidify(bm, 0.009)
    smooth(bm)
    parts.append(finish(bm, "Hair_Cap", "Hair_Black", smooth_faces=True))

    bm = bmesh.new()
    bun_z = HEAD_CENTER_Z + 0.150
    sphere(bm, (0.0, 0.034, bun_z), 0.050, scale=(1.0, 1.0, 0.94), subdivisions=2)
    cylinder(bm, (0.0, 0.034, bun_z + 0.046), 0.013, 0.030, segments=10)
    smooth(bm)
    parts.append(finish(bm, "Hair_Bun", "Hair_Black", smooth_faces=True))
    return parts


def build_all():
    return [
        build_upper_robe(),
        build_skirt(),
        build_robe_panels(),
        build_hem_band(),
        build_inner_robe(),
        build_collar(),
        build_sash(),
        *build_arms_and_sleeves(),
        *build_legs_and_feet(),
        *build_head(),
        *build_hair(),
    ]

# ---------------------------------------------------------------- export / stats
def export_glb(objects, path):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True,
                              export_apply=False, export_yup=True, export_materials="EXPORT",
                              export_cameras=False, export_lights=False, export_animations=False,
                              export_texcoords=True, export_normals=True, export_extras=False)


def save_blend(path):
    bpy.ops.wm.save_as_mainfile(filepath=path, check_existing=False)


def bounds(objects):
    xs, ys, zs = [], [], []
    for obj in objects:
        for vert in obj.data.vertices:
            co = obj.matrix_world @ vert.co
            xs.append(co.x)
            ys.append(co.y)
            zs.append(co.z)
    return (min(xs), max(xs)), (min(ys), max(ys)), (min(zs), max(zs))


def tri_count(obj):
    obj.data.calc_loop_triangles()
    return len(obj.data.loop_triangles)


def glb_mesh_bounds(path, y_range=None):
    """Read a GLB and return {node_name: (min_xyz, max_xyz)} from its POSITION accessors.

    y_range=(lo, hi) restricts the measurement to vertices whose Godot +Y height is inside the
    window. That is how "collar sits proud of the robe" is checked: both objects are measured at
    the same height, instead of comparing a chest feature against a hem.

    The contract is asserted on the written file, not on in-memory bmesh state, so a dropped
    orientation step or a wrong exporter flag cannot pass silently.
    """
    import struct

    with open(path, "rb") as handle:
        data = handle.read()
    offset = 12
    gltf = None
    binary = None
    while offset < len(data):
        length, kind = struct.unpack_from("<II", data, offset)
        offset += 8
        chunk = data[offset:offset + length]
        offset += length
        if kind == 0x4E4F534A:
            gltf = json.loads(chunk)
        elif kind == 0x004E4942:
            binary = chunk
    if gltf is None or binary is None:
        raise RuntimeError("GLB chunk parse failed: " + path)

    result = {}
    for node in gltf["nodes"]:
        if "mesh" not in node:
            continue
        name = node.get("name", "?")
        bounds = result.setdefault(name, [[1e30] * 3, [-1e30] * 3])
        for primitive in gltf["meshes"][node["mesh"]]["primitives"]:
            accessor = gltf["accessors"][primitive["attributes"]["POSITION"]]
            view = gltf["bufferViews"][accessor["bufferView"]]
            start = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
            for index in range(accessor["count"]):
                x, y, z = struct.unpack_from("<fff", binary, start + index * 12)
                if y_range is not None and not (y_range[0] <= y <= y_range[1]):
                    continue
                for axis, value in enumerate((x, y, z)):
                    bounds[0][axis] = min(bounds[0][axis], value)
                    bounds[1][axis] = max(bounds[1][axis], value)
    return {name: (tuple(lo), tuple(hi)) for name, (lo, hi) in result.items()}


def assert_axis_contract(path):
    """Assert the written GLB faces Godot -Z and stands on y=0; return the measured signs."""
    bounds = glb_mesh_bounds(path)
    for required in ("Head", "Face_Nose", "Face_Eyes", "Foot_L", "Foot_R", "Hair_Bun"):
        if required not in bounds:
            raise AssertionError("axis contract: GLB is missing node " + required)
    head = bounds["Head"]
    nose = bounds["Face_Nose"]
    eyes = bounds["Face_Eyes"]
    foot = bounds["Foot_L"]
    bun = bounds["Hair_Bun"]
    head_z = (head[0][2] + head[1][2]) / 2.0
    nose_z = nose[0][2]
    eye_z = (eyes[0][2] + eyes[1][2]) / 2.0
    toe_z = foot[0][2]
    bun_z = (bun[0][2] + bun[1][2]) / 2.0
    if foot[0][1] < -1e-6:
        raise AssertionError("axis contract: soles below y=0 (y_min=%.4f)" % foot[0][1])
    if not (nose_z < head_z and eye_z < head_z):
        raise AssertionError(
            "axis contract: face must point at Godot -Z (head_z=%.4f nose_z=%.4f eye_z=%.4f)" % (head_z, nose_z, eye_z))
    if bun_z <= head_z:
        raise AssertionError("axis contract: topknot must sit behind the face (bun_z=%.4f)" % bun_z)
    # Collar and chest panel must clear the robe shell in their own height band, or they
    # render buried inside the chest. Measured on the written GLB, same window for every part.
    chest = (1.16, 1.40)
    in_band = glb_mesh_bounds(path, y_range=chest)
    collar_z = in_band["Robe_Collar"][0][2]
    inner_z = in_band["Robe_Inner"][0][2]
    robe_z = in_band["Robe_Upper"][0][2]
    if not (collar_z < robe_z - 0.002 and inner_z < robe_z - 0.002):
        raise AssertionError(
            "surface contract: collar/chest panel must sit proud of the robe in y%s "
            "(collar_z=%.4f inner_z=%.4f robe_z=%.4f)"
            % (str(chest), collar_z, inner_z, robe_z))
    print("SURFACE y%s collar_z=%+.4f inner_z=%+.4f robe_z=%+.4f | collar_proud=%s inner_proud=%s" % (
        str(chest), collar_z, inner_z, robe_z, collar_z < robe_z, inner_z < robe_z))
    print("AXIS gltf(Godot) | head_z=%+.4f nose_z=%+.4f eye_z=%+.4f toe_z=%+.4f bun_z=%+.4f | "
          "nose<0=%s toe<0=%s bun>head=%s" % (
              head_z, nose_z, eye_z, toe_z, bun_z, nose_z < 0.0, toe_z < 0.0, bun_z > head_z))
    return {"head_z": round(head_z, 4), "nose_z": round(nose_z, 4), "eye_z": round(eye_z, 4),
            "toe_z": round(toe_z, 4), "bun_z": round(bun_z, 4), "front_is_negative_z": nose_z < 0.0}


def stage_build():
    reset_scene()
    build_materials()
    parts = build_all()
    # Normalize on the body (skull top), not the topknot, so the reported height is the figure's.
    body = [obj for obj in parts if obj.name != "Hair_Bun"]
    (_, _, body_z) = bounds(body)
    scale = TARGET_HEIGHT / body_z[1]
    normalize_orientation(parts, scale)
    (x_range, y_range, z_range) = bounds(parts)
    (_, _, body_z) = bounds(body)
    (_, _, head_z) = bounds([obj for obj in parts if obj.name in ("Head", "Face_Eyes", "Face_Brows")])
    head_height = head_z[1] - head_z[0]
    tris = sum(tri_count(obj) for obj in parts)
    export_glb(parts, CHAR_GLB)
    save_blend(os.path.join(DOCS, "cultivator_refined.blend"))
    axis = assert_axis_contract(CHAR_GLB)
    stats = {
        "phase": "build",
        "objects": len(parts),
        "triangles": tris,
        "height_body_m": round(body_z[1], 4),
        "height_total_m": round(z_range[1], 4),
        "head_height_m": round(head_height, 4),
        "head_units": round(body_z[1] / head_height, 3),
        "x_min": round(x_range[0], 4), "x_max": round(x_range[1], 4),
        "y_min": round(y_range[0], 4), "y_max": round(y_range[1], 4),
        "z_min": round(z_range[0], 4), "z_max": round(z_range[1], 4),
        "soles_at_zero": abs(z_range[0]) < 1e-6,
        "axis": axis,
        "names": [obj.name for obj in parts],
        "glb": CHAR_GLB,
    }
    print("STATS " + json.dumps(stats))
    return stats


# ---------------------------------------------------------------- preview renders
# Cinematic-ish studio turnaround, 24 samples, denoised. Not a runtime asset.
# Cameras sit on the Blender +Y side: normalize_orientation() rotated the model 180 degrees
# about Z, so the authored -Y face now points at Blender +Y (which is Godot -Z).
PREVIEW_SHOTS = {
    "front": ((0.0, 3.30, 0.95), (0.0, 0.0, 0.92), 62.0, (700, 940)),
    "side": ((-3.20, 0.0, 0.95), (0.0, 0.0, 0.92), 62.0, (700, 940)),
    "three_quarter": ((-2.35, 2.35, 1.10), (0.0, 0.0, 0.90), 62.0, (700, 940)),
    "closeup": ((-1.00, 1.60, 1.52), (0.0, 0.0, 1.48), 70.0, (860, 860)),
}


def stage_preview():
    bpy.ops.wm.open_mainfile(filepath=os.path.join(DOCS, "cultivator_refined.blend"), load_ui=False)
    scene = bpy.context.scene
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 24
    scene.cycles.use_denoising = True
    scene.render.film_transparent = False

    world = scene.world or bpy.data.worlds.new("StudioWorld")
    scene.world = world
    world.use_nodes = True
    background = world.node_tree.nodes.get("Background")
    background.inputs[0].default_value = (0.62, 0.65, 0.70, 1.0)
    background.inputs[1].default_value = 0.40
    # Negative exposure keeps skin and gold below clipping under the studio key.
    scene.view_settings.exposure = -0.45

    for location, energy, size, target in (
        ((-1.7, -2.5, 3.0), 95.0, 3.4, (0.0, 0.0, 1.0)),
        ((2.9, -1.6, 1.9), 42.0, 4.5, (0.0, 0.0, 1.0)),
        ((0.6, 2.9, 2.3), 52.0, 3.2, (0.0, 0.0, 1.1)),
    ):
        bpy.ops.object.light_add(type="AREA", location=location)
        light = bpy.context.object
        light.data.energy = energy
        light.data.size = size
        light.rotation_euler = (Vector(target) - light.location).to_track_quat("-Z", "Y").to_euler()

    bpy.ops.object.camera_add()
    camera = bpy.context.object
    camera.data.type = "PERSP"
    scene.camera = camera
    scene.render.image_settings.file_format = "PNG"
    scene.render.resolution_percentage = 100

    written = []
    for name, shot in PREVIEW_SHOTS.items():
        location, target, lens, resolution = shot
        camera.location = location
        camera.data.lens = lens
        camera.rotation_euler = (Vector(target) - Vector(location)).to_track_quat("-Z", "Y").to_euler()
        scene.render.resolution_x = resolution[0]
        scene.render.resolution_y = resolution[1]
        scene.render.filepath = os.path.join(DOCS, "cultivator_%s.png" % name)
        bpy.ops.render.render(write_still=True)
        written.append(scene.render.filepath)
        print("PREVIEW %s" % scene.render.filepath)
    print("STATS " + json.dumps({"phase": "preview", "shots": written}))
    return 0


STAGES = {"build": stage_build, "preview": stage_preview}


def main(argv):
    stages = [arg for arg in argv if arg in STAGES] or ["build"]
    ensure_dirs()
    for stage in stages:
        STAGES[stage]()
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
