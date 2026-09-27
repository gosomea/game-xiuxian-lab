#!/usr/bin/env python3
"""Retarget walk/run arms and retain the front-facing v9 jump.

The source character supplies global joint rotation changes and hip bounce.
The target retains its own rest joint positions, lengths, skin and materials.
The old Mixamo jump faces diagonally and ends in a seated pose. This version
keeps the v9 vertical jump and gives both arms a modest, symmetric lift.
The other four clips are copied from the base GLB as separate actions.
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
ART = ROOT / "docs/art/cultivator_aligned_motion_20260927"
BLEND = ART / "cultivator_aligned_motion_20260927.blend"
GLB = ROOT / "src/game/actors/swordsman/models/cultivator_aligned_motion_20260927.glb"
CLIPS = ("walk", "run")
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


def rotate_bone_world(rig: bpy.types.Object, name: str,
                      axis: Vector, degrees: float) -> None:
    """Add a world-axis rotation while retaining the bone's parent and bind axes."""
    bone = rig.pose.bones["mixamorig:" + name]
    rest = bone.bone.matrix_local.to_quaternion()
    parent_pose = bone.parent.matrix.to_quaternion() if bone.parent else Quaternion()
    local_rest = (bone.parent.bone.matrix_local.to_quaternion().inverted() @ rest
                  if bone.parent else rest)
    arm_q = rig.matrix_world.to_quaternion()
    world_delta = Quaternion(axis, math.radians(degrees))
    arm_delta = arm_q.inverted() @ world_delta @ arm_q
    parent_rest = parent_pose @ local_rest
    bone.rotation_quaternion = (
        parent_rest.inverted() @ arm_delta @ parent_rest
        @ bone.rotation_quaternion).normalized()


def point(rig: bpy.types.Object, name: str) -> Vector:
    return rig.matrix_world @ rig.pose.bones["mixamorig:" + name].head


def cap_arm_splay(rig: bpy.types.Object, side: str, lateral: Vector,
                  elbow_limit: float, wrist_limit: float,
                  frame: int) -> tuple[float, float]:
    """Keep the imported swing, but rotate the upper and lower arm inward."""
    shoulder = side + "Arm"
    elbow = side + "ForeArm"
    wrist = side + "Hand"
    results = []
    for name, endpoint, limit in ((shoulder, elbow, elbow_limit),
                                  (elbow, wrist, wrist_limit)):
        start = point(rig, shoulder)
        pivot = point(rig, name)
        end = point(rig, endpoint)
        offset = (end - start).dot(lateral)
        if offset > limit + .002:
            # Predict the endpoint from a world-Y rotation analytically. A
            # probe that updates Blender's dependency graph before keying can
            # restore the unkeyed pose and silently export the old splay.
            options = []
            axes = (Vector((0, 1, 0)), Vector((0, 0, 1)))
            for axis_index, axis in enumerate(axes):
                for step in range(-80, 81):
                    degrees = step * .5
                    rotated = pivot + Quaternion(axis, math.radians(degrees)) @ (end - pivot)
                    predicted = (rotated - start).dot(lateral)
                    if predicted <= limit + .001:
                        options.append((abs(degrees) + axis_index * 2.0,
                                        abs(predicted - limit), axis_index, degrees))
            if not options:
                raise RuntimeError(f"{side} {name} frame {frame}: outward {offset:.3f} m cannot reach {limit:.3f} m")
            chosen = min(options)
            rotate_bone_world(rig, name, axes[chosen[2]], chosen[3])
            rig.pose.bones["mixamorig:" + name].keyframe_insert(
                "rotation_quaternion", frame=frame)
            bpy.context.view_layer.update()
        final = (point(rig, endpoint) - point(rig, shoulder)).dot(lateral)
        if final > limit + .008:
            raise RuntimeError(f"{side} arm remains too far out: {final:.3f} m")
        results.append(round(final, 4))
    return tuple(results)


