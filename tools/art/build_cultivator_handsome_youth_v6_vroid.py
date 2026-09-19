#!/usr/bin/env python3
"""Build v6 from the preserved CC0 VRoid HairSample Male.

Run with Blender 5.x:
  blender --background --factory-startup --python \
    tools/art/build_cultivator_handsome_youth_v6_vroid.py

The source VRM is never modified. The script removes only the independently
connected hood and drawstring islands, recolours the mature continuous outfit,
adds fitted xianxia layers, and preserves the original armature/weights.
"""
from __future__ import annotations

import hashlib
import json
import math
import struct
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "docs/art/cultivator_handsome_youth_v6_vroid"
SOURCE = OUT / "source/HairSample_Male_original.vrm"
ITER = OUT / "iterations/iteration_02"
BLEND = OUT / "cultivator_handsome_youth_v6_vroid.blend"
ITER_BLEND = ITER / "cultivator_handsome_youth_v6_vroid_iteration_02.blend"
GLB = OUT / "cultivator_handsome_youth_v6_vroid_rigged.glb"

RIG = None
BODY = None
FACE = None
HAIR_SOURCE = None
ADDED_CLOTHING = []
ADDED_HAIR = []


def srgb(value: str):
    raw = [int(value[index:index + 2], 16) / 255 for index in (1, 3, 5)]
    return tuple(v / 12.92 if v <= .04045 else ((v + .055) / 1.055) ** 2.4 for v in raw)


def make_material(name, color, roughness=.78, metallic=0.0):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.diffuse_color = (*srgb(color), 1)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*srgb(color), 1)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    return mat


IVORY = None
BLUE = None
DEEP = None
JADE = None
INK = None
GREY = None


def init_materials():
    global IVORY, BLUE, DEEP, JADE, INK, GREY
    IVORY = make_material("V6 moon white #E4DFD2", "#E4DFD2", .88)
    BLUE = make_material("V6 clear blue #527D9C", "#527D9C", .76)
    DEEP = make_material("V6 deep indigo #18283F", "#18283F", .86)
    JADE = make_material("V6 jade clasp #67B8A2", "#67B8A2", .40, .04)
    INK = make_material("V6 ponytail ink #101722", "#101722", .84)
    GREY = make_material("V6 neutral clay", "#999994", .92)


def import_source():
    global RIG, BODY, FACE, HAIR_SOURCE
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    bpy.ops.import_scene.gltf(filepath=str(SOURCE))
    RIG = bpy.data.objects["Armature"]
    BODY = bpy.data.objects["Body"]
    FACE = bpy.data.objects["Face"]
    HAIR_SOURCE = bpy.data.objects["Hair001"]
    # Generic glTF import materializes VRM metadata as this unweighted helper.
    for obj in list(bpy.data.objects):
        if (obj.type == 'MESH' and obj.name.startswith("Icosphere") and
                not obj.material_slots and not obj.vertex_groups):
            bpy.data.objects.remove(obj, do_unlink=True)
    for obj in (BODY, FACE, HAIR_SOURCE):
        for poly in obj.data.polygons:
            poly.use_smooth = True


def connected_components(obj):
    adjacent = [set() for _ in obj.data.vertices]
    for edge in obj.data.edges:
        a, b = edge.vertices
        adjacent[a].add(b)
        adjacent[b].add(a)
    unseen = set(range(len(adjacent)))
    components = []
    while unseen:
        root = next(iter(unseen))
        unseen.remove(root)
        todo = [root]
        component = set()
        while todo:
            vertex = todo.pop()
            component.add(vertex)
            for neighbour in adjacent[vertex]:
                if neighbour in unseen:
                    unseen.remove(neighbour)
                    todo.append(neighbour)
        components.append(component)
    return components


def component_weight_sum(obj, indices, group_names):
    group_ids = {group.index for group in obj.vertex_groups if group.name in group_names}
    return sum(item.weight for index in indices for item in obj.data.vertices[index].groups
               if item.group in group_ids)


