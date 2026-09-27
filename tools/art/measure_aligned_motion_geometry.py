#!/usr/bin/env python3
"""Fail when the exported jump faces sideways or locomotion arms flare out."""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector


def args() -> argparse.Namespace:
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--glb", required=True)
    parser.add_argument("--report", required=True)
    return parser.parse_args(argv)


def main() -> int:
    config = args()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(Path(config.glb)))
    rig = next(obj for obj in bpy.data.objects if obj.type == "ARMATURE")
    scene = bpy.context.scene

    def point(name: str) -> Vector:
        return rig.matrix_world @ rig.pose.bones["mixamorig:" + name].head

    rig.animation_data.action = bpy.data.actions["idle"]
    scene.frame_set(round(bpy.data.actions["idle"].frame_range[0]))
    right = point("RightArm") - point("LeftArm")
    right.z = 0
    right.normalize()
    idle_head_right = (rig.matrix_world.to_quaternion()
                       @ rig.pose.bones["mixamorig:Head"].matrix.to_quaternion()
                       @ Vector((1, 0, 0)))
    idle_head_right.z = 0
    idle_head_right.normalize()

    def yaw(vector: Vector, baseline: Vector = right) -> float:
        vector.z = 0
        vector.normalize()
        return math.degrees(math.atan2(baseline.cross(vector).z,
                                       baseline.dot(vector)))

    report = {"glb": config.glb, "clips": {}, "problems": []}
    for clip in ("walk", "run", "jump"):
        action = bpy.data.actions[clip]
        rig.animation_data.action = action
        first, last = (round(v) for v in action.frame_range)
        frames = []
        for frame in range(first, last + 1):
            scene.frame_set(frame)
            item = {"frame": frame,
                    "shoulder_yaw_deg": round(yaw(point("RightArm") - point("LeftArm")), 3),
                    "hip_yaw_deg": round(yaw(point("RightUpLeg") - point("LeftUpLeg")), 3)}
            head_right = (rig.matrix_world.to_quaternion()
                          @ rig.pose.bones["mixamorig:Head"].matrix.to_quaternion()
                          @ Vector((1, 0, 0)))
            item["head_yaw_deg"] = round(yaw(head_right, idle_head_right), 3)
            item["foot_lateral_span_m"] = round(abs((point("RightFoot")
                                                      - point("LeftFoot")).dot(right)), 4)
            for side, sign in (("Left", -1), ("Right", 1)):
                shoulder = point(side + "Arm")
                elbow = point(side + "ForeArm")
                wrist = point(side + "Hand")
                item[side.lower() + "_elbow_out_m"] = round((elbow - shoulder).dot(right * sign), 4)
                item[side.lower() + "_wrist_out_m"] = round((wrist - shoulder).dot(right * sign), 4)
                item[side.lower() + "_wrist_forward_m"] = round(-(wrist - shoulder).y, 4)
            frames.append(item)
        report["clips"][clip] = {"frames": frames}
        for part in ("elbow", "wrist"):
            values = [item[f"{side}_{part}_out_m"]
                      for item in frames for side in ("left", "right")]
            maximum = round(max(values), 4)
            report["clips"][clip][part + "_out_max_m"] = maximum
            limit = {"walk": {"elbow": .08, "wrist": .14},
                     "run": {"elbow": .11, "wrist": .18},
                     "jump": {"elbow": .11, "wrist": .14}}[clip][part]
            if maximum > limit:
                report["problems"].append(
                    f"{clip} {part} outward {maximum:.3f} m exceeds {limit:.3f} m")
        if clip == "jump":
            for part in ("shoulder", "hip", "head"):
                maximum = max(abs(item[part + "_yaw_deg"]) for item in frames)
                report["clips"][clip][part + "_yaw_abs_max_deg"] = round(maximum, 3)
                if maximum > 8:
                    report["problems"].append(
                        f"jump {part} yaw {maximum:.1f}° exceeds 8°")
            foot_span = max(item["foot_lateral_span_m"] for item in frames)
            report["clips"][clip]["foot_lateral_span_max_m"] = round(foot_span, 4)
            if foot_span > .4:
                report["problems"].append(
                    f"jump feet separate {foot_span:.3f} m (limit 0.400 m)")
        else:
            for side in ("left", "right"):
                values = [item[side + "_wrist_forward_m"] for item in frames]
                swing = round(max(values) - min(values), 4)
                report["clips"][clip][side + "_wrist_swing_m"] = swing
                if swing < (0.12 if clip == "walk" else .25):
                    report["problems"].append(f"{clip} {side} arm swing disappeared")
        print(f"{clip}: elbow max {report['clips'][clip]['elbow_out_max_m']:.3f} m, "
              f"wrist max {report['clips'][clip]['wrist_out_max_m']:.3f} m", flush=True)
    Path(config.report).write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    for problem in report["problems"]:
        print("FAIL", problem)
    return 1 if report["problems"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
