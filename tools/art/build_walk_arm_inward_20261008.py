#!/usr/bin/env python3
"""Pull the walking forearms in to the standing wrist spread.

The 2026-10-06 walk already keeps the elbows near 6.5 cm outside the shoulders.
The remaining flare is the forearm on the backswing: the wrist reaches about
12.8 cm out, while standing is 7.7–8.5 cm. This pass rotates only the forearm
about the elbow, restores the hand's world orientation, and writes a new
version. The 20261006 source and export stay in place.

Blender --background --factory-startup --python-exit-code 1 \\
    --python tools/art/build_walk_arm_inward_20261008.py
"""

from __future__ import annotations

import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Matrix, Quaternion, Vector

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "docs/art/cultivator_balanced_motion_20261006/cultivator_balanced_motion_20261006.blend"
OUT = ROOT / "docs/art/cultivator_balanced_motion_20261008"
GLB = ROOT / "src/game/actors/swordsman/models/cultivator_balanced_motion_20261008.glb"
sys.path.insert(0, str(Path(__file__).parent))
from export_cultivator_aligned_motion_20260927 import CLIPS, glb_animation_names


def point(rig: bpy.types.Object, name: str) -> Vector:
    return rig.matrix_world @ rig.pose.bones["mixamorig:" + name].head


def shoulder_right(rig: bpy.types.Object) -> Vector:
    right = point(rig, "RightArm") - point(rig, "LeftArm")
    right.z = 0
    right.normalize()
    return right


def wrist_out(rig: bpy.types.Object, side: str, right: Vector) -> float:
    lateral = right if side == "Right" else -right
    return (point(rig, side + "Hand") - point(rig, side + "Arm")).dot(lateral)


def wrist_forward(rig: bpy.types.Object, side: str) -> float:
    # Same axis as measure_aligned_motion_geometry.py: -Y is the facing direction.
    return -(point(rig, side + "Hand") - point(rig, side + "Arm")).y


def set_linear(action: bpy.types.Action, bones: tuple[str, ...]) -> int:
    needles = tuple(f'pose.bones["mixamorig:{name}"].rotation_quaternion' for name in bones)
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
        raise RuntimeError("no forearm or hand rotation keys were switched to linear")
    return changed


def pull_forearm(rig: bpy.types.Object, side: str, target: float) -> float:
    """Rotate the forearm about the elbow until the wrist is at the standing spread.

    The angle is solved from the current bone positions. Updating the dependency
    graph before the new rotation is keyed would reload the old keys and discard
    the edit. The hand keeps the world orientation it had before this rotation.
    Returns the signed degrees applied.
    """
    forearm = rig.pose.bones["mixamorig:" + side + "ForeArm"]
    hand = rig.pose.bones["mixamorig:" + side + "Hand"]
    right = shoulder_right(rig)
    lateral = right if side == "Right" else -right
    shoulder = point(rig, side + "Arm")
    elbow = point(rig, side + "ForeArm")
    wrist = point(rig, side + "Hand")
    original = (wrist - shoulder).dot(lateral)
    if original <= target + 0.005:
        return 0.0
    axis = (wrist - elbow).cross(lateral)
    if axis.length < 1e-6:
        raise RuntimeError(f"{side} forearm is parallel to the outward axis")
    axis.normalize()
    offset = wrist - elbow

    def predicted(degrees: float) -> float:
        moved = elbow + Quaternion(axis, math.radians(degrees)) @ offset
        return (moved - shoulder).dot(lateral)

    sign = -1.0 if predicted(0.5) > original else 1.0
    if predicted(sign * 25.0) > target + 0.008:
        raise RuntimeError(
            f"{side} wrist stays {predicted(sign * 25.0):.3f} m out after 25° "
            f"(target {target:.3f} m, was {original:.3f} m)"
        )
    low, high = 0.0, 25.0
    for _ in range(16):
        mid = (low + high) / 2
        if predicted(sign * mid) <= target + 0.002:
            high = mid
        else:
            low = mid
    degrees = sign * high
    hand_world = (rig.matrix_world @ hand.matrix).to_quaternion()
    world = rig.matrix_world @ forearm.matrix
    pivot = world.translation.copy()
    rotated = Matrix.Rotation(math.radians(degrees), 4, axis)
    forearm.matrix = rig.matrix_world.inverted() @ (
        Matrix.Translation(pivot) @ rotated @ Matrix.Translation(-pivot) @ world
    )
    # The forearm edit above is local until the next update. Move the stored
    # hand orientation onto the predicted wrist so the palm does not twist.
    restored = hand_world.to_matrix().to_4x4()
    restored.translation = elbow + Quaternion(axis, math.radians(degrees)) @ offset
    # hand.matrix is in armature space. Convert the world pose back.
    hand.matrix = rig.matrix_world.inverted() @ restored
    return degrees


