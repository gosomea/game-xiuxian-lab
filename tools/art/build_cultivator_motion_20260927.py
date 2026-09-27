#!/usr/bin/env python3
"""Author a complete in-place movement set on the kept v9 character bind rig.

No animation curve is copied or sampled from the input GLB. The seven actions
are synthesized from a neutral stance, then exported with the existing mesh,
skin and material. Run with Blender in background mode.
"""

from __future__ import annotations

import json
import math
from pathlib import Path

import bpy
from mathutils import Quaternion, Vector


ROOT = Path(__file__).resolve().parents[2]
MODEL = ROOT / "src/game/actors/swordsman/models/cultivator_tripo_v9.glb"
ART = ROOT / "docs/art/cultivator_motion_20260927"
BLEND = ART / "cultivator_motion_20260927.blend"
GLB = ROOT / "src/game/actors/swordsman/models/cultivator_motion_20260927.glb"
FPS = 30
ID = Quaternion((1, 0, 0, 0))


def q(axis: tuple[float, float, float], degrees: float) -> Quaternion:
    return Quaternion(axis, math.radians(degrees))


def bone(arm: bpy.types.Object, name: str):
    return arm.pose.bones["mixamorig:" + name]


def point(arm: bpy.types.Object, name: str) -> Vector:
    return arm.matrix_world @ bone(arm, name).matrix.translation


def apply_neutral(arm: bpy.types.Object) -> None:
    for item in arm.pose.bones:
        item.rotation_mode = "QUATERNION"
        item.rotation_quaternion = ID.copy()
        item.location = Vector((0, 0, 0))
    for side, sign in (("Left", 1), ("Right", -1)):
        upper = bone(arm, side + "Arm")
        forearm = bone(arm, side + "ForeArm")
        rest_dir = (forearm.bone.head_local - upper.bone.head_local).normalized()
        direction = (arm.matrix_world.to_3x3().inverted()
                     @ Vector((sign * .14, -.035, -1))).normalized()
        aim = rest_dir.rotation_difference(direction)
        rest_q = upper.bone.matrix_local.to_quaternion()
        upper.rotation_quaternion = rest_q.inverted() @ aim @ rest_q
        # The imported bind legs place the ankles ~0.14 m behind the pelvis.
        # A -10 degree neutral thigh angle centers the pelvis over both feet.
        bone(arm, side + "UpLeg").rotation_quaternion = q((1, 0, 0), -10)
        bone(arm, side + "Leg").rotation_quaternion = q((1, 0, 0), -2)


def neutral_spine(arm: bpy.types.Object) -> tuple[float, float]:
    """Solve the bind character's side/fore lean, not an old clip's pose."""
    spine = bone(arm, "Spine")

    def offset(pitch: float, side: float) -> tuple[float, float]:
        spine.rotation_quaternion = q((1, 0, 0), pitch) @ q((0, 0, 1), side)
        bpy.context.view_layer.update()
        diff = point(arm, "Head") - point(arm, "Hips")
        return diff.x, diff.y

    pitch = side = 0.0
    for _ in range(6):
        x, y = offset(pitch, side)
        if math.hypot(x, y - .02) < .001:
            break
        dx, dy = offset(pitch + .5, side)
        ex, ey = offset(pitch, side + .5)
        a, b = (dx - x) * 2, (ex - x) * 2
        c, d = (dy - y) * 2, (ey - y) * 2
        det = a * d - b * c
        if abs(det) < 1e-6:
            raise RuntimeError("Neutral torso cannot be calibrated")
        target_x, target_y = -x, .02 - y
        pitch += max(-8, min(8, (d * target_x - b * target_y) / det))
        side += max(-8, min(8, (-c * target_x + a * target_y) / det))
    if max(abs(pitch), abs(side)) > 22:
        raise RuntimeError(f"Neutral torso correction too large: {pitch}, {side}")
    return pitch, side


def shoe_indices(mesh: bpy.types.Object) -> list[int]:
    bpy.context.view_layer.update()
    evaluated = mesh.evaluated_get(bpy.context.evaluated_depsgraph_get())
    data = evaluated.to_mesh()
    try:
        indices = [index for index, vertex in enumerate(data.vertices)
                   if (evaluated.matrix_world @ vertex.co).z < .32 and index % 3 == 0]
    finally:
        evaluated.to_mesh_clear()
    if len(indices) < 100:
        raise RuntimeError("Cannot identify shoe vertices")
    return indices


def shoe_floor(mesh: bpy.types.Object, indices: list[int]) -> float:
    bpy.context.view_layer.update()
    evaluated = mesh.evaluated_get(bpy.context.evaluated_depsgraph_get())
    data = evaluated.to_mesh()
    try:
        return min((evaluated.matrix_world @ data.vertices[index].co).z
                   for index in indices)
    finally:
        evaluated.to_mesh_clear()