def remove_hood_and_strings():
    hood = {"J_Sec_C_Hood", "J_Sec_C_Hood_end"}
    strings = {
        "J_Sec_L_HoodString1", "J_Sec_L_HoodString2", "J_Sec_L_HoodString2_end",
        "J_Sec_R_HoodString1", "J_Sec_R_HoodString2", "J_Sec_R_HoodString2_end",
    }
    removed = set()
    evidence = []
    for component in connected_components(BODY):
        hood_sum = component_weight_sum(BODY, component, hood)
        string_sum = component_weight_sum(BODY, component, strings)
        coords = [BODY.data.vertices[index].co for index in component]
        bounds = {
            "min": [min(co[axis] for co in coords) for axis in range(3)],
            "max": [max(co[axis] for co in coords) for axis in range(3)],
        }
        # The actual hood is an independent 251-vertex island with >50 total
        # hood weight. Each string is an independent 29-vertex island. The
        # fitted neck opening has only 2.7 incidental hood weight and remains.
        if hood_sum > 20 or string_sum > 1:
            removed.update(component)
            evidence.append({"vertices": len(component), "hood_weight": hood_sum,
                             "string_weight": string_sum, "bounds": bounds})
    bpy.context.view_layer.objects.active = BODY
    BODY.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='DESELECT')
    bpy.ops.object.mode_set(mode='OBJECT')
    for vertex in BODY.data.vertices:
        vertex.select = vertex.index in removed
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.delete(type='VERT')
    bpy.ops.object.mode_set(mode='OBJECT')
    BODY.select_set(False)
    return evidence


def recolor_source_outfit():
    # Body slot 0 is skin; keep its original texture. Slots 1/2/3 are the
    # existing continuous top, trousers and shoes.
    BODY.data.materials[1] = IVORY
    BODY.data.materials[2] = DEEP
    BODY.data.materials[3] = INK


def tailor_existing_hoodie():
    """Narrow only the original continuous torso island, never the sleeves."""
    components = connected_components(BODY)
    torso = max(components, key=lambda component: len(component) if len(component) > 500 else 0)
    # The largest component after hood removal is the skin body, so locate the
    # largest component whose polygons use the top material instead.
    polygon_material = {index: [] for index in range(len(BODY.data.vertices))}
    for polygon in BODY.data.polygons:
        for vertex in polygon.vertices:
            polygon_material[vertex].append(polygon.material_index)
    candidates = [component for component in components
                  if len(component) > 400 and sum(
                      polygon_material[index].count(1) for index in component) > len(component)]
    torso = max(candidates, key=len)
    for index in torso:
        vertex = BODY.data.vertices[index]
        progress = min(1.0, max(0.0, (vertex.co.z - 1.00) / .44))
        x_factor = .74 + .14 * progress
        vertex.co.x = .0005 + (vertex.co.x - .0005) * x_factor
        vertex.co.y = .006 + (vertex.co.y - .006) * .90
    BODY.data.update()
    return len(torso)


def soften_existing_shoes():
    """Reduce the original thick sole without changing topology or weights."""
    shoe_vertices = {index for polygon in BODY.data.polygons if polygon.material_index == 3
                     for index in polygon.vertices}
    for index in shoe_vertices:
        vertex = BODY.data.vertices[index]
        if vertex.co.z < .105:
            vertex.co.z = .0005 + (vertex.co.z - .0005) * .72
    BODY.data.update()
    return len(shoe_vertices)


def add_armature_binding(obj, weight_rows):
    groups = {}
    for index, weights in enumerate(weight_rows):
        total = sum(weights.values()) or 1.0
        for name, value in weights.items():
            group = groups.get(name)
            if group is None:
                group = obj.vertex_groups.get(name) or obj.vertex_groups.new(name=name)
                groups[name] = group
            group.add([index], value / total, 'REPLACE')
    modifier = obj.modifiers.new("V6 preserved armature deformation", 'ARMATURE')
    modifier.object = RIG
    obj.parent = RIG


