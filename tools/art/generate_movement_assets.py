"""movement_garden character asset: low-poly stylized cultivator (Blender 5.2.1 LTS).

Reproducible background build from original procedural geometry: no downloads,
no external assets, no textures, no armature, no animation. This script builds
ONLY the character; the courtyard comes from tools/art/generate_movement_garden.py.

Run:
  /Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup \
      --python tools/art/generate_movement_assets.py

Produces:
  docs/art/movement_garden/cultivator.blend
  src/game/actors/swordsman/models/cultivator.glb
Prints one "STATS {...}" JSON line to stdout; it writes no stats file.

Axes: Blender is Z-up. Parts are authored facing Blender -Y; orient_parts()
normalizes height and rotates 180 degrees about Z, so the exported front is
Blender +Y. The glTF export uses export_yup=True and Blender +Y maps to glTF
-Z, i.e. Godot -Z, matching Swordsman._face_aim().

Measured 2026-09-18 (Blender 5.2.1 LTS): 17 mesh objects, 5080 triangles,
7 materials, 1.70 m tall, soles at Blender z=0, object origins at the world
origin. Facts and checksums: docs/art/movement_garden/README.md.
"""
import json, math, os
from mathutils import Vector

import bmesh, bpy, mathutils

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DOCS = os.path.join(ROOT, "docs", "art", "movement_garden")
CHAR_GLB = os.path.join(ROOT, "src", "game", "actors", "swordsman", "models", "cultivator.glb")


def ensure_dirs():
    for p in (DOCS, os.path.dirname(CHAR_GLB)):
        os.makedirs(p, exist_ok=True)


