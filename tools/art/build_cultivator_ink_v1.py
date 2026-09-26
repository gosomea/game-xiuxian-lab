#!/usr/bin/env python3
"""Build the first ink-line cultivator from geometry and keyframes authored here.

This deliberately does not load the former Tripo/MIA mesh, rig, actions, or textures.
Run with Blender 5.2: blender -b --factory-startup --python this_file.py
"""

from __future__ import annotations

import json
import math
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[2]
ART = ROOT / "docs/art/cultivator_ink_v1"
OUT = ROOT / "src/game/actors/swordsman/models/cultivator_ink_v1.glb"
FPS = 30
INK = (0.035, 0.049, 0.054, 1)
HAIR = (0.053, 0.061, 0.069, 1)
ROBE = (0.76, 0.77, 0.735, 1)
ROBE_SHADE = (0.60, 0.65, 0.64, 1)
INNER = (0.90, 0.865, 0.79, 1)
ACCENT = (0.18, 0.33, 0.34, 1)
SKIN = (0.83, 0.72, 0.62, 1)
BOOT = (0.12, 0.145, 0.15, 1)

ARM = None
MESHES = []
BOOT_MESHES = []


def material(name, rgba):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = rgba
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = rgba
    bsdf.inputs["Roughness"].default_value = 0.96
    bsdf.inputs["Metallic"].default_value = 0.0
    return mat


def skin(obj, bone, mat, boot=False):
    obj.data.materials.append(mat)
    group = obj.vertex_groups.new(name=bone)
    group.add(list(range(len(obj.data.vertices))), 1.0, "REPLACE")
    mod = obj.modifiers.new("InkRig", "ARMATURE")
    mod.object = ARM
    obj.parent = ARM
    MESHES.append(obj)
    if boot:
        BOOT_MESHES.append(obj)
    return obj


def mesh(name, vertices, faces, bone, mat, boot=False):
    data = bpy.data.meshes.new(name)
    data.from_pydata(vertices, [], faces)
    data.update()
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    return skin(obj, bone, mat, boot)


def loft(name, rings, bone, mat, segments=10, boot=False):
    """Rings are (x,y,z,rx,ry); facets intentionally read as drawn planes."""
    vertices = []
    for cx, cy, z, rx, ry in rings:
        for i in range(segments):
            a = 2 * math.pi * i / segments
            vertices.append((cx + rx * math.cos(a), cy + ry * math.sin(a), z))
    faces = [tuple(reversed(range(segments)))]
    for r in range(len(rings) - 1):
        for i in range(segments):
            j = (i + 1) % segments
            faces.append((r * segments + i, r * segments + j,
                          (r + 1) * segments + j, (r + 1) * segments + i))
    faces.append(tuple((len(rings) - 1) * segments + i for i in range(segments)))
    return mesh(name, vertices, faces, bone, mat, boot)


def sphere(name, center, radius, bone, mat, boot=False, segments=12, rings=8):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings,
                                        location=center)
    obj = bpy.context.object
    obj.name = name
    obj.scale = radius
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return skin(obj, bone, mat, boot)


def bar(name, start, end, radius, bone, mat, vertices=8):
    a, b = Vector(start), Vector(end)
    mid = (a + b) / 2
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius,
                                        depth=(b-a).length, location=mid)
    obj = bpy.context.object
    obj.name = name
    obj.rotation_euler = (b-a).to_track_quat("Z", "Y").to_euler()
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return skin(obj, bone, mat)


