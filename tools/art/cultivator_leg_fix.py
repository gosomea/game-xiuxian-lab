#!/usr/bin/env python3
"""Correct the standing shear: legs slope forward while the torso is upright.

Imported by `build_cultivator_tripo_v9_runtime_glb.py`; usable standalone.

The bind pose puts the feet 0.175 m in front of the hips: both legs slope forward ~12
degrees and the character reads as leaning back even though every torso check passes.
The shear is inherited by every clip from the bind (each clip's pelvis-to-ankle offset is
constant), so the correction is a posture adjustment baked into the clips, not a
re-animation.

Correction, per clip, in three moves that mirror the measured geometry:

  1. rotate the leg chain (thigh, shin) so the ankle swings back under the pelvis -
     closed-form from leg lengths: theta = asin(shear / (thigh + shin));
  2. counter-rotate the foot so the sole is flat again - the sole pitch is measured, and
     the ankle had swung, so the foot rotation is solved per side, not assumed;
  3. translate the hips forward by the shear so the pelvis lands over the (unmoved)
     feet - the feet stay on the ground exactly where they were.

After the moves the ankle is ~1.9 cm higher (straightening a slanted leg shortens its
vertical reach); the per-clip ground offset pass absorbs that, so the feet stay on the
floor. A short residual polish (bounded, few passes) cleans up what the closed form
misses, because the chain is not perfectly straight.

Mixamo local axes are convention, not anatomy: the axis that swings the ankle is probed,
not guessed (same lesson as cultivator_lean_fix).
"""

from __future__ import annotations

import math

import bpy
from mathutils import Quaternion, Vector

## Corrected standing posture: pelvis over the feet, sole flat.
LEG_TOLERANCE_M = 0.02
SOLE_TOLERANCE_DEG = 2.5
POLISH_PASSES = 12

## Fallback responses used only for the FIRST step of each stage; after that the solver
## uses the response it measured on the previous pass. Both were probed on this rig:
## swing axis X moves the ankle +0.01254 m/deg, foot axis X folds the sole -1.01 deg/deg.
SWING_RESPONSE_FALLBACK = 0.01254
FOOT_RESPONSE_FALLBACK = -1.0111

## Clips whose legs hold a designed non-standing shape. Their SOLE is still flattened and
## the hips are still shifted (so contact stays consistent), but the leg swing is left to
## the pose itself: straightening a cross-legged or riding pose would destroy it.
SHAPE_PRESERVED_CLIPS = {"meditate", "sword_ride"}


def find_bone(armature, name):
    for candidate in (f"mixamorig:{name}", f"mixamorig_{name}"):
        bone = armature.pose.bones.get(candidate)
        if bone is not None:
            return bone
    return None


def find_chain(armature) -> dict | None:
    chain = {}
    for key in ("Hips", "LeftUpLeg", "LeftLeg", "LeftFoot", "LeftToeBase",
                "RightUpLeg", "RightLeg", "RightFoot", "RightToeBase"):
        bone = find_bone(armature, key)
        if bone is None:
            return None
        chain[key] = bone
    return chain


def world_of(armature, pose_bone, tip=False) -> Vector:
    matrix = armature.matrix_world @ pose_bone.matrix
    if tip:
        return armature.matrix_world @ (pose_bone.matrix
                                        @ Vector((0.0, pose_bone.length, 0.0)))
    return matrix.to_translation()


def forward_axis(armature, chain) -> Vector:
    """Facing measured ankle->toe, not assumed from a bone frame."""
    direction = (world_of(armature, chain["LeftToeBase"])
                 - world_of(armature, chain["LeftFoot"]))
    direction.z = 0.0
    if direction.length_squared < 1e-9:
        return Vector((0.0, -1.0, 0.0))
    return direction.normalized()


def pelvis_offset(armature, chain, forward: Vector) -> float:
    hips = world_of(armature, chain["Hips"])
    ankles = (world_of(armature, chain["LeftFoot"])
              + world_of(armature, chain["RightFoot"])) / 2.0
    delta = hips - ankles
    delta.z = 0.0
    return delta.dot(forward)


def sole_pitch(armature, chain, forward: Vector) -> float:
    ankle = world_of(armature, chain["LeftFoot"])
    toe = world_of(armature, chain["LeftToeBase"])
    return math.degrees(math.atan2(ankle.z - toe.z,
                                   max((toe - ankle).dot(forward), 1e-6)))


def measure(armature, scene, action, chain, forward) -> tuple[float, float]:
    armature.animation_data.action = action
    start, end = (int(round(v)) for v in action.frame_range)
    offsets, pitches = [], []
    for frame in range(start, end + 1):
        scene.frame_set(frame)
        bpy.context.view_layer.update()
        offsets.append(pelvis_offset(armature, chain, forward))
        pitches.append(sole_pitch(armature, chain, forward))
    mean = lambda v: sum(v) / len(v)
    return mean(offsets), mean(pitches)


