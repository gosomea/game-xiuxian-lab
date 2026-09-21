#!/usr/bin/env python3
"""Measure a locomotion clip's natural stride and cadence, to remove foot sliding.

Why this exists
---------------
`cultivator_skeleton_presentation.gd` advances a walk/run clip at

    rate = actual_speed / stride_meters

so `stride_meters` is the number that decides whether the feet appear to grip the
ground or skate. Guessing it (the current values, 1.6 and 3.2, are described in the
source as "approximate") means every speed change slides the feet.

These clips are IN PLACE: the root does not travel (that is what "in place" means, and
it is why root motion can be added by physics without double-counting). So measuring root
travel is meaningless here. The correct quantity is the **planted foot's backward travel
relative to the body** during its stance phase:

    while a foot is planted, the body would advance by exactly that distance

Therefore one step length `D` = the horizontal displacement of (foot - hips) over a
stance phase, and the speed at which the clip looks correctly grounded is

    natural_speed = D / stance_seconds

i.e. play at rate 1.0 while the actor moves at that speed and the foot grips the ground.
A full gait cycle is two steps, so stride_meters = 2 * D and
cadence = 1 / (2 * stance_seconds).

This also gives the anti-slide number directly: the residual wobble of the foot relative
to the body's own transport line. A clean clip keeps its planted foot on a straight
backward path; deviation from straight is the part a tween cannot hide.

Run with Blender:
    blender --background --factory-startup --python \
        tools/art/measure_clip_stride.py -- \
        --clip walk=docs/art/.../clip_walk_slot2.fbx \
        --clip run=docs/art/.../clip_run_slot2.fbx
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector

# Mixamo foot bones. The planted foot is whichever of these sits lowest.
FOOT_BONES = ("mixamorig:LeftToeBase", "mixamorig:RightToeBase",
              "mixamorig:LeftFoot", "mixamorig:RightFoot")
## How close to the clip's lowest contact counts as "on the ground".
CONTACT_BAND_M = 0.02


def parse_args() -> argparse.Namespace:
    argv = sys.argv
    argv = argv[argv.index("--") + 1 :] if "--" in argv else []
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--clip", action="append", required=True,
                        help="label=/path/to/clip.fbx")
    parser.add_argument("--report", default="")
    return parser.parse_args(argv)


def load_clip(fbx: Path):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=str(fbx), use_anim=True,
                             automatic_bone_orientation=True)
    armature = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    mesh = next(o for o in bpy.data.objects if o.type == "MESH")
    action = bpy.data.actions[0]
    if not armature.animation_data:
        armature.animation_data_create()
    armature.animation_data.action = action
    return armature, mesh, action


def bone_index(armature, *candidates) -> int:
    for name in candidates:
        for index, bone in enumerate(armature.pose.bones):
            if bone.name == name or bone.name.replace("_", ":") == name:
                return index
    return -1


def sample(armature, action) -> dict:
    """Per-frame foot world positions and root height, in armature space."""
    scene = bpy.context.scene
    foot_indices = {}
    for label, names in (("toe_l", ("mixamorig:LeftToeBase", "mixamorig_LeftToeBase")),
                         ("toe_r", ("mixamorig:RightToeBase", "mixamorig_RightToeBase")),
                         ("foot_l", ("mixamorig:LeftFoot", "mixamorig_LeftFoot")),
                         ("foot_r", ("mixamorig:RightFoot", "mixamorig_RightFoot"))):
        idx = bone_index(armature, *names)
        if idx >= 0:
            foot_indices[label] = idx
    if not foot_indices:
        raise RuntimeError("no foot bones found")

    hips = bone_index(armature, "mixamorig:Hips", "mixamorig_Hips")
    f_start, f_end = (int(round(v)) for v in action.frame_range)
    frames = []
    for frame in range(f_start, f_end + 1):
        scene.frame_set(frame)
        entry = {"frame": frame}
        for label, idx in foot_indices.items():
            pos = armature.matrix_world @ armature.pose.bones[idx].head
            entry[label] = (pos.x, pos.y, pos.z)
        if hips >= 0:
            hp = armature.matrix_world @ armature.pose.bones[hips].head
            entry["root"] = (hp.x, hp.y, hp.z)
        frames.append(entry)
    return {"frames": frames, "feet": sorted(foot_indices), "fps": scene.render.fps}


def analyse(data: dict) -> dict:
    frames = data["frames"]
    fps = data["fps"]
    n = len(frames)
    if n < 4:
        return {"error": "too few frames"}
    if "root" not in frames[0]:
        return {"error": "no hips/root bone found"}

    foot_keys = [k for k in data["feet"] if k.startswith("toe_")] or data["feet"]
    lows = [min(frames[i][k][2] for k in foot_keys) for i in range(n)]
    ground = min(lows)
    # "On the ground" band, relative to this clip's own lowest contact.
    band = ground + CONTACT_BAND_M

    def rel(i, k):
        """Foot position relative to the body root, horizontal only."""
        fx, fy, _fz = frames[i][k]
        rx, ry, _rz = frames[i]["root"]
        return fx - rx, fy - ry

    # Stance = the lowest foot is on the ground.
    stance = []
    for i in range(n):
        order = sorted(foot_keys, key=lambda k: frames[i][k][2])
        best = order[0]
        stance.append(best if frames[i][best][2] <= band else None)

    # Maximal runs of one planted foot.
    runs = []
    start = None
    for i, foot in enumerate(stance):
        if foot is None or (start is not None and stance[start] != foot):
            if start is not None:
                runs.append((start, i - 1, stance[start]))
            start = None if foot is None else i
        elif start is None:
            start = i
    if start is not None:
        runs.append((start, n - 1, stance[start]))

    steps = []
    for lo, hi in ((a, b) for a, b, _f in runs):
        foot = stance[lo]
        if hi <= lo:
            continue
        x0, y0 = rel(lo, foot)
        x1, y1 = rel(hi, foot)
        dx, dy = x1 - x0, y1 - y0
        travel = math.hypot(dx, dy)
        secs = (hi - lo) / fps
        # Straightness: how far each intermediate sample strays from the straight line
        # between the first and last sample of the stance.
        worst = 0.0
        if travel > 1e-6:
            ux, uy = dx / travel, dy / travel
            for j in range(lo, hi + 1):
                px, py = rel(j, foot)
                vx, vy = px - x0, py - y0
                # Perpendicular distance from the line.
                worst = max(worst, abs(vx * uy - vy * ux))
        steps.append({
            "foot": foot,
            "frames": [frames[lo]["frame"], frames[hi]["frame"]],
            "stance_seconds": round(secs, 4),
            "step_m": round(travel, 4),
            "path_wobble_m": round(worst, 4),
            "direction": [round(dx / travel, 3), round(dy / travel, 3)] if travel > 1e-6 else [0, 0],
        })

    # --- step length from the planted foot -------------------------------------------
    # These clips are IN PLACE (the root does not travel; physics supplies that). While a
    # foot is planted the body would advance by exactly the foot's backward travel through
    # the body's own frame, so that travel IS the step length, and
    #
    #     speed = step_length / stance_seconds
    #
    # is the speed at which the clip looks grounded (rate == 1.0). A full gait cycle is two
    # steps, so stride = 2 * step and cadence = 1 / (2 * stance).
    #
    # An earlier version tried autocorrelation to find the cycle length. It was removed
    # because it is unreliable on these signals: it locked onto step-to-step noise (returning
    # 3-frame "cycles" = 10 cycles/s) and disagreed between clips on which horizontal axis
    # is "forward". The stance measurement below needs no such inference and returns speeds
    # that match real human gait (walk ~1.3 m/s, run ~3.5 m/s), which is the check that it
    # is measuring the right thing.
    #
    # Clips with no usable stance (idle never steps; flight never touches down; sprint's
    # stance is 1-2 frames) are reported as having no measurable stride rather than given a
    # fabricated one.
    usable = [s for s in steps if s["step_m"] > 0.10 and s["stance_seconds"] > 0.03]

    def median(values):
        v = sorted(values)
        return v[len(v) // 2]

    duration = n / fps
    if usable:
        step_m = median(s["step_m"] for s in usable)
        stance_s = median(s["stance_seconds"] for s in usable)
        cycle_s = stance_s * 2.0
        stride_m = step_m * 2.0
        natural = step_m / stance_s if stance_s > 0 else 0.0
        wobbles = sorted(s["path_wobble_m"] for s in usable)
        stationary = False
    else:
        step_m = stance_s = stride_m = natural = 0.0
        cycle_s = duration
        wobbles = [0.0]
        stationary = True

    return {
        "frames": n,
        "fps": fps,
        "duration_s": round(duration, 4),
        "method": "planted-foot-stance",
        "stationary": stationary,
        "usable_stance_steps": len(usable),
        "step_meters": round(step_m, 4),
        "stride_meters": round(stride_m, 4),
        "stance_seconds": round(stance_s, 4),
        "cycle_seconds": round(cycle_s, 4),
        "cadence_cycles_per_s": round(1.0 / cycle_s, 4) if cycle_s > 0 else 0.0,
        "natural_speed_mps": round(natural, 4),
        "median_path_wobble_m": round(wobbles[len(wobbles) // 2], 4),
        "max_path_wobble_m": round(wobbles[-1], 4),
        "detail": steps,
    }


def main() -> int:
    args = parse_args()
    repo = Path(__file__).resolve().parents[2]
    results = {}
    for item in args.clip:
        label, sep, raw = item.partition("=")
        if not sep:
            print(f"FAIL: --clip needs label=path, got {item!r}", file=sys.stderr)
            return 2
        fbx = Path(raw)
        if not fbx.is_absolute():
            fbx = repo / fbx
        if not fbx.is_file():
            print(f"FAIL: missing {fbx}", file=sys.stderr)
            return 2
        armature, _mesh, action = load_clip(fbx)
        data = sample(armature, action)
        stats = analyse(data)
        results[label] = stats
        if "error" in stats:
            print(f"{label}: ERROR {stats['error']}")
            continue
        print(f"=== {label}  ({Path(raw).name})")
        print(f"    duration {stats['duration_s']:.3f}s  frames {stats['frames']} "
              f"@ {stats['fps']}fps  stance runs {stats['usable_stance_steps']}")
        print(f"    stance steps {stats['usable_stance_steps']}  "
              f"stationary={stats['stationary']}")
        print(f"    step {stats['step_meters']:.4f} m  stance {stats['stance_seconds']:.4f} s")
        print(f"    stride(2 steps) {stats['stride_meters']:.4f} m  "
              f"cycle {stats['cycle_seconds']:.4f} s  "
              f"cadence {stats['cadence_cycles_per_s']:.3f}/s")
        print(f"    NATURAL SPEED {stats['natural_speed_mps']:.4f} m/s "
              f"(rate==1.0 at this speed)")
        print(f"    planted-foot path wobble: median "
              f"{stats['median_path_wobble_m']:.4f} m  max {stats['max_path_wobble_m']:.4f} m")

    if args.report:
        out = Path(args.report)
        if not out.is_absolute():
            out = repo / out
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(json.dumps(results, indent=2, ensure_ascii=False) + "\n")
        print(f"\nreport {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
