"""Close-up render of the feet over a ground plane, to make a hover or a lean visible.

The question "does this character stand on the ground?" is answered by numbers, but a
numbers-only report is easy to disbelieve. This renders the answer: a ground plane at z=0,
a camera low and close so the contact patch fills the frame, and an optional true-vertical
reference bar at the foot so a lean reads against something real.

Run:
    blender --background --factory-startup --python tools/art/render_ground_contact.py -- \
        --glb path/model.glb --clip idle --out path/feet.png [--label A]
"""

from __future__ import annotations

import argparse
import math

import bpy
from mathutils import Vector


def parse_args() -> argparse.Namespace:
    import sys

    argv = sys.argv
    argv = argv[argv.index("--") + 1 :] if "--" in argv else []
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--glb", required=True)
    parser.add_argument("--clip", default="idle")
    parser.add_argument("--out", required=True)
    parser.add_argument("--framing", default="feet", choices=["feet", "full"])
    parser.add_argument("--height", type=float, default=0.42,
                        help="camera height for the feet framing (m)")
    parser.add_argument("--distance", type=float, default=1.5)
    parser.add_argument("--resolution", type=int, default=720)
    parser.add_argument("--no-vertical-bar", action="store_true")
    return parser.parse_args(argv)


def main() -> int:
    args = parse_args()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=args.glb)

    armature = next((o for o in bpy.data.objects if o.type == "ARMATURE"), None)
    if armature is None:
        print("no armature in", args.glb)
        return 1
    if armature.animation_data is None:
        armature.animation_data_create()
    action = bpy.data.actions.get(args.clip)
    if action is not None:
        armature.animation_data.action = action
        start, end = (int(round(v)) for v in action.frame_range)
        # Sample a third of the way in, where a loop has settled away from its first frame.
        bpy.context.scene.frame_set(start + (end - start) // 3)

    # Ground plane at exactly z=0: the plane the character is contracted to rest on.
    bpy.ops.mesh.primitive_plane_add(size=8.0, location=(0.0, 0.0, 0.0))
    plane = bpy.context.object
    material = bpy.data.materials.new("Ground")
    material.use_nodes = True
    material.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (
        0.16, 0.19, 0.15, 1.0)
    material.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.9
    plane.data.materials.append(material)

    # A thin dark line exactly on the plane, drawn at the origin, so the contact patch has a
    # fixed reference that does not depend on the plane's shading.
    line_mesh = bpy.data.meshes.new("RefLine")
    line_mesh.from_pydata(
        [(-1.0, 0.0, 0.002), (1.0, 0.0, 0.002), (1.0, 0.02, 0.002), (-1.0, 0.02, 0.002)],
        [], [(0, 1, 2, 3)])
    line = bpy.data.objects.new("RefLine", line_mesh)
    bpy.context.collection.objects.link(line)
    line_material = bpy.data.materials.new("RefLine")
    line_material.use_nodes = True
    line_material.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (
        0.02, 0.02, 0.02, 1.0)
    line.data.materials.append(line_material)

    if not args.no_vertical_bar:
        # True-vertical bar through the origin: world +Z is vertical in Blender, so a bar with
        # no rotation IS the plumb line. Anything tilted reads against it directly.
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0.0, 0.0, 0.6))
        bar = bpy.context.object
        bar.scale = (0.008, 0.008, 1.2)
        bar_material = bpy.data.materials.new("Plumb")
        bar_material.use_nodes = True
        bar_material.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (
            0.9, 0.1, 0.1, 1.0)
        bar.data.materials.append(bar_material)

    camera_data = bpy.data.cameras.new("Camera")
    camera = bpy.data.objects.new("Camera", camera_data)
    bpy.context.collection.objects.link(camera)
    bpy.context.scene.camera = camera
    if args.framing == "feet":
        target = Vector((0.0, 0.0, 0.16))
        camera.location = Vector((args.distance * 0.62, -args.distance, args.height))
    else:
        target = Vector((0.0, 0.0, 0.95))
        camera.location = Vector((args.distance * 1.6, -args.distance * 1.6, 1.5))
    camera.rotation_euler = (target - camera.location).to_track_quat("-Z", "Y").to_euler()
    camera_data.lens = 68.0

    sun = bpy.data.lights.new("Sun", type="SUN")
    sun.energy = 3.0
    sun.angle = math.radians(3.0)
    sun_object = bpy.data.objects.new("Sun", sun)
    bpy.context.collection.objects.link(sun_object)
    sun_object.rotation_euler = (math.radians(56.0), 0.0, math.radians(35.0))

    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = args.resolution
    scene.render.resolution_y = args.resolution
    scene.render.filepath = args.out
    bpy.ops.render.render(write_still=True)
    print(f"RENDERED {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