def make_mesh(name, vertices, faces, material, weights, thickness=.0, bevel=.0, subdiv=0):
    data = bpy.data.meshes.new(name)
    data.from_pydata(vertices, [], faces)
    data.update()
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(material)
    for poly in obj.data.polygons:
        poly.use_smooth = True
    add_armature_binding(obj, weights)
    if thickness:
        modifier = obj.modifiers.new("V6 soft fabric thickness", 'SOLIDIFY')
        modifier.thickness = thickness
        modifier.offset = 0
    if bevel:
        modifier = obj.modifiers.new("V6 soft tailored edge", 'BEVEL')
        modifier.width = bevel
        modifier.segments = 2
    if subdiv:
        modifier = obj.modifiers.new("V6 cloth subdivision", 'SUBSURF')
        modifier.levels = subdiv
        modifier.render_levels = subdiv
    return obj


def torso_weights(z):
    if z < 1.03:
        return {"J_Bip_C_Hips": .72, "J_Bip_C_Spine": .28}
    if z < 1.25:
        return {"J_Bip_C_Spine": .55, "J_Bip_C_Chest": .45}
    return {"J_Bip_C_Chest": .38, "J_Bip_C_UpperChest": .62}


def front_surface_y(x, z, offset=.003):
    candidates = sorted(BODY.data.vertices,
                        key=lambda vertex: (vertex.co.x - x) ** 2 + (vertex.co.z - z) ** 2)[:36]
    return max(vertex.co.y for vertex in candidates) + offset


def fitted_ribbon(name, path, widths, material, outward=.003):
    vertices = []
    weights = []
    for index, (x, z) in enumerate(path):
        point = Vector((x, 0, z))
        if index == 0:
            tangent = Vector((path[1][0], 0, path[1][1])) - point
        elif index == len(path) - 1:
            tangent = point - Vector((path[index - 1][0], 0, path[index - 1][1]))
        else:
            tangent = Vector((path[index + 1][0], 0, path[index + 1][1])) - Vector((path[index - 1][0], 0, path[index - 1][1]))
        side = Vector((tangent.z, 0, -tangent.x)).normalized() * widths[index] * .5
        for sign in (-1, 1):
            sample = point + side * sign
            sample.y = front_surface_y(sample.x, sample.z, outward)
            vertices.append(tuple(sample))
            weights.append(torso_weights(sample.z))
    faces = [(i * 2, i * 2 + 1, i * 2 + 3, i * 2 + 2)
             for i in range(len(path) - 1)]
    obj = make_mesh(name, vertices, faces, material, weights, .0028, .0012, 1)
    ADDED_CLOTHING.append(obj)
    return obj


def build_cross_collar():
    # A real right-over-left Y closure: the under-lapel terminates just below
    # the crossing while the over-lapel continues to the opposite waist.
    under = [(-.090, 1.505), (-.074, 1.470), (-.043, 1.415),
             (-.010, 1.362), (.020, 1.315)]
    over = [(.090, 1.505), (.074, 1.470), (.043, 1.415),
            (.006, 1.355), (-.042, 1.275), (-.082, 1.205)]
    under_widths = [.078, .080, .076, .068, .056]
    over_widths = [.078, .080, .076, .068, .060, .052]
    fitted_ribbon("V6 left under-lapel outer collar", under, under_widths, BLUE, .0035)
    fitted_ribbon("V6 right over-lapel outer collar", over, over_widths, BLUE, .0070)
    fitted_ribbon("V6 left under-lapel moon-white inset", under,
                  [value * .52 for value in under_widths], IVORY, .0075)
    fitted_ribbon("V6 right over-lapel moon-white inset", over,
                  [value * .52 for value in over_widths], IVORY, .0110)


def wrapped_outer_panel(name, angle_start, angle_end):
    columns = 11
    rows = [(1.430, .180, .154), (1.315, .174, .151),
            (1.190, .166, .147), (1.070, .158, .143), (.985, .154, .140)]
    vertices = []
    weights = []
    for z, radius_x, radius_y in rows:
        for column in range(columns):
            t = column / (columns - 1)
            angle = angle_start + (angle_end - angle_start) * t
            # A slight tailored waist hollow prevents another straight box.
            radial = 1.0 + .018 * math.sin(math.pi * t)
            vertices.append((radius_x * radial * math.sin(angle),
                             radius_y * radial * math.cos(angle), z))
            weights.append(torso_weights(z))
    faces = []
    for row in range(len(rows) - 1):
        for column in range(columns - 1):
            a = row * columns + column
            faces.append((a, a + 1, a + columns + 1, a + columns))
    obj = make_mesh(name, vertices, faces, BLUE, weights, .0032, .0015, 1)
    ADDED_CLOTHING.append(obj)
    return obj