def armature():
    global ARM
    data = bpy.data.armatures.new("InkCultivatorBones")
    ARM = bpy.data.objects.new("InkCultivatorRig", data)
    bpy.context.collection.objects.link(ARM)
    bpy.context.view_layer.objects.active = ARM
    ARM.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    specs = {
        "Root": ((0, 0, 0), (0, 0, .10), None),
        "Hips": ((0, 0, .91), (0, 0, 1.03), "Root"),
        "Spine": ((0, 0, 1.03), (0, 0, 1.43), "Hips"),
        "Head": ((0, 0, 1.43), (0, 0, 1.73), "Spine"),
        "Hair": ((0, .10, 1.70), (0, .13, 1.18), "Head"),
        "Skirt": ((0, 0, .99), (0, 0, .55), "Hips"),
    }
    for side, sign in (("L", -1), ("R", 1)):
        specs.update({
            f"Thigh{side}": ((sign*.115, 0, .89), (sign*.125, 0, .51), "Hips"),
            f"Shin{side}": ((sign*.125, 0, .51), (sign*.125, 0, .12), f"Thigh{side}"),
            f"Foot{side}": ((sign*.125, 0, .12), (sign*.125, -.17, .08), f"Shin{side}"),
            f"Arm{side}": ((sign*.255, 0, 1.39), (sign*.39, 0, 1.10), "Spine"),
            f"Forearm{side}": ((sign*.39, 0, 1.10), (sign*.42, -.02, .91), f"Arm{side}"),
        })
    for name, (head, tail, _) in specs.items():
        bone = data.edit_bones.new(name)
        bone.head, bone.tail = head, tail
    for name, (_, _, parent) in specs.items():
        if parent:
            data.edit_bones[name].parent = data.edit_bones[parent]
    bpy.ops.object.mode_set(mode="OBJECT")
    for bone in ARM.pose.bones:
        bone.rotation_mode = "XYZ"
    return specs


def body(mats):
    # Layered garment: pale silhouette, graphite hems, one restrained blue-green sash.
    loft("RobeTorso", [(0,0,1.00,.18,.12),(0,0,1.32,.23,.145),
                       (0,0,1.43,.25,.135)], "Spine", mats["robe"])
    loft("InnerCollar", [(0,-.112,1.26,.10,.031),(0,-.115,1.43,.075,.025)],
         "Spine", mats["inner"], 8)
    bar("LeftCollarInk", (-.14,-.143,1.42),(.005,-.151,1.23),.009,
        "Spine", mats["ink"], 6)
    bar("RightCollarInk", (.13,-.141,1.42),(-.007,-.155,1.26),.009,
        "Spine", mats["ink"], 6)
    loft("Sash", [(0,0,.98,.20,.148),(0,0,1.065,.205,.15)],
         "Hips", mats["accent"], 12)
    loft("SashInkTop", [(0,0,1.062,.207,.152),(0,0,1.074,.207,.152)],
         "Hips", mats["ink"], 12)
    loft("RobeSkirt", [(0,0,.48,.32,.255),(0,0,.60,.30,.23),
                       (0,0,.98,.185,.145)], "Skirt", mats["robe_shade"], 12)
    loft("SkirtInkHem", [(0,0,.472,.323,.258),(0,0,.493,.323,.258)],
         "Skirt", mats["ink"], 12)
    # Front ink seam and light overlapping panel retain readable hanfu structure.
    mesh("FrontPanel", [(-.13,-.16,.96),(.06,-.16,.96),(.16,-.257,.50),
                        (-.21,-.257,.50)], [(0,1,2,3)], "Skirt", mats["inner"])
    bar("FrontPanelEdge", (-.21,-.259,.50),(-.13,-.162,.96),.008,
        "Skirt", mats["ink"], 6)
    for side, s in (("L",-1),("R",1)):
        loft(f"UpperSleeve{side}", [(s*.40,0,1.095,.11,.095),
              (s*.32,0,1.31,.13,.12),(s*.255,0,1.40,.095,.095)],
             f"Arm{side}", mats["robe"])
        loft(f"Cuff{side}", [(s*.42,-.025,.89,.103,.083),
              (s*.40,0,1.105,.10,.09)], f"Forearm{side}", mats["robe_shade"])
        loft(f"CuffInk{side}", [(s*.42,-.025,.885,.104,.084),
              (s*.42,-.025,.905,.104,.084)], f"Forearm{side}", mats["ink"])
        sphere(f"Hand{side}", (s*.42,-.043,.855), (.052,.038,.095),
               f"Forearm{side}", mats["skin"])
        loft(f"Trouser{side}", [(s*.125,.005,.10,.075,.067),
              (s*.125,.005,.53,.085,.075)], f"Shin{side}", mats["boot"])
        sphere(f"Shoe{side}", (s*.125,-.067,.067), (.092,.185,.065),
               f"Foot{side}", mats["boot"], True)
        bar(f"ShoeInkLine{side}", (s*.21,-.12,.065),(s*.05,-.12,.065),.008,
            f"Foot{side}", mats["ink"], 6)
    # Face and hair: simple planes and silhouette rather than high-frequency skin detail.
    sphere("Face", (0,-.023,1.555), (.115,.105,.157), "Head", mats["skin"])
    sphere("HairCap", (0,.024,1.655), (.12,.105,.098), "Head", mats["hair"])
    sphere("HairKnot", (0,.065,1.762), (.078,.077,.058), "Head", mats["hair"])
    sphere("HairBack", (0,.102,1.39), (.116,.053,.285), "Hair", mats["hair"])
    for side,s in (("L",-1),("R",1)):
        sphere(f"HairSide{side}", (s*.107,-.038,1.54), (.025,.055,.145),
               "Head", mats["hair"])
        bar(f"Brow{side}", (s*.034,-.126,1.578),(s*.077,-.114,1.582),.006,
            "Head", mats["ink"], 6)
        sphere(f"Eye{side}", (s*.052,-.128,1.563), (.008,.004,.006),
               "Head", mats["ink"], segments=8, rings=4)
    bar("HairRibbon", (0,.135,1.70),(0,.145,1.35),.012,
        "Hair", mats["accent"], 6)