def probe_swing_axis(armature, scene, chain, forward) -> Vector:
    """Local axis of LeftUpLeg that moves the ankle most along -forward (deg/deg)."""
    thigh = chain["LeftUpLeg"]
    if thigh.rotation_mode != "QUATERNION":
        thigh.rotation_mode = "QUATERNION"
    saved = thigh.rotation_quaternion.copy()
    saved_action = armature.animation_data.action
    armature.animation_data.action = None
    bpy.context.view_layer.update()

    def ankle_forward_distance() -> float:
        ankle = world_of(armature, chain["LeftFoot"])
        return (ankle - world_of(armature, chain["Hips"])).dot(forward)

    base = ankle_forward_distance()
    best_axis, best_response = Vector((1.0, 0.0, 0.0)), 0.0
    probe = 8.0
    for axis_index in range(3):
        axis = Vector((0.0, 0.0, 0.0))
        axis[axis_index] = 1.0
        thigh.rotation_quaternion = saved @ Quaternion(axis, math.radians(probe))
        bpy.context.view_layer.update()
        response = (ankle_forward_distance() - base) / probe
        if abs(response) > abs(best_response):
            best_axis, best_response = axis.copy(), response
    thigh.rotation_quaternion = saved
    armature.animation_data.action = saved_action
    bpy.context.view_layer.update()
    print(f"leg shear: swing axis {tuple(round(c, 3) for c in best_axis)} "
          f"response {best_response:+.5f} m/deg", flush=True)
    return best_axis.normalized()


def snapshot(armature, scene, action, bones: list) -> dict:
    armature.animation_data.action = action
    start, end = (int(round(v)) for v in action.frame_range)
    state = {}
    for frame in range(start, end + 1):
        scene.frame_set(frame)
        for bone in bones:
            state[(frame, bone.name)] = bone.rotation_quaternion.copy()
    return state


def restore(armature, scene, action, state: dict, bones: list) -> None:
    armature.animation_data.action = action
    start, end = (int(round(v)) for v in action.frame_range)
    for frame in range(start, end + 1):
        scene.frame_set(frame)
        for bone in bones:
            bone.rotation_quaternion = state[(frame, bone.name)]
            bone.keyframe_insert("rotation_quaternion", frame=frame)
    bpy.context.view_layer.update()


def bake(armature, scene, action, state: dict, bones: list, swing_deg: float,
         swing_axis: Vector, foot_deg: float, hips_shift_m: float, forward: Vector) -> None:
    """From the clip's own keyframes: swing the legs, flatten the feet, shift the hips.

    Rotations are the same on both sides (the shear is a bind property, not a pose), and
    are composed onto the existing keyframe so they read as a posture adjustment.
    """
    armature.animation_data.action = action
    start, end = (int(round(v)) for v in action.frame_range)
    swing = Quaternion(swing_axis, math.radians(swing_deg))
    foot_q = Quaternion(Vector((1.0, 0.0, 0.0)), math.radians(foot_deg))
    swing_bones = [bones["thigh"], bones["shin"], bones["thigh_r"], bones["shin_r"]]
    foot_bones = [bones["foot"], bones["foot_r"]]
    hips = bones["hips"]
    for frame in range(start, end + 1):
        scene.frame_set(frame)
        for bone in swing_bones:
            bone.rotation_quaternion = state[(frame, bone.name)] @ swing
            bone.keyframe_insert("rotation_quaternion", frame=frame)
        for bone in foot_bones:
            bone.rotation_quaternion = state[(frame, bone.name)] @ foot_q
            bone.keyframe_insert("rotation_quaternion", frame=frame)
        if abs(hips_shift_m) > 1e-6:
            hips.location = hips.location + forward * hips_shift_m
            hips.keyframe_insert("location", frame=frame)
    bpy.context.view_layer.update()


def _cost(offset_m: float, pitch_deg: float) -> float:
    """Solver cost with both residuals normalized by their tolerance.

    Raw |offset| + |pitch| treats 1 cm as 1 degree. The standing defect the user reports
    is the offset, and its tolerance is 2 cm against the sole's 2.5 deg - so an unweighted
    sum rejects the very pass that nails the offset (measured: idle_guarded found
    offset -0.0003 m and rejected it three times because the pitch read 23 vs 20).
    """
    return abs(offset_m) / LEG_TOLERANCE_M + abs(pitch_deg) / SOLE_TOLERANCE_DEG


