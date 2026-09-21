#!/usr/bin/env python3
"""Diagnose per-frame quality of the cultivator_tripo_v9 action clips.

Run with Blender:
    blender --background --factory-startup --python \
        tools/art/diagnose_cultivator_tripo_v9_actions.py -- \
        --iteration docs/art/cultivator_tripo_v9/iterations/mia_rig/20260921-final2

For every clip, walks the whole frame range and reports, per frame, the world-space Z of
the lowest mesh vertex (foot contact) and the overall bounds. A clip that is meant to be
in place should keep the foot level roughly constant; a sudden excursion means a bad
keyframe or a retarget glitch. Also reports the Hips translation track so residual root
motion is visible as data rather than by eye.

Writes a JSON report and prints a compact per-frame table for the worst offenders.
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


def parse_args() -> argparse.Namespace:
    argv = sys.argv
    argv = argv[argv.index("--") + 1 :] if "--" in argv else []
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--iteration", required=True)
    parser.add_argument("--report", required=True)
    return parser.parse_args(argv)


def empty_scene() -> None:
    bpy.ops.wm.read_standard_settings()


def main() -> int:
    args = parse_args()
    repo = Path(__file__).resolve().parents[2]
    iteration = Path(args.iteration)
    if not iteration.is_absolute():
        iteration = repo / iteration
    report_path = Path(args.report)
    if not report_path.is_absolute():
        report_path = repo / report_path

    report: dict = {"asset": "cultivator_tripo_v9", "phase": "action_diagnosis",
                    "clips": {}, "problems": []}

    for clip in CLIP_ORDER:
        fbx = iteration / f"clip_{clip}_slot2.fbx"
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.import_scene.fbx(filepath=str(fbx), use_anim=True,
                                 automatic_bone_orientation=True)
        armature = next(o for o in bpy.data.objects if o.type == "ARMATURE")
        mesh = next(o for o in bpy.data.objects if o.type == "MESH")
        action = bpy.data.actions[0]
        if not armature.animation_data:
            armature.animation_data_create()
        armature.animation_data.action = action

        f_start, f_end = (int(round(v)) for v in action.frame_range)
        frames = []
        for frame in range(f_start, f_end + 1):
            bpy.context.scene.frame_set(frame)
            depsgraph = bpy.context.evaluated_depsgraph_get()
            evaluated = mesh.evaluated_get(depsgraph)
            coords = [mesh.matrix_world @ v.co for v in evaluated.data.vertices]
            zs = [c.z for c in coords]
            ys = [c.y for c in coords]
            xs = [c.x for c in coords]
            frames.append({
                "frame": frame,
                "z_min": round(min(zs), 5),
                "z_max": round(max(zs), 5),
                "x_mid": round((min(xs) + max(xs)) / 2.0, 5),
                "y_mid": round((min(ys) + max(ys)) / 2.0, 5),
            })

        z_mins = [f["z_min"] for f in frames]
        z_maxs = [f["z_max"] for f in frames]
        baseline = max(z_mins)  # the frame where the character is lowest to the ground
        excursion = max(z_mins) - min(z_mins)
        # A per-frame jump in the foot level much larger than the clip's own spread means a
        # discontinuity rather than motion.
        deltas = [abs(z_mins[i + 1] - z_mins[i]) for i in range(len(z_mins) - 1)]
        worst_delta = max(deltas) if deltas else 0.0
        worst_index = deltas.index(worst_delta) if deltas else -1

        entry = {
            "frames": len(frames),
            "frame_range": [f_start, f_end],
            "foot_level_min": round(min(z_mins), 5),
            "foot_level_max": round(max(z_mins), 5),
            "foot_excursion": round(excursion, 5),
            "worst_frame_to_frame_delta": round(worst_delta, 5),
            "worst_delta_at_frame": frames[worst_index + 1]["frame"] if worst_index >= 0 else None,
            "height_min": round(min(z_maxs[i] - z_mins[i] for i in range(len(frames))), 5),
            "height_max": round(max(z_maxs[i] - z_mins[i] for i in range(len(frames))), 5),
            "top_of_head_max": round(max(z_maxs), 5),
            "samples": frames,
        }
        report["clips"][clip] = entry

        print(f"\n=== {clip}  frames {f_start}..{f_end} ({len(frames)})")
        print(f"  foot level  min={entry['foot_level_min']:+.5f} "
              f"max={entry['foot_level_max']:+.5f} excursion={excursion:.5f}")
        print(f"  worst frame-to-frame foot jump: {worst_delta:.5f} at frame "
              f"{entry['worst_delta_at_frame']}")
        print(f"  height {entry['height_min']:.4f}..{entry['height_max']:.4f}  "
              f"top_of_head_max={entry['top_of_head_max']:.4f}")

        if worst_delta > 0.25:
            lo = max(0, worst_index - 2)
            print("  >>> discontinuity neighbourhood:")
            for f in frames[lo : worst_index + 4]:
                print(f"      frame {f['frame']:>4}  z_min={f['z_min']:+.5f} "
                      f"z_max={f['z_max']:+.5f} x_mid={f['x_mid']:+.4f} y_mid={f['y_mid']:+.4f}")
            report["problems"].append(
                f"{clip}: foot-level discontinuity {worst_delta:.4f} at frame "
                f"{entry['worst_delta_at_frame']}"
            )

    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n")
    print(f"\nreport {report_path}")
    print(f"problems: {report['problems']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
