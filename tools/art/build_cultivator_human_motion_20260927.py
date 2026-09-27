#!/usr/bin/env python3
"""Retarget the retained Mixamo human walk/run/jump to the active v9 mesh.

The source character supplies global joint rotation changes and hip bounce.
The target retains its own rest joint positions, lengths, skin and materials.
Other four clips are copied from the previous active GLB as separate actions.
Run with Blender --background --factory-startup --python this_file.py.
"""

from __future__ import annotations

import hashlib
import json
import math
from pathlib import Path

import bpy
from mathutils import Quaternion, Vector


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "docs/art/cultivator_jade/cultivator_rigged.blend"
BASE = ROOT / "src/game/actors/swordsman/models/cultivator_motion_20260927.glb"
ART = ROOT / "docs/art/cultivator_human_motion_20260927"
BLEND = ART / "cultivator_human_motion_20260927.blend"
GLB = ROOT / "src/game/actors/swordsman/models/cultivator_human_motion_20260927.glb"
CLIPS = ("walk", "run", "jump")
FPS = 30


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def read_source() -> dict:
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
    rig = bpy.data.objects["CultivatorRig"]
    arm_rotation = rig.matrix_world.to_quaternion()
    rest = {bone.name: bone.matrix_local.to_quaternion().copy()
            for bone in rig.data.bones}
    report = {}
    for clip in CLIPS:
        action = bpy.data.actions[clip]
        rig.animation_data.action = action
        first, last = (round(x) for x in action.frame_range)
        samples = []
        origin = None
        for frame in range(first, last + 1):
            bpy.context.scene.frame_set(frame)
            bpy.context.view_layer.update()
            hip = rig.pose.bones["mixamorig:Hips"]
            hip_world = rig.matrix_world @ hip.head
            if origin is None:
                origin = hip_world.copy()
            delta = hip_world - origin
            # Rotation change in world coordinates, per bone. Keeping only the
            # rotation prevents 65-bone source joint positions from stretching
            # the 22-bone target character into the source character's shape.
            rotations = {}
            for name, rest_q in rest.items():
                pose_q = rig.pose.bones[name].matrix.to_quaternion()
                local_delta = pose_q @ rest_q.inverted()
                world_delta = arm_rotation @ local_delta @ arm_rotation.inverted()
                rotations[name] = tuple(world_delta)
            samples.append({"rotations": rotations, "hip_delta": tuple(delta)})
        report[clip] = {"first": first, "last": last, "samples": samples}
    return report


def shoe_vertices(mesh: bpy.types.Object) -> list[int]:
    bpy.context.view_layer.update()
    evaluated = mesh.evaluated_get(bpy.context.evaluated_depsgraph_get())
    data = evaluated.to_mesh()
    try:
        indices = [vertex.index for vertex in data.vertices
                   if (evaluated.matrix_world @ vertex.co).z < .30
                   and vertex.index % 4 == 0]
    finally:
        evaluated.to_mesh_clear()
    if len(indices) < 60:
        raise RuntimeError("Cannot find target shoe vertices")
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


def straighten_jump_spine(rig: bpy.types.Object) -> float:
    """Level the jumping torso in world space without rotating either leg."""
    spine = rig.pose.bones["mixamorig:Spine"]

    def roll() -> float:
        bpy.context.view_layer.update()
        head = rig.matrix_world @ rig.pose.bones["mixamorig:Head"].head
        hips = rig.matrix_world @ rig.pose.bones["mixamorig:Hips"].head
        axis = head - hips
        return math.degrees(math.atan2(axis.x, axis.z))

    total = 0.0
    for _ in range(3):
        before = roll()
        if abs(before) <= 1.5:
            break
        initial = spine.rotation_quaternion.copy()
        spine.rotation_quaternion = initial @ Quaternion((1, 0, 0), math.radians(1.0))
        response = roll() - before
        spine.rotation_quaternion = initial
        if abs(response) < .1:
            raise RuntimeError(f"Jump torso roll cannot be corrected: {before:.2f}°")
        correction = max(-30.0 - total, min(30.0 - total, -before / response))
        spine.rotation_quaternion = (
            initial @ Quaternion((1, 0, 0), math.radians(correction)))
        total += correction
    if abs(roll()) > 2.5:
        raise RuntimeError(f"Jump torso still leans {roll():.2f}°")
    return total


