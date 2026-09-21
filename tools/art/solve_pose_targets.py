#!/usr/bin/env python3
"""Solve bone angles so a limb's end lands at a target position.

Run with Blender:
    blender --background --factory-startup --python tools/art/solve_pose_targets.py -- \
        --base docs/art/cultivator_tripo_v9/iterations/mia_rig/20260921-v2 \
        --target hand_l=0.08,-0.22,0.06 --target hand_r=-0.08,-0.22,0.06 \
        --report /tmp/solved.json

Why this exists
---------------
Hand-guessing Euler angles for a pose is slow and does not converge: rotating `LeftArm`
about X swings the hand OUT and UP, not forward, so the intuitive value puts the hand in
the wrong place and the error is only visible in a render. This tool removes the guessing.

It rotates a chain of bones with coordinate descent, minimising the straight-line distance
from the chain's end effector to a target world position. Coordinates are degrees in
Blender's bone-local XYZ Euler space, and the search is bounded to sane joint ranges so it
cannot find anatomically absurd solutions that merely happen to hit the target.

The output is a bone->degrees map in exactly the shape `author_cultivator_pose.py` uses, so
a solved chain can be pasted straight into its POSES table.
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Euler, Vector

## End effector -> (chain from proximal to distal, solved DOF per bone, joint limits).
##
## Limits are per-axis degrees. They exist so the solver cannot cheat with a shoulder
## dislocation to reach a nearby point: every accepted value must be a pose a person could
## actually hold.
CHAINS: dict[str, dict] = {
    "hand_l": {
        "end": "mixamorig:LeftHand",
        "bones": ["mixamorig:LeftArm", "mixamorig:LeftForeArm"],
        "limits": {
            "mixamorig:LeftArm": {"X": (-95, 95), "Y": (-70, 70), "Z": (-95, 60)},
            "mixamorig:LeftForeArm": {"X": (-10, 145), "Y": (-40, 40), "Z": (-45, 45)},
        },
    },
    "hand_r": {
        "end": "mixamorig:RightHand",
        "bones": ["mixamorig:RightArm", "mixamorig:RightForeArm"],
        # Mirrored: the right side's Z sign flips.
        "limits": {
            "mixamorig:RightArm": {"X": (-95, 95), "Y": (-70, 70), "Z": (-60, 95)},
            "mixamorig:RightForeArm": {"X": (-10, 145), "Y": (-40, 40), "Z": (-45, 45)},
        },
        "mirror_of": "hand_l",
    },
    "foot_l": {
        "end": "mixamorig:LeftToeBase",
        "bones": ["mixamorig:LeftUpLeg", "mixamorig:LeftLeg", "mixamorig:LeftFoot"],
        "limits": {
            "mixamorig:LeftUpLeg": {"X": (-45, 130), "Y": (-45, 45), "Z": (-5, 70)},
            "mixamorig:LeftLeg": {"X": (-155, 5), "Y": (-30, 30), "Z": (-60, 60)},
            "mixamorig:LeftFoot": {"X": (-40, 50), "Y": (-25, 25), "Z": (-30, 30)},
        },
    },
    "foot_r": {
        "end": "mixamorig:RightToeBase",
        "bones": ["mixamorig:RightUpLeg", "mixamorig:RightLeg", "mixamorig:RightFoot"],
        "limits": {
            "mixamorig:RightUpLeg": {"X": (-45, 130), "Y": (-45, 45), "Z": (-70, 5)},
            "mixamorig:RightLeg": {"X": (-155, 5), "Y": (-30, 30), "Z": (-60, 60)},
            "mixamorig:RightFoot": {"X": (-40, 50), "Y": (-25, 25), "Z": (-30, 30)},
        },
    },
}


def parse_args() -> argparse.Namespace:
    argv = sys.argv
    argv = argv[argv.index("--") + 1 :] if "--" in argv else []
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", required=True, help="dir holding clip_*_slot2.fbx")
    parser.add_argument("--target", action="append", required=True,
                        help="chain=x,y,z in metres (world, -Y is the character's front)")
    parser.add_argument("--fix", action="append", default=[],
                        help="bone=X,Y,Z to pin a bone the target depends on (e.g. the spine)")
    parser.add_argument("--coarse", type=float, default=12.0)
    parser.add_argument("--fine", type=float, default=1.0)
    parser.add_argument("--report", default="")
    return parser.parse_args(argv)


def bone(armature, name: str):
    for candidate in (name, name.replace(":", "_"), name.replace("_", ":")):
        found = armature.pose.bones.get(candidate)
        if found is not None:
            return found
    raise KeyError(name)


def apply_angles(armature, angles: dict, fixes: dict) -> None:
    for name, xyz in fixes.items():
        pb = bone(armature, name)
        pb.rotation_mode = "XYZ"
        pb.rotation_euler = Euler([math.radians(v) for v in xyz], "XYZ")
    for name, xyz in angles.items():
        pb = bone(armature, name)
        pb.rotation_mode = "XYZ"
        pb.rotation_euler = Euler([math.radians(v) for v in xyz], "XYZ")
    bpy.context.view_layer.update()


def end_position(armature, chain: dict) -> Vector:
    pb = bone(armature, chain["end"])
    return armature.matrix_world @ pb.head


def solve(armature, label: str, chain: dict, target: Vector, fixes: dict,
          coarse: float, fine: float) -> dict:
    names = chain["bones"]
    limits = chain["limits"]
    limits = {n: limits[n] for n in names}
    axes = ("X", "Y", "Z")
    angles = {n: [0.0, 0.0, 0.0] for n in names}

    def error(candidate: dict) -> float:
        apply_angles(armature, candidate, fixes)
        return (end_position(armature, chain) - target).length

    # Seed from zero, then coordinate descent at two granularities. Coordinate descent is
    # enough here: the chains are short (2-3 bones) and each sweep is cheap.
    for step in (coarse, coarse / 3.0, fine):
        improved = True
        sweeps = 0
        while improved and sweeps < 40:
            improved = False
            sweeps += 1
            for name in names:
                for axis_index, axis in enumerate(axes):
                    lo, hi = limits[name][axis]
                    best_value = angles[name][axis_index]
                    best_error = error(angles)
                    for delta in (step, -step):
                        trial = angles[name][axis_index] + delta
                        if trial < lo or trial > hi:
                            continue
                        angles[name][axis_index] = trial
                        candidate_error = error(angles)
                        if candidate_error < best_error - 1e-6:
                            best_error = candidate_error
                            best_value = trial
                            improved = True
                        angles[name][axis_index] = best_value
                    angles[name][axis_index] = best_value
        if step <= fine:
            break

    final_error = error(angles)
    return {
        "chain": label,
        "target": [round(v, 4) for v in target],
        "reached": [round(v, 4) for v in end_position(armature, chain)],
        "error_m": round(final_error, 5),
        "degrees": {n: [round(v, 1) for v in angles[n]] for n in names},
    }


def main() -> int:
    args = parse_args()
    repo = Path(__file__).resolve().parents[2]
    base = Path(args.base)
    if not base.is_absolute():
        base = repo / base

    # Prefer the idle clip: it is the rest-ish pose the authored pose should depart from.
    # Taking an arbitrary alphabetical match would silently use e.g. the flight clip as the
    # base, whose rest pose is already deformed.
    candidates = sorted(base.glob("clip_idle_slot2.fbx")) or sorted(base.glob("clip_*_slot2.fbx"))
    source = candidates[0] if candidates else None
    if source is None:
        print(f"FAIL: no clip_*_slot2.fbx under {base}", file=sys.stderr)
        return 2

    fixes: dict = {}
    for item in args.fix:
        name, _, raw = item.partition("=")
        fixes[name] = [float(v) for v in raw.split(",")]

    targets: dict = {}
    for item in args.target:
        label, _, raw = item.partition("=")
        if label not in CHAINS:
            print(f"FAIL: unknown chain {label!r}; known: {sorted(CHAINS)}", file=sys.stderr)
            return 2
        targets[label] = Vector([float(v) for v in raw.split(",")])

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=str(source), use_anim=True,
                             automatic_bone_orientation=True)
    armature = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    armature.animation_data_clear()

    report: dict = {"source": source.name, "fixes": fixes, "results": [],
                    "problems": []}
    print(f"source rig: {source.name}")
    if fixes:
        print(f"pinned: {fixes}")
    for label, target in targets.items():
        result = solve(armature, label, CHAINS[label], target, fixes,
                       args.coarse, args.fine)
        report["results"].append(result)
        print(f"\n=== {label} -> target ({target.x:+.3f}, {target.y:+.3f}, {target.z:+.3f})")
        print(f"    reached ({result['reached'][0]:+.3f}, {result['reached'][1]:+.3f}, "
              f"{result['reached'][2]:+.3f})  error {result['error_m']:.5f} m")
        for name, xyz in result["degrees"].items():
            print(f"      {name:<28} X={xyz[0]:+7.1f}  Y={xyz[1]:+6.1f}  Z={xyz[2]:+7.1f}")
        if result["error_m"] > 0.05:
            report["problems"].append(
                f"{label}: best solution is {result['error_m']:.3f} m from target "
                f"(joint limits may make it unreachable)")

    if args.report:
        out = Path(args.report)
        if not out.is_absolute():
            out = repo / out
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n")
        print(f"\nreport {out}")
    for problem in report["problems"]:
        print(f"  ! {problem}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
