#!/usr/bin/env python3
"""Re-author seven restrained clips from static poses on the detailed v9 mesh.

The committed v9 GLB supplies geometry, skin weights and two one-frame pose references.
None of its time-series animation curves are copied into the output. The new actions
are keyed below. The v9 runtime and its exploration sources are never overwritten.
"""

from __future__ import annotations

import json
import math
from pathlib import Path

import bpy
from mathutils import Quaternion


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "src/game/actors/swordsman/models/cultivator_tripo_v9.glb"
ART = ROOT / "docs/art/cultivator_ink_v2"
OUT = ROOT / "src/game/actors/swordsman/models/cultivator_ink_v2.glb"
FPS = 30


def bone(arm, short):
    for prefix in ("mixamorig:", "mixamorig_"):
        found = arm.pose.bones.get(prefix + short)
        if found is not None:
            return found
    raise KeyError(short)


def qx(degrees):
    return Quaternion((1, 0, 0), math.radians(degrees))


def qy(degrees):
    return Quaternion((0, 1, 0), math.radians(degrees))


def snapshot(arm, action_name, frame=2):
    arm.animation_data.action = bpy.data.actions[action_name]
    bpy.context.scene.frame_set(frame)
    return {b.name: (b.rotation_quaternion.copy(), b.location.copy(), b.scale.copy())
            for b in arm.pose.bones}


def corrected(source, leg_deg, foot_deg):
    """Place ankles beneath the pelvis and flatten the *skinned shoe* in side view.

    The previous experimental solver looked at the toe bone and rotated the visible
    shoe upward. These values were selected against rendered skinned shoes, not only
    ankle->toe bone vectors: trial -7.65 thigh/shin plus a net -5 foot correction.
    """
    state = {k: (q.copy(),loc.copy(),scale.copy())
             for k,(q,loc,scale) in source.items()}
    for short in ("LeftUpLeg","RightUpLeg","LeftLeg","RightLeg"):
        name = next(k for k in state if k.endswith(short))
        q,loc,scale = state[name]
        state[name] = (q @ qx(leg_deg),loc,scale)
    for short in ("LeftFoot","RightFoot"):
        name = next(k for k in state if k.endswith(short))
        q,loc,scale = state[name]
        state[name] = (q @ qx(foot_deg),loc,scale)
    return state


def select_foot_vertices(mesh):
    bpy.context.view_layer.update()
    deps = bpy.context.evaluated_depsgraph_get()
    obj = mesh.evaluated_get(deps)
    data = obj.to_mesh()
    try:
        indices = [i for i,v in enumerate(data.vertices)
                   if (mesh.matrix_world @ v.co).z < .30 and i % 3 == 0]
    finally:
        obj.to_mesh_clear()
    if len(indices) < 100:
        raise RuntimeError(f"no boot samples: {len(indices)}")
    return indices


def foot_min(mesh, indices):
    bpy.context.view_layer.update()
    deps = bpy.context.evaluated_depsgraph_get()
    obj = mesh.evaluated_get(deps)
    data = obj.to_mesh()
    try:
        return min((mesh.matrix_world @ data.vertices[i].co).z for i in indices)
    finally:
        obj.to_mesh_clear()


def key(arm, frame, base, rotations=None, shifts=None):
    scene = bpy.context.scene
    scene.frame_set(frame)
    rotations = rotations or {}
    shifts = shifts or {}
    for b in arm.pose.bones:
        q,loc,scale = base[b.name]
        b.rotation_mode = "QUATERNION"
        b.rotation_quaternion = q.copy()
        b.location = loc.copy()
        b.scale = scale.copy()
    for short, degrees in rotations.items():
        b = bone(arm, short)
        b.rotation_quaternion = b.rotation_quaternion @ qx(degrees)
    for short, delta in shifts.items():
        b = bone(arm, short)
        # Mixamo armature coordinates are centimetre-scale, so use measured units.
        b.location.y += delta
    for b in arm.pose.bones:
        b.keyframe_insert("rotation_quaternion", frame=frame)
        b.keyframe_insert("location", frame=frame)


def make_action(arm, mesh, indices, name, frames, base, poses, floor_mode="per_frame"):
    action = bpy.data.actions.new("ink_" + name)
    action.use_fake_user = True
    arm.animation_data.action = action
    home_z = arm.location.z
    for frame, rots, shifts in poses:
        key(arm, frame, base, rots, shifts)
        arm.location.z = home_z
        arm.keyframe_insert("location", frame=frame)
    lows = []
    once = None
    for frame in range(1, frames + 1):
        bpy.context.scene.frame_set(frame)
        low = foot_min(mesh, indices)
        lows.append(low)
        if once is None:
            once = low
        arm.location.z = home_z - (low if floor_mode == "per_frame" else once)
        arm.keyframe_insert("location", frame=frame)
    return {"frames":frames,"foot_min_before_m":round(min(lows),4),
            "foot_max_before_m":round(max(lows),4),"floor_mode":floor_mode}