def pose_key(frame, values):
    bpy.context.scene.frame_set(frame)
    for bone in ARM.pose.bones:
        bone.rotation_euler = (0, 0, 0)
        bone.location = (0, 0, 0)
    for name, value in values.items():
        bone = ARM.pose.bones[name]
        if isinstance(value, tuple):
            bone.rotation_euler = tuple(math.radians(x) for x in value)
        else:
            bone.rotation_euler.x = math.radians(value)
    for bone in ARM.pose.bones:
        bone.keyframe_insert(data_path="rotation_euler", frame=frame)
        bone.keyframe_insert(data_path="location", frame=frame)


def floor_height():
    bpy.context.view_layer.update()
    deps = bpy.context.evaluated_depsgraph_get()
    low = 1e9
    for obj in BOOT_MESHES:
        evaluated = obj.evaluated_get(deps)
        data = evaluated.to_mesh()
        try:
            low = min(low, min((obj.matrix_world @ v.co).z for v in data.vertices))
        finally:
            evaluated.to_mesh_clear()
    return low


def make_action(name, duration, poses, floor=True):
    action = bpy.data.actions.new(name)
    action.use_fake_user = True
    ARM.animation_data.action = action
    total = round(duration * FPS)
    for fraction, values in poses:
        pose_key(1 + round(fraction * total), values)
    if floor:
        # Root translation is authored per frame from actual deformed boot vertices.
        # This is not a single clip-wide minimum, which failed on the former asset.
        root = ARM.pose.bones["Root"]
        for frame in range(1, total + 2):
            bpy.context.scene.frame_set(frame)
            root.location.z = -floor_height()
            root.keyframe_insert(data_path="location", frame=frame)
    action.name = name
    return action


