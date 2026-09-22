#!/usr/bin/env python3
"""Measure a locomotion clip's step length from foot excursion (no stance detection).

Run with Blender:
    blender --background --factory-startup --python tools/art/measure_clip_excursion.py -- \
        --clip sprint=/path/clip_run_slot2.fbx

Why this exists alongside `measure_clip_stride.py`
--------------------------------------------------
`measure_clip_stride.py` finds the planted foot and measures how far it travels backwards
through the body. That needs a stance phase of at least a few frames, so it returns
"stationary / no stance" for very short or very fast clips - a 17-frame sprint has a
1-2 frame contact, and `Flying` never touches down at all.

This tool uses a method that needs no contact detection: for each foot it takes the
horizontal range of (foot - hips) over the clip. For a symmetric gait the foot swings
forward and back through the body once per full cycle, so that range IS the stride
(two steps), and dividing by the clip duration gives the speed at which the clip looks
grounded.

Trade-off: it assumes the clip contains ONE gait cycle. A clip holding several cycles
(e.g. a 10 s idle walk) would have its multi-cycle range treated as a single cycle, so
`measure_clip_stride.py` remains authoritative whenever a stance exists. Use this only
for the short/fast/airborne clips where that one cannot decide.
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path

import bpy

FOOT_PAIRS = (
    ("mixamorig:LeftToeBase", "mixamorig_LeftToeBase"),
    ("mixamorig:RightToeBase", "mixamorig_RightToeBase"),
)
HIP_NAMES = ("mixamorig:Hips", "mixamorig_Hips")


def parse_args() -> argparse.Namespace:
    argv = sys.argv
    argv = argv[argv.index("--") + 1 :] if "--" in argv else []
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--clip", action="append", required=True, help="label=/path/clip.fbx")
    parser.add_argument("--report", default="")
    return parser.parse_args(argv)


def find_bone(armature, names):
    for name in names:
        bone = armature.pose.bones.get(name)
        if bone is not None:
            return bone
    return None


def measure(fbx: Path) -> dict:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=str(fbx), use_anim=True,
                             automatic_bone_orientation=True)
    armature = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    action = bpy.data.actions[0]
    if not armature.animation_data:
        armature.animation_data_create()
    armature.animation_data.action = action

    hips = find_bone(armature, HIP_NAMES)
    if hips is None:
        return {"error": "no Hips bone"}
    feet = [find_bone(armature, pair) for pair in FOOT_PAIRS]
    feet = [f for f in feet if f is not None]
    if not feet:
        return {"error": "no foot bones"}

    fps = bpy.context.scene.render.fps
    start, end = (int(round(v)) for v in action.frame_range)
    per_foot = {}
    for foot in feet:
        xs, ys = [], []
        for frame in range(start, end + 1):
            bpy.context.scene.frame_set(frame)
            fp = armature.matrix_world @ foot.head
            hp = armature.matrix_world @ hips.head
            xs.append(fp.x - hp.x)
            ys.append(fp.y - hp.y)
        per_foot[foot.name] = math.hypot(max(xs) - min(xs), max(ys) - min(ys))

    excursion = sum(per_foot.values()) / len(per_foot)
    frames = end - start + 1
    duration = frames / fps
    # Excursion spans one full gait cycle (forward swing + backward push), i.e. two steps.
    step = excursion / 2.0
    stride = step * 2.0
    return {
        "file": fbx.name,
        "frames": frames,
        "fps": fps,
        "duration_s": round(duration, 4),
        "foot_excursion_m": round(excursion, 4),
        "per_foot_excursion_m": {k: round(v, 4) for k, v in per_foot.items()},
        "step_meters": round(step, 4),
        "stride_meters": round(stride, 4),
        "natural_speed_mps": round(stride / duration, 4) if duration > 0 else 0.0,
        "method": "foot excursion relative to hips / one cycle per clip",
        "assumption": "clip contains exactly one gait cycle",
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
        stats = measure(fbx)
        results[label] = stats
        if "error" in stats:
            print(f"{label}: ERROR {stats['error']}")
            continue
        print(f"=== {label}  ({Path(raw).name})")
        print(f"    frames {stats['frames']} @ {stats['fps']}fps = {stats['duration_s']}s")
        print(f"    foot excursion {stats['foot_excursion_m']:.4f} m")
        print(f"    step {stats['step_meters']:.4f} m   stride(2 steps) {stats['stride_meters']:.4f} m")
        print(f"    NATURAL SPEED {stats['natural_speed_mps']:.4f} m/s (rate==1.0 here)")
        print(f"    ({stats['assumption']})")

    if args.report:
        out = Path(args.report)
        if not out.is_absolute():
            out = repo / out
        out.write_text(json.dumps(results, indent=2, ensure_ascii=False) + "\n")
        print(f"\nreport {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
