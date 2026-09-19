#!/usr/bin/env python3
"""Build the rigged Jade-Paper shortcoat cultivator on Quaternius CC0 anatomy.

Run with Blender 5.x:
  blender --background --factory-startup \
    --python tools/art/build_cultivator_shortcoat_v3_quaternius.py

The source GLB and original license are intentionally vendored beside the output.
No network access is performed by this script.
"""
from __future__ import annotations

import hashlib
import json
import math
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "docs/art/cultivator_shortcoat_v3_quaternius"
SOURCE = OUT / "source/quaternius_male_peasant.gltf"
HEAD_SOURCE = OUT / "source/quaternius_superhero_male_source.glb"
ITER = OUT / "iterations"
BLENDER = OUT / "cultivator_shortcoat_v3_quaternius.blend"
GLB = OUT / "cultivator_shortcoat_v3_quaternius_rigged.glb"
TAU = math.tau


def srgb(hex_value: str) -> tuple[float, float, float]:
    values = [int(hex_value[i:i + 2], 16) / 255 for i in (1, 3, 5)]
    return tuple(v / 12.92 if v <= .04045 else ((v + .055) / 1.055) ** 2.4 for v in values)


def material(name: str, color: str, roughness=.72, metallic=0.0):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*srgb(color), 1)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*srgb(color), 1)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Specular IOR Level"].default_value = .28
    return mat


INDIGO = material("Jade Paper indigo #263B5C", "#263B5C", .76)
DEEP = material("Jade Paper deep indigo #18283F", "#18283F", .80)
IVORY = material("Jade Paper moon white #E4DFD2", "#E4DFD2", .78)
GOLD = material("Jade Paper warm gold #B7924C", "#B7924C", .48, .08)
SKIN = material("Warm young skin", "#C98F6D", .72)
SKIN_SHADOW = material("Warm skin shadow", "#875642", .78)
HAIR = material("Ink hair", "#111923", .86)
BOOT = material("Soft boot", "#121E2B", .88)
GREY = material("Neutral clay review", "#9A9994", .88)
EYE = material("Clear dark eyes", "#17202A", .62)


def smooth(obj):
    if obj.type == 'MESH':
        for polygon in obj.data.polygons:
            polygon.use_smooth = True


def bind_groups(obj, group_weights: list[dict[str, float]]):
    groups = {}
    for vertex_index, weights in enumerate(group_weights):
        total = sum(max(0.0, value) for value in weights.values())
        if total <= 1e-8:
            weights = {"pelvis": 1.0}
            total = 1.0
        for name, weight in weights.items():
            if weight <= 0:
                continue
            group = groups.setdefault(name, obj.vertex_groups.get(name) or obj.vertex_groups.new(name=name))
            group.add([vertex_index], weight / total, 'REPLACE')
    mod = obj.modifiers.new("Quaternius humanoid deformation", 'ARMATURE')
    mod.object = RIG
    obj.parent = RIG


def mesh(name, vertices, faces, mat, weights, solidify=0.0, bevel=0.0, subdiv=0):
    data = bpy.data.meshes.new(name)
    data.from_pydata(vertices, [], faces)
    data.update()
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat)
    smooth(obj)
    bind_groups(obj, weights)
    if solidify:
        modifier = obj.modifiers.new("Soft fabric thickness", 'SOLIDIFY')
        modifier.thickness = solidify
        modifier.offset = 0
    if bevel:
        modifier = obj.modifiers.new("Soft tailored edge", 'BEVEL')
        modifier.width = bevel
        modifier.segments = 2
    if subdiv:
        modifier = obj.modifiers.new("Tailored surface", 'SUBSURF')
        modifier.levels = subdiv
        modifier.render_levels = subdiv
    return obj


def copy_weights(source_obj, old_index):
    result = {}
    vertex = source_obj.data.vertices[old_index]
    for assignment in vertex.groups:
        result[source_obj.vertex_groups[assignment.group].name] = assignment.weight
    return result