def build_short_outer_layer():
    wrapped_outer_panel("V6 left shoulder-to-waist curved outer layer",
                        math.radians(25), math.radians(145))
    wrapped_outer_panel("V6 right shoulder-to-waist curved outer layer",
                        math.radians(-145), math.radians(-25))


def oval_band(name, z_bottom, z_top, radius_x, radius_y, material):
    segments = 48
    vertices = []
    weights = []
    for z in (z_bottom, z_top):
        for index in range(segments):
            angle = math.tau * index / segments
            vertices.append((radius_x * math.sin(angle), radius_y * math.cos(angle), z))
            weights.append(torso_weights(z))
    faces = []
    for index in range(segments):
        nxt = (index + 1) % segments
        faces.append((index, nxt, segments + nxt, segments + index))
    obj = make_mesh(name, vertices, faces, material, weights, .002, .0015, 1)
    ADDED_CLOTHING.append(obj)
    return obj


def arm_cuff(name, side):
    """A closed narrow cuff that overlaps the source sleeve-to-hand seam."""
    segments = 24
    left = side == "L"
    x_rows = (-.660, -.585) if left else (.585, .660)
    vertices = []
    weights = []
    lower_arm = f"J_Bip_{side}_LowerArm"
    hand = f"J_Bip_{side}_Hand"
    for row, x in enumerate(x_rows):
        for index in range(segments):
            angle = math.tau * index / segments
            vertices.append((x, .026 + .059 * math.sin(angle),
                             1.394 + .052 * math.cos(angle)))
            hand_weight = .28 if (row == 0) == left else .12
            weights.append({lower_arm: 1.0 - hand_weight, hand: hand_weight})
    faces = []
    for index in range(segments):
        nxt = (index + 1) % segments
        faces.append((index, nxt, segments + nxt, segments + index))
    obj = make_mesh(name, vertices, faces, BLUE, weights, .0025, .0018, 1)
    ADDED_CLOTHING.append(obj)
    return obj


def soft_gaiter(name, side):
    """A softly tapered indigo wrap over the original lower leg and shoe cuff."""
    segments = 28
    centre_x = -.069 if side == "L" else .070
    rows = [
        (.055, .069, .087),
        (.105, .071, .083),
        (.205, .067, .071),
        (.315, .061, .064),
        (.385, .058, .060),
    ]
    lower_leg = f"J_Bip_{side}_LowerLeg"
    foot = f"J_Bip_{side}_Foot"
    vertices = []
    weights = []
    for row_index, (z, radius_x, radius_y) in enumerate(rows):
        for index in range(segments):
            angle = math.tau * index / segments
            # A restrained forward bias covers the existing shoe tongue while
            # keeping the rear profile close to the leg.
            vertices.append((centre_x + radius_x * math.sin(angle),
                             .010 + radius_y * math.cos(angle), z))
            foot_weight = max(0.0, .52 - row_index * .17)
            weights.append({lower_leg: 1.0 - foot_weight, foot: foot_weight})
    faces = []
    for row in range(len(rows) - 1):
        for index in range(segments):
            nxt = (index + 1) % segments
            a = row * segments + index
            b = row * segments + nxt
            c = (row + 1) * segments + nxt
            d = (row + 1) * segments + index
            faces.append((a, b, c, d))
    obj = make_mesh(name, vertices, faces, DEEP, weights, .0028, .0018, 1)
    ADDED_CLOTHING.append(obj)
    return obj


def build_cuffs_and_soft_boots():
    arm_cuff("V6 left narrow blue sleeve cuff", "L")
    arm_cuff("V6 right narrow blue sleeve cuff", "R")
    soft_gaiter("V6 left deep-indigo soft gaiter", "L")
    soft_gaiter("V6 right deep-indigo soft gaiter", "R")


