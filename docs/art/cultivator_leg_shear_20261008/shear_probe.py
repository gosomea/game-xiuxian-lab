"""Probe: is the whole-body shear in the animation clips or in the armature rest pose?

The pelvis sits ~0.154 m horizontally off the feet in every clip (measure_glb_balance),
while the torso above it is upright. Two possible sources demand different fixes:

  * rest pose (edit-bone positions) already slanted  -> the bind is wrong; clips are
    "correct" relative to it and any per-clip bake fights the bind;
  * rest pose upright, clips slanted                 -> the clips carry the shear and a
    per-clip correction (like cultivator_lean_fix) is the right place.

This prints, per clip, the signed horizontal offset of the Hips joint from the ankle
midpoint, projected on the character's own forward axis (measured from ankle->toe, not
assumed), plus the same quantity for the REST pose.
"""
import sys
from pathlib import Path

import bpy
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
glb = argv[0] if argv else "src/game/actors/swordsman/models/cultivator_tripo_v9.glb"

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=glb)

arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
mesh = next(o for o in bpy.data.objects if o.type == "MESH"
            and any(m.type == "ARMATURE" for m in o.modifiers))
scene = bpy.context.scene


def bone(name):
    b = arm.pose.bones.get(name)
    return b


def world(pose_bone, tip=False):
    m = arm.matrix_world @ pose_bone.matrix
    v = m.to_translation()
    if tip:
        v = arm.matrix_world @ (pose_bone.matrix @ Vector((0, pose_bone.length, 0)))
    return Vector((v.x, v.y, v.z))


names = {
    "hips": next(n for n in ("mixamorig:Hips", "mixamorig_Hips") if bone(n)),
    "lfoot": next(n for n in ("mixamorig:LeftFoot", "mixamorig_LeftFoot") if bone(n)),
    "rfoot": next(n for n in ("mixamorig:RightFoot", "mixamorig_RightFoot") if bone(n)),
    "ltoe": next(n for n in ("mixamorig:LeftToeBase", "mixamorig_LeftToeBase") if bone(n)),
    "rtoe": next(n for n in ("mixamorig:RightToeBase", "mixamorig_RightToeBase") if bone(n)),
}

# Character forward = ankle -> toe direction (horizontal), averaged over both feet.
lw = world(bone(names["ltoe"]))
lfa = world(bone(names["lfoot"]))
fwd = (lw - lfa)
fwd.z = 0
fwd.normalize()
print(f"PROBE forward axis (ankle->toe): ({fwd.x:+.3f}, {fwd.y:+.3f})")

print("\nPROBE rest-pose (edit bones, world):")
for eb in arm.data.bones:
    if eb.name in (names["hips"], names["lfoot"], names["rfoot"], names["ltoe"], names["rtoe"]):
        p = arm.matrix_world @ eb.head_local
        print(f"  {eb.name:24s} head=({p.x:+.4f}, {p.y:+.4f}, {p.z:+.4f})")

hips_b = bone(names["hips"])
lfoot_b = bone(names["lfoot"])
rfoot_b = bone(names["rfoot"])


def offset(pose):
    h = world(hips_b)
    a = (world(lfoot_b) + world(rfoot_b)) / 2
    d = h - a
    d.z = 0
    return d.dot(fwd), Vector((d.x, d.y, 0)).length


print("\nPROBE per-clip signed offset (positive = pelvis toward facing direction):")
print(f"  {'clip':<14}{'mean_m':>9}{'min_m':>9}{'max_m':>9}{'frames':>8}")
if arm.animation_data is None:
    arm.animation_data_create()
for action in sorted(bpy.data.actions, key=lambda a: a.name):
    arm.animation_data.action = action
    f0, f1 = (int(round(v)) for v in action.frame_range)
    vals = []
    for f in range(f0, f1 + 1):
        scene.frame_set(f)
        bpy.context.view_layer.update()
        vals.append(offset(action)[0])
    print(f"  {action.name:<14}{sum(vals)/len(vals):>+9.4f}{min(vals):>+9.4f}"
          f"{max(vals):>+9.4f}{len(vals):>8}")

print("\nPROBE leg chain rest lengths (edit bones):")
for side in ("Left", "Right"):
    up = arm.data.bones.get(f"mixamorig:{side}UpLeg") or arm.data.bones.get(f"mixamorig_{side}UpLeg")
    leg = arm.data.bones.get(f"mixamorig:{side}Leg") or arm.data.bones.get(f"mixamorig_{side}Leg")
    foot = arm.data.bones.get(f"mixamorig:{side}Foot") or arm.data.bones.get(f"mixamorig_{side}Foot")
    if up and leg and foot:
        print(f"  {side}: UpLeg={up.length:.4f} Leg={leg.length:.4f} Foot={foot.length:.4f}")