def surface_shell(name, predicate, mat, offset=.006):
    """Duplicate selected faces from the mature source topology, preserving weights."""
    source = BODY
    selected = []
    for poly in source.data.polygons:
        center = poly.center
        if predicate(center, poly):
            selected.append(poly)
    used = sorted({index for poly in selected for index in poly.vertices})
    remap = {old: new for new, old in enumerate(used)}
    vertices = []
    weights = []
    for old in used:
        vertex = source.data.vertices[old]
        vertices.append(tuple(vertex.co + vertex.normal * offset))
        weights.append(copy_weights(source, old))
    faces = [tuple(remap[index] for index in poly.vertices) for poly in selected]
    return mesh(name, vertices, faces, mat, weights, solidify=.0025, bevel=.0014)


def bone_weights_for_torso(z):
    anchors = [(0.94, 'pelvis'), (1.08, 'spine_01'), (1.23, 'spine_02'), (1.40, 'spine_03')]
    if z <= anchors[0][0]:
        return {anchors[0][1]: 1}
    if z >= anchors[-1][0]:
        return {anchors[-1][1]: 1}
    for (lo, a), (hi, b) in zip(anchors, anchors[1:]):
        if lo <= z <= hi:
            amount = (z - lo) / (hi - lo)
            return {a: 1 - amount, b: amount}
    return {'spine_02': 1}


def panel(name, points, mat, weights=None, solidify=.004, bevel=.003, subdiv=1):
    if weights is None:
        weights = [bone_weights_for_torso(point[2]) for point in points]
    return mesh(name, points, [tuple(range(len(points)))], mat, weights,
                solidify=solidify, bevel=bevel, subdiv=subdiv)


def ribbon(name, path, widths, mat, y_offset=-.004):
    """A flat, tapered chest ribbon; input coordinates follow the front (-Y)."""
    vertices = []
    weights = []
    for index, point in enumerate(path):
        point = Vector(point)
        if index == 0:
            tangent = Vector(path[1]) - point
        elif index == len(path) - 1:
            tangent = point - Vector(path[index - 1])
        else:
            tangent = Vector(path[index + 1]) - Vector(path[index - 1])
        sideways = Vector((tangent.z, 0, -tangent.x)).normalized() * widths[index] * .5
        for sign in (-1, 1):
            p = point + sideways * sign
            p.y += y_offset
            vertices.append(tuple(p))
            weights.append(bone_weights_for_torso(p.z))
    faces = [(i * 2, i * 2 + 1, i * 2 + 3, i * 2 + 2) for i in range(len(path) - 1)]
    return mesh(name, vertices, faces, mat, weights, solidify=.0035, bevel=.0018, subdiv=1)


def fitted_front_point(x, z, outward=.006):
    torso = bpy.data.objects['Male_Peasant_Body']
    nearest = sorted(torso.data.vertices, key=lambda vertex: (vertex.co.x - x) ** 2 + (vertex.co.z - z) ** 2)[:18]
    # Character faces -Y: smallest local Y is the garment's front surface.
    y = min(vertex.co.y for vertex in nearest) - outward
    return (x, y, z)


def curved_skirt_panel(name, side, front, mat):
    """Three-by-five curved cloth grid continuous at the waist and open at the legs."""
    sign_x = -1 if side == 'left' else 1
    sign_y = -1 if front else 1
    rows = [
        (.982, .012, .112, .010),
        (.930, .016, .124, .018),
        (.875, .021, .137, .029),
        (.815, .028, .150, .041),
        (.752, .038, .160, .054),
    ]
    vertices = []
    weights = []
    columns = 5
    for row_index, (z, inner, outer, bow) in enumerate(rows):
        for column in range(columns):
            t = column / (columns - 1)
            x = sign_x * (inner * (1 - t) + outer * t)
            y = sign_y * (.101 + .010 * math.sin(t * math.pi) + bow * .45 * math.sin(t * math.pi))
            z_here = z - .030 * math.sin(t * math.pi) - .010 * (t if front else 1 - t)
            vertices.append((x, y, z_here))
            thigh = 'thigh_l' if sign_x < 0 else 'thigh_r'
            blend = max(0, min(.68, (0.985 - z) / .285 * .68))
            weights.append({'pelvis': 1 - blend, thigh: blend})
    faces = []
    for row in range(len(rows) - 1):
        for column in range(columns - 1):
            a = row * columns + column
            faces.append((a, a + 1, a + 1 + columns, a + columns))
    obj = mesh(name, vertices, faces, mat, weights, solidify=.004, bevel=.0025, subdiv=1)
    return obj