def rotate(arm: bpy.types.Object, name: str,
           axis: tuple[float, float, float], degrees: float) -> None:
    item = bone(arm, name)
    item.rotation_quaternion = item.rotation_quaternion @ q(axis, degrees)


def posture(arm: bpy.types.Object, torso: tuple[float, float],
            focus: float = 0.0) -> None:
    apply_neutral(arm)
    pitch, side = torso
    bone(arm, "Spine").rotation_quaternion = (
        q((1, 0, 0), pitch + focus) @ q((0, 0, 1), side))


def gait(arm: bpy.types.Object, torso: tuple[float, float],
         phase: float, fast: bool) -> None:
    posture(arm, torso, 3.5 if fast else 0.0)
    swing = 29.5 if fast else 24.0
    knee = 31.0 if fast else 20.0
    arm_swing = 8.0 if fast else 4.5
    cos_phase, sin_phase = math.cos(phase), math.sin(phase)
    for side, direction in (("Left", 1), ("Right", -1)):
        stride = direction * cos_phase
        airborne = max(0.0, -direction * sin_phase)
        hip = swing * stride
        knee_bend = knee * airborne
        rotate(arm, side + "UpLeg", (1, 0, 0), hip)
        rotate(arm, side + "Leg", (1, 0, 0), knee_bend)
        # Counter-rotate the ankle to keep the shoe near horizontal.
        rotate(arm, side + "Foot", (1, 0, 0), -hip * .55 - knee_bend * .60)
        rotate(arm, side + "Arm", (1, 0, 0), -arm_swing * stride)
        rotate(arm, side + "ForeArm", (1, 0, 0), 3.0 if fast else 1.5)
    rotate(arm, "Spine1", (0, 1, 0), 1.3 * sin_phase)
    rotate(arm, "Head", (1, 0, 0), -.7 * sin_phase)
    bone(arm, "Hips").location.x = .011 * sin_phase
    bone(arm, "Hips").location.z = .007 * (1 - math.cos(2 * phase))


def smooth(a: float, b: float, t: float) -> float:
    if b <= a:
        return 1.0 if t >= b else 0.0
    u = max(0.0, min(1.0, (t - a) / (b - a)))
    return u * u * (3 - 2 * u)


def jump(arm: bpy.types.Object, torso: tuple[float, float], t: float) -> None:
    posture(arm, torso)
    crouch = 1.0 - smooth(.10, .32, t)
    rise = smooth(.10, .42, t) * (1.0 - smooth(.65, .95, t))
    landing = smooth(.72, 1.0, t)
    for side, sign in (("Left", 1), ("Right", -1)):
        rotate(arm, side + "UpLeg", (1, 0, 0), 13 * crouch + (18 if sign == 1 else 8) * rise + 11 * landing)
        rotate(arm, side + "Leg", (1, 0, 0), -23 * crouch - (26 if sign == 1 else 18) * rise - 16 * landing)
        rotate(arm, side + "Foot", (1, 0, 0), 8 * crouch - 8 * rise)
        rotate(arm, side + "Arm", (1, 0, 0), (-9 if sign == 1 else 6) * rise)
    bone(arm, "Hips").location.z = -.045 * crouch
    rotate(arm, "Spine1", (1, 0, 0), -3 * rise)


def sword_ride(arm: bpy.types.Object, torso: tuple[float, float], t: float) -> None:
    posture(arm, torso, 1.5)
    wave = math.sin(2 * math.pi * t)
    for side, hip, knee in (("Left", 7.0, 7.0), ("Right", -5.0, 10.0)):
        rotate(arm, side + "UpLeg", (1, 0, 0), hip)
        rotate(arm, side + "Leg", (1, 0, 0), knee)
        rotate(arm, side + "Arm", (0, 0, 1), 3.0 if side == "Left" else -3.0)
    bone(arm, "Hips").location.z = .005 * wave
    rotate(arm, "Spine1", (0, 0, 1), .6 * wave)


def idle(arm: bpy.types.Object, torso: tuple[float, float],
         t: float, stance: str) -> None:
    posture(arm, torso)
    breath = math.sin(2 * math.pi * t)
    rotate(arm, "Spine1", (1, 0, 0), .7 * breath)
    rotate(arm, "Head", (1, 0, 0), -.35 * breath)
    if stance == "ready":
        for side in ("Left", "Right"):
            rotate(arm, side + "Arm", (1, 0, 0), -5)
            rotate(arm, side + "ForeArm", (1, 0, 0), 4)
    elif stance == "meditate":
        for side, spread in (("Left", 24), ("Right", -24)):
            rotate(arm, side + "UpLeg", (1, 0, 0), 67)
            rotate(arm, side + "UpLeg", (0, 1, 0), spread)
            rotate(arm, side + "Leg", (1, 0, 0), -108)
            rotate(arm, side + "Foot", (1, 0, 0), 41)
            arm_sign = 1 if side == "Left" else -1
            rotate(arm, side + "Arm", (0, 0, 1), 35 * arm_sign)
            rotate(arm, side + "ForeArm", (0, 0, 1), 30 * arm_sign)
        rotate(arm, "Spine1", (1, 0, 0), 1.2 * breath)