def skirt_panel(name, angle_start, angle_end, thigh_bone):
    columns = 9
    back = "back" in name.lower()
    final_z = .680 if back else .735
    rows = [(1.000, .190, .160), (.930, .196, .164), (.855, .202, .169),
            (.780, .210, .174), (final_z, .220, .181)]
    vertices = []
    weights = []
    for row_index, (z, radius_x, radius_y) in enumerate(rows):
        for column in range(columns):
            t = column / (columns - 1)
            angle = angle_start + (angle_end - angle_start) * t
            hem = .026 * abs(2 * t - 1) if row_index == len(rows) - 1 else 0
            radial = 1.0 + .025 * math.sin(math.pi * t)
            vertices.append((radius_x * radial * math.sin(angle),
                             radius_y * radial * math.cos(angle), z + hem))
            if row_index == 0:
                weights.append({"J_Bip_C_Hips": .88, thigh_bone: .12})
            elif row_index == 1:
                weights.append({"J_Bip_C_Hips": .72, thigh_bone: .28})
            else:
                weights.append({"J_Bip_C_Hips": .58, thigh_bone: .42})
    faces = []
    for row in range(len(rows) - 1):
        for column in range(columns - 1):
            a = row * columns + column
            faces.append((a, a + 1, a + columns + 1, a + columns))
    obj = make_mesh(name, vertices, faces, BLUE, weights, .004, .0020, 1)
    ADDED_CLOTHING.append(obj)
    return obj


def ellipsoid(name, location, scale, material, weights, segments=32, rings=16):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(material)
    for poly in obj.data.polygons:
        poly.use_smooth = True
    add_armature_binding(obj, [weights] * len(obj.data.vertices))
    return obj


def build_waist_and_skirts():
    oval_band("V6 fitted deep-indigo layered waist sash", .970, 1.015, .195, .165, DEEP)
    # Front and back centre seams plus broad side openings remain free.
    skirt_panel("V6 front-left curved short skirt", math.radians(10), math.radians(76), "J_Bip_L_UpperLeg")
    skirt_panel("V6 front-right curved short skirt", math.radians(-76), math.radians(-10), "J_Bip_R_UpperLeg")
    skirt_panel("V6 back-left curved short skirt", math.radians(104), math.radians(170), "J_Bip_L_UpperLeg")
    skirt_panel("V6 back-right curved short skirt", math.radians(190), math.radians(256), "J_Bip_R_UpperLeg")
    clasp = ellipsoid("V6 embedded jade waist clasp", (0, .173, .993), (.024, .012, .024),
                      JADE, {"J_Bip_C_Hips": .76, "J_Bip_C_Spine": .24}, 32, 12)
    ADDED_CLOTHING.append(clasp)


def add_hair_tail_bones():
    bpy.context.view_layer.objects.active = RIG
    RIG.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT')
    head = RIG.data.edit_bones.get("J_Bip_C_Head")
    first = RIG.data.edit_bones.new("V6_HairTail_01")
    first.head = (0, -.125, 1.690)
    first.tail = (0, -.178, 1.475)
    first.parent = head
    second = RIG.data.edit_bones.new("V6_HairTail_02")
    second.head = first.tail
    second.tail = (0, -.168, 1.255)
    second.parent = first
    second.use_connect = True
    bpy.ops.object.mode_set(mode='OBJECT')
    RIG.select_set(False)


def curve_mesh(name, splines, bevel_depth, material):
    curve = bpy.data.curves.new(name, 'CURVE')
    curve.dimensions = '3D'
    curve.resolution_u = 5
    curve.bevel_depth = bevel_depth
    curve.bevel_resolution = 3
    curve.resolution_u = 8
    for points in splines:
        spline = curve.splines.new('BEZIER')
        spline.bezier_points.add(len(points) - 1)
        for point_index, (point, coordinate) in enumerate(zip(spline.bezier_points, points)):
            point.co = coordinate
            point.handle_left_type = 'AUTO'
            point.handle_right_type = 'AUTO'
            fractions = [0.78, 1.06, .92, .38]
            point.radius = fractions[min(point_index, len(fractions) - 1)]
    obj = bpy.data.objects.new(name, curve)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(material)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.convert(target='MESH')
    obj = bpy.context.object
    for poly in obj.data.polygons:
        poly.use_smooth = True
    weights = []
    for vertex in obj.data.vertices:
        z = vertex.co.z
        if z >= 1.56:
            weights.append({"J_Bip_C_Head": .30, "V6_HairTail_01": .70})
        elif z >= 1.43:
            amount = (z - 1.43) / .13
            weights.append({"V6_HairTail_01": .55 + .45 * amount,
                            "V6_HairTail_02": .45 * (1 - amount)})
        else:
            weights.append({"V6_HairTail_02": 1.0})
    add_armature_binding(obj, weights)
    obj.select_set(False)
    return obj


