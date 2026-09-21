#!/usr/bin/env python3
"""Render candidate Make-It-Animatable clips side by side for visual selection.

Run with Blender:
    blender --background --factory-startup --python \
        tools/art/render_mia_clip_candidates.py -- \
        --pair "sprint=docs/art/.../clip_run_slot2.fbx" \
        --pair "run=docs/art/.../clip_run_slot2.fbx" \
        --out docs/art/cultivator_tripo_v9/renders/run_candidates

Numeric scoring (tools/art/score_mia_clip.py) catches gross retarget failures such as the
spine folding forward, but whether a clip reads as a believable run for this character is a
visual judgement. This renders each candidate's side profile at three phases of one cycle
so they can be compared directly.
"""

from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector

PHASES = [0.0, 0.3, 0.6]


def parse_args() -> argparse.Namespace:
    argv = sys.argv
    argv = argv[argv.index("--") + 1 :] if "--" in argv else []
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pair", action="append", required=True,
                        help="label=/path/to/clip_run_slot2.fbx")
    parser.add_argument("--out", required=True)
    parser.add_argument("--resolution", type=int, default=384)
    parser.add_argument("--samples", type=int, default=16)
    return parser.parse_args(argv)


def empty_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)


def find_one(kind: str):
    found = [o for o in bpy.data.objects if o.type == kind]
    if len(found) != 1:
        raise RuntimeError(f"expected 1 {kind}, got {[o.name for o in found]}")
    return found[0]


def world_bounds(obj):
    depsgraph = bpy.context.evaluated_depsgraph_get()
    evaluated = obj.evaluated_get(depsgraph)
    coords = [obj.matrix_world @ v.co for v in evaluated.data.vertices]
    lo = Vector((min(c.x for c in coords), min(c.y for c in coords), min(c.z for c in coords)))
    hi = Vector((max(c.x for c in coords), max(c.y for c in coords), max(c.z for c in coords)))
    return lo, hi


def setup_lighting(lo: Vector, hi: Vector, resolution: int, samples: int) -> None:
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = resolution
    scene.render.resolution_y = int(resolution * 1.45)
    scene.render.image_settings.file_format = "PNG"
    scene.eevee.taa_render_samples = samples
    scene.world = bpy.data.worlds.new("studio")
    scene.world.use_nodes = True
    scene.world.node_tree.nodes["Background"].inputs[0].default_value = (0.55, 0.55, 0.57, 1.0)

    centre = (lo + hi) * 0.5
    for location, energy, size in (
        ((2.5, -3.0, 3.0), 700.0, 3.0),
        ((-3.0, -2.0, 1.6), 220.0, 4.0),
        ((0.0, 3.5, 2.6), 320.0, 3.0),
    ):
        light_data = bpy.data.lights.new("l", type="AREA")
        light_data.energy = energy
        light_data.size = size
        light = bpy.data.objects.new("l", light_data)
        light.location = Vector(location) + Vector((centre.x, centre.y, centre.z))
        light.rotation_euler = (Vector(centre) - light.location).to_track_quat("-Z", "Y").to_euler()
        bpy.context.collection.objects.link(light)


def main() -> int:
    args = parse_args()
    repo = Path(__file__).resolve().parents[2]
    out_dir = Path(args.out)
    if not out_dir.is_absolute():
        out_dir = repo / args.out
    out_dir.mkdir(parents=True, exist_ok=True)

    for pair in args.pair:
        label, _, raw = pair.partition("=")
        fbx = Path(raw)
        if not fbx.is_absolute():
            fbx = repo / fbx
        if not fbx.is_file():
            print(f"SKIP {label}: missing {fbx}", flush=True)
            continue

        empty_scene()
        bpy.ops.import_scene.fbx(filepath=str(fbx), use_anim=True,
                                 automatic_bone_orientation=True)
        armature = find_one("ARMATURE")
        mesh = find_one("MESH")
        action = bpy.data.actions[0]
        if not armature.animation_data:
            armature.animation_data_create()
        armature.animation_data.action = action

        f_start, f_end = (int(round(v)) for v in action.frame_range)
        lo = Vector((math.inf,) * 3)
        hi = Vector((-math.inf,) * 3)
        step = max(1, int((f_end - f_start) / 10))
        for frame in range(f_start, f_end + 1, step):
            bpy.context.scene.frame_set(frame)
            f_lo, f_hi = world_bounds(mesh)
            lo = Vector((min(lo.x, f_lo.x), min(lo.y, f_lo.y), min(lo.z, f_lo.z)))
            hi = Vector((max(hi.x, f_hi.x), max(hi.y, f_hi.y), max(hi.z, f_hi.z)))

        setup_lighting(lo, hi, args.resolution, args.samples)
        centre = (lo + hi) * 0.5
        span = max(hi.x - lo.x, hi.y - lo.y, hi.z - lo.z, 0.1)

        cam_data = bpy.data.cameras.new("cam")
        cam_data.type = "ORTHO"
        cam_data.ortho_scale = span * 1.3
        camera = bpy.data.objects.new("cam", cam_data)
        bpy.context.collection.objects.link(camera)
        bpy.context.scene.camera = camera
        distance = span * 3.0

        for phase in PHASES:
            frame = int(round(f_start + (f_end - f_start) * phase))
            bpy.context.scene.frame_set(frame)
            for view, azimuth in (("side", 90.0), ("front", 0.0)):
                angle = math.radians(azimuth)
                camera.location = Vector(centre) + Vector(
                    (math.sin(angle) * distance, -math.cos(angle) * distance, 0.0)
                )
                camera.rotation_euler = (
                    Vector(centre) - camera.location
                ).to_track_quat("-Z", "Y").to_euler()
                name = f"{label}_{view}_p{int(phase * 100):03d}.png"
                bpy.context.scene.render.filepath = str(out_dir / name)
                bpy.ops.render.render(write_still=True)
        print(f"[{label}] rendered {len(PHASES) * 2} shots; "
              f"frames {f_start}..{f_end}", flush=True)

    print(f"out {out_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
