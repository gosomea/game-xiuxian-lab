#!/usr/bin/env python3
"""Correct a constant torso lean on an already-imported Blender armature.

Imported by `build_cultivator_tripo_v9_runtime_glb.py`; also usable from a standalone script.

Why this is a module rather than part of a Blender tool
------------------------------------------------------
The correction was first written as a tool that imported an FBX, fixed it and exported a new
FBX. That round-trip was the source of three separate defects, because Blender's FBX exporter
always bakes the armature OBJECT's transform into an animation track:

  * the downstream floor shift applied to that track as well as to the static root value, so
    the character floated 1.09 m (Armature translation +2.1066 m = 2 x the 1.0533 m shift);
  * clearing the object's animation to prevent it also deleted the BONE action, and the build
    failed with "import produced no action";
  * a re-baselining attempt to compensate made it worse again (+3.1600 = 3 x the shift).

Correcting the pose in memory, before anything is exported, removes the entire class of
problem: there is no intermediate file for an exporter to rewrite.

The measurement
---------------
The lean is the angle of the hips->head axis from world vertical, signed by whether the head
sits behind or in front of the hips. A whole-body tilt shows up here and is invisible to
rotation-only checks, because no single bone is rotated far from its rest orientation: the
error is distributed across the spine.
"""

from __future__ import annotations

import math

import bpy
from mathutils import Quaternion, Vector

SPINE_CHAIN = ("mixamorig:Spine", "mixamorig:Spine1", "mixamorig:Spine2")
HIP_NAMES = ("mixamorig:Hips", "mixamorig_Hips")
HEAD_NAMES = ("mixamorig:Head", "mixamorig_Head")

## Clips whose hips->head axis must NOT be forced upright: a seated pose is supposed to fold.
SEATED_CLIPS = {"meditate"}


def find_bone(armature, names):
    for name in names:
        bone = armature.pose.bones.get(name)
        if bone is not None:
            return bone
    return None


def lean_degrees(armature) -> float:
    """Signed lean of the hips->head axis: positive means the head is BEHIND the hips."""
    hips = find_bone(armature, HIP_NAMES)
    head = find_bone(armature, HEAD_NAMES)
    if hips is None or head is None:
        raise RuntimeError("missing hips or head bone")

    hips_pos = armature.matrix_world @ hips.head
    head_pos = armature.matrix_world @ head.head
    delta = head_pos - hips_pos

    # This rig's bind pose faces -Y, established by measuring the ankle->toe direction on the
    # service-produced clips. Using a fixed axis avoids depending on any bone's local frame.
    backward = Vector((0.0, 1.0, 0.0))
    horizontal = Vector((delta.x, delta.y, 0.0))
    signed = horizontal.dot(backward)
    return math.degrees(math.atan2(signed, max(delta.z, 1e-6)))


def mean_lean(armature, scene, frames) -> float:
    values = []
    for frame in frames:
        scene.frame_set(frame)
        bpy.context.view_layer.update()
        values.append(lean_degrees(armature))
    return sum(values) / len(values) if values else 0.0