def build_half_up_ponytail():
    add_hair_tail_bones()
    hair_material = HAIR_SOURCE.data.materials[0]
    root = ellipsoid("V6 half-up gathered hair root", (0, -.122, 1.694), (.050, .035, .040),
                     hair_material, {"J_Bip_C_Head": .55, "V6_HairTail_01": .45}, 32, 12)
    ADDED_HAIR.append(root)
    splines = [
        [(-.030, -.138, 1.683), (-.056, -.186, 1.570), (-.048, -.208, 1.415), (-.024, -.184, 1.275)],
        [(-.014, -.145, 1.688), (-.026, -.207, 1.565), (-.020, -.224, 1.405), (-.004, -.192, 1.245)],
        [(0, -.148, 1.690), (.006, -.218, 1.555), (-.004, -.235, 1.390), (.010, -.200, 1.225)],
        [(.014, -.145, 1.688), (.030, -.204, 1.565), (.024, -.220, 1.405), (.008, -.190, 1.250)],
        [(.030, -.138, 1.683), (.058, -.182, 1.570), (.050, -.202, 1.420), (.025, -.182, 1.285)],
    ]
    tail = curve_mesh("V6 curved half-up shoulder-blade ponytail", splines, .015, hair_material)
    ADDED_HAIR.append(tail)


def setup_render():
    scene = bpy.context.scene
    for obj in list(bpy.data.objects):
        if obj.type in {'CAMERA', 'LIGHT'}:
            bpy.data.objects.remove(obj, do_unlink=True)
    scene.render.engine = 'BLENDER_EEVEE'
    scene.render.resolution_x = 1024
    scene.render.resolution_y = 1024
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = 'PNG'
    scene.world.use_nodes = True
    scene.world.node_tree.nodes['Background'].inputs['Color'].default_value = (.025, .032, .040, 1)
    scene.world.node_tree.nodes['Background'].inputs['Strength'].default_value = .34
    for location, energy, size, color in [
        ((-3.0, 3.5, 4.7), 900, 3.2, (1.0, .84, .72)),
        ((3.2, -1.4, 3.0), 520, 2.6, (.58, .78, .88)),
        ((0, -3.0, 3.7), 700, 2.2, (.75, .84, 1.0)),
    ]:
        bpy.ops.object.light_add(type='AREA', location=location)
        light = bpy.context.object
        light.data.energy = energy
        light.data.size = size
        light.data.color = color
    bpy.ops.mesh.primitive_plane_add(size=200, location=(0, 0, -.006))
    ground = bpy.context.object
    ground.name = "V6 neutral review ground"
    ground.data.materials.append(make_material("V6 review ground", "#59615F", .94))


def camera(location, target=(0, 0, .90), ortho=2.05):
    data = bpy.data.cameras.new("V6 review camera")
    obj = bpy.data.objects.new("V6 review camera", data)
    bpy.context.collection.objects.link(obj)
    obj.location = location
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat('-Z', 'Y').to_euler()
    data.type = 'ORTHO'
    data.ortho_scale = ortho
    bpy.context.scene.camera = obj
    return obj


def render(path, location, grey=False, ortho=2.05, width=1024, height=1024):
    scene = bpy.context.scene
    previous = scene.view_layers[0].material_override
    scene.view_layers[0].material_override = GREY if grey else None
    scene.render.resolution_x = width
    scene.render.resolution_y = height
    cam = camera(location, ortho=ortho)
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(cam, do_unlink=True)
    scene.view_layers[0].material_override = previous


def render_four_views(directory, prefix):
    views = {
        "front": (0, 5.0, .94),
        "three_quarter": (-3.6, 3.6, .98),
        "side": (-5.0, 0, .94),
        "back": (0, -5.0, .94),
    }
    for label, location in views.items():
        render(directory / f"{prefix}_{label}.png", location)
        render(directory / f"{prefix}_grey_{label}.png", location, grey=True)


