#!/usr/bin/env python3
"""Bring the walking hands forward to the chest without reopening the arms.

The 20261008 walk already holds the wrists near the standing lateral spread,
but the upper arm only reaches about +2° in front of vertical. The visible
"swing" is almost all behind the body. This pass adds shoulder flexion on the
forward half of each arm's existing phase and leaves the backswing, the legs,
and the other clips alone.

Blender --background --factory-startup --python-exit-code 1 \\
    --python tools/art/build_walk_forward_swing_20261008.py
"""

from __future__ import annotations

import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "docs/art/cultivator_balanced_motion_20261008/cultivator_balanced_motion_20261008.blend"
OUT = ROOT / "docs/art/cultivator_balanced_motion_20261008_swing"
GLB = ROOT / "src/game/actors/swordsman/models/cultivator_balanced_motion_20261008_swing.glb"
# Added at the forward peak. A probe on this asset shows +26° carries the
# wrist from 6 cm to about 28 cm in front of the shoulder, past the chest,
# while the lateral offset stays put.
PEAK_FLEXION_DEG = 26.0
# Portion of the existing swing, measured from the back extreme, that stays
# unchanged. The rest eases up to PEAK_FLEXION_DEG.
BACKSWING_HOLD = 0.45

sys.path.insert(0, str(Path(__file__).parent))
from export_cultivator_aligned_motion_20260927 import CLIPS, glb_animation_names


def point(rig: bpy.types.Object, name: str) -> Vector:
    return rig.matrix_world @ rig.pose.bones["mixamorig:" + name].head


def body_axes(rig: bpy.types.Object) -> tuple[Vector, Vector]:
    right = point(rig, "RightArm") - point(rig, "LeftArm")
    right.z = 0
    right.normalize()
    toes = (point(rig, "LeftToeBase") + point(rig, "RightToeBase")) / 2
    feet = (point(rig, "LeftFoot") + point(rig, "RightFoot")) / 2
    forward = toes - feet
    forward.z = 0
    forward.normalize()
    return right, forward


def wrist_forward(rig: bpy.types.Object, side: str, forward: Vector) -> float:
    return (point(rig, side + "Hand") - point(rig, side + "Arm")).dot(forward)


def wrist_out(rig: bpy.types.Object, side: str, right: Vector) -> float:
    lateral = right if side == "Right" else -right
    return (point(rig, side + "Hand") - point(rig, side + "Arm")).dot(lateral)


def extra_flexion(forward_m: float, low: float, high: float) -> float:
    span = high - low
    if span < 1e-4:
        return 0.0
    phase = (forward_m - low) / span
    if phase <= BACKSWING_HOLD:
        return 0.0
    t = (phase - BACKSWING_HOLD) / (1.0 - BACKSWING_HOLD)
    t = t * t * (3.0 - 2.0 * t)
    return PEAK_FLEXION_DEG * t


def set_linear(action: bpy.types.Action) -> int:
    needles = (
        'pose.bones["mixamorig:LeftArm"].rotation_quaternion',
        'pose.bones["mixamorig:RightArm"].rotation_quaternion',
    )
    changed = 0
    for layer in action.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                for curve in bag.fcurves:
                    if not any(needle in curve.data_path for needle in needles):
                        continue
                    for key in curve.keyframe_points:
                        key.interpolation = "LINEAR"
                        changed += 1
    if changed == 0:
        raise RuntimeError("no upper-arm rotation keys were switched to linear")
    return changed


def flex_upper_arm(rig: bpy.types.Object, side: str, right: Vector, degrees: float) -> None:
    if degrees <= 0.05:
        return
    bone = rig.pose.bones["mixamorig:" + side + "Arm"]
    shoulder = point(rig, side + "Arm")
    world = rig.matrix_world @ bone.matrix
    rotated = Matrix.Rotation(math.radians(degrees), 4, right)
    bone.matrix = rig.matrix_world.inverted() @ (
        Matrix.Translation(shoulder) @ rotated @ Matrix.Translation(-shoulder) @ world
    )