def correct_clip(armature, scene, action, chain, forward, swing_axis: Vector,
                 clip: str) -> dict:
    legs = {
        "hips": chain["Hips"],
        "thigh": chain["LeftUpLeg"], "shin": chain["LeftLeg"],
        "foot": chain["LeftFoot"],
        "thigh_r": chain["RightUpLeg"], "shin_r": chain["RightLeg"],
        "foot_r": chain["RightFoot"],
    }
    bone_list = list(legs.values())
    for bone in bone_list:
        if bone.rotation_mode != "QUATERNION":
            bone.rotation_mode = "QUATERNION"

    original = snapshot(armature, scene, action, bone_list)
    start_offset, start_pitch = measure(armature, scene, action, chain, forward)

    # Closed-form first move: swing the leg so the ankle lands under the pelvis.
    shear = -start_offset          # positive shear means feet forward of the pelvis
    # Leg lengths from the DEFORMED chain (hip->knee, knee->ankle), not from bone.length:
    # this rig stores bone lengths in raw armature units (up.length == 4224, i.e. mm-scale)
    # while the world transforms are metres, so bone.length is off by three orders of
    # magnitude and silently produced swing_deg near zero on the first solver run.
    thigh_head = world_of(armature, chain["LeftUpLeg"])
    knee_head = world_of(armature, chain["LeftLeg"])
    ankle_head = world_of(armature, chain["LeftFoot"])
    thigh_len = (knee_head - thigh_head).length
    shin_len = (ankle_head - knee_head).length
    leg_reach = thigh_len + shin_len
    if clip in SHAPE_PRESERVED_CLIPS:
        swing_deg = 0.0
        hips_shift = 0.0
    else:
        # Swing the legs so the ankles land under the (unmoved) pelvis.
        # Measured response: +deg about the probed axis moves the ankle ALONG forward
        # (+12 deg -> delta=(-0.034,-0.165) with forward=(+0.28,-0.96)), so bringing the
        # ankle BACK under the hips needs -shear of travel => negative degrees.
        ratio = min(max(shear / max(leg_reach, 1e-6), -1.0), 1.0)
        swing_deg = -math.degrees(math.asin(ratio))
        # The pelvis must NOT translate: shifting the hips carries the whole leg - feet
        # included - with it, so the offset is unchanged and the ground contact is lost
        # (first solver run: offset went -0.16 -> -0.37). The rotation alone zeroes it.
        hips_shift = 0.0

    # Second move: 2x2 Newton with a finite-difference Jacobian. The two knobs are
    # COUPLED - rotating the foot folds the leg forward and shifts the offset as well
    # (measured: foot +20 deg changed pitch -25 deg AND offset +0.01 m) - so solving them
    # one at a time converged neither. Newton on both at once handles the coupling
    # explicitly: each pass measures all four partials from two probe bakes, then steps
    # both knobs against the local Jacobian.
    def bake_and_measure(swing_v: float, foot_v: float):
        """Bake from the clip's own keyframes with these knob values, then measure."""
        bake(armature, scene, action, original, legs, swing_v, swing_axis,
             foot_v, hips_shift, forward)
        return measure(armature, scene, action, chain, forward)

    swing_total = swing_deg
    foot_total = 0.0
    history = []
    offset, pitch = measure(armature, scene, action, chain, forward)
    best_cost = _cost(offset, pitch)
    best_pair = (swing_total, foot_total)
    probe_swing, probe_foot = 2.0, 4.0
    failures = 0
    for pass_index in range(POLISH_PASSES):
        leg_res = -offset
        sole_res = -pitch
        if (abs(leg_res) <= LEG_TOLERANCE_M and abs(sole_res) <= SOLE_TOLERANCE_DEG):
            break
        o_s, p_s = bake_and_measure(swing_total + probe_swing, foot_total)
        o_f, p_f = bake_and_measure(swing_total, foot_total + probe_foot)
        j11 = (o_s - offset) / probe_swing     # d(offset)/d(swing)
        j21 = (p_s - pitch) / probe_swing      # d(pitch)/d(swing)
        j12 = (o_f - offset) / probe_foot      # d(offset)/d(foot)
        j22 = (p_f - pitch) / probe_foot       # d(pitch)/d(foot)
        det = j11 * j22 - j12 * j21
        if abs(det) < 1e-9:
            history.append({"pass": pass_index + 1, "note": "singular jacobian"})
            break
        ds = (leg_res * j22 - sole_res * j12) / det
        df = (sole_res * j11 - leg_res * j21) / det
        # Bound the per-pass step: a wild Jacobian entry must not fling the pose.
        ds = max(min(ds, 6.0), -6.0)
        df = max(min(df, 12.0), -12.0)
        trial_swing = swing_total + ds
        trial_foot = foot_total + df
        trial_offset, trial_pitch = bake_and_measure(trial_swing, trial_foot)
        cost = _cost(trial_offset, trial_pitch)
        improved = cost < best_cost
        history.append({"pass": pass_index + 1,
                        "swing_deg": round(trial_swing, 3),
                        "foot_deg": round(trial_foot, 3),
                        "offset_m": round(trial_offset, 4),
                        "pitch_deg": round(trial_pitch, 3),
                        "accepted": improved})
        if improved:
            swing_total, foot_total = trial_swing, trial_foot
            offset, pitch = trial_offset, trial_pitch
            best_cost, best_pair = cost, (swing_total, foot_total)
            failures = 0
        else:
            trial_swing = swing_total + ds * 0.5
            trial_foot = foot_total + df * 0.5
            trial_offset, trial_pitch = bake_and_measure(trial_swing, trial_foot)
            cost = _cost(trial_offset, trial_pitch)
            halved_ok = cost < best_cost
            history.append({"pass": pass_index + 1, "halved": True,
                            "swing_deg": round(trial_swing, 3),
                            "foot_deg": round(trial_foot, 3),
                            "offset_m": round(trial_offset, 4),
                            "pitch_deg": round(trial_pitch, 3),
                            "accepted": halved_ok})
            if halved_ok:
                swing_total, foot_total = trial_swing, trial_foot
                offset, pitch = trial_offset, trial_pitch
                best_cost, best_pair = cost, (swing_total, foot_total)
                failures = 0
            else:
                # Rejecting both steps does NOT mean the target is unreachable: the
                # Jacobian is measured at the current point and can point the wrong way
                # in a nonlinear region (idle_guarded pass 1 rejected twice, yet the
                # closed-form start was already within 6 cm of the target). Back off to
                # the best pair, shrink the probe so the local Jacobian is more honest,
                # and only stop after several consecutive failures.
                bake_and_measure(*best_pair)
                offset, pitch = measure(armature, scene, action, chain, forward)
                probe_swing = max(probe_swing * 0.5, 0.25)
                probe_foot = max(probe_foot * 0.5, 0.5)
                failures += 1
                if failures >= 3:
                    break



    final_offset, final_pitch = offset, pitch
    leg_ok = (clip in SHAPE_PRESERVED_CLIPS
              or abs(final_offset) <= LEG_TOLERANCE_M)
    sole_ok = abs(final_pitch) <= SOLE_TOLERANCE_DEG
    return {
        "clip": clip,
        "offset_before_m": round(start_offset, 4),
        "offset_after_m": round(final_offset, 4),
        "pitch_before_deg": round(start_pitch, 3),
        "pitch_after_deg": round(final_pitch, 3),
        "swing_deg": round(swing_total, 3),
        "foot_deg": round(foot_total, 3),
        "hips_shift_m": round(hips_shift, 4),
        "converged": leg_ok and sole_ok,
        "passes": history,
    }


