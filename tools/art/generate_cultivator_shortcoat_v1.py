"""Build the movement-first jade-paper cultivator shortcoat T-pose.

This is a static, deliberately simple Blender white model for the next rigging round. It keeps
the established jade-paper palette and cultivation identity, while removing every garment shape
that hid or bridged a locomotion joint in the earlier long-robe candidates.

Run:
  /Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup \
    --python tools/art/generate_cultivator_shortcoat_v1.py -- build preview

Outputs are new exploration assets; the script never overwrites an older character version.
"""
import hashlib
import importlib.util
import json
import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector


ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DOCS = os.path.join(ROOT, "docs", "art", "cultivator_shortcoat_v1")
GLB = os.path.join(DOCS, "cultivator_shortcoat_v1.glb")
FBX = os.path.join(DOCS, "cultivator_shortcoat_v1_mixamo_tpose.fbx")
BLEND = os.path.join(DOCS, "cultivator_shortcoat_v1.blend")
MANIFEST = os.path.join(DOCS, "build_manifest.json")


def load_base():
    path = os.path.join(ROOT, "tools", "art", "generate_cultivator_refined.py")
    spec = importlib.util.spec_from_file_location("cultivator_refined_helpers", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


m = load_base()


def sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def shortcoat_materials():
    m.MATS.clear()
    # Blender node colours are linear; these deliberately low values render as the deep,
    # restrained jade-paper palette instead of the pastel cyan seen in the first light test.
    m.make_mat("Robe_Indigo", (0.026, 0.062, 0.125), rough=0.76)
    m.make_mat("Robe_Indigo_Dark", (0.010, 0.026, 0.058), rough=0.80)
    m.make_mat("Inner_Ivory", (0.430, 0.405, 0.340), rough=0.72)
    m.make_mat("Trim_Ivory", (0.350, 0.325, 0.270), rough=0.66)
    m.make_mat("Sash_Wood_Gold", (0.175, 0.095, 0.025), rough=0.56, metallic=0.18)
    m.make_mat("Skin", (0.410, 0.245, 0.145), rough=0.66)
    m.make_mat("Hair_Black", (0.008, 0.010, 0.017), rough=0.58)
    m.make_mat("Shoe_Dark", (0.014, 0.016, 0.024), rough=0.70)


def torso():
    bm = bmesh.new()
    m.tube_z(bm, [
        (0.0, 0.000, 1.430, 0.120, 0.090),
        (0.0, 0.000, 1.405, 0.158, 0.108),
        (0.0, 0.004, 1.300, 0.153, 0.113),
        (0.0, 0.008, 1.130, 0.135, 0.104),
        (0.0, 0.008, 0.990, 0.145, 0.113),
        (0.0, 0.006, 0.905, 0.158, 0.120),
    ], segments=18)
    m.smooth(bm)
    return m.finish(bm, "Shortcoat_Torso", "Robe_Indigo", smooth_faces=True)


def inner_chest():
    bm = bmesh.new()
    # Narrow ivory chest insert, lifted beyond the outer torso on the authored -Y front.
    strip = []
    for index in range(7):
        t = index / 6.0
        z = 1.385 - 0.245 * t
        half = 0.025 + 0.010 * t
        y = -0.118 + 0.006 * t
        strip.append([(-half, y, z), (half, y, z)])
    m.loft(bm, strip, cap_start=True, cap_end=True, closed=False)
    m.solidify(bm, 0.005)
    return m.finish(bm, "Inner_Chest", "Inner_Ivory", smooth_faces=True)


def collar():
    bm = bmesh.new()
    # Crossed lapels are short and chest-hugging; they never continue into a hanging scarf.
    for side in (-1.0, 1.0):
        strip = []
        for index in range(8):
            t = index / 7.0
            x = side * (0.090 * (1.0 - t) + 0.010 * t)
            z = 1.395 - 0.215 * t
            y = -0.116 - 0.004 * math.sin(math.pi * t)
            strip.append([(x - 0.018, y, z + 0.018), (x + 0.018, y - 0.004, z - 0.018)])
        m.loft(bm, strip, cap_start=True, cap_end=True, closed=False)
    m.solidify(bm, 0.004)
    return m.finish(bm, "Cross_Collar", "Trim_Ivory", smooth_faces=True)


def sash():
    bm = bmesh.new()
    m.tube_z(bm, [
        (0.0, 0.006, 1.010, 0.151, 0.119),
        (0.0, 0.006, 0.955, 0.159, 0.124),
        (0.0, 0.006, 0.920, 0.158, 0.123),
    ], segments=18)
    m.cube(bm, (0.0, -0.121, 0.964), (0.070, 0.028, 0.060))
    m.bevel(bm, 0.004, 1, only_sharp=False)
    return m.finish(bm, "Short_Sash", "Sash_Wood_Gold", smooth_faces=True)


def short_panels():
    """Six separate upper-thigh panels: never a bridge across both legs."""
    parts = []
    specs = [
        ("Front_L", (-0.052, -0.125, 0.820), (0.074, 0.025, 0.230), "Robe_Indigo_Dark"),
        ("Front_R", (0.052, -0.125, 0.820), (0.074, 0.025, 0.230), "Robe_Indigo_Dark"),
        ("Back_L", (-0.052, 0.117, 0.830), (0.074, 0.024, 0.210), "Robe_Indigo"),
        ("Back_R", (0.052, 0.117, 0.830), (0.074, 0.024, 0.210), "Robe_Indigo"),
        ("Left", (-0.145, 0.000, 0.825), (0.026, 0.165, 0.220), "Robe_Indigo"),
        ("Right", (0.145, 0.000, 0.825), (0.026, 0.165, 0.220), "Robe_Indigo"),
    ]
    for name, center, size, material in specs:
        bm = bmesh.new()
        m.cube(bm, center, size)
        m.bevel(bm, 0.010, 2, only_sharp=False)
        parts.append(m.finish(bm, "Short_Panel_" + name, material, smooth_faces=True))
    return parts


def arms():
    """Horizontal T-pose with fitted sleeves and exposed hands."""
    parts = []
    for side, tag in ((-1.0, "L"), (1.0, "R")):
        shoulder = (side * 0.135, 0.0, 1.390)
        elbow = (side * 0.405, 0.0, 1.390)
        wrist = (side * 0.640, 0.0, 1.390)
        hand = (side * 0.750, -0.004, 1.390)

        bm = bmesh.new()
        m.tube_axis(bm, shoulder, elbow,
                    [(0.065, 0.067), (0.060, 0.062), (0.054, 0.056)], segments=12)
        m.tube_axis(bm, elbow, wrist,
                    [(0.054, 0.056), (0.047, 0.049), (0.040, 0.043)], segments=12)
        m.smooth(bm)
        parts.append(m.finish(bm, "Fitted_Sleeve_" + tag, "Robe_Indigo", smooth_faces=True))

        bm = bmesh.new()
        m.tube_axis(bm, (side * 0.605, 0.0, 1.390), (side * 0.648, 0.0, 1.390),
                    [(0.047, 0.049), (0.043, 0.045)], segments=12)
        parts.append(m.finish(bm, "Cuff_" + tag, "Trim_Ivory", smooth_faces=True))

        bm = bmesh.new()
        m.tube_axis(bm, wrist, hand,
                    [(0.036, 0.040), (0.038, 0.043), (0.028, 0.034)], segments=10)
        # Small thumb marker below/front of the palm gives the rigger a readable hand direction.
        m.tube_axis(bm, (side * 0.690, -0.010, 1.370), (side * 0.725, -0.020, 1.345),
                    [(0.016, 0.017), (0.011, 0.012)], segments=8)
        m.smooth(bm)
        parts.append(m.finish(bm, "Hand_" + tag, "Skin", smooth_faces=True))
    return parts


def legs():
    """Separated trousers and compact boots; hips, knees, ankles all remain legible."""
    parts = []
    for side, tag in ((-1.0, "L"), (1.0, "R")):
        bm = bmesh.new()
        m.tube_z(bm, [
            (side * 0.083, 0.003, 0.930, 0.070, 0.068),
            (side * 0.088, 0.002, 0.720, 0.074, 0.070),
            (side * 0.092, 0.000, 0.510, 0.060, 0.060),
            (side * 0.093, 0.000, 0.300, 0.052, 0.054),
            (side * 0.093, -0.002, 0.135, 0.047, 0.050),
        ], segments=12)
        m.smooth(bm)
        parts.append(m.finish(bm, "Trouser_" + tag, "Robe_Indigo_Dark", smooth_faces=True))

        bm = bmesh.new()
        m.cube(bm, (side * 0.093, -0.025, 0.070), (0.115, 0.205, 0.140))
        m.sphere(bm, (side * 0.093, -0.105, 0.058), 0.057,
                 scale=(0.96, 0.72, 0.64), subdivisions=2)
        m.bevel(bm, 0.012, 2)
        parts.append(m.finish(bm, "Foot_" + tag, "Shoe_Dark", smooth_faces=True))
    return parts


def build_all():
    parts = [
        torso(), inner_chest(), collar(), sash(), *short_panels(),
        *arms(), *legs(), *m.build_head(), *m.build_hair(),
    ]
    # The inherited white-model head was intentionally generous for close camera shots. This
    # locomotion candidate needs the art-direction target (6.5-7 heads), so compress only the
    # cranium/face/hair above the neck pivot while preserving the 1.70 m full body target.
    head_names = {"Head", "Face_Nose", "Face_Eyes", "Face_Brows", "Hair_Cap", "Hair_Bun"}
    pivot_z = 1.410
    for obj in parts:
        if obj.name in head_names:
            for vertex in obj.data.vertices:
                vertex.co.z = pivot_z + (vertex.co.z - pivot_z) * 0.88
            obj.data.update()
    return parts


def export_fbx_single_mesh(parts):
    # Export-only copies are joined into one object; source parts remain editable in the .blend.
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
    upload.name = "Cultivator_Shortcoat_V1_TPose"
    bpy.ops.export_scene.fbx(
        filepath=FBX,
        use_selection=True,
        object_types={"MESH"},
        apply_unit_scale=True,
        bake_space_transform=False,
        add_leaf_bones=False,
        bake_anim=False,
        path_mode="AUTO",
    )
    bpy.data.objects.remove(upload, do_unlink=True)


def stage_build():
    os.makedirs(DOCS, exist_ok=True)
    m.reset_scene()
    shortcoat_materials()
    parts = build_all()
    body = [obj for obj in parts if obj.name != "Hair_Bun"]
    _, _, body_z = m.bounds(body)
    scale = 1.70 / body_z[1]
    m.normalize_orientation(parts, scale)

    m.export_glb(parts, GLB)
    export_fbx_single_mesh(parts)
    # The intentional iteration snapshot lives under docs/art/.../iterations; avoid Blender's
    # ambiguous .blend1 sidecar on deterministic rebuilds.
    bpy.context.preferences.filepaths.save_version = 0
    m.save_blend(BLEND)

    x_range, y_range, z_range = m.bounds(parts)
    _, _, body_z = m.bounds(body)
    _, _, head_z = m.bounds([obj for obj in parts if obj.name in ("Head", "Face_Eyes", "Face_Brows")])
    head_height = head_z[1] - head_z[0]
    stats = {
        "generator": "tools/art/generate_cultivator_shortcoat_v1.py",
        "blender": bpy.app.version_string,
        "objects": len(parts),
        "triangles": sum(m.tri_count(obj) for obj in parts),
        "body_height_m": round(body_z[1] - body_z[0], 4),
        "total_height_m": round(z_range[1] - z_range[0], 4),
        "head_units": round((body_z[1] - body_z[0]) / head_height, 3),
        "arm_span_m": round(x_range[1] - x_range[0], 4),
        "depth_m": round(y_range[1] - y_range[0], 4),
        "soles_at_zero": abs(z_range[0]) < 1e-6,
        "static_t_pose": True,
        "rigged": False,
        "animations": 0,
        "outputs": {},
    }
    for path in (GLB, FBX, BLEND):
        stats["outputs"][os.path.basename(path)] = {
            "bytes": os.path.getsize(path),
            "sha256": sha256(path),
        }
    with open(MANIFEST, "w", encoding="utf-8") as handle:
        json.dump(stats, handle, ensure_ascii=False, indent=2)
        handle.write("\n")
    print("STATS " + json.dumps(stats, ensure_ascii=False))


SHOTS = {
    "front": ((0.0, 3.55, 1.05), (0.0, 0.0, 0.95), 65.0, (1000, 900)),
    "three_quarter": ((-2.65, 2.65, 1.18), (0.0, 0.0, 0.95), 65.0, (1000, 900)),
    "back": ((0.0, -3.55, 1.05), (0.0, 0.0, 0.95), 65.0, (1000, 900)),
}


def stage_preview():
    bpy.ops.wm.open_mainfile(filepath=BLEND, load_ui=False)
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.image_settings.file_format = "PNG"
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "Medium High Contrast"
    scene.view_settings.exposure = -0.35
    world = scene.world or bpy.data.worlds.new("ShortcoatStudio")
    scene.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.72, 0.74, 0.74, 1.0)
    world.node_tree.nodes["Background"].inputs[1].default_value = 0.45

    for location, energy, size in (
        ((-2.2, 2.7, 3.2), 800.0, 3.2),
        ((2.8, 1.5, 2.1), 520.0, 3.8),
        ((0.0, -3.0, 2.4), 700.0, 3.0),
    ):
        bpy.ops.object.light_add(type="AREA", location=location)
        light = bpy.context.object
        light.data.energy = energy
        light.data.size = size
        light.rotation_euler = (Vector((0.0, 0.0, 1.0)) - light.location).to_track_quat("-Z", "Y").to_euler()

    bpy.ops.object.camera_add()
    camera = bpy.context.object
    scene.camera = camera
    camera.data.type = "PERSP"
    scene.render.resolution_percentage = 100
    written = []
    for name, (location, target, lens, resolution) in SHOTS.items():
        camera.location = location
        camera.data.lens = lens
        camera.rotation_euler = (Vector(target) - camera.location).to_track_quat("-Z", "Y").to_euler()
        scene.render.resolution_x, scene.render.resolution_y = resolution
        scene.render.filepath = os.path.join(DOCS, "cultivator_shortcoat_v1_%s.png" % name)
        bpy.ops.render.render(write_still=True)
        written.append(scene.render.filepath)
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


STAGES = {"build": stage_build, "preview": stage_preview}


def main(argv):
    stages = [arg for arg in argv if arg in STAGES] or ["build"]
    for stage in stages:
        STAGES[stage]()


if __name__ == "__main__":
    main(sys.argv[1:])
