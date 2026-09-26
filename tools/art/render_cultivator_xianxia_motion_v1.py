#!/usr/bin/env python3
"""Render the new bind-pose-authored xianxia motion silhouettes."""

from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[2]
ART = ROOT / "docs/art/cultivator_xianxia_motion_v1"
RENDERS = ART / "renders/motion"


def main():
    bpy.ops.wm.open_mainfile(filepath=str(ART / "cultivator_xianxia_motion_v1.blend"))
    scene = bpy.context.scene
    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    world = bpy.data.worlds.new("warm paper")
    scene.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (.86,.83,.78,1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = .8
    light_data = bpy.data.lights.new("soft sun", "AREA")
    light = bpy.data.objects.new("soft sun", light_data)
    bpy.context.collection.objects.link(light)
    light.location = (-3,-4,6)
    light_data.energy = 520
    light_data.size = 5
    camera_data = bpy.data.cameras.new("motion camera")
    camera = bpy.data.objects.new("motion camera", camera_data)
    bpy.context.collection.objects.link(camera)
    scene.camera = camera
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = 2.25
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 12
    scene.render.resolution_x = 600
    scene.render.resolution_y = 760
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    RENDERS.mkdir(parents=True, exist_ok=True)
    views = [
        ("idle_guarded",1,"front",(0,-5,2)),
        ("idle_guarded",1,"side",(5,0,2)),
        ("walk",1,"side_stride_a",(5,0,2)),
        ("walk",16,"side_stride_b",(5,0,2)),
        ("run",1,"side_stride_a",(5,0,2)),
        ("run",12,"side_stride_b",(5,0,2)),
        ("jump",1,"side_crouch",(5,0,2)),
        ("jump",19,"side_apex",(5,0,2)),
        ("sword_ride",1,"three_quarter",(3,-4,2)),
        ("meditate",1,"front",(0,-5,2)),
        ("meditate",1,"side",(5,0,2)),
    ]
    for clip, frame, view, pos in views:
        arm.animation_data.action = bpy.data.actions[clip]
        scene.frame_set(frame)
        camera.location = pos
        camera.rotation_euler = (Vector((0,0,.85)) - camera.location).to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = str(RENDERS / f"{clip}_{view}.png")
        bpy.ops.render.render(write_still=True)
        print(scene.render.filepath,flush=True)


if __name__ == "__main__":
    main()