def author_clip(rig: bpy.types.Object, mesh: bpy.types.Object,
                indices: list[int], source: dict, clip: str,
                home: Vector, idle_basis: dict[str, Quaternion],
                idle_right: Vector) -> dict:
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
    arm_outward = []
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
            limb = name.rsplit(":", 1)[-1]
            if limb in ("LeftArm", "RightArm", "LeftForeArm", "RightForeArm",
                        "LeftHand", "RightHand"):
                # The source arms swing forward and back naturally, but its
                # broad shoulders and hand twist do not fit the v9 robe.
                # Keep motion in walk/run, then cap only lateral spread.
                weight = 0.45 if clip == "walk" else 1.0
                if limb.endswith("Hand"):
                    weight = 0.0
                basis = idle_basis[name].slerp(basis.normalized(), weight)
            pose_bone.rotation_quaternion = basis.normalized()
            solved[name] = desired
        # Establish every source pose as a key before any dependency-graph
        # update. Later local corrections must be keyed before the next update.
        for bone in parent_order:
            rig.pose.bones[bone.name].keyframe_insert(
                "rotation_quaternion", frame=frame)
        bpy.context.view_layer.update()
        if clip == "walk":
            # Source walk keeps its upper body about 10 degrees behind the
            # pelvis in every phase. A local Spine X rotation brings the
            # hips-to-head axis back over the support leg without changing
            # the source leg motion or the root's vertical bounce.
            spine = rig.pose.bones["mixamorig:Spine"]
            spine.rotation_quaternion = (
                spine.rotation_quaternion
                @ Quaternion((1, 0, 0), math.radians(10.0)))
            spine.keyframe_insert("rotation_quaternion", frame=frame)
            bpy.context.view_layer.update()
        for side, sign in (("Left", -1), ("Right", 1)):
            limits = (.065, .12) if clip == "walk" else (.09, .15)
            arm_outward.append(cap_arm_splay(rig, side, idle_right * sign,
                                            *limits, frame))
        # Root object height carries source hip bounce. Horizontal source root
        # motion is removed because gameplay owns movement in world space.
        hip_z = sample["hip_delta"][2]
        rig.location = home + Vector((0, 0, hip_z))
        rig.keyframe_insert("location", frame=frame)
        for bone in parent_order:
            pose = rig.pose.bones[bone.name]
            pose.keyframe_insert("rotation_quaternion", frame=frame)
        bpy.context.view_layer.update()
        lows.append(shoe_floor(mesh, indices))
        hip_trace.append(hip_z)
    # Fixed, whole-clip ground correction. Per-frame correction would erase
    # weight transfer and make the character visibly bob to hide foot errors.
    correction = -min(lows)
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
    result["arm_outward_max_m"] = {
        "elbow": max(v[0] for v in arm_outward),
        "wrist": max(v[1] for v in arm_outward),
    }
    return result


def author_vertical_jump(rig: bpy.types.Object, idle_right: Vector) -> dict:
    """Keep the v9 jump's front-facing legs and give both arms a small lift."""
    action = bpy.data.actions["jump"]
    rig.animation_data.action = action
    first, last = (round(v) for v in action.frame_range)
    arm_outward = []
    for frame in range(first, last + 1):
        bpy.context.scene.frame_set(frame)
        phase = (frame - first) / max(1, last - first)
        lift = 14.0 * math.sin(math.pi * phase) ** 2
        for side, sign in (("Left", -1), ("Right", 1)):
            rotate_bone_world(rig, side + "Arm", Vector((1, 0, 0)), -lift)
            rig.pose.bones["mixamorig:" + side + "Arm"].keyframe_insert(
                "rotation_quaternion", frame=frame)
            bpy.context.view_layer.update()
            rotate_bone_world(rig, side + "ForeArm", Vector((1, 0, 0)),
                              -lift * .35)
            rig.pose.bones["mixamorig:" + side + "ForeArm"].keyframe_insert(
                "rotation_quaternion", frame=frame)
            bpy.context.view_layer.update()
            arm_outward.append(cap_arm_splay(rig, side, idle_right * sign,
                                            .09, .13, frame))
    rig.animation_data.action = None
    return {"source": "target_base:jump", "frames": last - first + 1,
            "symmetric_arm_lift_max_deg": 14.0,
            "arm_outward_max_m": {
                "elbow": max(v[0] for v in arm_outward),
                "wrist": max(v[1] for v in arm_outward),
            }}


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
    idle_right = (point(rig, "RightArm") - point(rig, "LeftArm"))
    idle_right.z = 0
    idle_right.normalize()
    result = {}
    for clip in CLIPS:
        result[clip] = author_clip(rig, mesh, shoes, source[clip], clip,
                                   home, idle_basis, idle_right)
        print(f"retargeted {clip}: {result[clip]}", flush=True)
    result["jump"] = author_vertical_jump(rig, idle_right)
    print(f"authored jump: {result['jump']}", flush=True)
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
        "retargeted_clips": {name: result[name] for name in CLIPS},
        "authored_jump": result["jump"],
        "kept_clips": sorted(name for name in original_actions
                             if name not in (*CLIPS, "jump")),
        "output": str(GLB.relative_to(ROOT)), "output_sha256": sha256(GLB),
    }
    (ART / "build_manifest.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2), flush=True)


if __name__ == "__main__":
    main()