def sample_frames(start: int, end: int, count: int = 16):
    if end <= start:
        return [start]
    step = max(1, (end - start + 1) // count)
    return list(range(start, end + 1, step))


def _probe_axis(armature, scene, frame: int, spines, probe_deg: float = 6.0):
    """Which local axis of the spine moves the head forward/back most, and how strongly.

    Solved by measurement: a Mixamo bone's local axes are a rigging convention, not anatomy, so
    "X is pitch" is a guess. An earlier hand-authored pose was wrong for exactly that reason.
    """
    # Detach the action while probing. `scene.frame_set` re-evaluates the animation and would
    # overwrite each trial rotation, so every axis reads as zero response ("no spine axis
    # changes the lean"). Probing against a frozen pose is also what we actually want: the
    # response is a property of the rig at this pose, not of the clip's timeline.
    scene.frame_set(frame)
    action = armature.animation_data.action if armature.animation_data else None
    if armature.animation_data:
        armature.animation_data.action = None
    bpy.context.view_layer.update()

    baseline = lean_degrees(armature)
    responses = {}
    for bone_index, bone in enumerate(spines):
        original = bone.rotation_quaternion.copy()
        for axis_index in range(3):
            axis = Vector((0.0, 0.0, 0.0))
            axis[axis_index] = 1.0
            bone.rotation_quaternion = original @ Quaternion(axis, math.radians(probe_deg))
            bpy.context.view_layer.update()
            moved = lean_degrees(armature)
            responses[(bone_index, axis_index)] = (moved - baseline) / probe_deg
            bone.rotation_quaternion = original
    bpy.context.view_layer.update()
    if armature.animation_data:
        armature.animation_data.action = action
    bpy.context.view_layer.update()
    best = max(responses, key=lambda key: abs(responses[key]))
    return best[0], best[1], responses[best], responses


def correct_action(armature, scene, action, clip: str, target_lean_deg: float,
                   tolerance: float = 0.35, max_passes: int = 8) -> dict:
    """Bake a constant counter-rotation across the spine chain so the torso stands as asked.

    Uses a bracketed line search rather than a derivative step. The derivative is not safe
    here: re-probing after a first correction reports the response in the ALREADY-rotated
    state, where the chain has crossed upright and the effective sign flips, so dividing by it
    diverges (measured: 3.5 -> 5.5 -> 9.1 -> 15.4 -> 26.7 -> 47.1 -> 84.6 degrees).
    """
    if clip in SEATED_CLIPS:
        return {"skipped": "seated pose - must not be planted upright"}

    spines = []
    for name in SPINE_CHAIN:
        bone = armature.pose.bones.get(name)
        if bone is not None:
            bone.rotation_mode = "QUATERNION"
            spines.append(bone)
    if not spines:
        return {"error": "no spine bones found"}

    start, end = (int(round(v)) for v in action.frame_range)
    frames = sample_frames(start, end)
    before = mean_lean(armature, scene, frames)
    if abs(before - target_lean_deg) < tolerance:
        return {"lean_before_deg": round(before, 3), "lean_after_deg": round(before, 3),
                "residual_deg": round(before - target_lean_deg, 3), "converged": True,
                "passes": [], "note": "already within tolerance"}

    probe_frame = frames[len(frames) // 2]
    bone_index, axis_index, response, all_responses = _probe_axis(
        armature, scene, probe_frame, spines)
    if abs(response) < 1e-3:
        return {"error": "no spine axis changes the lean"}

    def bake(rotation_deg: float) -> None:
        axis = Vector((0.0, 0.0, 0.0))
        axis[axis_index] = 1.0
        delta = Quaternion(axis, math.radians(rotation_deg / len(spines)))
        for frame in range(start, end + 1):
            scene.frame_set(frame)
            for bone in spines:
                bone.rotation_quaternion = bone.rotation_quaternion @ delta
                bone.keyframe_insert("rotation_quaternion", frame=frame)

    def snapshot():
        state = {}
        for frame in range(start, end + 1):
            scene.frame_set(frame)
            for bone in spines:
                state[(frame, bone.name)] = bone.rotation_quaternion.copy()
        return state

    def restore(state):
        for frame in range(start, end + 1):
            scene.frame_set(frame)
            for bone in spines:
                bone.rotation_quaternion = state[(frame, bone.name)]
                bone.keyframe_insert("rotation_quaternion", frame=frame)

    # First step from the initial probe: -residual / response, since `response` is
    # d(lean)/d(rotation) and the change in lean we want is -(current - target).
    passes = []
    total = 0.0
    first = (-(before - target_lean_deg) / response)
    bake(first)
    best = mean_lean(armature, scene, frames)
    total += first
    passes.append({"pass": 1, "before": round(before, 3), "after": round(best, 3),
                   "applied_deg": round(first, 3), "accepted": True})

    step_scale = 1.0
    for attempt in range(max_passes):
        residual = best - target_lean_deg
        if abs(residual) < tolerance:
            break
        trial_rotation = (-residual / response) * step_scale
        state = snapshot()
        bake(trial_rotation)
        trial = mean_lean(armature, scene, frames)
        improved = abs(trial - target_lean_deg) < abs(best - target_lean_deg)
        passes.append({"pass": attempt + 2, "before": round(best, 3), "after": round(trial, 3),
                       "applied_deg": round(trial_rotation, 3), "accepted": improved})
        if improved:
            best = trial
            total += trial_rotation
            step_scale = 1.0
        else:
            restore(state)
            step_scale *= 0.5
            if step_scale < 0.05:
                passes.append({"pass": attempt + 2, "note": "line search exhausted"})
                break

    return {
        "lean_before_deg": round(before, 3),
        "lean_after_deg": round(best, 3),
        "residual_deg": round(best - target_lean_deg, 3),
        "converged": abs(best - target_lean_deg) < tolerance,
        "target_lean_deg": target_lean_deg,
        "probe_axis": "XYZ"[axis_index],
        "probe_bone": spines[bone_index].name,
        "probe_response_deg_per_deg": round(response, 4),
        "probe_all_axes": {f"{SPINE_CHAIN[k[0]]}.{'XYZ'[k[1]]}": round(v, 4)
                           for k, v in all_responses.items()},
        "rotation_applied_total_deg": round(total, 3),
        "passes": passes,
    }
