#!/usr/bin/env python3
"""Retarget two licensed walking sources onto the unchanged v9 mesh and rig.

Run with Blender in background mode.  This produces an isolated comparison
asset; it never writes the active character animation file.
"""

from __future__ import annotations

import json
import math
from pathlib import Path

import bpy
from mathutils import Quaternion, Vector


ROOT = Path(__file__).resolve().parents[2]
TARGET = ROOT / "src/game/actors/swordsman/models/cultivator_tripo_v9.glb"
KAYKIT = ROOT / "docs/art/kaykit_route_ab/upstream/kaykit-adventurers-1.0-672074b/Rogue_Hooded.glb"
CMU = ROOT / "docs/art/cultivator_walk_sources/upstream/cmu_016/16_47.bvh"
ART = ROOT / "docs/art/cultivator_walk_sources"
OUT = ROOT / "src/game/actors/swordsman/models/cultivator_walk_sources_v5.glb"
FPS = 30

KAYKIT_MAP = {
    "Hips": "hips", "Spine": "spine", "Spine1": "chest", "Spine2": "chest",
    "Neck": "head", "Head": "head",
    "LeftArm": "upperarm.l", "LeftForeArm": "lowerarm.l", "LeftHand": "hand.l",
    "RightArm": "upperarm.r", "RightForeArm": "lowerarm.r", "RightHand": "hand.r",
    "LeftUpLeg": "upperleg.l", "LeftLeg": "lowerleg.l", "LeftFoot": "foot.l",
    "LeftToeBase": "toes.l", "RightUpLeg": "upperleg.r", "RightLeg": "lowerleg.r",
    "RightFoot": "foot.r", "RightToeBase": "toes.r",
}
CMU_MAP = {name: name for name in (
    "Hips", "Spine", "Spine1", "Neck", "Head", "LeftShoulder",
    "LeftArm", "LeftForeArm", "LeftHand", "RightShoulder", "RightArm",
    "RightForeArm", "RightHand", "LeftUpLeg", "LeftLeg", "LeftFoot",
    "LeftToeBase", "RightUpLeg", "RightLeg", "RightFoot", "RightToeBase")}


def import_target():
    bpy.ops.import_scene.gltf(filepath=str(TARGET))
    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    mesh = max((o for o in bpy.data.objects if o.type == "MESH"),
               key=lambda o: len(o.data.vertices))
    target_objects = set(bpy.data.objects)
    arm.animation_data_clear()
    for action in list(bpy.data.actions):
        bpy.data.actions.remove(action)
    arm.animation_data_create()
    return arm, mesh, target_objects


def import_source(kind):
    before = set(bpy.data.objects)
    if kind == "kaykit":
        bpy.ops.import_scene.gltf(filepath=str(KAYKIT))
        action = bpy.data.actions["Walking_A"]
    else:
        # CMU BVH is in centimeters and 120 Hz. Rotations, rather than its
        # trajectory, are transferred; target movement remains game driven.
        bpy.ops.import_anim.bvh(filepath=str(CMU), global_scale=0.01,
                                update_scene_fps=False)
        action = bpy.data.actions["16_47"]
    objects = set(bpy.data.objects) - before
    arm = next(o for o in objects if o.type == "ARMATURE")
    arm.animation_data.action = action
    return arm, objects, action


def source_motion(arm, mapping, frame):
    bpy.context.scene.frame_set(math.floor(frame), subframe=frame % 1)
    bpy.context.view_layer.update()
    result = {}
    for short, source_name in mapping.items():
        bone = arm.pose.bones[source_name]
        result[short] = bone.matrix_basis.to_quaternion().copy()
    root = arm.pose.bones[mapping["Hips"]]
    result["_root_world"] = (arm.matrix_world @ root.matrix.translation).copy()
    return result


def sample_floor(mesh):
    bpy.context.view_layer.update()
    evaluated = mesh.evaluated_get(bpy.context.evaluated_depsgraph_get())
    data = evaluated.to_mesh()
    try:
        return min((evaluated.matrix_world @ vertex.co).z for vertex in data.vertices)
    finally:
        evaluated.to_mesh_clear()