def main() -> None:
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
    bpy.context.preferences.filepaths.save_version = 0
    rig = next(obj for obj in bpy.data.objects if obj.type == "ARMATURE")
    scene = bpy.context.scene
    assert {action.name for action in bpy.data.actions} == CLIPS

    rig.animation_data.action = bpy.data.actions["idle"]
    scene.frame_set(round(bpy.data.actions["idle"].frame_range[0]))
    bpy.context.view_layer.update()
    idle_right, _idle_forward = body_axes(rig)
    standing_out = {side: wrist_out(rig, side, idle_right) for side in ("Left", "Right")}

    action = bpy.data.actions["walk"]
    rig.animation_data.action = action
    first, last = (round(value) for value in action.frame_range)
    frames = list(range(first, last + 1))
    before = []
    for frame in frames:
        scene.frame_set(frame)
        bpy.context.view_layer.update()
        right, forward = body_axes(rig)
        before.append({
            side: {
                "forward": wrist_forward(rig, side, forward),
                "out": wrist_out(rig, side, right),
            }
            for side in ("Left", "Right")
        })
    span = {
        side: (
            min(item[side]["forward"] for item in before),
            max(item[side]["forward"] for item in before),
        )
        for side in ("Left", "Right")
    }

    applied = []
    for frame, sample in zip(frames, before):
        scene.frame_set(frame)
        bpy.context.view_layer.update()
        right, _forward = body_axes(rig)
        degrees = {}
        for side in ("Left", "Right"):
            low, high = span[side]
            degrees[side] = extra_flexion(sample[side]["forward"], low, high)
            flex_upper_arm(rig, side, right, degrees[side])
            rig.pose.bones["mixamorig:" + side + "Arm"].keyframe_insert(
                "rotation_quaternion", frame=frame
            )
        applied.append(degrees)
    linear_keys = set_linear(action)

    after = []
    for frame in frames:
        scene.frame_set(frame)
        bpy.context.view_layer.update()
        right, forward = body_axes(rig)
        chest = point(rig, "Spine2")
        after.append({
            side: {
                "forward": wrist_forward(rig, side, forward),
                "out": wrist_out(rig, side, right),
                "chest": (point(rig, side + "Hand") - chest).dot(forward),
            }
            for side in ("Left", "Right")
        })

    problems = []
    for side in ("Left", "Right"):
        peak = max(item[side]["forward"] for item in after)
        chest = max(item[side]["chest"] for item in after)
        outward = max(item[side]["out"] for item in after)
        if peak < 0.20:
            problems.append(f"{side} forward reach {peak:.3f} m is still short of the chest")
        if chest < 0.15:
            problems.append(f"{side} wrist only {chest:.3f} m in front of the chest")
        if outward > standing_out[side] + 0.025:
            problems.append(
                f"{side} wrist flared to {outward:.3f} m "
                f"(standing {standing_out[side]:.3f} m)"
            )
    scene.frame_set(first)
    bpy.context.view_layer.update()
    start = {bone.name: bone.matrix.copy() for bone in rig.pose.bones}
    scene.frame_set(last)
    bpy.context.view_layer.update()
    seam = max(
        math.degrees(start[bone.name].to_quaternion().rotation_difference(
            bone.matrix.to_quaternion()).angle)
        for bone in rig.pose.bones
    )
    if seam > 0.5:
        problems.append(f"walk loop seam is {seam:.2f}°")
    if problems:
        raise RuntimeError("; ".join(problems))

    def bounds(samples: list[dict], side: str, key: str) -> list[float]:
        values = [item[side][key] for item in samples]
        return [round(min(values), 4), round(max(values), 4)]

    report = {
        "source": str(SOURCE.relative_to(ROOT)),
        "peak_flexion_deg": PEAK_FLEXION_DEG,
        "before_wrist_forward_m": {side: bounds(before, side, "forward") for side in ("Left", "Right")},
        "after_wrist_forward_m": {side: bounds(after, side, "forward") for side in ("Left", "Right")},
        "after_wrist_ahead_of_chest_m": {side: bounds(after, side, "chest") for side in ("Left", "Right")},
        "after_wrist_out_m": {side: bounds(after, side, "out") for side in ("Left", "Right")},
        "standing_wrist_out_m": {side: round(standing_out[side], 4) for side in standing_out},
        "max_flexion_deg": {
            side: round(max(item[side] for item in applied), 2) for side in ("Left", "Right")
        },
        "loop_seam_deg": round(seam, 3),
        "linear_rotation_keys": linear_keys,
    }
    for clip in bpy.data.actions:
        clip.use_fake_user = True
    rig.animation_data.action = bpy.data.actions["idle"]
    scene.frame_set(0)
    bpy.context.view_layer.update()
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "build_report.json").write_text(json.dumps(report, indent=2) + "\n")
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT / "cultivator_balanced_motion_20261008_swing.blend"))
    meshes = [obj for obj in bpy.data.objects if obj.type == "MESH"
              and any(mod.type == "ARMATURE" for mod in obj.modifiers)]
    if len(meshes) != 1:
        raise RuntimeError(f"expected one skinned mesh, found {len(meshes)}")
    bpy.ops.object.select_all(action="DESELECT")
    rig.select_set(True)
    meshes[0].select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.export_scene.gltf(
        filepath=str(GLB),
        export_format="GLB",
        use_selection=True,
        export_animation_mode="ACTIONS",
        export_animations=True,
        export_skins=True,
        export_yup=True,
        export_apply=False,
        export_normals=True,
        export_materials="EXPORT",
        export_frame_range=False,
        export_force_sampling=True,
        export_bake_animation=False,
    )
    names = glb_animation_names(GLB)
    if names != CLIPS:
        raise RuntimeError(f"exported clips {sorted(names)} != {sorted(CLIPS)}")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