def render_only_added_clothing():
    meshes = [obj for obj in bpy.data.objects if obj.type == 'MESH']
    states = {obj: obj.hide_render for obj in meshes}
    for obj in meshes:
        if obj.name == "V6 neutral review ground":
            continue
        obj.hide_render = obj not in ADDED_CLOTHING
    render(OUT / "cultivator_handsome_youth_v6_vroid_only_added_clothing_grey.png",
           (0, 5.0, .94), grey=True)
    for obj, state in states.items():
        obj.hide_render = state


def set_idle_pose():
    states = {}
    for name, angle in [("J_Bip_L_UpperArm", math.radians(70)),
                        ("J_Bip_R_UpperArm", math.radians(-70))]:
        bone = RIG.pose.bones[name]
        states[name] = [constraint.mute for constraint in bone.constraints]
        for constraint in bone.constraints:
            constraint.mute = True
        bone.rotation_mode = 'XYZ'
        bone.rotation_euler = (0, 0, angle)
    bpy.context.view_layer.update()
    return states


def clear_pose(states):
    for bone in RIG.pose.bones:
        bone.matrix_basis.identity()
    for name, muted in states.items():
        for constraint, state in zip(RIG.pose.bones[name].constraints, muted):
            constraint.mute = state
    bpy.context.view_layer.update()


def render_idle_and_scale():
    states = set_idle_pose()
    render(OUT / "cultivator_handsome_youth_v6_vroid_idle_front.png", (0, 5.0, .94))
    render(OUT / "cultivator_handsome_youth_v6_vroid_idle_three_quarter.png", (-3.6, 3.6, .98))
    render(OUT / "cultivator_handsome_youth_v6_vroid_idle_back.png", (0, -5.0, .94))
    render(OUT / "cultivator_handsome_youth_v6_vroid_2p5d_size6.png",
           (0, 8.0, .94), ortho=6.0, width=1280, height=720)
    render(OUT / "cultivator_handsome_youth_v6_vroid_2p5d_size18.png",
           (0, 18.0, .94), ortho=18.0, width=1280, height=720)
    clear_pose(states)


def export_glb():
    bpy.ops.object.select_all(action='DESELECT')
    RIG.select_set(True)
    for obj in bpy.data.objects:
        if obj.type != 'MESH' or obj.name == "V6 neutral review ground" or obj.hide_render:
            continue
        if obj in (BODY, FACE, HAIR_SOURCE) or obj.parent == RIG or any(
                modifier.type == 'ARMATURE' and modifier.object == RIG for modifier in obj.modifiers):
            obj.select_set(True)
    bpy.context.view_layer.objects.active = RIG
    bpy.ops.export_scene.gltf(filepath=str(GLB), export_format='GLB', use_selection=True,
                              export_skins=True, export_animations=False, export_apply=False)


def glb_structure(path):
    raw = path.read_bytes()
    offset = 12
    payload = None
    while offset < len(raw):
        length, chunk_type = struct.unpack_from('<II', raw, offset)
        chunk = raw[offset + 8:offset + 8 + length]
        offset += 8 + length
        if chunk_type == 0x4E4F534A:
            payload = json.loads(chunk.rstrip(b' \0'))
            break
    return {
        "nodes": len(payload.get("nodes", [])),
        "meshes": len(payload.get("meshes", [])),
        "skins": len(payload.get("skins", [])),
        "materials": len(payload.get("materials", [])),
        "animations": len(payload.get("animations", [])),
    }