def correct_standing_shear(armature, scene, clips: list[str] | None = None) -> dict:
    """Correct the leg shear across every clip. Returns a report for the build log."""
    chain = find_chain(armature)
    if chain is None:
        return {"error": "leg chain bones not found"}
    forward = forward_axis(armature, chain)
    if armature.animation_data is None:
        armature.animation_data_create()
    swing_axis = probe_swing_axis(armature, scene, chain, forward)

    actions = ([bpy.data.actions[name] for name in clips if name in bpy.data.actions]
               if clips else sorted(bpy.data.actions, key=lambda a: a.name))
    reports = []
    for action in actions:
        report = correct_clip(armature, scene, action, chain, forward, swing_axis,
                              action.name)
        reports.append(report)
        print(f"leg shear [{action.name:<13}] offset {report['offset_before_m']:+.4f} -> "
              f"{report['offset_after_m']:+.4f} m, sole {report['pitch_before_deg']:+.2f} -> "
              f"{report['pitch_after_deg']:+.2f} deg (swing {report['swing_deg']:+.2f}, "
              f"foot {report['foot_deg']:+.2f}, hips shift {report['hips_shift_m']:+.4f})"
              f"{'  OK' if report['converged'] else '  NOT CONVERGED'}", flush=True)

    failed = [r["clip"] for r in reports if not r["converged"]]
    return {
        "forward_axis": [round(forward.x, 4), round(forward.y, 4)],
        "clips": reports,
        "failed_clips": failed,
        "targets": {"offset_m": 0.0, "pitch_deg": 0.0,
                    "leg_tolerance_m": LEG_TOLERANCE_M,
                    "sole_tolerance_deg": SOLE_TOLERANCE_DEG},
    }