def build():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(SOURCE))
    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    mesh = next(o for o in bpy.data.objects if o.type == "MESH" and len(o.data.vertices) > 100000)
    scene = bpy.context.scene
    scene.render.fps = FPS
    # One static source frame per pose family. No source time-series are retained.
    guard = corrected(snapshot(arm,"idle_guarded"), -7.65, -4.93)
    neutral = corrected(snapshot(arm,"idle",1), -7.3, -5.0)
    # The old seated frame is a shape reference only. Close the excessive leg
    # spread and key a new breathing loop below; no old animation curve is copied.
    seated = snapshot(arm,"meditate")
    for short, direction in (("LeftUpLeg",1),("RightUpLeg",-1)):
        name = next(k for k in seated if k.endswith(short))
        q,loc,scale = seated[name]
        seated[name] = (q @ qy(-36 * direction),loc,scale)
    arm.animation_data.action = bpy.data.actions["idle_guarded"]
    scene.frame_set(2)
    indices = select_foot_vertices(mesh)
    old_actions = list(bpy.data.actions)
    results = {}
    idle = [(1,{},{}),(37,{"Spine":1,"Head":-.5,"LeftArm":.5,"RightArm":.5},{}),
            (73,{},{})]
    results["idle_guarded"] = make_action(arm,mesh,indices,"idle_guarded",73,guard,idle)
    results["idle"] = make_action(arm,mesh,indices,"idle",73,neutral,idle)

    def gait(amplitude, knee, arm_swing, frames):
        return [
            (1,{"LeftUpLeg":amplitude,"RightUpLeg":-amplitude,
                "LeftLeg":knee,"LeftArm":-arm_swing,"RightArm":arm_swing},{}),
            (1+frames//4,{"LeftUpLeg":0,"RightUpLeg":0,
                "LeftLeg":knee*.35,"RightLeg":knee*.35,"Spine":1},{}),
            (1+frames//2,{"LeftUpLeg":-amplitude,"RightUpLeg":amplitude,
                "RightLeg":knee,"LeftArm":arm_swing,"RightArm":-arm_swing},{}),
            (1+frames*3//4,{"LeftUpLeg":0,"RightUpLeg":0,
                "LeftLeg":knee*.35,"RightLeg":knee*.35,"Spine":1},{}),
            (frames,{"LeftUpLeg":amplitude,"RightUpLeg":-amplitude,
                "LeftLeg":knee,"LeftArm":-arm_swing,"RightArm":arm_swing},{})]
    results["walk"] = make_action(arm,mesh,indices,"walk",31,neutral,gait(21,14,9,31))
    results["run"] = make_action(arm,mesh,indices,"run",23,neutral,gait(28,22,14,23))
    results["jump"] = make_action(arm,mesh,indices,"jump",32,neutral,[
        (1,{"LeftUpLeg":8,"RightUpLeg":8,"LeftLeg":-14,"RightLeg":-14,
            "Spine":4},{}),
        (9,{"LeftUpLeg":29,"RightUpLeg":-14,"LeftLeg":-38,"RightLeg":22,
            "LeftArm":-19,"RightArm":12,"Spine":-3},{}),
        (19,{"LeftUpLeg":34,"RightUpLeg":-18,"LeftLeg":-42,"RightLeg":26,
             "LeftArm":-21,"RightArm":15,"Spine":-4},{}),
        (32,{"LeftUpLeg":11,"RightUpLeg":11,"LeftLeg":-20,"RightLeg":-20,
             "LeftArm":-8,"RightArm":-8,"Spine":5},{}),
    ],"first_frame")
    ride = [(1,{"LeftUpLeg":2,"RightUpLeg":2,"LeftLeg":-3,"RightLeg":-3},{}),
            (37,{"LeftUpLeg":2,"RightUpLeg":2,"LeftLeg":-3,"RightLeg":-3,
                 "Spine":2,"Head":-1},{}),
            (73,{"LeftUpLeg":2,"RightUpLeg":2,"LeftLeg":-3,"RightLeg":-3},{})]
    results["sword_ride"] = make_action(arm,mesh,indices,"sword_ride",73,guard,ride)
    # Sitting is intentionally its own non-standing base; the body lowers to the
    # contact point. A tiny breathing loop replaces the former 73-frame animation.
    results["meditate"] = make_action(arm,mesh,indices,"meditate",73,seated,
        [(1,{},{}),(37,{"Spine":1,"Head":-.5},{}),(73,{},{})])
    for action in old_actions:
        bpy.data.actions.remove(action)
    for action in bpy.data.actions:
        if action.name.startswith("ink_"):
            action.name = action.name.removeprefix("ink_")
    ART.mkdir(parents=True, exist_ok=True)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    arm.animation_data.action = bpy.data.actions["idle_guarded"]
    scene.frame_set(1)
    bpy.ops.wm.save_as_mainfile(filepath=str(ART/"cultivator_ink_v2.blend"))
    bpy.ops.export_scene.gltf(filepath=str(OUT),export_format="GLB",
        export_animation_mode="ACTIONS",export_animations=True,
        export_skins=True,export_yup=True,export_apply=False,
        export_normals=True,export_materials="EXPORT",
        export_frame_range=False,export_force_sampling=True,
        export_bake_animation=False,use_selection=False,use_visible=True)
    report={"source_mesh":str(SOURCE.relative_to(ROOT)),
            "source_time_series_copied":False,
            "foot_sample_vertices":len(indices),"clips":results}
    (ART/"build_manifest.json").write_text(json.dumps(report,indent=2)+"\n")
    print(json.dumps(report,indent=2),flush=True)


if __name__ == "__main__":
    build()
