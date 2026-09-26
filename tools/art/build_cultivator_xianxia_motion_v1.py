#!/usr/bin/env python3
"""Author a seven-clip xianxia motion set from the v9 skeleton's bind pose.

The committed v9 GLB is used only for mesh, texture, armature and skin weights.
All imported animation data is deleted before the first new pose is constructed.
Run: blender -b -t 4 --python tools/art/build_cultivator_xianxia_motion_v1.py
"""

from __future__ import annotations

import json
import math
from pathlib import Path

import bpy
from mathutils import Quaternion, Vector


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "src/game/actors/swordsman/models/cultivator_tripo_v9.glb"
ART = ROOT / "docs/art/cultivator_xianxia_motion_v1"
OUT = ROOT / "src/game/actors/swordsman/models/cultivator_xianxia_motion_v1.glb"
FPS = 30


def bone(arm, short):
    return arm.pose.bones["mixamorig:" + short]


def qx(degrees):
    return Quaternion((1, 0, 0), math.radians(degrees))


def aim_from_bind(arm, short, child, target_world):
    """Aim a limb from its rest direction, not from an old clip's rotation."""
    b = bone(arm, short)
    c = bone(arm, child)
    rest = (c.bone.head_local - b.bone.head_local).normalized()
    target = (arm.matrix_world.to_3x3().inverted() @ Vector(target_world)).normalized()
    turn = rest.rotation_difference(target)
    orientation = b.bone.matrix_local.to_quaternion()
    return orientation.inverted() @ turn @ orientation


def bend_forearms_toward(arm, pose, target_for_side):
    """Pose both forearms toward an intentional hand placement in world space."""
    for b in arm.pose.bones:
        q, location = pose[b.name]
        b.rotation_quaternion = q.copy()
        b.location = location.copy()
    bpy.context.view_layer.update()
    for side, sign in (("Left", 1), ("Right", -1)):
        forearm = bone(arm, side + "ForeArm")
        hand = bone(arm, side + "Hand")
        current = ((arm.matrix_world @ hand.matrix.translation)
                   - (arm.matrix_world @ forearm.matrix.translation)).normalized()
        goal = Vector(target_for_side(sign)).normalized()
        world_turn = current.rotation_difference(goal)
        arm_world = arm.matrix_world.to_quaternion()
        arm_turn = arm_world.inverted() @ world_turn @ arm_world
        pose_orientation = forearm.matrix.to_quaternion()
        local_turn = pose_orientation.inverted() @ arm_turn @ pose_orientation
        forearm.rotation_quaternion = forearm.rotation_quaternion @ local_turn
        bpy.context.view_layer.update()
        pose[forearm.name] = (forearm.rotation_quaternion.copy(),
                              pose[forearm.name][1])
    return pose


def bind_base(arm, hand_position="down"):
    pose = {b.name: (Quaternion((1, 0, 0, 0)), Vector((0, 0, 0)))
            for b in arm.pose.bones}

    def set_rotation(short, rotation):
        name = bone(arm, short).name
        pose[name] = (rotation, pose[name][1])

    # 12 degrees removes the bind pose's backward-leaning chest and raised chin.
    set_rotation("Spine", qx(12))
    for short in ("LeftUpLeg", "RightUpLeg", "LeftLeg", "RightLeg"):
        set_rotation(short, qx(-5))
    for side, sign in (("Left", 1), ("Right", -1)):
        if hand_position == "guarded":
            target = (sign * .11, .13, -1)
        elif hand_position == "breath":
            target = (sign * .13, -.08, -.82)
        elif hand_position == "air":
            target = (sign * .55, -.20, -.50)
        else:
            target = (sign * .16, 0, -1)
        set_rotation(side + "Arm", aim_from_bind(arm, side + "Arm",
                                                   side + "ForeArm", target))
    if hand_position == "guarded":
        # 负手：elbows remain close; wrists meet behind the sash.
        return bend_forearms_toward(arm, pose,
                                   lambda sign: (-sign * .35, .28, .05))
    if hand_position == "breath":
        # 站桩吐纳：palms gather in front of the lower chest.
        return bend_forearms_toward(arm, pose,
                                   lambda sign: (-sign * .30, -.32, .02))
    return pose