def actions():
    # Axes are intentionally modest: the silhouette should move quietly in the world.
    neutral = {"ArmL": (1,0,-5), "ArmR": (1,0,5),
               "ForearmL": (-6,0,0), "ForearmR": (-6,0,0)}
    make_action("idle", 2.4, [(0, neutral), (.5,{**neutral,"Spine":(1,0,0),
        "Hair":(-2,0,0)}),(1,neutral)])
    guard = {**neutral,"ArmL":(-7,0,-8),"ArmR":(-7,0,8),
             "ForearmL":(-15,0,0),"ForearmR":(-15,0,0)}
    make_action("idle_guarded", 2.4, [(0,guard),(.5,{**guard,"Spine":(1,0,0),
        "Skirt":(1,0,0),"Hair":(-3,0,0)}),(1,guard)])
    def gait(amp, bend, arm, bob):
        return [(0,{**neutral,"ThighL":amp,"ThighR":-amp,
                    "ShinL":bend,"ArmL":-arm,"ArmR":arm,"Skirt":2}),
                (.25,{**neutral,"ThighL":0,"ThighR":0,
                      "ShinL":bend*.4,"ShinR":bend*.4,"Spine":bob,
                      "Hair":-bob}),
                (.5,{**neutral,"ThighL":-amp,"ThighR":amp,
                     "ShinR":bend,"ArmL":arm,"ArmR":-arm,"Skirt":-2}),
                (.75,{**neutral,"ThighL":0,"ThighR":0,
                      "ShinL":bend*.4,"ShinR":bend*.4,"Spine":bob,
                      "Hair":-bob}),
                (1,{**neutral,"ThighL":amp,"ThighR":-amp,
                    "ShinL":bend,"ArmL":-arm,"ArmR":arm,"Skirt":2})]
    make_action("walk", .93, gait(18, 9, 7, 1.5))
    make_action("run", .72, gait(25, 18, 12, 3))
    make_action("jump", 1.05, [(0,{**neutral,"ThighL":5,"ThighR":5,
                                 "ShinL":-9,"ShinR":-9}),
        (.22,{**neutral,"ThighL":-10,"ThighR":-10,"ShinL":17,"ShinR":17,
              "ArmL":(-16,0,-10),"ArmR":(-16,0,10),"Skirt":-4}),
        (.55,{**neutral,"ThighL":-14,"ThighR":-10,"ShinL":22,"ShinR":20,
              "ArmL":(-14,0,-10),"ArmR":(-14,0,10),"Hair":-7}),
        (1,{**neutral,"ThighL":5,"ThighR":5,"ShinL":-9,"ShinR":-9,
             "ArmL":(-10,0,-8),"ArmR":(-10,0,8)})], floor=False)
    ride = {**guard,"ThighL":3,"ThighR":3,"ShinL":-4,"ShinR":-4,
            "Spine":(2,0,0)}
    make_action("sword_ride", 2.4, [(0,ride),(.5,{**ride,"Hair":-5,
        "Skirt":-3,"Spine":(3,0,0)}),(1,ride)])
    sit = {**neutral,"ThighL":(65,0,-25),"ThighR":(65,0,25),
           "ShinL":(-100,0,0),"ShinR":(-100,0,0),
           "ArmL":(20,0,-15),"ArmR":(20,0,15),"Spine":(2,0,0)}
    make_action("meditate", 2.4, [(0,sit),(.5,{**sit,"Spine":(3,0,0),
        "Hair":-2}),(1,sit)])


def save_and_export():
    ART.mkdir(parents=True, exist_ok=True)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    bpy.context.scene.frame_set(1)
    ARM.animation_data.action = bpy.data.actions["idle_guarded"]
    bpy.ops.wm.save_as_mainfile(filepath=str(ART / "cultivator_ink_v1.blend"))
    bpy.ops.export_scene.gltf(filepath=str(OUT), export_format="GLB",
        export_animation_mode="ACTIONS", export_animations=True,
        export_skins=True, export_yup=True, export_apply=False,
        export_normals=True, export_materials="EXPORT",
        export_frame_range=False, export_force_sampling=True,
        export_bake_animation=False, use_selection=False, use_visible=True)
    report = {"source": "tools/art/build_cultivator_ink_v1.py",
        "mesh_objects": len(MESHES),
        "triangles": sum(len(p.vertices)-2 for o in MESHES for p in o.data.polygons),
        "bones": len(ARM.data.bones),
        "clips": {a.name: [round(x,2) for x in a.frame_range] for a in bpy.data.actions},
        "rest_foot_height_m": round(floor_height(),4)}
    (ART / "build_manifest.json").write_text(json.dumps(report,indent=2)+"\n")
    print(json.dumps(report, indent=2))


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.fps = FPS
    specs = armature()
    mats = {name:material(name,rgba) for name,rgba in {
        "ink":INK,"hair":HAIR,"robe":ROBE,"robe_shade":ROBE_SHADE,
        "inner":INNER,"accent":ACCENT,"skin":SKIN,"boot":BOOT}.items()}
    body(mats)
    ARM.animation_data_create()
    actions()
    save_and_export()


if __name__ == "__main__":
    main()
