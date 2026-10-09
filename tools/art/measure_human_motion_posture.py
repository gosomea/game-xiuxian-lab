#!/usr/bin/env python3
"""Check sustained torso lean on the exported human motion GLB.

Run with Blender --background --factory-startup --python this_file.py --
    --glb src/game/actors/swordsman/models/cultivator_human_motion_20260927.glb
    --report docs/art/cultivator_human_motion_20260927/posture.json

The facing basis is measured once in idle. Measuring it separately in each
running frame is incorrect: airborne toes rotate and can even point backward.
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector


def parse_args() -> argparse.Namespace:
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--glb", "--blend", dest="glb", required=True)
    parser.add_argument("--report", default="")
    parser.add_argument("--limit-pitch", type=float, default=4.0)
    parser.add_argument("--limit-roll", type=float, default=4.0)
    return parser.parse_args(args)


def main() -> int:
    args = parse_args()
    path = Path(args.glb)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    if path.suffix.lower() == ".blend":
        bpy.ops.wm.open_mainfile(filepath=str(path.resolve()))
    else:
        bpy.ops.import_scene.gltf(filepath=str(path))
    rig = next(obj for obj in bpy.data.objects if obj.type == "ARMATURE")
    scene = bpy.context.scene

    def point(name: str) -> Vector:
        return rig.matrix_world @ rig.pose.bones["mixamorig:" + name].head

    rig.animation_data.action = bpy.data.actions["idle"]
    scene.frame_set(round(bpy.data.actions["idle"].frame_range[0]))
    ankles = (point("LeftFoot") + point("RightFoot")) / 2
    toes = (point("LeftToeBase") + point("RightToeBase")) / 2
    forward = toes - ankles
    forward.z = 0
    forward.normalize()
    right = Vector((-forward.y, forward.x, 0))
    report = {"glb": str(path), "forward": [round(v, 5) for v in forward],
              "clips": {}, "problems": []}
    for clip in ("idle", "walk", "run", "jump", "sword_ride"):
        action = bpy.data.actions[clip]
        rig.animation_data.action = action
        start, end = (round(v) for v in action.frame_range)
        pitch, roll = [], []
        for frame in range(start, end + 1):
            scene.frame_set(frame)
            axis = point("Head") - point("Hips")
            pitch.append(math.degrees(math.atan2(axis.dot(forward), axis.z)))
            roll.append(math.degrees(math.atan2(axis.dot(right), axis.z)))
        entry = {
            "frames": end - start + 1,
            "pitch_mean_deg": round(sum(pitch) / len(pitch), 3),
            "pitch_min_deg": round(min(pitch), 3),
            "pitch_max_deg": round(max(pitch), 3),
            "roll_mean_deg": round(sum(roll) / len(roll), 3),
            "roll_min_deg": round(min(roll), 3),
            "roll_max_deg": round(max(roll), 3),
        }
        report["clips"][clip] = entry
        print(f"{clip:12} pitch={entry['pitch_mean_deg']:+6.2f}° "
              f"[{entry['pitch_min_deg']:+6.2f}, {entry['pitch_max_deg']:+6.2f}] "
              f"roll={entry['roll_mean_deg']:+6.2f}°", flush=True)
        # Jump bends at takeoff, so its pitch is free; side lean would make
        # the character look crooked throughout the airborne state.
        if clip in ("idle", "walk", "run"):
            if abs(entry["pitch_mean_deg"]) > args.limit_pitch:
                report["problems"].append(f"{clip}: sustained pitch exceeds {args.limit_pitch}°")
            if abs(entry["roll_mean_deg"]) > args.limit_roll:
                report["problems"].append(f"{clip}: sustained roll exceeds {args.limit_roll}°")
        elif clip == "jump":
            if max(abs(entry["roll_min_deg"]), abs(entry["roll_max_deg"])) > 6.0:
                report["problems"].append("jump: a frame rolls more than 6°")
    if args.report:
        Path(args.report).write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n")
    for problem in report["problems"]:
        print("FAIL", problem)
    return 1 if report["problems"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