def main() -> None:
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
    bpy.context.preferences.filepaths.save_version = 0
    rig = next(obj for obj in bpy.data.objects if obj.type == "ARMATURE")
    scene = bpy.context.scene
    assert {action.name for action in bpy.data.actions} == CLIPS

    rig.animation_data.action = bpy.data.actions["idle"]
    scene.frame_set(round(bpy.data.actions["idle"].frame_range[0]))
    bpy.context.view_layer.update()
    right = shoulder_right(rig)
    targets = {side: wrist_out(rig, side, right) for side in ("Left", "Right")}

    action = bpy.data.actions["walk"]
    rig.animation_data.action = action
    first, last = (round(value) for value in action.frame_range)
    before = []
    for frame in range(first, last + 1):
        scene.frame_set(frame)
        bpy.context.view_layer.update()
        right = shoulder_right(rig)
        before.append({
            side: {
                "out": wrist_out(rig, side, right),
                "forward": wrist_forward(rig, side),
            }
            for side in ("Left", "Right")
        })

    applied = []
    for frame in range(first, last + 1):
        scene.frame_set(frame)
        bpy.context.view_layer.update()
        degrees = {}
        for side in ("Left", "Right"):
            degrees[side] = pull_forearm(rig, side, targets[side])
            for bone_name in (side + "ForeArm", side + "Hand"):
                rig.pose.bones["mixamorig:" + bone_name].keyframe_insert(
                    "rotation_quaternion", frame=frame
                )
        applied.append(degrees)
        bpy.context.view_layer.update()
    linear_keys = set_linear(action, (
        "LeftForeArm", "RightForeArm", "LeftHand", "RightHand",
    ))

    after = []
    for frame in range(first, last + 1):
        scene.frame_set(frame)
        bpy.context.view_layer.update()
        right = shoulder_right(rig)
        after.append({
            side: {
                "out": round(wrist_out(rig, side, right), 4),
                "forward": round(wrist_forward(rig, side), 4),
            }
            for side in ("Left", "Right")
        })

    def swing(samples: list[dict], side: str) -> float:
        values = [item[side]["forward"] for item in samples]
        return max(values) - min(values)

    problems = []
    for side, floor in (("Left", 0.12), ("Right", 0.12)):
        amount = swing(after, side)
        if amount < floor:
            problems.append(f"{side} forward swing {amount:.3f} m fell below {floor:.3f} m")
        peak = max(item[side]["out"] for item in after)
        if peak > targets[side] + 0.01:
            problems.append(f"{side} wrist still {peak:.3f} m outside standing {targets[side]:.3f} m")
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

    report = {
        "source": str(SOURCE.relative_to(ROOT)),
        "standing_wrist_out_m": {side: round(targets[side], 4) for side in targets},
        "before_wrist_out_m": {
            side: [round(min(item[side]["out"] for item in before), 4),
                   round(max(item[side]["out"] for item in before), 4)]
            for side in ("Left", "Right")
        },
        "after_wrist_out_m": {
            side: [round(min(item[side]["out"] for item in after), 4),
                   round(max(item[side]["out"] for item in after), 4)]
            for side in ("Left", "Right")
        },
        "forward_swing_m": {
            side: {
                "before": round(swing(before, side), 4),
                "after": round(swing(after, side), 4),
            }
            for side in ("Left", "Right")
        },
        "max_abs_forearm_deg": {
            side: round(max(abs(item[side]) for item in applied), 2)
            for side in ("Left", "Right")
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
    blend_path = OUT / "cultivator_balanced_motion_20261008.blend"
    bpy.ops.wm.save_as_mainfile(filepath=str(blend_path))
    meshes = [obj for obj in bpy.data.objects if obj.type == "MESH"
              and any(mod.type == "ARMATURE" for mod in obj.modifiers)]
    if len(meshes) != 1:
        raise RuntimeError(f"expected one skinned mesh, found {len(meshes)}")
    mesh = meshes[0]
    bpy.ops.object.select_all(action="DESELECT")
    rig.select_set(True)
    mesh.select_set(True)
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
