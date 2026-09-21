#!/usr/bin/env python3
"""Render the cultivator_tripo_v9 rigged character for each action.

Run with Blender:
    blender --background --factory-startup --python \
        tools/art/render_cultivator_tripo_v9_actions.py -- \
        --iteration docs/art/cultivator_tripo_v9/iterations/mia_rig/20260921-final2 \
        --out docs/art/cultivator_tripo_v9/renders/v9_actions

Produces, per clip, orthographic front / side / back views at three phases of the action,
so the pose, the limb coverage and the robe/ponytail deformation can be judged visually.
The renders double as the orientation record: Blender front is -Y, so the `front` camera
is the one at -Y.
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector

CLIP_ORDER = ["idle", "walk", "run", "jump"]
PHASES = [0.0, 0.35, 0.7]


def parse_args() -> argparse.Namespace:
    argv = sys.argv
    argv = argv[argv.index("--") + 1 :] if "--" in argv else []
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--iteration", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--resolution", type=int, default=512)
    parser.add_argument("--samples", type=int, default=32)
    return parser.parse_args(argv)


def empty_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)


def import_fbx(path: Path) -> None:
    bpy.ops.import_scene.fbx(
        filepath=str(path),
        use_anim=True,
        automatic_bone_orientation=True,
        ignore_leaf_bones=False,
    )


def find_one(kind: str):
    found = [o for o in bpy.data.objects if o.type == kind]
    if len(found) != 1:
        raise RuntimeError(f"expected 1 {kind}, found {[o.name for o in found]}")
    return found[0]


def world_bounds(obj) -> tuple[Vector, Vector]:
    depsgraph = bpy.context.evaluated_depsgraph_get()
    evaluated = obj.evaluated_get(depsgraph)
    coords = [obj.matrix_world @ v.co for v in evaluated.data.vertices]
    lo = Vector((min(c.x for c in coords), min(c.y for c in coords), min(c.z for c in coords)))
    hi = Vector((max(c.x for c in coords), max(c.y for c in coords), max(c.z for c in coords)))
    return lo, hi


def setup_render(out_dir: Path, resolution: int, samples: int, lo: Vector, hi: Vector):
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = resolution
    scene.render.resolution_y = int(resolution * 1.45)
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = False
    scene.render.image_settings.file_format = "PNG"
    scene.eevee.taa_render_samples = samples

    # Neutral studio background, matching the existing v9 renders.
    scene.world = bpy.data.worlds.new("v9_studio")
    scene.world.use_nodes = True
    background = scene.world.node_tree.nodes["Background"]
    background.inputs[0].default_value = (0.55, 0.55, 0.57, 1.0)
    background.inputs[1].default_value = 1.0

    centre = (lo + hi) * 0.5
    height = hi.z - lo.z
    span = max(hi.x - lo.x, hi.y - lo.y, height)

    # Key light from front-left-above plus a fill, so silhouette and form read clearly.
    for name, location, energy, size in (
        ("key", (2.5, -3.0, 3.0), 700.0, 3.0),
        ("fill", (-3.0, -2.0, 1.6), 220.0, 4.0),
        ("rim", (0.0, 3.5, 2.6), 320.0, 3.0),
    ):
        light_data = bpy.data.lights.new(name, type="AREA")
        light_data.energy = energy
        light_data.size = size
        light = bpy.data.objects.new(name, light_data)
        light.location = Vector(location) + Vector((centre.x, centre.y, centre.z))
        light.rotation_euler = (math.radians(55), 0.0, math.radians(math.degrees(math.atan2(-location[1], location[0])) if False else 0.0))
        bpy.context.collection.objects.link(light)
        # Aim the light at the character centre.
        direction = Vector(centre) - light.location
        light.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()

    cam_data = bpy.data.cameras.new("cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = span * 1.25
    camera = bpy.data.objects.new("cam", cam_data)
    bpy.context.collection.objects.link(camera)
    scene.camera = camera
    return camera, centre, span


def place_camera(camera, centre: Vector, distance: float, azimuth_deg: float) -> None:
    """Azimuth 0 = looking from -Y (Blender front) toward +Y."""
    angle = math.radians(azimuth_deg)
    offset = Vector((math.sin(angle) * distance, -math.cos(angle) * distance, 0.0))
    camera.location = Vector(centre) + offset
    direction = Vector(centre) - camera.location
    camera.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def main() -> int:
    args = parse_args()
    repo = Path(__file__).resolve().parents[2]
    iteration = Path(args.iteration)
    if not iteration.is_absolute():
        iteration = repo / iteration
    out_dir = Path(args.out)
    if not out_dir.is_absolute():
        out_dir = repo / out_dir
    out_dir.mkdir(parents=True, exist_ok=True)

    report: dict = {
        "asset": "cultivator_tripo_v9",
        "phase": "action_renders",
        "views": {"front": "camera at -Y (Blender front)", "side": "camera at +X",
                  "back": "camera at +Y"},
        "clips": {},
        "problems": [],
    }

    for clip in CLIP_ORDER:
        empty_scene()
        import_fbx(iteration / f"clip_{clip}_slot2.fbx")
        armature = find_one("ARMATURE")
        mesh = find_one("MESH")
        action = bpy.data.actions[0]
        if not armature.animation_data:
            armature.animation_data_create()
        armature.animation_data.action = action

        f_start, f_end = action.frame_range

        # Frame the action from the union of the whole clip's poses, so no pose clips out.
        lo = Vector((math.inf,) * 3)
        hi = Vector((-math.inf,) * 3)
        step = max(1, int((f_end - f_start) / 12.0))
        for frame in range(int(f_start), int(f_end) + 1, step):
            bpy.context.scene.frame_set(frame)
            f_lo, f_hi = world_bounds(mesh)
            lo = Vector((min(lo.x, f_lo.x), min(lo.y, f_lo.y), min(lo.z, f_lo.z)))
            hi = Vector((max(hi.x, f_hi.x), max(hi.y, f_hi.y), max(hi.z, f_hi.z)))
        centre = (lo + hi) * 0.5
        span = max(hi.x - lo.x, hi.y - lo.y, hi.z - lo.z, 0.1)

        camera, _centre, _span = setup_render(
            out_dir, args.resolution, args.samples, lo, hi
        )
        camera.data.ortho_scale = span * 1.3
        distance = span * 3.0

        clip_info = {
            "action": action.name,
            "frame_range": [round(v, 3) for v in (f_start, f_end)],
            "bounds": {
                "min": [round(v, 4) for v in lo],
                "max": [round(v, 4) for v in hi],
                "z_min": round(lo.z, 4),
                "height": round(hi.z - lo.z, 4),
                "x_span": round(hi.x - lo.x, 4),
                "y_span": round(hi.y - lo.y, 4),
            },
            "shots": [],
        }
        print(f"[{clip}] bounds z_min={clip_info['bounds']['z_min']} "
              f"height={clip_info['bounds']['height']}", flush=True)

        for phase in PHASES:
            frame = f_start + (f_end - f_start) * phase
            bpy.context.scene.frame_set(int(round(frame)))
            for view, azimuth in (("front", 0.0), ("side", 90.0), ("back", 180.0)):
                place_camera(camera, centre, distance, azimuth)
                name = f"{clip}_{view}_p{int(phase * 100):03d}.png"
                bpy.context.scene.render.filepath = str(out_dir / name)
                bpy.ops.render.render(write_still=True)
                clip_info["shots"].append(
                    {"file": name, "view": view, "phase": phase,
                     "frame": int(round(frame))}
                )
        print(f"  {len(clip_info['shots'])} shots", flush=True)
        report["clips"][clip] = clip_info

    report_path = out_dir / "action_render_manifest.json"
    report_path.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n")
    print(f"manifest {report_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
