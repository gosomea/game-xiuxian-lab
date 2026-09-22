#!/usr/bin/env python3
"""Measure a character's spine axis against world vertical, for FBX or GLB.

Run with Blender:
    blender --background --factory-startup --python tools/art/measure_spine_axis.py -- \
        --source idle=/path/clip_idle_slot2.fbx --source runtime=/path/model.glb

Why this exists
---------------
A character can stand visibly crooked while every rotation-based check passes, because the
crookedness is a small forward/sideways offset of the upper body rather than a rotation of
any single bone. `measure_glb_upright.py` reads the hips yaw (catches "turned sideways") and
`score_mia_clip.py` reads the hips yaw bias too; neither reads whether the head is actually
ABOVE the feet.

This tool answers exactly that, in world space, for both the source FBX and the built GLB, so
"did the build introduce the lean?" is answerable rather than a matter of opinion. It reports:

  spine_tilt_deg    angle between the hips->head axis and world vertical
  horizontal_m      how far the head is displaced horizontally from the hips
  head_over_feet_m  horizontal distance from the head to the midpoint of the two toes
  facing            the horizontal direction the toes extend in (the character's forward)

Read the numbers, not a render: a 12 deg tilt is plainly visible in a game view but easy to
miss in a small thumbnail, and a thumbnail cannot tell a real lean from a camera choice.
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector

BONE_ALIASES = {
    "hips": ("mixamorig:Hips", "mixamorig_Hips", "Hips"),
    "head": ("mixamorig:Head", "mixamorig_Head", "Head"),
    "neck": ("mixamorig:Neck", "mixamorig_Neck", "Neck"),
    "toe_l": ("mixamorig:LeftToeBase", "mixamorig_LeftToeBase", "LeftToeBase"),
    "toe_r": ("mixamorig:RightToeBase", "mixamorig_RightToeBase", "RightToeBase"),
    "foot_l": ("mixamorig:LeftFoot", "mixamorig_LeftFoot", "LeftFoot"),
    "foot_r": ("mixamorig:RightFoot", "mixamorig_RightFoot", "RightFoot"),
}


def parse_args() -> argparse.Namespace:
    argv = sys.argv
    argv = argv[argv.index("--") + 1 :] if "--" in argv else []
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", action="append", required=True, help="label=/path/file")
    parser.add_argument("--report", default="")
    return parser.parse_args(argv)


def find_bone(armature, key: str):
    for name in BONE_ALIASES[key]:
        bone = armature.pose.bones.get(name)
        if bone is not None:
            return bone
    return None


def measure(path: Path, sample_frames: int = 12) -> dict:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    if path.suffix.lower() == ".glb":
        bpy.ops.import_scene.gltf(filepath=str(path))
    else:
        bpy.ops.import_scene.fbx(filepath=str(path), use_anim=True,
                                 automatic_bone_orientation=True)

    armatures = [o for o in bpy.data.objects if o.type == "ARMATURE"]
    if not armatures:
        return {"error": "no armature"}
    armature = armatures[0]

    # Character stands along world Z in Blender (Z-up). Bind the animation if one exists.
    action = bpy.data.actions[0] if bpy.data.actions else None
    if action is not None:
        if not armature.animation_data:
            armature.animation_data_create()
        armature.animation_data.action = action
        frame_start, frame_end = (int(round(v)) for v in action.frame_range)
    else:
        frame_start, frame_end = 1, 1

    bones = {key: find_bone(armature, key) for key in BONE_ALIASES}
    if bones["hips"] is None or bones["head"] is None:
        return {"error": "missing hips or head bone"}

    step = max(1, (frame_end - frame_start + 1) // sample_frames)
    samples = []
    for frame in range(frame_start, frame_end + 1, step):
        bpy.context.scene.frame_set(frame)
        positions = {}
        for key, bone in bones.items():
            if bone is None:
                continue
            positions[key] = armature.matrix_world @ bone.head
        if "hips" not in positions or "head" not in positions:
            continue
        hips, head = positions["hips"], positions["head"]

        spine = head - hips
        horizontal = math.hypot(spine.x, spine.y)
        tilt = math.degrees(math.atan2(horizontal, spine.z)) if spine.z > 0 else 180.0

        head_over_feet = None
        facing = None
        if "toe_l" in positions and "toe_r" in positions:
            feet = (positions["toe_l"] + positions["toe_r"]) * 0.5
            offset = Vector((head.x - feet.x, head.y - feet.y, 0.0))
            offset_len = offset.magnitude
            head_over_feet = offset_len
            if offset_len > 1e-6:
                d = offset.normalized()
                facing = [-round(d.x, 3), -round(d.y, 3)]

        samples.append(
            {
                "frame": frame,
                "tilt_deg": round(tilt, 2),
                "horizontal_m": round(horizontal, 4),
                "head_over_feet_m": round(head_over_feet, 4) if head_over_feet else None,
                "facing": facing,
                # Signed components: +X is the character's left-right axis in Blender's Z-up
                # frame after the Mixamo import, +Y is forward for this rig's bind pose.
                "spine_x": round(spine.x, 4),
                "spine_y": round(spine.y, 4),
                "spine_z": round(spine.z, 4),
            }
        )

    if not samples:
        return {"error": "no samples"}
    tilts = [s["tilt_deg"] for s in samples]
    hxs = [s["horizontal_m"] for s in samples]
    sxs = [s["spine_x"] for s in samples]
    syss = [s["spine_y"] for s in samples]
    return {
        "file": path.name,
        "frames_sampled": len(samples),
        "tilt_deg_mean": round(sum(tilts) / len(tilts), 2),
        "tilt_deg_max": round(max(tilts), 2),
        "horizontal_m_mean": round(sum(hxs) / len(hxs), 4),
        # Which horizontal direction the head is offset in decides whether this is a forward
        # lean (natural posture) or a sideways lean (crooked).
        "spine_x_mean": round(sum(sxs) / len(sxs), 4),
        "spine_y_mean": round(sum(syss) / len(syss), 4),
        "facing": samples[0]["facing"],
        "head_over_feet_m_mean": (
            round(sum(s["head_over_feet_m"] for s in samples if s["head_over_feet_m"]) /
                  max(1, len([s for s in samples if s["head_over_feet_m"]])), 4)
        ),
        "samples": samples,
    }


def main() -> int:
    args = parse_args()
    repo = Path(__file__).resolve().parents[2]
    report = {}
    for item in args.source:
        label, sep, raw = item.partition("=")
        if not sep:
            print(f"FAIL: --source needs label=path, got {item!r}", file=sys.stderr)
            return 2
        path = Path(raw)
        if not path.is_absolute():
            path = repo / path
        if not path.is_file():
            print(f"FAIL: missing {path}", file=sys.stderr)
            return 2
        stats = measure(path)
        report[label] = stats
        if "error" in stats:
            print(f"  {label:<22} ERROR {stats['error']}")
            continue
        axis = "前后(forward/back)" if abs(stats["spine_y_mean"]) > abs(stats["spine_x_mean"]) \
            else "左右(sideways)"
        print(f"  {label:<22} tilt={stats['tilt_deg_mean']:>6.2f}°  "
              f"horizontal={stats['horizontal_m_mean']:.4f} m  "
              f"偏移主轴={axis}  facing={stats['facing']}")
    if args.report:
        out = Path(args.report)
        out.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n")
        print(f"\nreport {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
