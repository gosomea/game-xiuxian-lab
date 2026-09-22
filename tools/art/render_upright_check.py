#!/usr/bin/env python3
"""Render a character beside a true-vertical reference line to settle "is it tilted?".

Run with Blender:
    blender --background --factory-startup --python tools/art/render_upright_check.py -- \
        --glb path/model.glb --clip idle --out docs/.../renders/upright --anchor ankle

Why this exists
---------------
Reasoning about bone frames kept producing contradictory conclusions: a quaternion read one
way says "leaning back", the render looks upright, and an isometric game view looks tilted.
None of those are trustworthy on their own, because hips->head is not anatomically vertical
and a bone's local axes are conventions rather than anatomy.

So this draws the reference explicitly. It adds a bright vertical bar at a chosen anchor
(ankle, pelvis or head) and renders the character from the side and the front in the SAME
frame. Anything that lines up with the bar is vertical; anything that visibly departs from
it is tilted, and the direction of the departure is readable at a glance.

`--anchor` selects where the bar's vertical line passes through, which changes the question:
  ankle  - "is the body standing over its feet?" (the balance question)
  pelvis - "is the upper body stacked over the hips?" (the posture question)
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector

ANCHORS = {
    "ankle": ("mixamorig:LeftFoot", "mixamorig_LeftFoot", "LeftFoot"),
    "pelvis": ("mixamorig:Hips", "mixamorig_Hips", "Hips"),
    "head": ("mixamorig:Head", "mixamorig_Head", "Head"),
}


def parse_args() -> argparse.Namespace:
    argv = sys.argv
    argv = argv[argv.index("--") + 1 :] if "--" in argv else []
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--glb", required=True)
    parser.add_argument("--clip", default="", help="clip name to bind (default: first)")
    parser.add_argument("--anchor", default="ankle", choices=sorted(ANCHORS))
    parser.add_argument("--out", required=True, help="output directory for PNGs")
    parser.add_argument("--resolution", type=int, default=700)
    parser.add_argument("--samples", type=int, default=24)
    return parser.parse_args(argv)


def bone(armature, names):
    for name in names:
        found = armature.pose.bones.get(name)
        if found is not None:
            return found
    return None


def main() -> int:
    args = parse_args()
    repo = Path(__file__).resolve().parents[2]
    glb = Path(args.glb)
    if not glb.is_absolute():
        glb = repo / glb
    out_dir = Path(args.out)
    if not out_dir.is_absolute():
        out_dir = repo / out_dir
    if not glb.is_file():
        print(f"FAIL: missing {glb}", file=sys.stderr)
        return 2

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(glb))

    armature = next((o for o in bpy.data.objects if o.type == "ARMATURE"), None)
    mesh = next((o for o in bpy.data.objects if o.type == "MESH"), None)
    if armature is None or mesh is None:
        print("FAIL: need both an armature and a mesh", file=sys.stderr)
        return 2

    # Bind the requested clip; the importer may leave several actions around.
    clips = {}
    for action in bpy.data.actions:
        clips[action.name] = action
    if args.clip and args.clip in clips:
        chosen = clips[args.clip]
    elif clips:
        chosen = next(iter(clips.values()))
    else:
        chosen = None
    if chosen is not None:
        if not armature.animation_data:
            armature.animation_data_create()
        armature.animation_data.action = chosen
        mid = int(sum(chosen.frame_range) / 2)
        bpy.context.scene.frame_set(max(1, mid))
    print(f"clip bound: {chosen.name if chosen else '<none>'}")

    anchor_bone = bone(armature, ANCHORS[args.anchor])
    if anchor_bone is None:
        print(f"FAIL: anchor bone missing for {args.anchor}", file=sys.stderr)
        return 2
    anchor = armature.matrix_world @ anchor_bone.head

    # Reference bar: thin, tall, unmistakably vertical, offset slightly so it does not hide
    # the body. It spans well above the head and below the feet.
    height = (mesh.dimensions.z if mesh.dimensions.z > 0.1 else 1.9) * 2.2
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(anchor.x, anchor.y, anchor.z + height * 0.15))
    bar = bpy.context.active_object
    bar.name = "VerticalReference"
    bar.scale = (0.01, 0.012, height / 2.0)
    mat = bpy.data.materials.new("ReferenceRed")
    mat.use_nodes = True
    mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (1.0, 0.05, 0.05, 1)
    bar.data.materials.append(mat)

    # A second, shorter bar at the far side makes the horizon readable in the side view.
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(anchor.x, anchor.y - 1.6, anchor.z + height * 0.15))
    far = bpy.context.active_object
    far.scale = (0.01, 0.012, height / 2.0)
    far.data.materials.append(mat)

    # Lighting: bright, even, no shadows to confuse silhouette reading.
    bpy.ops.object.light_add(type="SUN", location=(3.0, -3.0, 6.0))
    sun = bpy.context.active_object
    sun.data.energy = 4.0
    sun.rotation_euler = (math.radians(45), 0.0, math.radians(45))
    world = bpy.context.scene.world or bpy.data.worlds.new("W")
    bpy.context.scene.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.55, 0.55, 0.58, 1)
    world.node_tree.nodes["Background"].inputs[1].default_value = 1.0

    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = args.samples
    scene.render.resolution_x = args.resolution
    scene.render.resolution_y = int(args.resolution * 1.45)
    scene.render.film_transparent = False

    focus = Vector((anchor.x, anchor.y, anchor.z + 0.95))

    def render_from(name: str, offset: Vector) -> None:
        bpy.ops.object.camera_add(location=focus + offset)
        camera = bpy.context.active_object
        direction = focus - camera.location
        camera.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
        camera.data.type = "ORTHO"
        camera.data.ortho_scale = 2.6
        scene.camera = camera
        path = out_dir / f"{name}.png"
        scene.render.filepath = str(path)
        bpy.ops.render.render(write_still=True)
        print(f"  rendered {path}")
        bpy.data.objects.remove(camera, do_unlink=True)

    print(f"anchor {args.anchor} at ({anchor.x:+.3f}, {anchor.y:+.3f}, {anchor.z:+.3f})")
    render_from("side", Vector((4.0, 0.0, 0.0)))
    render_from("front", Vector((0.0, -4.0, 0.0)))
    render_from("three_quarter", Vector((3.0, -2.6, 0.6)))

    # Numeric summary alongside the images: where is the head relative to the anchor?
    head_bone = bone(armature, ANCHORS["head"])
    if head_bone is not None:
        head = armature.matrix_world @ head_bone.head
        delta = head - anchor
        horizontal = math.hypot(delta.x, delta.y)
        print()
        print(f"  head is {delta.z:+.4f} m above the {args.anchor}, "
              f"{horizontal:.4f} m horizontally away")
        print(f"  => {math.degrees(math.atan2(horizontal, delta.z)):.2f} deg off the vertical bar")
        print(f"  horizontal direction: ({delta.x / max(horizontal, 1e-9):+.3f}, "
              f"{delta.y / max(horizontal, 1e-9):+.3f})")
    print("compare each render against the red bar: aligned = upright")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
