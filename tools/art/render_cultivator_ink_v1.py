#!/usr/bin/env python3
"""Render reproducible front/side/three-quarter animation checks from the ink source."""

from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[2]
ART = ROOT / "docs/art/cultivator_ink_v1"
SOURCE = ART / "cultivator_ink_v1.blend"
RENDERS = ART / "renders"


def point_camera(camera, target):
    camera.rotation_euler = (Vector(target) - camera.location).to_track_quat("-Z", "Y").to_euler()


def main():
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
    scene = bpy.context.scene
    rig = bpy.data.objects["InkCultivatorRig"]
    world = bpy.data.worlds.new("Warm paper")
    scene.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (.86,.83,.77,1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = .8
    floor = bpy.data.materials.new("Check ground")
    floor.diffuse_color = (.84,.82,.77,1)
    bpy.ops.mesh.primitive_plane_add(size=200, location=(0,0,-.016))
    bpy.context.object.name = "RenderOnlyGround"
    bpy.context.object.data.materials.append(floor)
    sun_data = bpy.data.lights.new("Large warm sun", "AREA")
    sun = bpy.data.objects.new("Large warm sun", sun_data)
    bpy.context.collection.objects.link(sun)
    sun.location = (-3,-4,6)
    sun_data.energy = 450
    sun_data.shape = "DISK"
    sun_data.size = 5
    camera_data = bpy.data.cameras.new("Evidence camera")
    camera = bpy.data.objects.new("Evidence camera", camera_data)
    bpy.context.collection.objects.link(camera)
    scene.camera = camera
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = 2.18
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 32
    scene.render.resolution_x = 640
    scene.render.resolution_y = 800
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.view_settings.view_transform = "AgX"
    RENDERS.mkdir(parents=True, exist_ok=True)
    specs = [
        ("idle_guarded", 1, "front", (0,-5,2)),
        ("idle_guarded", 1, "side", (5,0,2)),
        ("walk", 6, "side", (5,0,2)),
        ("run", 6, "side", (5,0,2)),
        ("jump", 17, "side", (5,0,2)),
        ("sword_ride", 1, "three_quarter", (3,-4,2)),
        ("meditate", 1, "front", (0,-5,2)),
    ]
    for clip, frame, view, position in specs:
        rig.animation_data.action = bpy.data.actions[clip]
        scene.frame_set(frame)
        camera.location = position
        point_camera(camera, (0,0,.86))
        scene.render.filepath = str(RENDERS / f"{clip}_{view}.png")
        bpy.ops.render.render(write_still=True)
        print(scene.render.filepath, flush=True)


if __name__ == "__main__":
    main()