def make_action(arm: bpy.types.Object, mesh: bpy.types.Object,
                shoes: list[int], torso: tuple[float, float],
                name: str, frames: int, pose_function,
                home_z: float, grounded: bool = True) -> dict:
    action = bpy.data.actions.new(name)
    action.use_fake_user = True
    arm.animation_data.action = action
    arm.location.z = home_z
    raw_lows = []
    for frame in range(1, frames + 1):
        t = (frame - 1) / (frames - 1)
        bpy.context.scene.frame_set(frame)
        pose_function(arm, torso, t)
        arm.location.z = home_z
        bpy.context.view_layer.update()
        low = shoe_floor(mesh, shoes)
        raw_lows.append(low)
        arm.location.z = home_z - low if grounded else home_z
        arm.keyframe_insert("location", frame=frame)
        for item in arm.pose.bones:
            item.keyframe_insert("rotation_quaternion", frame=frame)
            item.keyframe_insert("location", frame=frame)
    if not grounded:
        # A jump is allowed to lift its feet. Use one floor offset for the whole
        # clip and a root arc; per-frame floor correction would cancel the jump.
        floor_offset = -min(raw_lows)
        for frame in range(1, frames + 1):
            t = (frame - 1) / (frames - 1)
            lift = .14 * smooth(.10, .42, t) * (1.0 - smooth(.65, .95, t))
            arm.location.z = home_z + floor_offset + lift
            arm.keyframe_insert("location", frame=frame)
    bpy.context.scene.frame_set(1)
    return {"frames": frames, "grounded_floor_track": grounded,
            "shoe_floor_raw_min_m": round(min(raw_lows), 4),
            "shoe_floor_raw_max_m": round(max(raw_lows), 4)}


def main() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(MODEL))
    arm = next(obj for obj in bpy.data.objects if obj.type == "ARMATURE")
    mesh = next(obj for obj in bpy.data.objects if obj.type == "MESH"
                and any(mod.type == "ARMATURE" for mod in obj.modifiers))
    discarded = sorted(action.name for action in bpy.data.actions)
    arm.animation_data_clear()
    for action in list(bpy.data.actions):
        bpy.data.actions.remove(action)
    arm.animation_data_create()
    bpy.context.scene.render.fps = FPS
    bpy.context.scene.frame_set(1)
    apply_neutral(arm)
    torso = neutral_spine(arm)
    shoes = shoe_indices(mesh)
    home_z = arm.location.z
    specs = (
        ("idle", 73, lambda a, p, t: idle(a, p, t, "plain"), True),
        ("idle_guarded", 73, lambda a, p, t: idle(a, p, t, "ready"), True),
        ("walk", 29, lambda a, p, t: gait(a, p, 2 * math.pi * t, False), True),
        ("run", 25, lambda a, p, t: gait(a, p, 2 * math.pi * t, True), True),
        ("jump", 37, jump, False),
        ("sword_ride", 73, sword_ride, True),
        ("meditate", 91, lambda a, p, t: idle(a, p, t, "meditate"), True),
    )
    results = {}
    for name, frames, fn, grounded in specs:
        results[name] = make_action(arm, mesh, shoes, torso, name, frames, fn,
                                    home_z, grounded)
        print(f"authored {name}: {results[name]}", flush=True)
    ART.mkdir(parents=True, exist_ok=True)
    bpy.context.preferences.filepaths.save_version = 0
    arm.animation_data.action = bpy.data.actions["idle"]
    bpy.context.scene.frame_set(1)
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND))
    bpy.ops.object.select_all(action="DESELECT")
    arm.select_set(True)
    mesh.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.export_scene.gltf(
        filepath=str(GLB), export_format="GLB", use_selection=True,
        export_animation_mode="ACTIONS", export_animations=True,
        export_skins=True, export_yup=True, export_apply=False,
        export_normals=True, export_materials="EXPORT",
        export_frame_range=False, export_force_sampling=True,
        export_bake_animation=False)
    report = {"source_model": str(MODEL.relative_to(ROOT)),
              "discarded_imported_actions": discarded,
              "sampled_imported_action_frames": 0,
              "neutral_spine_correction_degrees": [round(x, 3) for x in torso],
              "clips": results}
    (ART / "build_manifest.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2), flush=True)


if __name__ == "__main__":
    main()