def apply_pose(arm, frame, base, rotations):
    scene = bpy.context.scene
    scene.frame_set(frame)
    for b in arm.pose.bones:
        base_q, base_loc = base[b.name]
        b.rotation_mode = "QUATERNION"
        b.rotation_quaternion = base_q.copy()
        b.location = base_loc.copy()
    for short, degrees in rotations.items():
        b = bone(arm, short)
        b.rotation_quaternion = b.rotation_quaternion @ qx(degrees)
    for b in arm.pose.bones:
        b.keyframe_insert("rotation_quaternion", frame=frame)
        b.keyframe_insert("location", frame=frame)


def foot_indices(mesh):
    bpy.context.view_layer.update()
    deps = bpy.context.evaluated_depsgraph_get()
    obj = mesh.evaluated_get(deps)
    data = obj.to_mesh()
    try:
        found = [i for i, vertex in enumerate(data.vertices)
                 if (mesh.matrix_world @ vertex.co).z < .30 and i % 3 == 0]
    finally:
        obj.to_mesh_clear()
    if len(found) < 100:
        raise RuntimeError("No skinned shoe vertices were found")
    return found


def boot_floor(mesh, indices):
    bpy.context.view_layer.update()
    deps = bpy.context.evaluated_depsgraph_get()
    obj = mesh.evaluated_get(deps)
    data = obj.to_mesh()
    try:
        return min((mesh.matrix_world @ data.vertices[i].co).z for i in indices)
    finally:
        obj.to_mesh_clear()


def foot_spread(arm):
    bpy.context.view_layer.update()
    left = arm.matrix_world @ bone(arm, "LeftFoot").matrix.translation
    right = arm.matrix_world @ bone(arm, "RightFoot").matrix.translation
    return abs(left.y - right.y)


def action(arm, mesh, indices, name, frames, base, keys, floor_mode="track"):
    clip = bpy.data.actions.new(name)
    clip.use_fake_user = True
    arm.animation_data.action = clip
    home_z = arm.location.z
    for frame, turns in keys:
        apply_pose(arm, frame, base, turns)
        arm.location.z = home_z
        arm.keyframe_insert("location", frame=frame)
    lows = []
    first_low = None
    for frame in range(1, frames + 1):
        bpy.context.scene.frame_set(frame)
        low = boot_floor(mesh, indices)
        lows.append(low)
        if first_low is None:
            first_low = low
        # The jump mesh follows CharacterBody3D physics. Only its initial pose
        # receives the standing offset; tracking the airborne foot would pull it
        # toward an imaginary floor during flight.
        arm.location.z = home_z - (first_low if floor_mode == "start" else low)
        arm.keyframe_insert("location", frame=frame)
    bpy.context.scene.frame_set(1)
    spread = foot_spread(arm)
    natural_speed = 2 * spread / (frames / FPS) if name in ("walk", "run") else 0
    return {"frames": frames, "floor_mode": floor_mode,
            "boot_min_before_m": round(min(lows), 4),
            "boot_max_before_m": round(max(lows), 4),
            "foot_spread_at_stride_extreme_m": round(spread, 4),
            "estimated_natural_speed_mps": round(natural_speed, 4)}