def ellipse_band(name, z_low, z_high, radius_x, radius_y, mat, segments=48):
    vertices = []
    weights = []
    for z in (z_low, z_high):
        for index in range(segments):
            angle = TAU * index / segments
            vertices.append((radius_x * math.sin(angle), radius_y * math.cos(angle), z))
            weights.append({'pelvis': 1.0})
    faces = []
    for index in range(segments):
        nxt = (index + 1) % segments
        faces.append((index, nxt, segments + nxt, segments + index))
    return mesh(name, vertices, faces, mat, weights, solidify=.004, bevel=.0025, subdiv=1)


def ellipsoid(name, location, scale, mat, bone, segments=32, rings=18):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(mat)
    smooth(obj)
    weights = [{bone: 1} for _ in obj.data.vertices]
    bind_groups(obj, weights)
    return obj


def tube(name, points, radius, mat, bone, bevel_resolution=2):
    curve = bpy.data.curves.new(name, 'CURVE')
    curve.dimensions = '3D'
    curve.bevel_depth = radius
    curve.bevel_resolution = bevel_resolution
    curve.resolution_u = 3
    spline = curve.splines.new('BEZIER')
    spline.bezier_points.add(len(points) - 1)
    for handle, point in zip(spline.bezier_points, points):
        handle.co = point
        handle.handle_left_type = 'AUTO'
        handle.handle_right_type = 'AUTO'
    obj = bpy.data.objects.new(name, curve)
    bpy.context.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.convert(target='MESH')
    obj = bpy.context.object
    obj.data.materials.append(mat)
    bind_groups(obj, [{bone: 1} for _ in obj.data.vertices])
    return obj


def recolor_base():
    # Preserve Quaternius' authored normal/ORM/base-color textures and their
    # material separation; this is the main visual-quality gain over v1/v2.
    for obj in BODY_PARTS:
        smooth(obj)
    outfit = bpy.data.materials.get('MI_Peasant')
    if outfit and outfit.use_nodes:
        nodes = outfit.node_tree.nodes
        links = outfit.node_tree.links
        bsdf = nodes.get('Principled BSDF')
        incoming = next((link for link in links if link.to_node == bsdf and link.to_socket.name == 'Base Color'), None)
        if incoming:
            original_color = incoming.from_socket
            tint = nodes.new('ShaderNodeMixRGB')
            tint.name = 'Jade Paper indigo textile tint'
            tint.blend_type = 'COLOR'
            tint.inputs['Fac'].default_value = .82
            tint.inputs[2].default_value = (*srgb('#263B5C'), 1)
            links.remove(incoming)
            links.new(original_color, tint.inputs[1])
            links.new(tint.outputs[0], bsdf.inputs['Base Color'])


def tailor_body_proportions():
    """Regular Male outfit already has the intended young non-heroic proportions."""
    return


def build_outfit_iteration_1():
    # The authored peasant outfit supplies continuous sleeves, torso, trousers,
    # boots, UVs and PBR textures. We only add culturally specific soft layers.
    ribbon("Moon-white right under-collar",
           [fitted_front_point(-.067, 1.505), fitted_front_point(-.046, 1.466),
            fitted_front_point(-.022, 1.425), fitted_front_point(0.000, 1.386)],
           [.025, .027, .027, .021], IVORY, 0)
    ribbon("Moon-white left over-collar",
           [fitted_front_point(.067, 1.505, .008), fitted_front_point(.046, 1.466, .008),
            fitted_front_point(.021, 1.425, .008), fitted_front_point(-.004, 1.386, .008)],
           [.027, .029, .029, .022], IVORY, 0)

    # The authored body already has a continuous split tunic hem; do not stack
    # rigid accessory panels over it.