def write_manifest(removed_components, tailored_vertices, softened_shoe_vertices):
    bones = [bone.name for bone in RIG.data.bones]
    meshes = []
    for obj in bpy.data.objects:
        if obj.type != 'MESH' or obj.name == "V6 neutral review ground" or obj.hide_render:
            continue
        if not (obj in (BODY, FACE, HAIR_SOURCE) or obj.parent == RIG or any(
                modifier.type == 'ARMATURE' and modifier.object == RIG for modifier in obj.modifiers)):
            continue
        below = sum(1 for vertex in obj.data.vertices
                    if sum(item.weight for item in vertex.groups) < .999)
        meshes.append({"name": obj.name, "vertices": len(obj.data.vertices),
                       "polygons": len(obj.data.polygons),
                       "vertex_groups": len(obj.vertex_groups),
                       "vertices_below_weight_0_999": below})
    manifest = {
        "route": "cultivator_handsome_youth_v6_vroid",
        "iteration": "iteration_02",
        "source": {
            "title": "HairSample_Male", "author": "VRoid Project",
            "license": "CC0", "download_date": "2026-09-19",
            "source_page": "https://opengameart.org/content/vroid-studio-cc0-models",
            "zip_sha256": "ba87440272b157a443dbe2cddb375eb175bce3586a45a84779bb018a5e730129",
            "vrm_sha256": hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
            "vrm_version": "0.x", "embedded_animations": 0,
        },
        "source_preservation": {
            "mature_body_face_hair_topology_preserved_except_declared_hood_islands": True,
            "original_armature_bones_preserved": 91,
            "original_hair_joint_bones_preserved": 16,
            "removed_auxiliary_icosphere": True,
            "removed_hood_drawstring_components": removed_components,
            "existing_hoodie_torso_vertices_tailored": tailored_vertices,
            "existing_shoe_vertices_sole_softened_topology_and_weights_preserved": softened_shoe_vertices,
        },
        "orientation": {
            "blender_source_front": "+Y (verified by eyes, nose, hoodie front and toes)",
            "mixamo_fbx_front": "not applicable; no Mixamo upload or FBX in this route",
            "godot_glb_front": "-Z via Blender glTF Y-up coordinate conversion",
        },
        "armature": {
            "name": RIG.name, "bone_count_total": len(bones),
            "original_bone_count": 91, "added_hair_bones": ["V6_HairTail_01", "V6_HairTail_02"],
            "humanoid_core_present": all(name in bones for name in [
                "J_Bip_C_Hips", "J_Bip_C_Spine", "J_Bip_C_Head",
                "J_Bip_L_UpperArm", "J_Bip_R_UpperArm",
                "J_Bip_L_UpperLeg", "J_Bip_R_UpperLeg"]),
            "rest_pose_preserved": True,
        },
        "weights": {"mesh_audit": meshes,
                    "objects_with_incomplete_weights": [m["name"] for m in meshes if m["vertices_below_weight_0_999"]]},
        "evidence": {
            "t_pose_color_and_grey_four_views": True,
            "static_idle_pose_rendered": True,
            "only_added_clothing_grey_rendered": True,
            "size18_and_size6_rendered": True,
            "real_animation_tested": False,
            "mixamo_uploaded": False,
            "visual_review_status": "iteration 01 69/100 FAIL; iteration 02 visual regression FAIL; route stopped",
            "technical_pass_is_not_visual_pass": True,
        },
        "glb": glb_structure(GLB),
    }
    files = sorted(path for path in OUT.rglob('*') if path.is_file() and path.name != "build_manifest.json")
    manifest["file_sha256"] = {
        str(path.relative_to(OUT)): hashlib.sha256(path.read_bytes()).hexdigest() for path in files
    }
    (OUT / "build_manifest.json").write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(json.dumps(manifest, indent=2, ensure_ascii=False))


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    ITER.mkdir(parents=True, exist_ok=True)
    init_materials()
    import_source()
    removed = remove_hood_and_strings()
    recolor_source_outfit()
    tailored_vertices = tailor_existing_hoodie()
    softened_shoe_vertices = soften_existing_shoes()
    build_short_outer_layer()
    build_cross_collar()
    build_waist_and_skirts()
    build_cuffs_and_soft_boots()
    build_half_up_ponytail()
    setup_render()
    bpy.ops.wm.save_as_mainfile(filepath=str(ITER_BLEND), compress=True)
    render_four_views(ITER, "cultivator_handsome_youth_v6_vroid_iteration_02")
    render_four_views(OUT, "cultivator_handsome_youth_v6_vroid")
    render_only_added_clothing()
    render_idle_and_scale()
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND), compress=True)
    export_glb()
    write_manifest(removed, tailored_vertices, softened_shoe_vertices)


if __name__ == "__main__":
    main()
