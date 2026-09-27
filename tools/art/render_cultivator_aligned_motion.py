#!/usr/bin/env python3
"""Render five comparable front and side phases of walk, run, and jump."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[2]
GLB = ROOT / "src/game/actors/swordsman/models/cultivator_aligned_motion_20260927.glb"
OUT = ROOT / "docs/art/cultivator_aligned_motion_20260927/frames"


def main() -> None:
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--glb", default=str(GLB))
    parser.add_argument("--out", default=str(OUT))
    parser.add_argument("--clips", default="walk,run,jump")
    args = parser.parse_args(argv)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(Path(args.glb)))
    rig = next(obj for obj in bpy.data.objects if obj.type == "ARMATURE")
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 360
    scene.render.resolution_y = 480
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.filepath = ""
    scene.world = bpy.data.worlds.new("PostureStudio")
    scene.world.color = (0.22, 0.22, 0.23)
    scene.view_settings.view_transform = "AgX"

    camera_data = bpy.data.cameras.new("PostureCamera")
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = 2.55
    camera = bpy.data.objects.new("PostureCamera", camera_data)
    scene.collection.objects.link(camera)
    scene.camera = camera
    aim = Vector((0, 0, 0.94))

    for name, location, energy, size in (
        ("Key", (-2.0, -3.0, 3.3), 600, 4),
        ("Fill", (2.0, 1.0, 2.4), 420, 4),
    ):
        data = bpy.data.lights.new(name, type="AREA")
        data.energy = energy
        data.shape = "DISK"
        data.size = size
        obj = bpy.data.objects.new(name, data)
        scene.collection.objects.link(obj)
        obj.location = location
        obj.rotation_euler = (aim - obj.location).to_track_quat("-Z", "Y").to_euler()

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    for clip in args.clips.split(","):
        action = bpy.data.actions[clip]
        rig.animation_data.action = action
        first, last = (round(v) for v in action.frame_range)
        for view, position in (("front", Vector((0, -5, aim.z))),
                               ("side", Vector((5, 0, aim.z)))):
            camera.location = position
            camera.rotation_euler = (aim - position).to_track_quat("-Z", "Y").to_euler()
            for index in range(5):
                frame = first + round((last - first) * index / 4)
                scene.frame_set(frame)
                scene.render.filepath = str(out / f"{view}_{clip}_{index}.png")
                bpy.ops.render.render(write_still=True)
                print(f"rendered {view} {clip} {index}/{frame}", flush=True)


if __name__ == "__main__":
    main()
