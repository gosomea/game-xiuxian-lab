#!/usr/bin/env python3
"""Correct a constant backward/forward lean baked into a locomotion clip.

Run with Blender:
    blender --background --factory-startup --python tools/art/correct_clip_lean.py -- \
        --input  docs/.../clip_idle_slot2.fbx \
        --output docs/.../clip_idle_slot2.fbx \
        --target-lean-deg 1.0

Why this exists
---------------
The v9 character stands visibly tilted: measured against a rendered plumb line, the torso
leans back about 12.5 degrees from the vertical through the ankles, and the same offset is
present in the freshly rigged `slot1.glb` (13.9 deg) before this repository touched it. So it
is inherited from the auto-rig rather than introduced by the build, but it is still wrong for
a character who is supposed to stand like a pine.

The tilt shows up in an isometric game view as the figure appearing to lean, which reads as
"the character is crooked" and is easy to mistake for a camera-angle artifact. Reasoning about
bone frames produced contradictory answers, so the correction here is solved numerically
rather than derived: probe which local axis of the spine actually moves the head back over the
hips, then scale that response to reach the target.

Where the correction goes
-------------------------
The spine chain, not the hips. The legs are siblings of the spine under Hips, so rotating the
spine leaves the feet planted; rotating Hips would swing the legs and lift the feet off the
ground. The correction is spread evenly over Spine/Spine1/Spine2 so no single joint takes a
visibly sharp bend.

Output is `clip_<name>_slot2.fbx` in the same shape the build script already consumes, so a
corrected clip flows through the normal ground-align and material-splice pipeline.
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Euler, Quaternion, Vector

SPINE_CHAIN = ("mixamorig:Spine", "mixamorig:Spine1", "mixamorig:Spine2")
HIP_NAMES = ("mixamorig:Hips", "mixamorig_Hips")
HEAD_NAMES = ("mixamorig:Head", "mixamorig_Head")
FOOT_NAMES = (("mixamorig:LeftFoot", "mixamorig_LeftFoot"),
              ("mixamorig:RightFoot", "mixamorig_RightFoot"))


def parse_args() -> argparse.Namespace:
    argv = sys.argv
    argv = argv[argv.index("--") + 1 :] if "--" in argv else []
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--target-lean-deg", type=float, default=1.0,
                        help="desired backward lean; 0 = perfectly plumb, small positive "
                             "keeps a natural posture (default: %(default)s)")
    parser.add_argument("--report", default="")
    return parser.parse_args(argv)


def find_bone(armature, names):
    for name in names:
        bone = armature.pose.bones.get(name)
        if bone is not None:
            return bone
    return None


def lean_degrees(armature) -> tuple[float, Vector]:
    """Signed backward lean of the hips->head axis, plus the raw horizontal offset.

    Positive means the head sits BEHIND the hips (a backward lean). The forward direction is
    taken from the feet: for this rig the toes extend along -Y, so "behind" is +Y.
    """
    hips = find_bone(armature, HIP_NAMES)
    head = find_bone(armature, HEAD_NAMES)
    feet = [find_bone(armature, names) for names in FOOT_NAMES]
    if hips is None or head is None:
        raise RuntimeError("missing hips or head bone")

    hips_pos = armature.matrix_world @ hips.head
    head_pos = armature.matrix_world @ head.head
    delta = head_pos - hips_pos

    # Forward axis from the feet when available; fall back to -Y, this rig's bind forward.
    forward = Vector((0.0, -1.0, 0.0))
    toe_bones = [find_bone(armature, ("mixamorig:LeftToeBase", "mixamorig_LeftToeBase")),
                 find_bone(armature, ("mixamorig:RightToeBase", "mixamorig_RightToeBase"))]
    if all(f is not None for f in feet) and all(t is not None for t in toe_bones):
        ankle = (armature.matrix_world @ feet[0].head + armature.matrix_world @ feet[1].head) * 0.5
        toe = (armature.matrix_world @ toe_bones[0].head + armature.matrix_world @ toe_bones[1].head) * 0.5
        flat = Vector((toe.x - ankle.x, toe.y - ankle.y, 0.0))
        if flat.length > 1e-4:
            forward = flat.normalized()

    horizontal = Vector((delta.x, delta.y, 0.0))
    # Project onto the backward axis: positive = head behind the hips.
    backward = -forward
    signed = horizontal.dot(backward)
    degrees = math.degrees(math.atan2(signed, max(delta.z, 1e-6)))
    return degrees, horizontal


def mean_lean(armature, frames: list[int]) -> float:
    values = []
    for frame in frames:
        bpy.context.scene.frame_set(frame)
        degrees, _ = lean_degrees(armature)
        values.append(degrees)
    return sum(values) / len(values) if values else 0.0


def sample_frames(start: int, end: int, count: int = 16) -> list[int]:
    if end <= start:
        return [start]
    step = max(1, (end - start + 1) // count)
    return list(range(start, end + 1, step))


def probe_spine_axis(armature, frame: int, spines: list, probe_deg: float = 6.0):
    """Find which local axis of the spine moves the head forward/back most effectively.

    Returns (bone_index, axis_index, degrees_of_lean_per_degree_of_rotation). Solved by
    measurement because a Mixamo bone's local axes are a rigging convention, not anatomy:
    guessing "X is pitch" is how an earlier pose ended up with the arms overhead.
    """
    bpy.context.scene.frame_set(frame)
    baseline, _ = lean_degrees(armature)
    responses = {}
    for bone_index, bone in enumerate(spines):
        original = bone.rotation_quaternion.copy()
        for axis_index in range(3):
            axis = Vector((0.0, 0.0, 0.0))
            axis[axis_index] = 1.0
            bone.rotation_quaternion = original @ Quaternion(axis, math.radians(probe_deg))
            bpy.context.view_layer.update()
            moved, _ = lean_degrees(armature)
            responses[(bone_index, axis_index)] = (moved - baseline) / probe_deg
            bone.rotation_quaternion = original
    bpy.context.view_layer.update()
    best = max(responses, key=lambda k: abs(responses[k]))
    return best[0], best[1], responses[best], responses


def main() -> int:
    args = parse_args()
    repo = Path(__file__).resolve().parents[2]
    source = Path(args.input)
    if not source.is_absolute():
        source = repo / source
    if not source.is_file():
        print(f"FAIL: missing {source}", file=sys.stderr)
        return 2

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=str(source), use_anim=True,
                             automatic_bone_orientation=True)
    armature = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    action = bpy.data.actions[0]
    if not armature.animation_data:
        armature.animation_data_create()
    armature.animation_data.action = action

    spines = []
    for name in SPINE_CHAIN:
        bone = armature.pose.bones.get(name)
        if bone is not None:
            bone.rotation_mode = "QUATERNION"
            spines.append(bone)
    if not spines:
        print("FAIL: none of the spine bones found", file=sys.stderr)
        return 2

    start, end = (int(round(v)) for v in action.frame_range)
    frames = sample_frames(start, end)

    before = mean_lean(armature, frames)
    needed = args.target_lean_deg - before
    print(f"clip frames {start}..{end} ({end - start + 1})")
    print(f"mean backward lean BEFORE: {before:+.2f} deg   target {args.target_lean_deg:+.2f} "
          f"=> need {needed:+.2f} deg")

    if abs(needed) < 0.35:
        print("already within tolerance; writing a byte-identical copy is unnecessary, "
              "but the output is still produced so the pipeline stays uniform")

    # Probe on a mid-clip frame where the pose is representative.
    probe_frame = frames[len(frames) // 2]
    bone_index, axis_index, response, responses = probe_spine_axis(armature, probe_frame, spines)
    print(f"probe: axis {'XYZ'[axis_index]} of {spines[bone_index].name} moves the lean "
          f"{response:+.3f} deg per deg")
    if abs(response) < 1e-3:
        print("FAIL: no spine axis changes the lean; cannot correct", file=sys.stderr)
        return 3

    # `needed > 0` means we want MORE backward lean; the probe response is signed, so the
    # rotation to apply is needed/response regardless of direction.
    total_rotation = needed / response
    per_bone = total_rotation / len(spines)
    axis = Vector((0.0, 0.0, 0.0))
    axis[axis_index] = 1.0
    delta_quat = Quaternion(axis, math.radians(per_bone))
    print(f"applying {total_rotation:+.2f} deg total, {per_bone:+.2f} deg on each of "
          f"{len(spines)} spine bones")

    # Bake the correction into every frame, distributing it over the chain. Sampling every
    # frame keeps the loop intact and avoids interpolating across the correction.
    for frame in range(start, end + 1):
        bpy.context.scene.frame_set(frame)
        for bone in spines:
            # Pre-multiplying in the bone's own space yields a constant offset for every pose.
            bone.rotation_quaternion = bone.rotation_quaternion @ delta_quat
            bone.keyframe_insert("rotation_quaternion", frame=frame)

    after = mean_lean(armature, sample_frames(start, end))
    # One pass undershoots: the probe measures the response at a single frame and the chain
    # response bends as the joints accumulate rotation (measured: 12.81 -> 3.53 when the
    # target was 1.0). Refine until inside tolerance, and record every pass so a failure to
    # converge is visible in the report instead of silently shipping a half-corrected clip.
    passes = [{"pass": 1, "before": round(before, 3), "after": round(after, 3),
               "correction_deg": round(total_rotation, 3), "accepted": True}]
    # A derivative step is unsafe here: re-probing after the first pass reports the response in
    # the ALREADY-rotated state, where the chain has crossed the upright position and the
    # effective sign flips, so dividing by it diverges (measured: 3.5 -> 5.5 -> 9.1 -> 15.4 ->
    # 26.7 -> 47.1 -> 84.6 deg). Use a bracketed line search that only accepts improvements and
    # halves the step when a trial makes things worse.
    axis_index_ref = axis_index
    best = after
    step_scale = 1.0
    for attempt in range(8):
        residual = best - args.target_lean_deg
        if abs(residual) < 0.35:
            break
        # `residual = current - target` is positive when still leaning too far back, so the
        # change in lean we want is -residual. `response` is d(lean)/d(rotation), hence the
        # rotation needed is (-residual)/response.
        trial_rotation = (-residual / response) * step_scale

        previous_state = {}
        for frame in range(start, end + 1):
            bpy.context.scene.frame_set(frame)
            for bone in spines:
                previous_state[(frame, bone.name)] = bone.rotation_quaternion.copy()

        axis_vec = Vector((0.0, 0.0, 0.0))
        axis_vec[axis_index_ref] = 1.0
        dq = Quaternion(axis_vec, math.radians(trial_rotation / len(spines)))
        for frame in range(start, end + 1):
            bpy.context.scene.frame_set(frame)
            for bone in spines:
                bone.rotation_quaternion = bone.rotation_quaternion @ dq
                bone.keyframe_insert("rotation_quaternion", frame=frame)

        trial = mean_lean(armature, sample_frames(start, end))
        improved = abs(trial - args.target_lean_deg) < abs(best - args.target_lean_deg)
        passes.append({"pass": attempt + 2, "before": round(best, 3),
                       "trial": round(trial, 3),
                       "correction_deg": round(trial_rotation, 3),
                       "accepted": improved})
        print(f"  search pass {attempt + 2}: trial {best:+.2f} -> {trial:+.2f} deg "
              f"(applied {trial_rotation:+.2f}) {'accepted' if improved else 'rejected'}")
        if improved:
            best = trial
            total_rotation += trial_rotation
            step_scale = 1.0
        else:
            # Restore the previous pose and try a smaller step in the same direction.
            for frame in range(start, end + 1):
                bpy.context.scene.frame_set(frame)
                for bone in spines:
                    bone.rotation_quaternion = previous_state[(frame, bone.name)]
                    bone.keyframe_insert("rotation_quaternion", frame=frame)
            step_scale *= 0.5
            if step_scale < 0.05:
                print("  line search exhausted; stopping at the best found")
                break
    after = best

    print(f"mean backward lean AFTER:  {after:+.2f} deg  (residual "
          f"{after - args.target_lean_deg:+.2f} deg)")

    out = Path(args.output)
    if not out.is_absolute():
        out = repo / out
    out.parent.mkdir(parents=True, exist_ok=True)

    # Strip only the OBJECT-level transform curves, keeping the bone action.
    #
    # `bake_anim=True` also bakes the armature OBJECT's transform into an animation track, and
    # the downstream floor shift then applies to that track on top of the static shift it
    # already writes, lifting the character twice (measured Armature translation +2.1066 m =
    # 2 x 1.0533 m, feet floating 1.09 m). The armature object never moves, so those curves
    # carry no information the bones lack.
    #
    # Clearing the whole object's animation_data would be wrong: it also removes the bone
    # action, and the build then fails with "import produced no action".
    stripped_curves: list[str] = []
    for obj in bpy.data.objects:
        if obj.type != "ARMATURE" or obj.animation_data is None:
            continue
        action = obj.animation_data.action
        if action is None:
            continue
        # Blender 5 action layout: curves live in channelbags inside layer strips. Fall back
        # to the flat attribute for older/other action shapes.
        try:
            bags = [cb for layer in action.layers for strip in layer.strips
                    for cb in strip.channelbags]
        except AttributeError:
            bags = []
        if not bags and hasattr(action, "fcurves"):
            bags = [action]
        for bag in bags:
            for curve in [fc for fc in bag.fcurves
                          if not fc.data_path.startswith("pose.bones")]:
                stripped_curves.append(f"{curve.data_path}[{curve.array_index}]")
                bag.fcurves.remove(curve)
    if stripped_curves:
        print(f"stripped {len(stripped_curves)} object-level curve(s): {stripped_curves[:6]}")
    bpy.context.view_layer.update()

    bpy.ops.export_scene.fbx(
        filepath=str(out),
        use_selection=False,
        bake_anim=True,
        bake_anim_use_all_bones=True,
        bake_anim_use_nla_strips=False,
        bake_anim_force_startend_keying=True,
        path_mode="COPY",
        embed_textures=False,
    )
    size = out.stat().st_size
    print(f"wrote {out} ({size:,} bytes)")

    report = {
        "input": str(source),
        "output": str(out),
        "bytes": size,
        "frames": [start, end],
        "lean_before_deg": round(before, 3),
        "lean_after_deg": round(after, 3),
        "target_lean_deg": args.target_lean_deg,
        "residual_deg": round(after - args.target_lean_deg, 3),
        "probe_axis": "XYZ"[axis_index],
        "probe_bone": spines[bone_index].name,
        "probe_response_deg_per_deg": round(response, 4),
        "probe_all_axes": {f"{SPINE_CHAIN[k[0]]}.{'XYZ'[k[1]]}": round(v, 4)
                           for k, v in responses.items()},
        "rotation_applied_total_deg": round(total_rotation, 3),
        "refinement_passes": passes,
        "converged": abs(after - args.target_lean_deg) < 0.35,
        "rotation_per_bone_deg": round(per_bone, 3),
        "stripped_object_curves": sorted(set(stripped_curves)),
        "method": "measure mean hips->head lean, probe the spine axis that moves it, "
                  "bake a constant counter-rotation across the spine chain, then export "
                  "bone curves only so the downstream floor shift is not applied twice",
    }
    if args.report:
        path = Path(args.report)
        if not path.is_absolute():
            path = repo / path
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n")
        print(f"report {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