def reset_scene():
    """Empty factory scene: no default cube, no camera, no light."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.unit_settings.system = "METRIC"
    bpy.context.scene.unit_settings.scale_length = 1.0


# ---------------------------------------------------------------- materials
MATS = {}


def make_mat(name, color, rough=0.62, metallic=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (color[0], color[1], color[2], 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metallic
    m.diffuse_color = (color[0], color[1], color[2], 1.0)
    m.roughness = rough
    m.metallic = metallic
    MATS[name] = m
    return m


def get_mat(name):
    if name not in MATS:
        raise KeyError("material not built yet: " + name)
    return MATS[name]


def build_materials():
    make_mat("Robe_Blue", (0.106, 0.190, 0.290), rough=0.72)
    make_mat("Inner_Ivory", (0.902, 0.867, 0.765), rough=0.70)
    make_mat("Trim_Ivory", (0.847, 0.816, 0.714), rough=0.55)
    make_mat("Sash_Teal", (0.086, 0.310, 0.322), rough=0.60)
    make_mat("Metal_Gold", (0.760, 0.575, 0.220), rough=0.34, metallic=0.85)
    make_mat("Skin", (0.878, 0.706, 0.580), rough=0.58)
    make_mat("Hair_Black", (0.048, 0.048, 0.064), rough=0.45)


# ---------------------------------------------------------------- mesh helpers
def orient_parts(parts, target_height):
    """Normalize height (feet stay at z=0) and rotate 180 degrees about Z.

    Parts are authored facing Blender -Y; after this rotation the front is
    Blender +Y. glTF export_yup maps Blender +Y to glTF -Z, so the exported
    character front is Godot -Z (Swordsman._face_aim assumes local -Z).
    Mesh data is transformed; every object keeps an identity matrix at world origin.
    """
    zs = [v.co.z for o in parts for v in o.data.vertices]
    scale = target_height / (max(zs) - min(zs))
    rot = mathutils.Matrix.Rotation(math.pi, 4, "Z") @ mathutils.Matrix.Scale(scale, 4)
    for o in parts:
        o.data.transform(rot)
        o.data.update()
    return scale


def box(bm, center, size, rot=(0.0, 0.0, 0.0)):
    b = bmesh.new()
    bmesh.ops.create_cube(b, size=1.0)
    bmesh.ops.scale(b, vec=Vector(size), verts=b.verts)
    if any(rot):
        m = mathutils.Matrix.Rotation(rot[2], 4, "Z") @ mathutils.Matrix.Rotation(rot[1], 4, "Y") @ mathutils.Matrix.Rotation(rot[0], 4, "X")
        bmesh.ops.transform(b, matrix=m, verts=b.verts)
    bmesh.ops.translate(b, vec=Vector(center), verts=b.verts)
    me = bpy.data.meshes.new("_b")
    b.to_mesh(me)
    b.free()
    bm.from_mesh(me)
    bpy.data.meshes.remove(me)


def cone(bm, center, r1, r2, depth, segments=10, rot=(0.0, 0.0, 0.0), cap=True):
    b = bmesh.new()
    bmesh.ops.create_cone(b, cap_ends=cap, cap_tris=False, segments=segments,
                          radius1=r1, radius2=r2, depth=depth)
    if any(rot):
        m = mathutils.Matrix.Rotation(rot[2], 4, "Z") @ mathutils.Matrix.Rotation(rot[1], 4, "Y") @ mathutils.Matrix.Rotation(rot[0], 4, "X")
        bmesh.ops.transform(b, matrix=m, verts=b.verts)
    bmesh.ops.translate(b, vec=Vector(center), verts=b.verts)
    me = bpy.data.meshes.new("_c")
    b.to_mesh(me)
    b.free()
    bm.from_mesh(me)
    bpy.data.meshes.remove(me)


def sphere(bm, center, radius, scale=(1.0, 1.0, 1.0), subdivisions=2):
    b = bmesh.new()
    bmesh.ops.create_icosphere(b, subdivisions=subdivisions, radius=radius)
    bmesh.ops.scale(b, vec=Vector(scale), verts=b.verts)
    bmesh.ops.translate(b, vec=Vector(center), verts=b.verts)
    me = bpy.data.meshes.new("_s")
    b.to_mesh(me)
    b.free()
    bm.from_mesh(me)
    bpy.data.meshes.remove(me)


def bevel_bm(bm, offset=0.012, segments=2, only_sharp=True, angle=math.radians(35.0)):
    if only_sharp:
        edges = [e for e in bm.edges if e.is_manifold and e.calc_face_angle(0.0) > angle]
    else:
        edges = [e for e in bm.edges if e.is_manifold]
    if not edges:
        return
    bmesh.ops.bevel(bm, geom=edges, offset=offset, offset_type="OFFSET",
                    segments=segments, profile=0.5, affect="EDGES", clamp_overlap=True)


def finish_object(bm, name, mat_name, smooth=False):
    me = bpy.data.meshes.new(name + "_mesh")
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    ob.data.materials.append(get_mat(mat_name))
    bpy.context.collection.objects.link(ob)
    if smooth:
        smooth_geom_faces(me)
    return ob


def smooth_geom_faces(me):
    for p in me.polygons:
        p.use_smooth = True


def tri_count(ob):
    ob.data.calc_loop_triangles()
    return len(ob.data.loop_triangles)


def export_glb(objs, path):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True,
                              export_apply=False, export_yup=True, export_materials="EXPORT",
                              export_cameras=False, export_lights=False, export_animations=False,
                              export_texcoords=True, export_normals=True, export_extras=False)


def save_blend(path):
    bpy.ops.wm.save_as_mainfile(filepath=path, check_existing=False)


# ---------------------------------------------------------------- cultivator
def build_cultivator():
    parts = []
    robe = bmesh.new()
    box(robe, (0.0, 0.0, 1.145), (0.335, 0.225, 0.265))           # chest
    box(robe, (0.0, 0.0, 0.825), (0.315, 0.215, 0.385))           # waist block
    cone(robe, (0.0, 0.0, 0.405), 0.335, 0.185, 0.455, segments=12)  # skirt flare
    box(robe, (0.0, -0.012, 1.278), (0.245, 0.235, 0.055), rot=(0.0, 0.0, math.radians(45)))
    bevel_bm(robe, 0.013, 2)
    parts.append(finish_object(robe, "Body_Robe", "Robe_Blue"))

    inner = bmesh.new()
    box(inner, (0.0, -0.118, 1.135), (0.105, 0.020, 0.300))
    box(inner, (0.0, 0.0, 0.640), (0.250, 0.180, 0.120))
    bevel_bm(inner, 0.008, 2)
    parts.append(finish_object(inner, "Body_Inner", "Inner_Ivory"))

    collar = bmesh.new()
    for sx in (-1.0, 1.0):
        box(collar, (sx * 0.088, -0.118, 1.150), (0.070, 0.040, 0.310), rot=(0.0, sx * math.radians(11), 0.0))
        box(collar, (sx * 0.098, -0.100, 1.262), (0.105, 0.215, 0.042))
    bevel_bm(collar, 0.006, 2)
    parts.append(finish_object(collar, "Body_Collar", "Trim_Ivory"))

    sash = bmesh.new()
    box(sash, (0.0, 0.0, 0.985), (0.345, 0.250, 0.088))
    box(sash, (0.0, -0.128, 0.985), (0.120, 0.022, 0.066))
    box(sash, (0.0, 0.128, 0.985), (0.120, 0.022, 0.066))
    bevel_bm(sash, 0.008, 2)
    parts.append(finish_object(sash, "Body_Sash", "Sash_Teal"))

    trim = bmesh.new()
    cone(trim, (0.0, 0.0, 0.152), 0.348, 0.336, 0.062, segments=12, cap=False)
    box(trim, (0.0, -0.128, 0.988), (0.086, 0.026, 0.048))
    bevel_bm(trim, 0.005, 1, only_sharp=False)
    parts.append(finish_object(trim, "Body_Trim", "Metal_Gold"))

    for sx, side in ((-1.0, "L"), (1.0, "R")):
        arm = bmesh.new()
        box(arm, (sx * 0.238, 0.0, 1.055), (0.120, 0.130, 0.185))  # sleeve shoulder
        box(arm, (sx * 0.252, -0.010, 0.828), (0.300, 0.395, 0.325))  # wide sleeve
        box(arm, (sx * 0.238, -0.006, 0.545), (0.128, 0.138, 0.075))  # cuff
        bevel_bm(arm, 0.012, 2)
        parts.append(finish_object(arm, "Arm_" + side, "Robe_Blue"))

        hand = bmesh.new()
        box(hand, (sx * 0.238, -0.010, 0.478), (0.086, 0.062, 0.078))
        bevel_bm(hand, 0.008, 2)
        parts.append(finish_object(hand, "Hand_" + side, "Skin"))

        cuffm = bmesh.new()
        box(cuffm, (sx * 0.238, -0.006, 0.576), (0.146, 0.152, 0.030))
        bevel_bm(cuffm, 0.004, 1, only_sharp=False)
        parts.append(finish_object(cuffm, "Trim_" + side, "Metal_Gold"))

    for sx, side in ((-1.0, "L"), (1.0, "R")):
        leg = bmesh.new()
        cone(leg, (sx * 0.088, 0.0, 0.345), 0.098, 0.078, 0.640, segments=10)
        bevel_bm(leg, 0.010, 2)
        parts.append(finish_object(leg, "Leg_" + side, "Inner_Ivory"))

        shoe = bmesh.new()
        box(shoe, (sx * 0.088, -0.022, 0.038), (0.118, 0.230, 0.076))
        bevel_bm(shoe, 0.014, 2)
        parts.append(finish_object(shoe, "Foot_" + side, "Hair_Black"))

    head = bmesh.new()
    sphere(head, (0.0, -0.004, 1.512), 0.100, scale=(1.0, 1.06, 1.14), subdivisions=2)
    box(head, (0.0, 0.004, 1.372), (0.078, 0.078, 0.130))
    bevel_bm(head, 0.006, 2, only_sharp=False)
    parts.append(finish_object(head, "Head", "Skin", smooth=True))

    hair = bmesh.new()
    sphere(hair, (0.0, 0.014, 1.532), 0.106, scale=(1.02, 1.06, 1.10), subdivisions=2)
    sphere(hair, (0.0, 0.052, 1.640), 0.055, scale=(1.0, 1.0, 1.15), subdivisions=1)
    cone(hair, (0.0, 0.052, 1.726), 0.036, 0.020, 0.120, segments=8)
    bevel_bm(hair, 0.004, 1, only_sharp=False)
    parts.append(finish_object(hair, "Hair", "Hair_Black", smooth=True))
    return parts


def main_character():
    reset_scene()
    build_materials()
    parts = build_cultivator()
    orient_parts(parts, 1.70)
    tris = sum(tri_count(o) for o in parts)
    zmin = min((o.matrix_world @ v.co).z for o in parts for v in o.data.vertices)
    zmax = max((o.matrix_world @ v.co).z for o in parts for v in o.data.vertices)
    export_glb(parts, CHAR_GLB)
    save_blend(os.path.join(DOCS, "cultivator.blend"))
    stats = {"phase": "character", "objects": len(parts), "triangles": tris,
             "height_m": round(zmax - zmin, 4), "z_min": round(zmin, 4), "z_max": round(zmax, 4),
             "names": [o.name for o in parts], "glb": CHAR_GLB}
    print("STATS " + json.dumps(stats))
    return stats


if __name__ == "__main__":
    ensure_dirs()
    main_character()