def gait(base, amplitude, knee, frames, restrained_arm):
    def phase(left, right, bent_l=0, bent_r=0, arm=0):
        return {"LeftUpLeg": left, "RightUpLeg": right,
                "LeftLeg": bent_l, "RightLeg": bent_r,
                "LeftArm": arm, "RightArm": -arm}
    return [(1, phase(amplitude, -amplitude, knee, 0, -restrained_arm)),
            (1 + frames // 4, phase(0, 0, knee * .35, knee * .35, 0)),
            (1 + frames // 2, phase(-amplitude, amplitude, 0, knee, restrained_arm)),
            (1 + frames * 3 // 4, phase(0, 0, knee * .35, knee * .35, 0)),
            (frames, phase(amplitude, -amplitude, knee, 0, -restrained_arm))]


def build():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(SOURCE))
    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    mesh = next(o for o in bpy.data.objects
                if o.type == "MESH" and len(o.data.vertices) > 100000)
    imported_names = [a.name for a in bpy.data.actions]
    arm.animation_data_clear()
    for old in list(bpy.data.actions):
        bpy.data.actions.remove(old)
    arm.animation_data_create()
    scene = bpy.context.scene
    scene.render.fps = FPS
    scene.frame_set(1)
    for b in arm.pose.bones:
        b.rotation_mode = "QUATERNION"
        b.rotation_quaternion = Quaternion((1, 0, 0, 0))
        b.location = Vector((0, 0, 0))
    indices = foot_indices(mesh)
    calm = bind_base(arm, "down")
    guarded = bind_base(arm, "guarded")
    breathing = bind_base(arm, "breath")
    airborne = bind_base(arm, "air")
    result = {}
    result["idle"] = action(arm, mesh, indices, "idle", 73, calm,
        [(1, {}), (37, {"Spine": 1.1, "Head": -.7}), (73, {})])
    result["idle_guarded"] = action(arm, mesh, indices, "idle_guarded", 73, guarded,
        [(1, {}), (37, {"Spine": 1.0, "Head": -.5}), (73, {})])
    # 行云步：踏实支撑，袖手低垂，上身中轴稳定。
    result["walk"] = action(arm, mesh, indices, "walk", 31, calm,
        gait(calm, 21, 14, 31, 2.5))
    # 轻身急步：脚步加快但不作西式大幅摆臂或前弓冲刺。
    result["run"] = action(arm, mesh, indices, "run", 23, guarded,
        gait(guarded, 28, 22, 23, 3.5))
    result["jump"] = action(arm, mesh, indices, "jump", 32, airborne, [
        (1, {"LeftUpLeg": 8, "RightUpLeg": 8, "LeftLeg": -14,
             "RightLeg": -14, "Spine": 3}),
        (9, {"LeftUpLeg": 27, "RightUpLeg": -12, "LeftLeg": -35,
             "RightLeg": 20, "LeftArm": -15, "RightArm": 8}),
        (19, {"LeftUpLeg": 31, "RightUpLeg": -15, "LeftLeg": -39,
              "RightLeg": 24, "LeftArm": -17, "RightArm": 9}),
        (32, {"LeftUpLeg": 10, "RightUpLeg": 10, "LeftLeg": -18,
              "RightLeg": -18, "Spine": 4})], "start")
    result["sword_ride"] = action(arm, mesh, indices, "sword_ride", 73, guarded,
        [(1, {"LeftUpLeg": 6, "RightUpLeg": -4, "LeftLeg": 5,
              "RightLeg": 7}),
         (37, {"LeftUpLeg": 6, "RightUpLeg": -4, "LeftLeg": 5,
               "RightLeg": 7, "Spine": 1}),
         (73, {"LeftUpLeg": 6, "RightUpLeg": -4, "LeftLeg": 5,
               "RightLeg": 7})])
    # 站桩吐纳：22-bone rig has no fingers, so convey cultivation through
    # composed shoulders, hands gathered near the abdomen, and slow breathing.
    result["meditate"] = action(arm, mesh, indices, "meditate", 91, breathing,
        [(1, {}), (46, {"Spine": 2, "Head": -1}), (91, {})])

    ART.mkdir(parents=True, exist_ok=True)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    arm.animation_data.action = bpy.data.actions["idle_guarded"]
    scene.frame_set(1)
    bpy.ops.wm.save_as_mainfile(filepath=str(ART / "cultivator_xianxia_motion_v1.blend"))
    bpy.ops.export_scene.gltf(filepath=str(OUT), export_format="GLB",
        export_animation_mode="ACTIONS", export_animations=True,
        export_skins=True, export_yup=True, export_apply=False,
        export_normals=True, export_materials="EXPORT",
        export_frame_range=False, export_force_sampling=True,
        export_bake_animation=False, use_selection=False, use_visible=True)
    report = {"source_mesh": str(SOURCE.relative_to(ROOT)),
              "imported_actions_removed_before_authoring": imported_names,
              "source_animation_frames_sampled": 0,
              "boot_sample_vertices": len(indices), "clips": result}
    (ART / "build_manifest.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2), flush=True)


if __name__ == "__main__":
    build()