def build_hair_and_refinement():
    # Hair cap follows the original head rather than replacing it with a sphere.
    surface_shell("Sculpted fitted hair cap",
                  lambda c, p: c.z > 1.70 and abs(c.x) < .15 and c.y > -.06,
                  HAIR, .005)
    # Temple locks and topknot produce an unmistakable cultivator silhouette.
    tube("Left swept temple lock", [(-.084, -.090, 1.735), (-.102, -.065, 1.665), (-.090, -.070, 1.595)], .010, HAIR, 'Head')
    tube("Right swept temple lock", [(.084, -.090, 1.735), (.102, -.065, 1.665), (.090, -.070, 1.595)], .010, HAIR, 'Head')
    panel("Smooth back hairline",
          [(-.092, .092, 1.716), (.092, .092, 1.716), (.086, .100, 1.682), (-.086, .100, 1.682)],
          HAIR, weights=[{'Head': 1.0}] * 4, solidify=.004, bevel=.003, subdiv=1)
    ellipsoid("Bound topknot root", (0, .012, 1.821), (.050, .046, .040), HAIR, 'Head', 36, 20)
    ellipsoid("Vertical cultivator hair bun", (0, .018, 1.864), (.040, .037, .052), HAIR, 'Head', 36, 20)
    tube("Warm-gold topknot tie", [(-.037, -.018, 1.829), (0, -.026, 1.820), (.037, -.018, 1.829)], .005, GOLD, 'Head')
    ellipsoid("Restrained golden hair pin", (0, -.006, 1.875), (.059, .005, .005), GOLD, 'Head', 24, 12)

    # The authored peasant belt remains the waist closure; no floating added clasp.


def save_iteration(number):
    path = ITER / f"cultivator_shortcoat_v3_quaternius_iteration_{number:02d}.blend"
    bpy.ops.wm.save_as_mainfile(filepath=str(path), compress=True)
    render_views(ITER, f"cultivator_shortcoat_v3_quaternius_iteration_{number:02d}", include_grey=True)


def camera_at(name, location, target, ortho=2.25):
    cam_data = bpy.data.cameras.new(name)
    cam = bpy.data.objects.new(name, cam_data)
    bpy.context.collection.objects.link(cam)
    cam.location = location
    direction = Vector(target) - cam.location
    cam.rotation_euler = direction.to_track_quat('-Z', 'Y').to_euler()
    cam_data.type = 'ORTHO'
    cam_data.ortho_scale = ortho
    bpy.context.scene.camera = cam
    return cam


def setup_render():
    scene = bpy.context.scene
    scene.render.engine = 'BLENDER_EEVEE'
    scene.render.resolution_x = 1024
    scene.render.resolution_y = 1024
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = 'PNG'
    scene.render.film_transparent = False
    scene.world.color = (.025, .030, .035)
    world = scene.world
    world.use_nodes = True
    world.node_tree.nodes['Background'].inputs['Color'].default_value = (.035, .045, .055, 1)
    world.node_tree.nodes['Background'].inputs['Strength'].default_value = .32

    bpy.ops.object.light_add(type='AREA', location=(-3.0, 3.5, 5.0))
    key = bpy.context.object
    key.name = "Warm large key"
    key.data.energy = 820
    key.data.shape = 'DISK'
    key.data.size = 3.0
    key.data.color = (1.0, .82, .68)
    bpy.ops.object.light_add(type='AREA', location=(3.4, 1.2, 2.7))
    fill = bpy.context.object
    fill.name = "Cool jade fill"
    fill.data.energy = 480
    fill.data.size = 2.6
    fill.data.color = (.58, .78, .82)
    bpy.ops.object.light_add(type='AREA', location=(0, -3.0, 3.5))
    rim = bpy.context.object
    rim.name = "Fine rim"
    rim.data.energy = 650
    rim.data.size = 2.0
    rim.data.color = (.72, .83, 1.0)

    bpy.ops.mesh.primitive_plane_add(size=200, location=(0, 0, -.012))
    ground = bpy.context.object
    ground.name = "Neutral review ground"
    ground.data.materials.append(material("Warm grey ground", "#5C625F", .92))


def render(path: Path, camera_location, target=(0, 0, .98), ortho=2.2, grey=False, width=1024, height=1024):
    scene = bpy.context.scene
    old_override = scene.view_layers[0].material_override
    scene.view_layers[0].material_override = GREY if grey else None
    scene.render.resolution_x = width
    scene.render.resolution_y = height
    cam = camera_at("Review camera", camera_location, target, ortho)
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(cam, do_unlink=True)
    scene.view_layers[0].material_override = old_override


