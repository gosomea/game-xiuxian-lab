"""Closed-form check: can upright legs + flat sole + pelvis-over-ankle be satisfied at all?

Geometry of one leg: hips H, knee K, ankle A. Current: |HK| = thigh, |KA| = shin,
A sits FORWARD of H by s = 0.146 m (rest measurement), leg nearly straight.

Plan: rotate the leg chain about the hips so the ankle moves straight back under the
hips, counter-rotate the foot to flatten the sole, then move the HIPS bone forward by
the horizontal distance the ankle just travelled -- which keeps the feet exactly where
they were on the ground (no re-grounding needed) while putting the pelvis above them.

This script verifies the numbers before any solver is trusted: how many degrees the
thigh must rotate for a given forward shear, and where the ankle/toe end up.
"""
import math
import sys

import bpy
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
glb = argv[0]

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=glb)
arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
scene = bpy.context.scene


def pb(name):
    for c in (f"mixamorig:{name}", f"mixamorig_{name}"):
        b = arm.pose.bones.get(c)
        if b:
            return b
    return None


def wp(bone, tip=False):
    m = arm.matrix_world @ bone.matrix
    if tip:
        return (arm.matrix_world @ (bone.matrix @ Vector((0, bone.length, 0))))
    return m.to_translation()


chain = {k: pb(k) for k in ("Hips", "LeftUpLeg", "LeftLeg", "LeftFoot", "LeftToeBase")}
fwd = wp(chain["LeftToeBase"]) - wp(chain["LeftFoot"])
fwd.z = 0
fwd.normalize()

H = wp(chain["Hips"])
A = wp(chain["LeftFoot"])
T = wp(chain["LeftToeBase"])

shear = (A - H).project(fwd).length
thigh = (wp(chain["LeftUpLeg"], tip=True) - H).length
shin = (A - wp(chain["LeftUpLeg"], tip=True)).length

print(f"CHECK shear={shear:.4f}m thigh={thigh:.4f} shin={shin:.4f}")
# Leg is nearly straight: small-angle relation, ankle travels ~ (thigh+shin)*sin(theta).
theta = math.degrees(math.asin(min(shear / (thigh + shin), 1.0)))
print(f"CHECK thigh rotation to bring ankle under hips: {theta:.2f} deg")
# Ankle drop when straightening (cos vs 1): the foot rises, which the ground-offset pass
# re-absorbs; report the magnitude so we know whether re-grounding matters.
drop = (thigh + shin) * (1 - math.cos(math.radians(theta)))
print(f"CHECK ankle rise from straightening: {drop:.4f} m (re-grounding must absorb)")
# Foot counter-rotation: sole pitch now, and what the flat target implies.
ankle = wp(chain["LeftFoot"])
toe = wp(chain["LeftToeBase"])
pitch = math.degrees(math.atan2(ankle.z - toe.z, max((toe - ankle).dot(fwd), 1e-6)))
print(f"CHECK sole pitch now: {pitch:+.2f} deg -> foot must counter-rotate ~{-pitch:+.2f} deg")
# After both rotations the toe must still point forward, not up.
print("CHECK plan: rotate thigh+shin+foot chain by -theta about hips local X, "
      "then rotate foot alone by +pitch about its own X, then shift Hips forward by `shear`.")
