#!/usr/bin/env python3
"""Stand the cultivator's upper body up and give the arms a front-of-thigh neutral.

The rig was bound with the chest about 15 cm behind the pelvis. The leg pass
of 2026-10-06 put the ankles back under the pelvis but left the chest leaning
back about 5.4°, and the standing idle swings both arms another 11° back, so
the wrists rest 16 cm behind the hips. The walk swing oscillates around that
backward neutral. This build starts from the 20261008 source (before the
forward-swing layer) and, for every clip:

* rotates Spine / Spine1 / Spine2 forward by a per-clip constant so the mean
  pelvis-to-neck pitch is 0° (run is already upright and is left alone), and
  counter-rotates Neck so the head keeps its world orientation;
* idle, idle_guarded, sword_ride: sets the upper arm neutral slightly in front
  of vertical and flexes the forearm so the wrist sits beside the thigh;
* meditate, jump, run: keeps the arms' world orientation;
* walk: remaps each arm's existing swing phase onto a range centred on the new
  neutral and adds elbow flexion on the forward half.

Blender --background --factory-startup --python-exit-code 1 \\
    --python tools/art/build_upright_motion_20261009.py
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
NAME = "cultivator_upright_motion_20261009"
OUT = ROOT / "docs/art" / NAME
GLB = ROOT / "src/game/actors/swordsman/models" / (NAME + ".glb")

TRUNK_TARGET_DEG = 0.0
TRUNK_SKIP = {"run"}
# Share of the trunk correction per spine bone, lower to upper. The measured
# lean sits mostly between Spine2 and Neck, so the upper bones take more.
SPINE_SHARE = {"Spine": 0.2, "Spine1": 0.35, "Spine2": 0.45}
NEUTRAL_CLIPS = {"idle", "idle_guarded", "sword_ride"}
UPPER_ARM_NEUTRAL_DEG = 2.0
WRIST_AHEAD_OF_HIPS_M = 0.03
WALK_BACK_DEG = -16.0
WALK_FRONT_DEG = 20.0
WALK_REACH_M = 0.22
SIDES = ("Left", "Right")
TOUCHED = ["Spine", "Spine1", "Spine2", "Neck",
           "LeftArm", "LeftForeArm", "RightArm", "RightForeArm"]

sys.path.insert(0, str(Path(__file__).parent))
from export_cultivator_aligned_motion_20260927 import CLIPS, glb_animation_names

rig: bpy.types.Object
FORWARD = Vector()
# Positive rotation about AXIS tilts an upward segment forward and swings a
# hanging segment backward.
AXIS = Vector()


def pb(name: str) -> bpy.types.PoseBone:
    return rig.pose.bones["mixamorig:" + name]


def point(name: str) -> Vector:
    return rig.matrix_world @ pb(name).head


def update() -> None:
    bpy.context.view_layer.update()


def rotate(name: str, degrees: float, axis: Vector | None = None) -> None:
    """Rotate a bone about its own head around AXIS (or `axis`), in world space."""
    if abs(degrees) < 1e-6:
        return
    bone = pb(name)
    head = point(name)
    world = rig.matrix_world @ bone.matrix
    turn = Matrix.Translation(head) @ Matrix.Rotation(math.radians(degrees), 4, axis or AXIS) \
        @ Matrix.Translation(-head)
    bone.matrix = rig.matrix_world.inverted() @ (turn @ world)
    update()


def keep_world_rotation(name: str, world_rotation: Matrix) -> None:
    bone = pb(name)
    head = point(name)
    target = Matrix.Translation(head) @ world_rotation.to_4x4()
    current = rig.matrix_world @ bone.matrix
    scale = Matrix.Diagonal(current.to_scale().to_4d())
    bone.matrix = rig.matrix_world.inverted() @ (target @ scale)
    update()


def up_pitch(a: Vector, b: Vector) -> float:
    v = b - a
    return math.degrees(math.atan2(v.dot(FORWARD), v.z))


def hang_pitch(a: Vector, b: Vector, forward: Vector | None = None) -> float:
    v = b - a
    return math.degrees(math.atan2(v.dot(forward or FORWARD), -v.z))


def trunk_pitch() -> float:
    return up_pitch(point("Hips"), point("Neck"))


def arm_pitch(side: str, forward: Vector | None = None) -> float:
    return hang_pitch(point(side + "Arm"), point(side + "ForeArm"), forward)


def body_frame() -> tuple[Vector, Vector]:
    """Forward and swing axis that follow the current shoulder line."""
    forward = Vector((0, 0, 1)).cross(body_right()).normalized()
    if forward.dot(FORWARD) < 0:
        forward = -forward
    return forward, Vector((0, 0, 1)).cross(forward).normalized()


def wrist_ahead_of_hips(side: str) -> float:
    return (point(side + "Hand") - point("Hips")).dot(FORWARD)


def wrist_ahead_of_shoulder(side: str) -> float:
    return (point(side + "Hand") - point(side + "Arm")).dot(FORWARD)


def wrist_out(side: str, right: Vector) -> float:
    lateral = right if side == "Right" else -right
    return (point(side + "Hand") - point(side + "Arm")).dot(lateral)


def body_right() -> Vector:
    right = point("RightArm") - point("LeftArm")
    right.z = 0
    return right.normalized()


def frames_of(action: bpy.types.Action) -> list[int]:
    first, last = (round(v) for v in action.frame_range)
    return list(range(first, last + 1))


def capture(action: bpy.types.Action) -> dict[int, dict[str, Matrix]]:
    rig.animation_data.action = action
    basis = {}
    for frame in frames_of(action):
        bpy.context.scene.frame_set(frame)
        basis[frame] = {name: pb(name).matrix_basis.copy() for name in TOUCHED}
    return basis


def restore(basis: dict[str, Matrix]) -> None:
    for name, matrix in basis.items():
        pb(name).matrix_basis = matrix
    update()


def pose(frame: int, basis: dict[str, Matrix], trunk: float, arm: dict | None,
         walk: dict | None) -> None:
    """Pose one frame from the original basis. Pure function of the inputs."""
    bpy.context.scene.frame_set(frame)
    restore(basis)
    neck_world = (rig.matrix_world @ pb("Neck").matrix).to_3x3().normalized()
    arm_world = {side: (rig.matrix_world @ pb(side + "Arm").matrix).to_3x3().normalized()
                 for side in SIDES}
    original_pitch = {side: arm_pitch(side, body_frame()[0]) for side in SIDES}
    for name, share in SPINE_SHARE.items():
        rotate(name, trunk * share)
    keep_world_rotation("Neck", neck_world)
    for side in SIDES:
        keep_world_rotation(side + "Arm", arm_world[side])
    if arm is not None:
        for side in SIDES:
            rotate(side + "Arm", -arm["upper"][side])
            rotate(side + "ForeArm", -arm["fore"][side])
    if walk is not None:
        _forward, swing_axis = body_frame()
        for side in SIDES:
            low, high = walk["span"][side]
            phase = (original_pitch[side] - low) / (high - low)
            target = WALK_BACK_DEG + phase * (WALK_FRONT_DEG - WALK_BACK_DEG)
            rotate(side + "Arm", -(target - original_pitch[side]), swing_axis)
            ease = max(0.0, min(1.0, (phase - 0.5) / 0.5))
            ease = ease * ease * (3.0 - 2.0 * ease)
            rotate(side + "ForeArm", -walk["elbow"] * ease, swing_axis)


def mean(values: list[float]) -> float:
    return sum(values) / len(values)


def clip_mean(action, basis, fn, trunk=0.0, arm=None, walk=None, frames=None) -> float:
    rig.animation_data.action = action
    picks = frames or frames_of(action)
    return mean([(pose(f, basis[f], trunk, arm, walk), fn())[1] for f in picks])


def solve_trunk(action, basis) -> float:
    if action.name in TRUNK_SKIP:
        return 0.0
    picks = frames_of(action)[:: max(1, len(frames_of(action)) // 8)]
    base = clip_mean(action, basis, trunk_pitch, frames=picks)
    probe = clip_mean(action, basis, trunk_pitch, trunk=4.0, frames=picks)
    gain = (probe - base) / 4.0
    delta = (TRUNK_TARGET_DEG - base) / gain
    after = clip_mean(action, basis, trunk_pitch, trunk=delta, frames=picks)
    return delta + (TRUNK_TARGET_DEG - after) / gain


def solve_neutral_arm(action, basis, trunk) -> dict:
    picks = frames_of(action)[:: max(1, len(frames_of(action)) // 8)]
    zero = {"upper": {s: 0.0 for s in SIDES}, "fore": {s: 0.0 for s in SIDES}}
    upper = {}
    for side in SIDES:
        current = clip_mean(action, basis, lambda: arm_pitch(side), trunk, zero, frames=picks)
        upper[side] = UPPER_ARM_NEUTRAL_DEG - current
    arm = {"upper": upper, "fore": {s: 0.0 for s in SIDES}}
    for side in SIDES:
        base = clip_mean(action, basis, lambda: wrist_ahead_of_hips(side), trunk, arm, frames=picks)
        arm["fore"][side] = 5.0
        probe = clip_mean(action, basis, lambda: wrist_ahead_of_hips(side), trunk, arm, frames=picks)
        gain = (probe - base) / 5.0
        arm["fore"][side] = max(0.0, min(25.0, (WRIST_AHEAD_OF_HIPS_M - base) / gain))
    return arm


def solve_walk(action, basis, trunk) -> dict:
    rig.animation_data.action = action
    span = {}
    for side in SIDES:
        values = []
        for frame in frames_of(action):
            bpy.context.scene.frame_set(frame)
            restore(basis[frame])
            values.append(arm_pitch(side, body_frame()[0]))
        span[side] = (min(values), max(values))

    def reach(elbow: float) -> float:
        walk = {"span": span, "elbow": elbow}
        best = -1.0
        for frame in frames_of(action):
            pose(frame, basis[frame], trunk, None, walk)
            best = max(best, *(wrist_ahead_of_shoulder(s) for s in SIDES))
        return best

    low, high = 0.0, 40.0
    if reach(low) >= WALK_REACH_M:
        return {"span": span, "elbow": 0.0}
    for _ in range(12):
        mid = (low + high) / 2
        if reach(mid) < WALK_REACH_M:
            low = mid
        else:
            high = mid
    return {"span": span, "elbow": round(high, 3)}


def write_keys(action, basis, trunk, arm, walk) -> None:
    rig.animation_data.action = action
    for frame in frames_of(action):
        pose(frame, basis[frame], trunk, arm, walk)
        for name in TOUCHED:
            bone = pb(name)
            if bone.rotation_mode != "QUATERNION":
                raise RuntimeError(f"{name} uses {bone.rotation_mode}")
            bone.keyframe_insert("rotation_quaternion", frame=frame)


def measure(action) -> dict:
    rig.animation_data.action = action
    rows = []
    for frame in frames_of(action):
        bpy.context.scene.frame_set(frame)
        update()
        hips = point("Hips")
        right = body_right()
        rows.append({
            "trunk": trunk_pitch(),
            "neck": (point("Neck") - hips).dot(FORWARD),
            "shoulder": ((point("LeftArm") + point("RightArm")) / 2 - hips).dot(FORWARD),
            "head": (point("Head") - hips).dot(FORWARD),
            **{side[0] + "_arm": arm_pitch(side) for side in SIDES},
            **{side[0] + "_wrist_hips": wrist_ahead_of_hips(side) for side in SIDES},
            **{side[0] + "_wrist_shoulder": wrist_ahead_of_shoulder(side) for side in SIDES},
            **{side[0] + "_wrist_out": wrist_out(side, right) for side in SIDES},
        })
    return {key: [round(min(r[key] for r in rows), 4),
                  round(mean([r[key] for r in rows]), 4),
                  round(max(r[key] for r in rows), 4)] for key in rows[0]}


def seam(action) -> float:
    rig.animation_data.action = action
    first, last = frames_of(action)[0], frames_of(action)[-1]
    bpy.context.scene.frame_set(first)
    start = {b.name: b.matrix.copy() for b in rig.pose.bones}
    bpy.context.scene.frame_set(last)
    angles = (math.degrees(start[b.name].to_quaternion().rotation_difference(
        b.matrix.to_quaternion()).angle) for b in rig.pose.bones)
    return max(min(angle, 360.0 - angle) for angle in angles)


def main() -> None:
    global rig, FORWARD, AXIS
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
    bpy.context.preferences.filepaths.save_version = 0
    rig = next(obj for obj in bpy.data.objects if obj.type == "ARMATURE")
    actions = {action.name: action for action in bpy.data.actions}
    assert set(actions) == CLIPS

    rig.animation_data.action = actions["idle"]
    bpy.context.scene.frame_set(frames_of(actions["idle"])[0])
    update()
    toes = (point("LeftToeBase") + point("RightToeBase")) / 2
    feet = (point("LeftFoot") + point("RightFoot")) / 2
    FORWARD = toes - feet
    FORWARD.z = 0
    FORWARD.normalize()
    AXIS = Vector((0, 0, 1)).cross(FORWARD).normalized()
    idle_right = body_right()
    standing_out = {side: wrist_out(side, idle_right) for side in SIDES}

    before = {name: measure(action) for name, action in actions.items()}
    seams_before = {name: round(seam(action), 3) for name, action in actions.items()}
    plan = {}
    for name in sorted(actions):
        action = actions[name]
        basis = capture(action)
        trunk = solve_trunk(action, basis)
        arm = solve_neutral_arm(action, basis, trunk) if name in NEUTRAL_CLIPS else None
        walk = solve_walk(action, basis, trunk) if name == "walk" else None
        write_keys(action, basis, trunk, arm, walk)
        plan[name] = {"trunk_deg": round(trunk, 3)}
        if arm:
            plan[name]["upper_arm_deg"] = {s: round(v, 3) for s, v in arm["upper"].items()}
            plan[name]["forearm_deg"] = {s: round(v, 3) for s, v in arm["fore"].items()}
        if walk:
            plan[name]["walk_source_span_deg"] = {
                s: [round(v, 3) for v in walk["span"][s]] for s in SIDES}
            plan[name]["walk_elbow_deg"] = walk["elbow"]
        print(name, json.dumps(plan[name]), flush=True)

    after = {name: measure(action) for name, action in actions.items()}
    seams = {name: round(seam(action), 3) for name, action in actions.items()}

    problems = []
    for name in ("idle", "idle_guarded", "walk", "sword_ride", "meditate"):
        stats = after[name]
        if abs(stats["trunk"][1]) > 1.0:
            problems.append(f"{name} mean trunk pitch {stats['trunk'][1]:.2f}°")
        for key in ("neck", "shoulder"):
            if abs(stats[key][1]) > 0.03:
                problems.append(f"{name} {key} {stats[key][1]:.3f} m from the pelvis")
    for name in NEUTRAL_CLIPS:
        for side in "LR":
            value = after[name][side + "_wrist_hips"][1]
            if not -0.03 <= value <= 0.06:
                problems.append(f"{name} {side} wrist {value:.3f} m ahead of the pelvis")
    walk = after["walk"]
    for side, key in (("Left", "L"), ("Right", "R")):
        if walk[key + "_wrist_shoulder"][2] < 0.18:
            problems.append(f"walk {side} reach {walk[key + '_wrist_shoulder'][2]:.3f} m")
        if walk[key + "_wrist_out"][2] > standing_out[side] + 0.025:
            problems.append(f"walk {side} wrist flares to {walk[key + '_wrist_out'][2]:.3f} m")
    for name in ("idle", "walk", "run", "idle_guarded", "meditate", "sword_ride"):
        if seams[name] > seams_before[name] + 0.5:
            problems.append(f"{name} loop seam {seams_before[name]:.2f}° -> {seams[name]:.2f}°")

    report = {
        "source": str(SOURCE.relative_to(ROOT)),
        "targets": {
            "trunk_deg": TRUNK_TARGET_DEG, "trunk_skip": sorted(TRUNK_SKIP),
            "spine_share": SPINE_SHARE, "upper_arm_neutral_deg": UPPER_ARM_NEUTRAL_DEG,
            "wrist_ahead_of_hips_m": WRIST_AHEAD_OF_HIPS_M,
            "walk_swing_deg": [WALK_BACK_DEG, WALK_FRONT_DEG], "walk_reach_m": WALK_REACH_M,
        },
        "plan": plan,
        "standing_wrist_out_m": {s: round(v, 4) for s, v in standing_out.items()},
        "before_min_mean_max": before,
        "after_min_mean_max": after,
        "loop_seam_deg_before": seams_before,
        "loop_seam_deg": seams,
        "problems": problems,
    }
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "build_report.json").write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n")
    if problems:
        raise RuntimeError("; ".join(problems))

    for action in actions.values():
        action.use_fake_user = True
    rig.animation_data.action = actions["idle"]
    bpy.context.scene.frame_set(0)
    update()
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT / (NAME + ".blend")))
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
    print(json.dumps({"plan": plan, "seams": seams}, indent=2))


if __name__ == "__main__":
    main()
