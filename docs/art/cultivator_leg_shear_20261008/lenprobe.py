import bpy
import math
import pathlib
from mathutils import Vector

LINES = []


def P(msg):
    LINES.append(msg)


bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath="tmp_probe/work.glb")
arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")


def pb(n):
    for c in (f"mixamorig:{n}", f"mixamorig_{n}"):
        b = arm.pose.bones.get(c)
        if b:
            return b
    return None


up = pb("LeftUpLeg")
head = (arm.matrix_world @ up.matrix).to_translation()
tip = arm.matrix_world @ (up.matrix @ Vector((0, up.length, 0)))
P(f"LENPROBE up.length = {up.length:.4f}")
P(f"LENPROBE head {tuple(round(v, 4) for v in head)}")
P(f"LENPROBE tip  {tuple(round(v, 4) for v in tip)}")

knee = pb("LeftLeg")
khead = (arm.matrix_world @ knee.matrix).to_translation()
P(f"LENPROBE thigh hip->knee = {(khead - head).length:.4f}")

ank = pb("LeftFoot")
ahead = (arm.matrix_world @ ank.matrix).to_translation()
P(f"LENPROBE shin knee->ankle = {(ahead - khead).length:.4f}")

P(f"LENPROBE asin(0.1609/0.8372) deg = {math.degrees(math.asin(0.1609 / 0.8372)):.3f}")

# What does rotating LeftUpLeg about local X by 12 deg actually DO to the ankle?
if up.rotation_mode != "QUATERNION":
    up.rotation_mode = "QUATERNION"
saved = up.rotation_quaternion.copy()
from mathutils import Quaternion  # noqa: E402

scene = bpy.context.scene
base = ahead.copy()
for deg in (6.0, 12.0):
    up.rotation_quaternion = saved @ Quaternion(Vector((1, 0, 0)), math.radians(deg))
    bpy.context.view_layer.update()
    new = (arm.matrix_world @ ank.matrix).to_translation()
    P(f"LENPROBE after {deg:+.0f} deg X: ankle moves {(new - base).length * 1000:.1f} mm, "
      f"delta=({new.x - base.x:+.4f}, {new.y - base.y:+.4f}, {new.z - base.z:+.4f})")
up.rotation_quaternion = saved

pathlib.Path("tmp_probe/lenprobe.out").write_text("\n".join(LINES))