def author_clip(rig: bpy.types.Object, mesh: bpy.types.Object,
                indices: list[int], source: dict, clip: str,
                home: Vector, idle_basis: dict[str, Quaternion]) -> dict:
    samples = source["samples"]
    parent_order = []
    def visit(bone):
        if bone.parent and bone.parent not in parent_order:
            visit(bone.parent)
        if bone not in parent_order:
            parent_order.append(bone)
    for bone in rig.data.bones:
        visit(bone)
    rest = {bone.name: bone.matrix_local.to_quaternion().copy()
            for bone in parent_order}
    arm_q = rig.matrix_world.to_quaternion()
    inverse_arm_q = arm_q.inverted()
    action = bpy.data.actions.new(clip)
    action.use_fake_user = True
    rig.animation_data.action = action
    lows = []
    hip_trace = []
    jump_roll_corrections = []
    for index, sample in enumerate(samples):
        frame = index + 1
        bpy.context.scene.frame_set(frame)
        solved = {}
        for bone in parent_order:
            name = bone.name
            if name not in sample["rotations"]:
                raise RuntimeError(f"Source missing target bone {name}")
            delta_world = Quaternion(sample["rotations"][name])
            delta_arm = inverse_arm_q @ delta_world @ arm_q
            desired = delta_arm @ rest[name]
            parent_pose = solved[bone.parent.name] if bone.parent else Quaternion((1, 0, 0, 0))
            local_rest = (rest[bone.parent.name].inverted() @ rest[name]
                          if bone.parent else rest[name])
            basis = local_rest.inverted() @ parent_pose.inverted() @ desired
            pose_bone = rig.pose.bones[name]
            pose_bone.rotation_mode = "QUATERNION"
            pose_bone.location = Vector((0, 0, 0))
            if clip == "walk" and name.rsplit(":", 1)[-1] in (
                    "LeftArm", "RightArm", "LeftForeArm", "RightForeArm",
                    "LeftHand", "RightHand"):
                # The retained Mixamo body had much narrower shoulders. Its
                # absolute arm spread does not suit v9's broader robe; keep
                # v9's relaxed hanging arms and transfer the swing at 45%.
                basis = idle_basis[name].slerp(basis.normalized(), .45)
            pose_bone.rotation_quaternion = basis.normalized()
            solved[name] = desired
        if clip == "walk":
            # Source walk keeps its upper body about 10 degrees behind the
            # pelvis in every phase. A local Spine X rotation brings the
            # hips-to-head axis back over the support leg without changing
            # the source leg motion or the root's vertical bounce.
            spine = rig.pose.bones["mixamorig:Spine"]
            spine.rotation_quaternion = (
                spine.rotation_quaternion
                @ Quaternion((1, 0, 0), math.radians(10.0)))
        elif clip == "jump":
            jump_roll_corrections.append(straighten_jump_spine(rig))
        # Root object height carries source hip bounce. Horizontal source root
        # motion is removed because gameplay owns movement in world space.
        hip_z = sample["hip_delta"][2]
        rig.location = home + Vector((0, 0, hip_z))
        bpy.context.view_layer.update()
        lows.append(shoe_floor(mesh, indices))
        hip_trace.append(hip_z)
        rig.keyframe_insert("location", frame=frame)
        for bone in parent_order:
            pose = rig.pose.bones[bone.name]
            pose.keyframe_insert("rotation_quaternion", frame=frame)
    # Fixed, whole-clip ground correction. Per-frame correction would erase
    # weight transfer and make the character visibly bob to hide foot errors.
    correction = -min(lows) if clip != "jump" else -lows[0]
    for index, hip_z in enumerate(hip_trace):
        rig.location = home + Vector((0, 0, hip_z + correction))
        rig.keyframe_insert("location", frame=index + 1)
    action.use_frame_range = True
    action.frame_start = 1
    action.frame_end = len(samples)
    rig.animation_data.action = None
    result = {"frames": len(samples), "duration_s": round((len(samples)-1)/FPS, 4),
            "hip_vertical_range_m": [round(min(hip_trace), 4), round(max(hip_trace), 4)],
            "raw_shoe_floor_range_m": [round(min(lows), 4), round(max(lows), 4)],
            "fixed_ground_correction_m": round(correction, 4)}
    if jump_roll_corrections:
        result["spine_roll_correction_deg"] = [
            round(min(jump_roll_corrections), 3),
            round(max(jump_roll_corrections), 3)]
    return result


def main() -> None:
    source = read_source()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(BASE))
    rig = next(obj for obj in bpy.data.objects if obj.type == "ARMATURE")
    mesh = next(obj for obj in bpy.data.objects if obj.type == "MESH"
                and any(mod.type == "ARMATURE" for mod in obj.modifiers))
    assert len(rig.data.bones) == 22
    original_actions = sorted(action.name for action in bpy.data.actions)
    rig.animation_data_clear()
    for clip in CLIPS:
        bpy.data.actions.remove(bpy.data.actions[clip])
    rig.animation_data_create()
    bpy.context.scene.render.fps = FPS
    bpy.context.scene.frame_set(1)
    home = rig.location.copy()
    shoes = shoe_vertices(mesh)
    rig.animation_data.action = bpy.data.actions["idle"]
    bpy.context.scene.frame_set(1)
    idle_basis = {bone.name: bone.rotation_quaternion.copy()
                  for bone in rig.pose.bones}
    result = {}
    for clip in CLIPS:
        result[clip] = author_clip(rig, mesh, shoes, source[clip], clip,
                                   home, idle_basis)
        print(f"retargeted {clip}: {result[clip]}", flush=True)
    ART.mkdir(parents=True, exist_ok=True)
    bpy.context.preferences.filepaths.save_version = 0
    rig.animation_data.action = bpy.data.actions["idle"]
    bpy.context.scene.frame_set(1)
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND))
    bpy.ops.object.select_all(action="DESELECT")
    rig.select_set(True)
    mesh.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.export_scene.gltf(
        filepath=str(GLB), export_format="GLB", use_selection=True,
        export_animation_mode="ACTIONS", export_animations=True,
        export_skins=True, export_yup=True, export_apply=False,
        export_normals=True, export_materials="EXPORT",
        export_frame_range=False, export_force_sampling=True,
        export_bake_animation=False)
    report = {
        "source": str(SOURCE.relative_to(ROOT)), "source_sha256": sha256(SOURCE),
        "target_base": str(BASE.relative_to(ROOT)), "target_base_sha256": sha256(BASE),
        "original_actions": original_actions,
        "retargeted_clips": result,
        "kept_clips": sorted(name for name in original_actions if name not in CLIPS),
        "output": str(GLB.relative_to(ROOT)), "output_sha256": sha256(GLB),
    }
    (ART / "build_manifest.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2), flush=True)


if __name__ == "__main__":
    main()
