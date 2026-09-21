#!/usr/bin/env python3
"""Hand-author character poses that the stock animation library does not contain.

Run with Blender:
    blender --background --factory-startup --python \
        tools/art/author_cultivator_pose.py -- \
        --base docs/art/cultivator_tripo_v9/iterations/mia_rig/20260921-v2 \
        --pose meditate --name meditate_seat \
        --out-iteration docs/art/cultivator_tripo_v9/iterations/authored_poses \
        --render docs/art/cultivator_tripo_v9/renders/authored

Why this exists
---------------
The Mixamo library has no 打坐 (seated meditation), no 负手而立 (standing with hands
behind the back) and no 结印 (hand seals). Its closest entries are a Western lounging idle,
a martial-arts crouch and a Superman-style dive. Eastern cultivation poses have to be
authored rather than downloaded, and this builds them on the rig the character already has
instead of importing a second skeleton.

What the rig can and cannot express
-----------------------------------
22 bones: hips, 3 spine, neck, head, 2x(shoulder, arm, forearm, hand) and
2x(upleg, leg, foot, toe). **There are no finger bones**, so a true 掐诀/结印 cannot be
posed - the hands are rigid mitts. Everything else a cultivator pose needs (crossed legs,
hands behind the back, upright spine, level head) is available.

Axis conventions, measured rather than assumed
----------------------------------------------
Rotating a pose bone rotates about the BONE's local axes. Probing `LeftUpLeg` and
`LeftLeg` with +45 degrees about each axis in turn shows both bones swing the distal
joint toward -Y (the character's front) under a POSITIVE X rotation. Therefore:

  * hip flexion (thigh forward/up)   = +X on UpLeg
  * knee flexion (shin backward)     = -X on Leg
  * leg abduction (spread outward)   = +Z, mirrored between sides
  * twist along the limb             = Y

Signs were confirmed against the front axis (-Y, established from the toe/hip offsets) so
these are not guesses.

Output
------
Writes `clip_<name>_slot2.fbx` into the given iteration directory, matching the shape
`tools/art/build_cultivator_tripo_v9_runtime_glb.py` already consumes, so an authored pose
joins the normal ground-align + material-splice pipeline with no special casing. Also
renders orthographic front/side/three-quarter views for review.
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector

# --------------------------------------------------------------------------------------
# Pose library
# --------------------------------------------------------------------------------------
# Each entry maps a bone name to bone-local Euler degrees (X, Y, Z). `hips_offset` is an
# extra armature-local translation for poses that sit lower than standing (the ground
# alignment upstream normalises the final height, so this only shapes the pose itself).
#
# Coverage note: the spec may name bones the rig does not have (fingers); those are
# reported as skipped rather than silently dropped, because "the hands cannot do this" is
# a real limitation the caller should see.

POSES: dict[str, dict] = {
    # 打坐：盘腿坐，脊柱正直，双手落于膝上。混合式（半跏趺坐），四根腿骨可达。
    "meditate": {
        "description": "盘腿打坐（半跏趺坐）：小腿收向身体中线交叠，脊柱正直，双手相叠于腹前",
        "bones": {
            # 骨盆后倾一点，让坐骨坐实、腰自然直（不是塌腰也不是挺胸）。
            "mixamorig:Hips": (-14.0, 0.0, 0.0),
            "mixamorig:Spine": (5.0, 0.0, 0.0),
            "mixamorig:Spine1": (4.0, 0.0, 0.0),
            "mixamorig:Spine2": (3.0, 0.0, 0.0),
            "mixamorig:Neck": (-3.0, 0.0, 0.0),
            "mixamorig:Head": (-2.0, 0.0, 0.0),
            # 大腿：前抬到水平稍上 + 外展。外展角要小：盘腿是「小腿」横收，不是大腿摊平。
            "mixamorig:LeftUpLeg": (78.0, 0.0, 26.0),
            "mixamorig:RightUpLeg": (78.0, 0.0, -26.0),
            # 小腿：向后折到底，并沿 Z 内收，使两小腿在身前交叠而非左右摊开。
            # 左腿收向右侧（负 Z 内旋）、右腿收向左侧，交叠后右脚在外、左脚在内。
            "mixamorig:LeftLeg": (-152.0, 0.0, -34.0),
            "mixamorig:RightLeg": (-152.0, 0.0, 34.0),
            # 脚踝：放松，脚背贴地
            "mixamorig:LeftFoot": (26.0, 0.0, 0.0),
            "mixamorig:RightFoot": (26.0, 0.0, 0.0),
            # 双臂：收在腹前相叠（无手指骨，只能到「手叠手」这一层，做不到指印）。
            # 以下是 tools/art/solve_pose_targets.py 反解出来的角度，不是手调的：
            # 目标 hand_l=(+0.075,-0.190,+0.030)、hand_r=(-0.075,-0.190,+0.030)，
            # 实测到达误差 3.6–4.4 cm。手调角度容易失败，因为 LeftArm 绕 X 会让手
            # 向「外上方」走而不是前方，直觉值会把手放错而只在渲染里才看得出来。
            "mixamorig:LeftShoulder": (0.0, 0.0, -6.0),
            "mixamorig:RightShoulder": (0.0, 0.0, 6.0),
            "mixamorig:LeftArm": (86.0, -43.0, 18.0),
            "mixamorig:RightArm": (73.0, 40.0, -31.0),
            "mixamorig:LeftForeArm": (9.0, 18.0, 12.0),
            "mixamorig:RightForeArm": (9.0, 2.0, -11.0),
            "mixamorig:LeftHand": (-12.0, 0.0, -6.0),
            "mixamorig:RightHand": (-12.0, 0.0, 6.0),
        },
    },
    # 负手而立：双手负于身后，身姿端正。最贴「修士」气质的站姿。
    "hands_behind_back": {
        "description": "负手而立：双手背于身后交叠，脊柱正直，下颌微收",
        "bones": {
            "mixamorig:Spine": (1.0, 0.0, 0.0),
            "mixamorig:Spine1": (1.0, 0.0, 0.0),
            "mixamorig:Spine2": (1.0, 0.0, 0.0),
            "mixamorig:Neck": (-2.0, 0.0, 0.0),
            "mixamorig:Head": (-1.0, 0.0, 0.0),
            # 双臂后旋内收，手在背后相叠。反解自 solve_pose_targets.py：
            # 目标 hand_l=(+0.055,+0.165,-0.055)、hand_r=(-0.055,+0.165,-0.055)，误差 1.0–1.1 cm。
            # 手调会失败——LeftArm 的 X 是「抬臂外展」，负 X 是把手上举而不是后旋。
            "mixamorig:LeftShoulder": (0.0, 0.0, -6.0),
            "mixamorig:RightShoulder": (0.0, 0.0, 6.0),
            "mixamorig:LeftArm": (82.0, -2.0, 56.0),
            "mixamorig:RightArm": (72.0, -20.0, 95.0),
            "mixamorig:LeftForeArm": (27.0, -22.0, 21.0),
            "mixamorig:RightForeArm": (34.0, -23.0, -36.0),
            "mixamorig:LeftHand": (-6.0, 0.0, 0.0),
            "mixamorig:RightHand": (-6.0, 0.0, 0.0),
            # 双脚并拢站定
            "mixamorig:LeftUpLeg": (0.0, 0.0, 3.0),
            "mixamorig:RightUpLeg": (0.0, 0.0, -3.0),
            "mixamorig:LeftLeg": (-2.0, 0.0, 0.0),
            "mixamorig:RightLeg": (-2.0, 0.0, 0.0),
        },
    },
    # 御剑：脚踏飞剑而立。手臂复用已解好的「负手」角度——负手御剑才是修士的标志姿态，
    # 双臂微分保持平衡是西方飞行姿态的读法，不是这一套。
    # 与 hands_behind_back 的差别只在体势：上身前倾迎风、双膝屈以吸震、双脚并拢。
    "sword_riding": {
        "description": "御剑而立：负手于背，上身前倾迎风，双膝微屈，双脚并拢立于剑上",
        "bones": {
            # 迎风前倾：从髋起逐节前倾，颈项反向上抬以保持目视前方。
            "mixamorig:Hips": (9.0, 0.0, 0.0),
            "mixamorig:Spine": (6.0, 0.0, 0.0),
            "mixamorig:Spine1": (5.0, 0.0, 0.0),
            "mixamorig:Spine2": (4.0, 0.0, 0.0),
            "mixamorig:Neck": (-13.0, 0.0, 0.0),
            "mixamorig:Head": (-10.0, 0.0, 0.0),
            # 手臂：与 hands_behind_back 同源（同一次反解结果，误差 1.0–1.1 cm）。
            "mixamorig:LeftShoulder": (0.0, 0.0, -6.0),
            "mixamorig:RightShoulder": (0.0, 0.0, 6.0),
            "mixamorig:LeftArm": (82.0, -2.0, 56.0),
            "mixamorig:RightArm": (72.0, -20.0, 95.0),
            "mixamorig:LeftForeArm": (27.0, -22.0, 21.0),
            "mixamorig:RightForeArm": (34.0, -23.0, -36.0),
            "mixamorig:LeftHand": (-6.0, 0.0, 0.0),
            "mixamorig:RightHand": (-6.0, 0.0, 0.0),
            # 双腿并拢立于剑上，膝微屈吸震（不是双腿微分悬空）。
            "mixamorig:LeftUpLeg": (-7.0, 0.0, 3.0),
            "mixamorig:RightUpLeg": (-7.0, 0.0, -3.0),
            "mixamorig:LeftLeg": (-14.0, 0.0, 0.0),
            "mixamorig:RightLeg": (-14.0, 0.0, 0.0),
            "mixamorig:LeftFoot": (10.0, 0.0, 0.0),
            "mixamorig:RightFoot": (10.0, 0.0, 0.0),
        },
    },
}

## Bones the rig deliberately does not have. Named here so a pose spec that wants them is
## reported as a real limitation instead of failing obscurely.
MISSING_BY_DESIGN = {
    "fingers": "本骨架无手指骨（No Fingers 绑骨），掐诀/结印的手指动作无法摆出",
}


def parse_args() -> argparse.Namespace:
    argv = sys.argv
    argv = argv[argv.index("--") + 1 :] if "--" in argv else []
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", required=True,
                        help="iteration dir holding an existing clip_*_slot2.fbx to take the rig from")
    parser.add_argument("--pose", required=True, choices=sorted(POSES))
    parser.add_argument("--name", required=True, help="output clip name (file becomes clip_<name>_slot2.fbx)")
    parser.add_argument("--out-iteration", required=True)
    parser.add_argument("--render", default="")
    parser.add_argument("--frames", type=int, default=90,
                        help="loop length; the pose is held with a subtle breath cycle")
    parser.add_argument("--fps", type=int, default=30)
    parser.add_argument("--resolution", type=int, default=420)
    parser.add_argument("--samples", type=int, default=20)
    parser.add_argument("--report", default="")
    return parser.parse_args(argv)


def find_rig() -> tuple[object, object]:
    armature = next((o for o in bpy.data.objects if o.type == "ARMATURE"), None)
    mesh = next((o for o in bpy.data.objects if o.type == "MESH"), None)
    if armature is None or mesh is None:
        raise RuntimeError("no armature/mesh in scene")
    return armature, mesh


def action_fcurves(action) -> list:
    """Every F-curve in an action, across both Blender action APIs.

    Blender 5.2 replaced the flat `Action.fcurves` collection with slotted/layered actions
    (`action.layers[*].strips[*].channelbags[*].fcurves`). Support both so this script does
    not silently report zero curves on either.
    """
    try:
        return list(action.fcurves)
    except AttributeError:
        pass
    curves = []
    for layer in getattr(action, "layers", []) or []:
        for strip in getattr(layer, "strips", []) or []:
            for bag in getattr(strip, "channelbags", []) or []:
                curves.extend(getattr(bag, "fcurves", []) or [])
    return curves


def bone_lookup(armature, name: str):
    """Accept both `mixamorig:X` and `mixamorig_X`, since import settings vary."""
    for candidate in (name, name.replace(":", "_"), name.replace("_", ":")):
        bone = armature.pose.bones.get(candidate)
        if bone is not None:
            return bone
    return None


def apply_pose(armature, spec: dict, report: dict) -> None:
    applied, skipped = [], []
    for name, degrees in spec["bones"].items():
        bone = bone_lookup(armature, name)
        if bone is None:
            skipped.append(name)
            continue
        bone.rotation_mode = "XYZ"
        bone.rotation_euler = [math.radians(d) for d in degrees]
        applied.append(name)
    report["bones_applied"] = len(applied)
    report["bones_skipped"] = skipped
    if skipped:
        report["problems"].append(f"pose names bones the rig lacks: {skipped}")
    bpy.context.view_layer.update()


def lowest_vertex_z(armature, mesh) -> float:
    """Lowest evaluated world Z of the skinned mesh in its current pose."""
    depsgraph = bpy.context.evaluated_depsgraph_get()
    evaluated = mesh.evaluated_get(depsgraph)
    matrix = evaluated.matrix_world
    return min((matrix @ v.co).z for v in evaluated.data.vertices)


def align_floor_with_rest(armature, mesh, rest_lowest: float, report: dict) -> Vector:
    """Remove the height a pose gained or lost, by moving the HIPS BONE (not the object).

    Three separate traps make the obvious implementations wrong; all three were hit:

    1. "Put the lowest vertex on z=0" is wrong. The build step afterwards lifts the whole
       scene root by the standing clips' lowest point (~+1.01 m), applied to every clip
       equally, so normalising here would be lifted again and hover a metre up. The correct
       target is the REST pose's own floor.

    2. Moving the ARMATURE OBJECT is silently discarded. Measured: an FBX round-trip returns
       the pose at exactly its pre-shift height (and the glTF export writes `T=None` on the
       Armature node). The displacement must live in the POSE data, i.e. on the root bone.

    3. The relationship between `hips.location` and world height is NOT a clean axis scale.
       Measured on this rig (armature scale 0.01, cm rig): `location.Y += 1.0` raises the
       silhouette by 0.0098 m and `location.Z += 1.0` by only 0.0021 m, because the bone's
       rest matrix rotates the translation axes. Assuming "Z is up" or "divide by 0.01"
       gives a corrective that does nothing or goes sideways.

    So the effective direction is solved numerically: probe each local axis, then scale the
    unit response to reach the requested world offset. This is cheap (3 evaluations) and
    immune to however the importer chose to orient the root bone.
    """
    posed_lowest = lowest_vertex_z(armature, mesh)
    world_offset = rest_lowest - posed_lowest

    hips = bone_lookup(armature, "mixamorig:Hips")
    if hips is None:
        raise RuntimeError("no Hips bone to carry the floor offset")

    base_location = hips.location.copy()
    baseline = posed_lowest
    response: list[float] = []
    for axis in range(3):
        trial = base_location.copy()
        trial[axis] += 1.0
        hips.location = trial
        bpy.context.view_layer.update()
        bpy.context.evaluated_depsgraph_get().update()
        response.append(lowest_vertex_z(armature, mesh) - baseline)

    # Choose the axis that actually moves the character vertically, then scale it.
    best_axis = max(range(3), key=lambda i: abs(response[i]))
    if abs(response[best_axis]) < 1e-9:
        raise RuntimeError("no Hips axis changes world height; cannot align the floor")
    units = world_offset / response[best_axis]

    final = base_location.copy()
    final[best_axis] += units
    hips.location = final
    bpy.context.view_layer.update()
    bpy.context.evaluated_depsgraph_get().update()
    after = lowest_vertex_z(armature, mesh)

    report["ground"] = {
        "rest_lowest": round(rest_lowest, 5),
        "posed_lowest_before": round(posed_lowest, 5),
        "world_offset_requested": round(world_offset, 5),
        "axis_response_m_per_unit": [round(v, 6) for v in response],
        "axis_used": "XYZ"[best_axis],
        "units_applied": round(units, 5),
        "posed_lowest_after": round(after, 5),
        "residual_m": round(after - rest_lowest, 5),
        "method": "solve the Hips root bone's effective vertical axis numerically; "
                  "object-level shifts do not survive FBX/glTF export",
    }
    print(f"floor align: posed {posed_lowest:+.4f} -> {after:+.4f} "
          f"(wanted {rest_lowest:+.4f}, residual {after - rest_lowest:+.5f} m; "
          f"axis {'XYZ'[best_axis]}, response {response[best_axis]:+.5f} m/unit)", flush=True)
    return final - base_location


def keyframe_breath(armature, spec: dict, frames: int, report: dict) -> None:
    """Hold the pose across a loop with a subtle breath cycle.

    A perfectly static clip looks dead and also gives the presentation layer's cross-fade
    nothing to blend against. The breath is deliberately small: a few tenths of a degree on
    the spine plus a millimetre-scale hip lift, which reads as breathing without turning the
    pose into a different one.
    """
    scene = bpy.context.scene
    scene.render.fps = report["fps"]
    scene.frame_start = 1
    scene.frame_end = frames

    armature.animation_data_create()
    action = bpy.data.actions.new(name=report["clip_name"])
    armature.animation_data.action = action

    spine_names = ["mixamorig:Spine", "mixamorig:Spine1", "mixamorig:Spine2"]
    # Captured AFTER the floor alignment, so the breathing loop oscillates around the
    # corrected height instead of undoing it on the first keyframe.
    hips = bone_lookup(armature, "mixamorig:Hips")
    base_hips_loc = hips.location.copy() if hips is not None else None

    # Two full breath cycles across the loop so the ends match.
    samples = 9
    for step in range(samples):
        frame = 1 + round((frames - 1) * step / (samples - 1))
        scene.frame_set(frame)
        phase = 2.0 * math.pi * 2.0 * step / (samples - 1)
        breath = math.sin(phase)

        for index, name in enumerate(spine_names):
            bone = bone_lookup(armature, name)
            if bone is None:
                continue
            base = spec["bones"].get(name, (0.0, 0.0, 0.0))
            # Deeper spine bones move less; the chest is what visibly rises.
            amplitude = (0.45, 0.6, 0.8)[index]
            bone.rotation_mode = "XYZ"
            bone.rotation_euler = (
                math.radians(base[0] + amplitude * breath),
                math.radians(base[1]),
                math.radians(base[2]),
            )
            bone.keyframe_insert("rotation_euler", frame=frame)

        if hips is not None and base_hips_loc is not None:
            # Armature-local: a small lift/return, mirrored exactly at both ends. The
            # ground correction lives on the armature OBJECT, not here, so it is not
            # re-applied per keyframe.
            hips.location = base_hips_loc + Vector((0.0, 0.0, 0.0))
            hips.keyframe_insert("location", frame=frame)

    # Keyframe every posed bone at the first and last frame so the loop is seamless and the
    # clip holds the pose rather than drifting back toward rest.
    for name in spec["bones"]:
        bone = bone_lookup(armature, name)
        if bone is None:
            continue
        for frame in (1, frames):
            scene.frame_set(frame)
            bone.keyframe_insert("rotation_euler", frame=frame)

    curves = action_fcurves(action)
    for fcurve in curves:
        for kp in fcurve.keyframe_points:
            kp.interpolation = "BEZIER"
    report["keyframed_action"] = action.name
    report["fcurves"] = len(curves)
    scene.frame_set(1)


def setup_and_render(mesh, out_dir: Path, resolution: int, samples: int, report: dict) -> None:
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = resolution
    scene.render.resolution_y = int(resolution * 1.45)
    scene.render.image_settings.file_format = "PNG"
    scene.eevee.taa_render_samples = samples
    scene.world = bpy.data.worlds.new("studio")
    scene.world.use_nodes = True
    scene.world.node_tree.nodes["Background"].inputs[0].default_value = (0.55, 0.55, 0.57, 1.0)

    depsgraph = bpy.context.evaluated_depsgraph_get()
    evaluated = mesh.evaluated_get(depsgraph)
    coords = [mesh.matrix_world @ v.co for v in evaluated.data.vertices]
    lo = Vector((min(c.x for c in coords), min(c.y for c in coords), min(c.z for c in coords)))
    hi = Vector((max(c.x for c in coords), max(c.y for c in coords), max(c.z for c in coords)))
    centre = (lo + hi) * 0.5
    span = max(hi.x - lo.x, hi.y - lo.y, hi.z - lo.z, 0.1)
    report["bounds"] = {
        "min": [round(v, 4) for v in lo],
        "max": [round(v, 4) for v in hi],
        "size": [round(hi[i] - lo[i], 4) for i in range(3)],
    }

    for location, energy, size in (((2.5, -3.0, 3.0), 700.0, 3.0),
                                   ((-3.0, -2.0, 1.6), 220.0, 4.0),
                                   ((0.0, 3.5, 2.6), 320.0, 3.0)):
        data = bpy.data.lights.new("l", type="AREA")
        data.energy = energy
        data.size = size
        light = bpy.data.objects.new("l", data)
        light.location = Vector(location) + Vector(centre)
        light.rotation_euler = (Vector(centre) - light.location).to_track_quat("-Z", "Y").to_euler()
        bpy.context.collection.objects.link(light)

    cam_data = bpy.data.cameras.new("cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = span * 1.35
    camera = bpy.data.objects.new("cam", cam_data)
    bpy.context.collection.objects.link(camera)
    scene.camera = camera
    distance = span * 3.0

    for view, azimuth in (("front", 0.0), ("side", 90.0), ("threequarter", 35.0)):
        angle = math.radians(azimuth)
        camera.location = Vector(centre) + Vector(
            (math.sin(angle) * distance, -math.cos(angle) * distance, 0.0))
        camera.rotation_euler = (Vector(centre) - camera.location).to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = str(out_dir / f"{report['clip_name']}_{view}.png")
        bpy.ops.render.render(write_still=True)
    report["rendered"] = [f"{report['clip_name']}_{v}.png"
                          for v in ("front", "side", "threequarter")]


def main() -> int:
    args = parse_args()
    repo = Path(__file__).resolve().parents[2]
    base = Path(args.base)
    if not base.is_absolute():
        base = repo / base
    out_iteration = Path(args.out_iteration)
    if not out_iteration.is_absolute():
        out_iteration = repo / out_iteration

    # Prefer the idle clip as the rest pose the authored pose departs from; an arbitrary
    # alphabetical match would silently use e.g. the flight clip, already deformed.
    candidates = sorted(base.glob("clip_idle_slot2.fbx")) or sorted(base.glob("clip_*_slot2.fbx"))
    source = candidates[0] if candidates else None
    if source is None:
        print(f"FAIL: no clip_*_slot2.fbx under {base}", file=sys.stderr)
        return 2

    report: dict = {
        "asset": "cultivator_tripo_v9",
        "phase": "authored_pose",
        "pose": args.pose,
        "pose_description": POSES[args.pose]["description"],
        "clip_name": args.name,
        "source_rig": source.name,
        "fps": args.fps,
        "frames": args.frames,
        "problems": [],
        "missing_by_design": MISSING_BY_DESIGN,
    }

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=str(source), use_anim=True,
                             automatic_bone_orientation=True)
    armature, mesh = find_rig()
    armature.animation_data_clear()
    # Every action from the source must go, or the export ships the wrong clip alongside.
    for action in list(bpy.data.actions):
        bpy.data.actions.remove(action)

    # The rest floor must be measured before the pose is applied - afterwards the pose's own
    # silhouette has replaced it and the reference is gone.
    rest_lowest = lowest_vertex_z(armature, mesh)
    apply_pose(armature, POSES[args.pose], report)
    align_floor_with_rest(armature, mesh, rest_lowest, report)
    keyframe_breath(armature, POSES[args.pose], args.frames, report)

    out_iteration.mkdir(parents=True, exist_ok=True)
    fbx_out = out_iteration / f"clip_{args.name}_slot2.fbx"
    # Blender 5.2's FBX exporter has no `use_anim` switch; `bake_anim` is the one that
    # decides whether animation is written. Property list confirmed against the operator RNA.
    bpy.ops.export_scene.fbx(
        filepath=str(fbx_out),
        use_selection=False,
        bake_anim=True,
        bake_anim_use_all_actions=False,
        bake_anim_use_all_bones=True,
        bake_anim_use_nla_strips=False,
        bake_anim_force_startend_keying=True,
        add_leaf_bones=False,
    )
    report["output"] = {"file": str(fbx_out), "bytes": fbx_out.stat().st_size}
    print(f"wrote {fbx_out} ({fbx_out.stat().st_size:,} bytes)", flush=True)

    if args.render:
        render_dir = Path(args.render)
        if not render_dir.is_absolute():
            render_dir = repo / render_dir
        render_dir.mkdir(parents=True, exist_ok=True)
        setup_and_render(mesh, render_dir, args.resolution, args.samples, report)
        print(f"renders -> {render_dir}", flush=True)

    report_path = Path(args.report) if args.report else out_iteration / f"{args.name}_report.json"
    if not report_path.is_absolute():
        report_path = repo / report_path
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n")
    print(f"report {report_path}")
    if report["problems"]:
        for problem in report["problems"]:
            print(f"  ! {problem}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