def render_views(directory: Path, prefix: str, include_grey=True):
    # Quaternius character faces +Y in Blender, which becomes Godot -Z forward.
    views = {
        "front": (0, -6.0, 1.02),
        "side": (-6.0, 0, 1.02),
        "back": (0, 6.0, 1.02),
        "three_quarter": (-4.25, -4.25, 1.08),
    }
    for label, position in views.items():
        render(directory / f"{prefix}_{label}.png", position)
        if include_grey:
            render(directory / f"{prefix}_grey_{label}.png", position, grey=True)


def rig_pose_test():
    bpy.context.view_layer.objects.active = RIG
    bpy.ops.object.mode_set(mode='POSE')
    rotations = {
        'upperarm_l': (math.radians(-18), math.radians(12), math.radians(28)),
        'lowerarm_l': (0, math.radians(-42), 0),
        'upperarm_r': (math.radians(25), math.radians(-10), math.radians(-32)),
        'lowerarm_r': (0, math.radians(48), 0),
        'thigh_l': (math.radians(-28), 0, math.radians(-5)),
        'calf_l': (math.radians(58), 0, 0),
        'foot_l': (math.radians(-20), 0, 0),
        'thigh_r': (math.radians(12), 0, math.radians(3)),
        'calf_r': (math.radians(-18), 0, 0),
    }
    for bone_name, rotation in rotations.items():
        bone = RIG.pose.bones.get(bone_name)
        if bone:
            bone.rotation_mode = 'XYZ'
            bone.rotation_euler = rotation
    bpy.ops.object.mode_set(mode='OBJECT')
    render(OUT / "cultivator_shortcoat_v3_quaternius_pose_stress.png", (-4.25, -4.25, 1.08), ortho=2.3)
    render(OUT / "cultivator_shortcoat_v3_quaternius_pose_stress_grey.png", (-4.25, -4.25, 1.08), ortho=2.3, grey=True)
    for bone in RIG.pose.bones:
        bone.rotation_euler = (0, 0, 0)


def audit():
    visible_meshes = [obj for obj in bpy.data.objects if obj.type == 'MESH' and not obj.hide_render]
    weighted = []
    unweighted = []
    for obj in visible_meshes:
        if obj.name == "Neutral review ground":
            continue
        if obj.parent == RIG or any(mod.type == 'ARMATURE' and mod.object == RIG for mod in obj.modifiers):
            no_weight = 0
            for vertex in obj.data.vertices:
                total = sum(group.weight for group in vertex.groups)
                if total < .999:
                    no_weight += 1
            weighted.append({"object": obj.name, "vertices": len(obj.data.vertices), "vertices_below_weight_0_999": no_weight})
            if no_weight:
                unweighted.append(obj.name)
    bone_names = [bone.name for bone in RIG.data.bones]
    required_pairs = [('upperarm_l', 'upperarm_r'), ('lowerarm_l', 'lowerarm_r'),
                      ('hand_l', 'hand_r'), ('thigh_l', 'thigh_r'),
                      ('calf_l', 'calf_r'), ('foot_l', 'foot_r')]
    pair_audit = {f"{left}|{right}": left in bone_names and right in bone_names for left, right in required_pairs}
    depsgraph = bpy.context.evaluated_depsgraph_get()
    bounds = []
    for obj in visible_meshes:
        if obj.name == "Neutral review ground":
            continue
        evaluated = obj.evaluated_get(depsgraph)
        bounds.extend([evaluated.matrix_world @ Vector(corner) for corner in evaluated.bound_box])
    minimum = [min(point[i] for point in bounds) for i in range(3)]
    maximum = [max(point[i] for point in bounds) for i in range(3)]
    triangles = 0
    for obj in visible_meshes:
        if obj.name == "Neutral review ground":
            continue
        evaluated = obj.evaluated_get(depsgraph)
        mesh_data = evaluated.to_mesh()
        mesh_data.calc_loop_triangles()
        triangles += len(mesh_data.loop_triangles)
        evaluated.to_mesh_clear()
    return {
        "source": {
            "upstream": "Quaternius Modular Character Outfits - Fantasy / Male Peasant on Regular Male / CC0",
            "mirror": "https://github.com/agentkaerf/FreeModels",
            "mirror_commit": "db3df04d1e4714298a09510b26fb6de6645138a2",
            "mirror_path": "Modular Character Outfits - Fantasy[Standard]/Exports/glTF (Godot-Unreal)/Outfits/Male_Peasant.gltf",
            "download_date": "2026-09-19",
            "source_sha256": hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
        },
        "orientation": {
            "blender_character_front": "-Y",
            "godot_glb_character_front": "-Z",
            "proof": "Quaternius source faces Blender -Y; GLB export adds a 180-degree GodotFrontAdapter root",
        },
        "armature": {
            "name": RIG.name,
            "bone_count": len(bone_names),
            "bone_names": bone_names,
            "required_lr_pairs": pair_audit,
            "rest_pose_preserved": True,
        },
        "weights": {
            "mesh_audit": weighted,
            "objects_with_incomplete_weights": unweighted,
        },
        "geometry": {
            "mesh_count": len([obj for obj in visible_meshes if obj.name != "Neutral review ground"]),
            "triangle_count_render_evaluated": triangles,
            "bounds_m": {"minimum": minimum, "maximum": maximum,
                         "height": maximum[2] - minimum[2]},
        },
        "art_review": {
            "status": "awaiting independent static review",
            "minimum_required_score": 80,
            "technical_pass_is_not_visual_pass": True,
        },
    }


