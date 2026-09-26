#!/usr/bin/env python3
"""Build a new paper-and-ink cultivator from an empty Blender scene.

This deliberately does not load any former character mesh, rig, action, or texture.
Run with Blender 5.2: blender -b --factory-startup --python this_file.py
"""

from __future__ import annotations

import json
import math
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[2]
ART = ROOT / "docs/art/cultivator_paper_v1"
OUT = ROOT / "src/game/actors/swordsman/models/cultivator_paper_v1.glb"
FPS = 30
INK = (0.075, 0.092, 0.094, 1)
HAIR = (0.055, 0.071, 0.078, 1)
ROBE = (0.74, 0.79, 0.75, 1)
ROBE_SHADE = (0.57, 0.69, 0.68, 1)
INNER = (0.93, 0.89, 0.79, 1)
ACCENT = (0.28, 0.49, 0.49, 1)
SKIN = (0.89, 0.76, 0.66, 1)
BOOT = (0.16, 0.19, 0.19, 1)

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
    for polygon in obj.data.polygons:
        polygon.use_smooth = True
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
            f"Arm{side}": ((sign*.225, 0, 1.39), (sign*.33, 0, 1.11), "Spine"),
            f"Forearm{side}": ((sign*.33, 0, 1.11), (sign*.365, -.02, .90), f"Arm{side}"),
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
    # One soft, narrow silhouette: overlapping cloth panels carry the black brush lines.
    loft("inner_tunic", [(0,0,.87,.16,.11),(0,0,1.13,.16,.12),
        (0,0,1.34,.195,.135),(0,0,1.42,.175,.115)], "Spine", mats["inner"], 24)
    loft("outer_jacket", [(0,.018,1.01,.17,.125),(0,.018,1.19,.188,.14),
        (0,.018,1.36,.22,.13),(0,.018,1.42,.18,.11)], "Spine", mats["robe"], 24)
    loft("lower_robe", [(0,.01,.37,.29,.23),(0,0,.45,.29,.22),
        (0,0,.65,.25,.195),(0,0,.94,.17,.12)], "Skirt", mats["robe"], 28)
    loft("hem_ink", [(0,.01,.367,.292,.232),(0,.01,.388,.292,.232)],
        "Skirt", mats["ink"], 28)
    # Three asymmetrical paper panels, each with a drawn seam and a soft folded edge.
    for name, s, color in (("left",-1,"inner"),("right",1,"robe_shade")):
        vertices=[(s*.015,-.128,.97),(s*.135,-.105,.96),
            (s*.215,-.193,.46),(s*.135,-.24,.39),(s*.025,-.247,.42)]
        mesh(name+"_front_panel",vertices,[(0,1,2,3,4)],"Skirt",mats[color])
        bar(name+"_ink_seam",vertices[0],vertices[4],.0045,
            "Skirt",mats["ink"],8)
        bar(name+"_fold",vertices[1],vertices[2],.004,
            "Skirt",mats["ink"],8)
    loft("waist_sash",[(0,0,.95,.172,.128),(0,0,1.03,.179,.133)],
        "Hips",mats["accent"],24)
    loft("sash_lower_ink",[(0,0,.946,.174,.13),(0,0,.952,.174,.13)],
        "Hips",mats["ink"],24)
    for s,name in ((-1,"left"),(1,"right")):
        # Crossed lapels are narrow tapered cloth, not a painted V on a cylinder.
        lapel=[(s*.105,-.116,1.425),(s*.16,-.129,1.407),
            (s*.015,-.151,1.126),(-s*.025,-.147,1.145)]
        mesh(name+"_lapel",lapel,[(0,1,2,3)],"Spine",mats["inner"])
        bar(name+"_lapel_brush",lapel[1],lapel[2],.005,
            "Spine",mats["ink"],8)
        # Loose hanfu sleeves taper at shoulder and flare into a curved cuff.
        loft(name+"_upper_sleeve",[(s*.325,0,1.08,.083,.09),
            (s*.31,0,1.19,.10,.12),(s*.27,0,1.32,.102,.11),
            (s*.225,0,1.40,.072,.075)],f"Arm{'L' if s<0 else 'R'}",
            mats["robe_shade"],18)
        loft(name+"_flowing_cuff",[(s*.37,-.02,.88,.113,.112),
            (s*.36,-.01,.95,.115,.106),(s*.34,0,1.12,.084,.087)],
            f"Forearm{'L' if s<0 else 'R'}",mats["robe"],18)
        loft(name+"_cuff_brush",[(s*.37,-.02,.875,.114,.113),
            (s*.37,-.02,.886,.114,.113)],
            f"Forearm{'L' if s<0 else 'R'}",mats["ink"],18)
        sphere(name+"_hand",(s*.365,-.055,.845),(.035,.034,.075),
            f"Forearm{'L' if s<0 else 'R'}",mats["skin"],20,12)
        loft(name+"_trouser",[(s*.125,0,.11,.058,.058),
            (s*.125,0,.40,.068,.062),(s*.12,0,.52,.075,.066)],
            f"Shin{'L' if s<0 else 'R'}",mats["boot"],16)
        loft(name+"_boot_shaft",[(s*.125,0,.055,.07,.075),
            (s*.125,0,.13,.065,.064),(s*.125,0,.29,.072,.065)],
            f"Foot{'L' if s<0 else 'R'}",mats["boot"],18,True)
        sphere(name+"_shoe",(s*.125,-.065,.052),(.079,.145,.045),
            f"Foot{'L' if s<0 else 'R'}",mats["boot"],True,24,14)
        # Thin low sole creates an unambiguous floor contact line.
        loft(name+"_sole",[(s*.125,-.05,.003,.08,.15),
            (s*.125,-.05,.02,.082,.151)],
            f"Foot{'L' if s<0 else 'R'}",mats["ink"],24,True)
    # A sculpted chin and fine brush strokes make the face readable at game scale.
    loft("face",[(0,-.047,1.43,.032,.032),(0,-.045,1.48,.073,.068),
        (0,-.038,1.55,.092,.083),(0,-.034,1.62,.091,.075),
        (0,-.018,1.675,.073,.055)],"Head",mats["skin"],24)
    sphere("nose",(0,-.116,1.541),(.012,.018,.027),"Head",mats["skin"],16,10)
    bar("mouth",(-.019,-.116,1.489),(.019,-.116,1.489),.0018,
        "Head",mats["ink"],6)
    sphere("hair_crown",(0,.022,1.661),(.104,.088,.092),"Head",mats["hair"],24,14)
    sphere("hair_knot",(0,.061,1.749),(.055,.055,.057),"Head",mats["hair"],20,12)
    # Split tapered locks read as painted strokes rather than one solid hair block.
    for i in range(9):
        x=(i-4)*.024
        z=1.29-.11*(i%3==0)
        vertices=[(x-.012,.095,1.67),(x+.012,.095,1.67),
            (x+.016,.108,1.52),(x+.006,.125,z),
            (x-.012,.11,1.51)]
        mesh(f"back_hair_stroke_{i}",vertices,[(0,1,2,3,4)],"Hair",mats["hair"])
    for s,name in ((-1,"left"),(1,"right")):
        mesh(name+"_temple_lock",[(s*.081,-.057,1.66),
            (s*.101,-.044,1.66),(s*.105,-.056,1.48),
            (s*.084,-.066,1.37)],[(0,1,2,3)],"Head",mats["hair"])
        bar(name+"_brow",(s*.025,-.115,1.592),(s*.066,-.111,1.589),
            .0035,"Head",mats["ink"],8)
        bar(name+"_eye",(s*.027,-.121,1.574),(s*.064,-.119,1.574),
            .0028,"Head",mats["ink"],8)
    bar("hairpin",(-.055,.06,1.745),(.055,.06,1.745),.006,
        "Head",mats["accent"],8)


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
    bpy.ops.wm.save_as_mainfile(filepath=str(ART / "cultivator_paper_v1.blend"))
    bpy.ops.export_scene.gltf(filepath=str(OUT), export_format="GLB",
        export_animation_mode="ACTIONS", export_animations=True,
        export_skins=True, export_yup=True, export_apply=False,
        export_normals=True, export_materials="EXPORT",
        export_frame_range=False, export_force_sampling=True,
        export_bake_animation=False, use_selection=False, use_visible=True)
    report = {"source": "tools/art/build_cultivator_paper_v1.py",
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
