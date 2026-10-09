"""Probe leg geometry: is the shear a straight slanted leg or a bent knee?

Decides the correction strategy:
  * straight leg sloping forward -> one constant UpLeg rotation + Foot counter-rotation
    keeps the leg straight, just vertical;
  * bent knee                    -> a single UpLeg rotation would change the bend, so a
    2-bone solve is needed instead.

Also probes which LOCAL axis of UpLeg / Foot rotates the ankle along the character's
forward axis and the sole pitch (Mixamo local axes are convention, not anatomy -- same
lesson as cultivator_lean_fix's spine probe).
"""
import math
import sys

import bpy
from mathutils import Vector, Quaternion

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
glb = argv[0] if argv else "src/game/actors/swordsman/models/cultivator_tripo_v9.glb"
CLIP = argv[1] if len(argv) > 1 else "idle_guarded"

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=glb)

arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
scene = bpy.context.scene


def pb(name):
    for candidate in (f"mixamorig:{name}", f"mixamorig_{name}"):
        b = arm.pose.bones.get(candidate)
        if b:
            return b
    return None


def world_of(bone, tip=False):
    m = arm.matrix_world @ bone.matrix
    v = m.to_translation()
    if tip:
        v = (arm.matrix_world @ (bone.matrix @ Vector((0, bone.length, 0)))).normalized() * 0
        v = arm.matrix_world @ (bone.matrix @ Vector((0, bone.length, 0)))
    return Vector(v)


fwd = world_of(pb("LeftToeBase")) - world_of(pb("LeftFoot"))
fwd.z = 0
fwd.normalize()

if arm.animation_data is None:
    arm.animation_data_create()
action = bpy.data.actions[CLIP]
arm.animation_data.action = action
f0, f1 = (int(round(v)) for v in action.frame_range)
frame = f0 + (f1 - f0) // 2
scene.frame_set(frame)
bpy.context.view_layer.update()

hips = pb("Hips")
lknee = pb("LeftLeg")
lankle = pb("LeftFoot")
ltoe = pb("LeftToeBase")
rknee = pb("RightLeg")
rankle = pb("RightFoot")

H = world_of(hips)
K = world_of(lknee)
A = world_of(lankle)
T = world_of(ltoe)
A2 = world_of(rankle)

print(f"PROBE2 clip={CLIP} frame={frame}")
d = A - H
print(f"PROBE2 hips->ankle L: horiz={math.hypot(d.x, d.y):+.4f} vert={d.z:+.4f} "
      f"angle_from_vertical={math.degrees(math.atan2(d.dot(fwd), d.z)):+.2f} deg")
d2 = A2 - H
print(f"PROBE2 hips->ankle R: horiz={math.hypot(d2.x, d2.y):+.4f} vert={d2.z:+.4f} "
      f"angle={math.degrees(math.atan2(d2.dot(fwd), d2.z)):+.2f} deg")

# Straightness: compare knee position with the hips->ankle midpoint.
mid = (H + A) / 2
knee_dev = (K - mid) - (K - mid).project((A - H).normalized())
print(f"PROBE2 knee deviation from hips-ankle line: {knee_dev.length:+.4f} m "
      f"(toward forward: {knee_dev.dot(fwd):+.4f})")
thigh = (K - H).length
shin = (A - K).length
print(f"PROBE2 thigh={thigh:.4f} shin={shin:.4f} "
      f"sum={thigh + shin:.4f} direct={ (A-H).length:.4f} "
      f"bend_gap={(thigh + shin) - (A - H).length:.4f}")

# Sole flatness reference: ankle height minus toe height.
print(f"PROBE2 sole: ankle_z={A.z:+.4f} toe_z={T.z:+.4f} pitch="
      f"{math.degrees(math.atan2(A.z - T.z, (T - A).dot(fwd))):+.2f} deg")


def probe_axis(pose_bone, metric_fn, probe_deg=6.0):
    """Which local axis of this bone most strongly changes the metric (deg/deg)."""
    saved = {}
    for b in (pose_bone, hips, lknee, lankle, rknee, rankle):
        if b:
            if b.rotation_mode != "QUATERNION":
                b.rotation_mode = "QUATERNION"
            saved[b.name] = b.rotation_quaternion.copy()
    saved_action = arm.animation_data.action
    arm.animation_data.action = None
    bpy.context.view_layer.update()
    base = metric_fn()
    out = {}
    for axis_index in range(3):
        axis = Vector((0.0, 0.0, 0.0))
        axis[axis_index] = 1.0
        pose_bone.rotation_quaternion = (
            saved[pose_bone.name] @ Quaternion(axis, math.radians(probe_deg)))
        bpy.context.view_layer.update()
        out[("XYZ"[axis_index])] = (metric_fn() - base) / probe_deg
        pose_bone.rotation_quaternion = saved[pose_bone.name]
        bpy.context.view_layer.update()
    arm.animation_data.action = saved_action
    bpy.context.view_layer.update()
    return out


def offset_metric():
    a = (world_of(lankle) + world_of(rankle)) / 2
    d = world_of(hips) - a
    d.z = 0
    return d.dot(fwd)


def sole_metric():
    a = world_of(lankle)
    t = world_of(ltoe)
    return math.degrees(math.atan2(a.z - t.z, max((t - a).dot(fwd), 1e-6)))


for bone_name, metric, label in (
        ("LeftUpLeg", offset_metric, "ankle offset (m per deg)"),
        ("LeftFoot", sole_metric, "sole pitch (deg per deg)"),
):
    bone = pb(bone_name)
    was_quat = bone.rotation_mode
    bone.rotation_mode = "QUATERNION"
    responses = probe_axis(bone, metric)
    bone.rotation_mode = was_quat
    print(f"PROBE2 {bone_name} -> {label}: "
          + ", ".join(f"{k}={v:+.4f}" for k, v in responses.items()))