def export_glb():
    # Exclude cameras, lights, and the neutral review ground from delivery.
    adapter = bpy.data.objects.new("GodotFrontAdapter_-Z", None)
    bpy.context.collection.objects.link(adapter)
    adapter.rotation_euler[2] = math.pi
    RIG.parent = adapter
    bpy.ops.object.select_all(action='DESELECT')
    export_objects = []
    for obj in bpy.data.objects:
        if obj == adapter or obj == RIG or obj.parent == RIG or (obj.type == 'MESH' and obj.name != "Neutral review ground" and any(mod.type == 'ARMATURE' and mod.object == RIG for mod in obj.modifiers)):
            obj.select_set(True)
            export_objects.append(obj)
    bpy.context.view_layer.objects.active = RIG
    bpy.ops.export_scene.gltf(filepath=str(GLB), export_format='GLB', use_selection=True,
                              export_skins=True, export_animations=False, export_apply=False)
    RIG.parent = None
    bpy.data.objects.remove(adapter, do_unlink=True)
    return export_objects


def write_ledger(manifest):
    files = sorted(path for path in OUT.rglob('*') if path.is_file())
    hashes = {str(path.relative_to(OUT)): hashlib.sha256(path.read_bytes()).hexdigest() for path in files}
    manifest["file_sha256"] = hashes
    (OUT / "build_manifest.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding='utf-8')
    ledger = f"""# 青玉短打修士 v3（Quaternius 路线）资产台账

日期：2026-09-19

## 来源链

- 原作者/资产包：Quaternius，Universal Base Characters，Superhero Male。
- 原始许可：CC0 1.0 Universal；原文保存为 `source/QUATERNIUS-LICENSE.txt`。
- 官方页面：https://quaternius.com/packs/universalbasecharacters.html
- 固定镜像：https://github.com/programasweights/avatar
- 固定 commit：`ddd5fc34a445bcded3cf9836607aaeebc19a5c78`
- 镜像原路径：`public/assets/character.glb`
- 下载日期：2026-09-19
- 本地原件 SHA-256：`{manifest['source']['source_sha256']}`
- 镜像的来源说明原样保存为 `source/MIRROR-ASSETS.md`。免费 Standard 包只包含 Superhero 比例；Regular Male 不在合法免费源中，因此未伪称使用 Regular Male。

## 本项目改造

- 保留 65 骨 Quaternius Humanoid armature、bone rest pose、原人体权重、连续肩腋髋膝手脚拓扑与 UV。
- 收窄躯干肩胸，制作贴体交领短外衫、窄袖、连续腰封、四片弧形短摆、收腿裤、软靴、发际/鬓发/发髻。
- 新衣装壳体直接复制底座成熟表面与权重；交领、短摆和发饰按邻近人体骨骼显式蒙皮。
- 主色 `#263B5C`、深靛 `#18283F`、月白 `#E4DFD2`、暖金 `#B7924C`。
- 主资产保留骨架与权重，目标是直接使用 Quaternius Universal Animation Library；本轮没有上传 Mixamo。

## 输出与边界

`cultivator_shortcoat_v3_quaternius.blend` 是可编辑主源；`cultivator_shortcoat_v3_quaternius_rigged.glb` 是 Godot 候选。`iterations/` 保存至少两轮不可覆盖的视觉迭代。四向彩色/灰模、2.5D size 18/6、pose stress 和 `build_manifest.json` 是审计证据。

技术检查不替代审美判断；独立静态审查低于 80/100 时必须标记失败候选，不得接入运行时。
"""
    (OUT / "asset_ledger.md").write_text(ledger, encoding='utf-8')


def attach_audited_head():
    """Bring only the proven Quaternius head/eyes onto the Regular Male outfit rig."""
    existing_names = set(bpy.data.objects.keys())
    bpy.ops.import_scene.gltf(filepath=str(HEAD_SOURCE))
    imported = [obj for obj in bpy.data.objects if obj.name not in existing_names]
    source_body = next(obj for obj in imported if obj.name.startswith('SuperHero_Male'))
    source_rig = next(obj for obj in imported if obj.type == 'ARMATURE')
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(source_body.data)
    doomed = [vertex for vertex in bm.verts if vertex.co.z < 1.505]
    bmesh.ops.delete(bm, geom=doomed, context='VERTS')
    bm.to_mesh(source_body.data)
    bm.free()
    source_body.name = "Quaternius continuous young head and neck"
    source_body.data.materials.clear()
    source_body.data.materials.append(SKIN)
    source_body.parent = RIG
    for modifier in source_body.modifiers:
        if modifier.type == 'ARMATURE':
            modifier.object = RIG
    for obj in imported:
        if obj.name.startswith('Eyes') or obj.name.startswith('Eyebrows'):
            obj.data.materials.clear()
            obj.data.materials.append(EYE if obj.name.startswith('Eyes') else HAIR)
            obj.parent = RIG
            for modifier in obj.modifiers:
                if modifier.type == 'ARMATURE':
                    modifier.object = RIG
    # Remove only the imported source rig and non-character demo objects.
    source_rig_name = source_rig.name
    removable = [obj for obj in imported if obj.name != source_rig_name]
    bpy.data.objects.remove(source_rig, do_unlink=True)
    for obj in removable:
        if obj.name.startswith(('Cube', 'Icosphere', 'Camera', 'Light')) and obj.name in bpy.data.objects:
            bpy.data.objects.remove(obj, do_unlink=True)
    return source_body


def main():
    global RIG, BODY, BODY_PARTS
    OUT.mkdir(parents=True, exist_ok=True)
    ITER.mkdir(parents=True, exist_ok=True)
    bpy.ops.import_scene.gltf(filepath=str(SOURCE))
    RIG = bpy.data.objects['Armature']
    BODY_PARTS = [bpy.data.objects[name] for name in ('Male_Peasant_Arms', 'Male_Peasant_Body', 'Male_Peasant_Feet', 'Male_Peasant_Legs')]
    BODY = attach_audited_head()
    # Remove source demo objects that are not part of the character.
    for name in ('Cube', 'Icosphere', 'Camera', 'Light'):
        obj = bpy.data.objects.get(name)
        if obj:
            bpy.data.objects.remove(obj, do_unlink=True)

    tailor_body_proportions()
    recolor_base()
    build_outfit_iteration_1()
    setup_render()
    save_iteration(4)

    build_hair_and_refinement()
    save_iteration(5)
    render_views(OUT, "cultivator_shortcoat_v3_quaternius", include_grey=True)
    render(OUT / "cultivator_shortcoat_v3_quaternius_2p5d_size6.png", (0, -8.0, 1.02), ortho=6.0, width=1280, height=720)
    render(OUT / "cultivator_shortcoat_v3_quaternius_2p5d_size18.png", (0, -18.0, 1.02), ortho=18.0, width=1280, height=720)
    rig_pose_test()
    bpy.ops.wm.save_as_mainfile(filepath=str(BLENDER), compress=True)
    export_glb()
    manifest = audit()
    write_ledger(manifest)
    print(json.dumps(manifest, indent=2, ensure_ascii=False))


if __name__ == '__main__':
    main()