def target_pose(target, motion, mapping, root_reference, kind):
    for bone in target.pose.bones:
        bone.rotation_mode = "QUATERNION"
        bone.rotation_quaternion = Quaternion((1, 0, 0, 0))
        bone.location = Vector((0, 0, 0))
    for short in mapping:
        dst = target.pose.bones.get("mixamorig:" + short)
        if dst is None:
            continue
        source_basis = motion[short]
        if short == "Hips" and kind == "cmu":
            # The CMU BVH bind pose points down. Its imported root contains a
            # constant 180-degree correction; remove that static orientation.
            source_basis = root_reference["Hips"].inverted() @ source_basis
        elif short in ("LeftArm", "RightArm"):
            # Use only the walking swing. Absolute BVH/Mixamo shoulder poses
            # include incompatible T-pose corrections on this bind skeleton.
            source_basis = root_reference[short].inverted() @ source_basis
            if kind == "kaykit":
                source_basis = Quaternion((1, 0, 0, 0)).slerp(source_basis, 0.2)
        elif short in ("LeftUpLeg", "RightUpLeg") and kind == "kaykit":
            source_basis = Quaternion((1, 0, 0, 0)).slerp(source_basis, 0.55)
        src = mapping[short]
        source_arm = bpy.data.objects["Rig"] if kind == "kaykit" else bpy.data.objects["16_47"]
        src_rest = source_arm.pose.bones[src].bone.matrix_local.to_quaternion()
        dst_rest = dst.bone.matrix_local.to_quaternion()
        common = src_rest @ source_basis @ src_rest.inverted()
        converted = dst_rest.inverted() @ common @ dst_rest
        if short in ("LeftArm", "RightArm"):
            # Both imported bind poses are near a T pose. Keep their small
            # walking swing, but lower this character's arms to a natural rest.
            side = 1 if short == "LeftArm" else -1
            child = target.pose.bones["mixamorig:" + short.replace("Arm", "ForeArm")]
            rest_dir = (child.bone.head_local - dst.bone.head_local).normalized()
            world_down = Vector((side * .16, 0, -1)).normalized()
            arm_down = (target.matrix_world.to_3x3().inverted() @ world_down).normalized()
            aim = rest_dir.rotation_difference(arm_down)
            lowered = dst_rest.inverted() @ aim @ dst_rest
            converted = lowered @ converted
        elif short == "Spine":
            converted = Quaternion((1, 0, 0), math.radians(12)) @ converted
        dst.rotation_quaternion = converted
    # Relative vertical bob. Horizontal path is owned by CharacterBody3D.
    delta = motion["_root_world"].z - root_reference["_root_world"].z
    ratio = 1.1 if kind == "kaykit" else 6.3
    target.pose.bones["mixamorig:Hips"].location.y = delta * ratio


def make_action(target, mesh, source, mapping, kind, source_frames, source_fps):
    scene = bpy.context.scene
    scene.render.fps = FPS
    reference = source_motion(source, mapping, source_frames[0])
    name = "walk_kaykit" if kind == "kaykit" else "walk_cmu"
    action = bpy.data.actions.new(name)
    action.use_fake_user = True
    target.animation_data.action = action
    target_home = target.location.copy()
    sampled = []
    for index, source_frame in enumerate(source_frames):
        dst_frame = index + 1
        motion = source_motion(source, mapping, source_frame)
        scene.frame_set(dst_frame)
        target_pose(target, motion, mapping, reference, kind)
        target.location = target_home
        bpy.context.view_layer.update()
        for bone in target.pose.bones:
            bone.keyframe_insert("rotation_quaternion", frame=dst_frame)
            bone.keyframe_insert("location", frame=dst_frame)
        floor = sample_floor(mesh)
        target.location.z -= floor
        target.keyframe_insert("location", frame=dst_frame)
        sampled.append({"frame": dst_frame, "source_frame": source_frame,
                        "floor_before_m": round(floor, 4)})
    scene.frame_set(1)
    return action, sampled


def build():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    target, mesh, target_objects = import_target()
    reports = {}
    for kind, mapping, frames, source_fps in (
        ("kaykit", KAYKIT_MAP, [1 + i * 24 / 30 for i in range(31)], 24),
        ("cmu", CMU_MAP, [63 + i * 4 for i in range(35)], 120),
    ):
        source, objects, _ = import_source(kind)
        action, floors = make_action(target, mesh, source, mapping, kind,
                                     frames, source_fps)
        reports[action.name] = {"source": kind, "source_frames": [frames[0], frames[-1]],
                                "source_fps": source_fps, "sampled_fps": FPS,
                                "frames": len(frames), "floors": floors}
        for obj in objects:
            if obj not in target_objects:
                bpy.data.objects.remove(obj, do_unlink=True)
        for stale in list(bpy.data.actions):
            if stale.name not in ("walk_kaykit", "walk_cmu"):
                bpy.data.actions.remove(stale)
    ART.mkdir(parents=True, exist_ok=True)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    target.animation_data.action = bpy.data.actions["walk_kaykit"]
    bpy.context.scene.frame_set(1)
    bpy.ops.wm.save_as_mainfile(filepath=str(ART / "cultivator_walk_sources_v5.blend"))
    bpy.ops.object.select_all(action="DESELECT")
    for obj in target_objects:
        if obj.name in bpy.data.objects:
            obj.select_set(True)
    bpy.context.view_layer.objects.active = target
    bpy.ops.export_scene.gltf(filepath=str(OUT), export_format="GLB",
        export_animation_mode="ACTIONS", export_animations=True,
        export_skins=True, export_yup=True, export_apply=False,
        export_normals=True, export_materials="EXPORT",
        export_frame_range=False, export_force_sampling=True,
        export_bake_animation=False, use_selection=True)
    (ART / "build_manifest_v5.json").write_text(json.dumps(reports, indent=2) + "\n")
    print(json.dumps({k: {x: v for x, v in info.items() if x != "floors"}
                      for k, info in reports.items()}, indent=2), flush=True)


if __name__ == "__main__":
    build()
