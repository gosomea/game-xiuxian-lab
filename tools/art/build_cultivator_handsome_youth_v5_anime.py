#!/usr/bin/env python3
"""Build the v5 handsome youth cultivator from jonshipman's CC-BY anime base.

Run with Blender 5.x, loading the vendored source blend first:
  blender --background docs/art/cultivator_handsome_youth_v5_anime/source/\
generic_anime_male_original.blend --python \
tools/art/build_cultivator_handsome_youth_v5_anime.py

Pass ``-- --source-preview`` to render the untouched source for orientation audit.
No network access is performed.
"""
from __future__ import annotations

import hashlib
import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Matrix, Vector


ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "docs/art/cultivator_handsome_youth_v5_anime"
SOURCE = OUT / "source/generic_anime_male_original.blend"
ITER = OUT / "iterations"
BLEND = OUT / "cultivator_handsome_youth_v5_anime.blend"
GLB = OUT / "cultivator_handsome_youth_v5_anime_rigged.glb"
CLOTHING = []


def srgb(value: str):
    raw = [int(value[index:index + 2], 16) / 255 for index in (1, 3, 5)]
    return tuple(v / 12.92 if v <= .04045 else ((v + .055) / 1.055) ** 2.4 for v in raw)


def material(name, color, roughness=.75, metallic=0.0):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.diffuse_color = (*srgb(color), 1)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*srgb(color), 1)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    return mat


IVORY = material("V5 moon white", "#F0EEE5", .80)
BLUE = material("V5 clear blue #527D9C", "#527D9C", .74)
DEEP = material("V5 deep blue #1D304A", "#1D304A", .82)
HAIR = material("V5 ink hair", "#111923", .86)
JADE = material("V5 jade accent", "#6EC0AD", .42, .02)
GOLD = material("V5 warm gold", "#B7924C", .48, .08)
GREY = material("V5 neutral clay", "#999994", .88)


def character_meshes():
    return [obj for obj in bpy.data.objects
            if obj.type == 'MESH' and len(obj.data.polygons) > 0
            and obj.name.startswith("model_0_submesh_")]


def hide_rig_controls():
    for obj in bpy.data.objects:
        if obj.type == 'MESH' and len(obj.data.polygons) == 0:
            obj.hide_render = True
            obj.hide_viewport = True


def smooth_all():
    for obj in character_meshes():
        for poly in obj.data.polygons:
            poly.use_smooth = True


def camera(location, target=(0, 0, .88), ortho=1.95):
    data = bpy.data.cameras.new("V5 review camera")
    obj = bpy.data.objects.new("V5 review camera", data)
    bpy.context.collection.objects.link(obj)
    obj.location = location
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat('-Z', 'Y').to_euler()
    data.type = 'ORTHO'
    data.ortho_scale = ortho
    bpy.context.scene.camera = obj
    return obj


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
        ((-3.0, -3.5, 4.7), 850, 3.2, (1.0, .84, .72)),
        ((3.3, 1.5, 2.8), 500, 2.6, (.58, .78, .86)),
        ((0, 3.0, 3.6), 700, 2.2, (.75, .84, 1.0)),
    ]:
        bpy.ops.object.light_add(type='AREA', location=location)
        light = bpy.context.object
        light.data.energy = energy
        light.data.size = size
        light.data.color = color
    bpy.ops.mesh.primitive_plane_add(size=200, location=(0, 0, -.006))
    ground = bpy.context.object
    ground.name = "V5 neutral review ground"
    ground.data.materials.append(material("V5 review ground", "#59615F", .92))


def render(path, location, grey=False, ortho=1.95, width=1024, height=1024, target=(0, 0, .88)):
    scene = bpy.context.scene
    previous = scene.view_layers[0].material_override
    scene.view_layers[0].material_override = GREY if grey else None
    scene.render.resolution_x = width
    scene.render.resolution_y = height
    cam = camera(location, target=target, ortho=ortho)
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(cam, do_unlink=True)
    scene.view_layers[0].material_override = previous


def source_preview():
    OUT.mkdir(parents=True, exist_ok=True)
    hide_rig_controls()
    smooth_all()
    setup_render()
    views = {
        "minus_y": (0, -5.0, .92),
        "plus_y": (0, 5.0, .92),
        "minus_x": (-5.0, 0, .92),
        "plus_x": (5.0, 0, .92),
    }
    for label, location in views.items():
        render(OUT / f"source_orientation_{label}.png", location)


def copy_weights(source, vertex_index):
    vertex = source.data.vertices[vertex_index]
    return {source.vertex_groups[item.group].name: item.weight for item in vertex.groups}


def bind_mesh(obj, weights):
    groups = {}
    for index, assignments in enumerate(weights):
        total = sum(assignments.values())
        if total <= 1e-8:
            assignments = {"mixamorig:Hips": 1.0}
            total = 1.0
        for name, value in assignments.items():
            group = groups.setdefault(name, obj.vertex_groups.get(name) or obj.vertex_groups.new(name=name))
            group.add([index], value / total, 'REPLACE')
    modifier = obj.modifiers.new("Preserved Mixamo deformation", 'ARMATURE')
    modifier.object = RIG
    obj.parent = RIG


def make_mesh(name, vertices, faces, mat, weights, solidify=0.0, bevel=0.0, subdiv=0):
    data = bpy.data.meshes.new(name)
    data.from_pydata(vertices, [], faces)
    data.update()
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat)
    for poly in obj.data.polygons:
        poly.use_smooth = True
    bind_mesh(obj, weights)
    if solidify:
        mod = obj.modifiers.new("Soft fabric thickness", 'SOLIDIFY')
        mod.thickness = solidify
        mod.offset = 0
    if bevel:
        mod = obj.modifiers.new("Soft tailored edge", 'BEVEL')
        mod.width = bevel
        mod.segments = 2
    if subdiv:
        mod = obj.modifiers.new("Soft cloth subdivision", 'SUBSURF')
        mod.levels = subdiv
        mod.render_levels = subdiv
    return obj


def surface_shell(source, name, predicate, mat, offset=.004, thickness=.002):
    selected = [poly for poly in source.data.polygons if predicate(poly.center, poly)]
    used = sorted({index for poly in selected for index in poly.vertices})
    remap = {old: new for new, old in enumerate(used)}
    vertices = []
    weights = []
    for old in used:
        vertex = source.data.vertices[old]
        vertices.append(tuple(vertex.co + vertex.normal * offset))
        weights.append(copy_weights(source, old))
    faces = [tuple(remap[index] for index in poly.vertices) for poly in selected]
    return make_mesh(name, vertices, faces, mat, weights, thickness, .0012)


def front_y(x, z, outward=.003):
    candidates = sorted(BODY.data.vertices,
                        key=lambda vertex: (vertex.co.x - x) ** 2 + (vertex.co.z - z) ** 2)[:24]
    return min(vertex.co.y for vertex in candidates) - outward


def torso_weights(z):
    if z < .92:
        return {"mixamorig:Hips": 1.0}
    if z < 1.10:
        amount = (z - .92) / .18
        return {"mixamorig:Hips": 1 - amount, "mixamorig:Spine": amount}
    if z < 1.28:
        amount = (z - 1.10) / .18
        return {"mixamorig:Spine": 1 - amount, "mixamorig:Spine1": amount}
    amount = min(1.0, max(0.0, (z - 1.28) / .17))
    return {"mixamorig:Spine1": 1 - amount, "mixamorig:Spine2": amount}


def fitted_ribbon(name, xz_path, widths, mat, outward=.003, thickness=.0025):
    vertices = []
    weights = []
    for index, (x, z) in enumerate(xz_path):
        current = Vector((x, 0, z))
        if index == 0:
            tangent = Vector((xz_path[1][0], 0, xz_path[1][1])) - current
        elif index == len(xz_path) - 1:
            tangent = current - Vector((xz_path[index - 1][0], 0, xz_path[index - 1][1]))
        else:
            tangent = Vector((xz_path[index + 1][0], 0, xz_path[index + 1][1])) - Vector((xz_path[index - 1][0], 0, xz_path[index - 1][1]))
        side = Vector((tangent.z, 0, -tangent.x)).normalized() * widths[index] * .5
        for sign in (-1, 1):
            point = current + side * sign
            point.y = front_y(point.x, point.z, outward)
            vertices.append(tuple(point))
            weights.append(torso_weights(point.z))
    faces = [(i * 2, i * 2 + 1, i * 2 + 3, i * 2 + 2) for i in range(len(xz_path) - 1)]
    return make_mesh(name, vertices, faces, mat, weights, thickness, .0015, 1)


def continuous_tunic():
    """A clean, slightly loose oval shell that suppresses bare torso anatomy."""
    rows = [(.865, .132, .073), (.980, .136, .076), (1.105, .142, .079),
            (1.230, .151, .084), (1.355, .163, .089), (1.430, .154, .078)]
    segments = 32
    vertices = []
    weights = []
    for z, radius_x, radius_y in rows:
        for index in range(segments):
            angle = math.tau * index / segments
            vertices.append((radius_x * math.sin(angle), radius_y * math.cos(angle), z))
            weights.append(torso_weights(z))
    faces = []
    for row in range(len(rows) - 1):
        for index in range(segments):
            nxt = (index + 1) % segments
            base = row * segments + index
            faces.append((base, row * segments + nxt, (row + 1) * segments + nxt,
                          (row + 1) * segments + index))
    return make_mesh("Moon-white continuous tailored tunic", vertices, faces, IVORY,
                     weights, .004, .002, 2)


def continuous_sleeve(side):
    """Closed narrow sleeve tube following the source T-pose arm axis."""
    sign = -1 if side == 'left' else 1
    rows = [(.145, .074, .076), (.255, .070, .071), (.410, .058, .061),
            (.565, .048, .052), (.690, .041, .045)]
    segments = 24
    vertices = []
    weights = []
    for row, (distance, radius_y, radius_z) in enumerate(rows):
        x = sign * distance
        for index in range(segments):
            angle = math.tau * index / segments
            vertices.append((x, radius_y * math.sin(angle), 1.370 + radius_z * math.cos(angle)))
            if distance < .25:
                assignments = {"mixamorig:Spine2": .20,
                               f"mixamorig:{'Left' if side == 'left' else 'Right'}Shoulder": .80}
            elif distance < .48:
                assignments = {f"mixamorig:{'Left' if side == 'left' else 'Right'}Arm": 1.0}
            else:
                assignments = {f"mixamorig:{'Left' if side == 'left' else 'Right'}ForeArm": 1.0}
            weights.append(assignments)
    faces = []
    for row in range(len(rows) - 1):
        for index in range(segments):
            nxt = (index + 1) % segments
            base = row * segments + index
            faces.append((base, row * segments + nxt, (row + 1) * segments + nxt,
                          (row + 1) * segments + index))
    return make_mesh(f"Blue continuous {side} narrow sleeve", vertices, faces, BLUE,
                     weights, .003, .0015, 2)


def clean_ellipse_band(name, z_low, z_high, radius_x, radius_y, mat):
    segments = 40
    vertices = []
    weights = []
    for z in (z_low, z_high):
        for index in range(segments):
            angle = math.tau * index / segments
            vertices.append((radius_x * math.sin(angle), radius_y * math.cos(angle), z))
            weights.append({"mixamorig:Hips": 1.0})
    faces = []
    for index in range(segments):
        nxt = (index + 1) % segments
        faces.append((index, nxt, segments + nxt, segments + index))
    return make_mesh(name, vertices, faces, mat, weights, .003, .002, 1)


def reassign_continuous_body_materials():
    """Use the mature continuous body as a gap-free fitted under-layer.

    This deliberately assigns complete source polygons instead of duplicating a
    polygon-center subset, so no shoulder/armpit/chest geometry can disappear.
    """
    skin_index = 0
    ivory_index = len(BODY.data.materials); BODY.data.materials.append(IVORY)
    blue_index = len(BODY.data.materials); BODY.data.materials.append(BLUE)
    deep_index = len(BODY.data.materials); BODY.data.materials.append(DEEP)
    for poly in BODY.data.polygons:
        center = poly.center
        # Keep hands and the neck skin visible; everything else is a continuous
        # fitted inner garment, trousers, or soft boot colour block.
        if center.z > 1.515 and abs(center.x) < .115:
            poly.material_index = skin_index
        elif center.z > 1.220 and abs(center.x) > .690:
            poly.material_index = skin_index
        elif center.z > .900:
            poly.material_index = ivory_index
        else:
            poly.material_index = deep_index


def arm_cuff(side):
    sign = -1 if side == 'left' else 1
    x_values = (sign * .665, sign * .705)
    segments = 24
    vertices = []
    weights = []
    forearm = f"mixamorig:{'Left' if side == 'left' else 'Right'}ForeArm"
    for x in x_values:
        for index in range(segments):
            angle = math.tau * index / segments
            vertices.append((x, .027 * math.sin(angle), 1.370 + .030 * math.cos(angle)))
            weights.append({forearm: 1.0})
    faces = []
    for index in range(segments):
        nxt = (index + 1) % segments
        faces.append((index, nxt, segments + nxt, segments + index))
    return make_mesh(f"Deep-blue complete {side} wrist cuff", vertices, faces, DEEP,
                     weights, .003, .0015, 1)


def short_outer_jacket():
    """Two clean blue jacket halves with a V opening, waist and armholes."""
    rows = [
        (.835, .142, .081, .10),
        (.925, .136, .078, .12),
        (1.090, .146, .083, .25),
        (1.260, .160, .089, .43),
        (1.390, .174, .092, .63),
    ]
    columns = 16
    vertices = []
    weights = []
    faces = []
    for half in ('right', 'left'):
        base_index = len(vertices)
        for z, radius_x, radius_y, gap in rows:
            start, end = ((0.0, math.pi - gap) if half == 'right' else (math.pi + gap, math.tau))
            for column in range(columns):
                t = column / (columns - 1)
                angle = start * (1 - t) + end * t
                vertices.append((radius_x * math.sin(angle), radius_y * math.cos(angle), z))
                weights.append(torso_weights(z))
        for row in range(len(rows) - 1):
            for column in range(columns - 1):
                a = base_index + row * columns + column
                faces.append((a, a + 1, a + 1 + columns, a + columns))
    obj = make_mesh("Blue fitted short outer jacket with V opening", vertices, faces, BLUE,
                    weights, .004, .002, 2)
    CLOTHING.append(obj)
    return obj


def short_cap_sleeve(side):
    """A complete short sleeve grown from the jacket armhole, not a ring."""
    sign = -1 if side == 'left' else 1
    rows = [(.135, .071, .073), (.205, .068, .070), (.275, .061, .064)]
    segments = 24
    vertices = []
    weights = []
    shoulder = f"mixamorig:{'Left' if side == 'left' else 'Right'}Shoulder"
    upper = f"mixamorig:{'Left' if side == 'left' else 'Right'}Arm"
    for row, (distance, radius_y, radius_z) in enumerate(rows):
        x = sign * distance
        for index in range(segments):
            angle = math.tau * index / segments
            vertices.append((x, radius_y * math.sin(angle), 1.370 + radius_z * math.cos(angle)))
            blend = row / (len(rows) - 1)
            weights.append({shoulder: 1 - blend, upper: blend})
    faces = []
    for row in range(len(rows) - 1):
        for index in range(segments):
            nxt = (index + 1) % segments
            a = row * segments + index
            faces.append((a, row * segments + nxt, (row + 1) * segments + nxt,
                          (row + 1) * segments + index))
    obj = make_mesh(f"Blue continuous {side} jacket cap sleeve", vertices, faces, BLUE,
                    weights, .003, .0015, 2)
    CLOTHING.append(obj)
    return obj


def robe_panel(name, side, front, mat, outer=False):
    sign_x = -1 if side == 'left' else 1
    sign_y = -1 if front else 1
    rows = [(.855, .025, .133), (.805, .030, .142), (.755, .038, .150),
            ((.695 if front else .660), .050, .157)]
    vertices = []
    weights = []
    columns = 5
    for row_index, (z, inner, outer_x) in enumerate(rows):
        progress = row_index / (len(rows) - 1)
        for column in range(columns):
            t = column / (columns - 1)
            x = sign_x * (inner * (1 - t) + outer_x * t)
            base_y = front_y(x, .90, .004) if front else -front_y(x, .90, .004)
            y = sign_y * (abs(base_y) + .006 + progress * (.020 if front else .028))
            z_here = z - .018 * math.sin(math.pi * t) - .009 * progress * t
            vertices.append((x, y, z_here))
            leg = "mixamorig:LeftUpLeg" if sign_x < 0 else "mixamorig:RightUpLeg"
            blend = progress * .66
            weights.append({"mixamorig:Hips": 1 - blend, leg: blend})
    faces = []
    for row in range(len(rows) - 1):
        for column in range(columns - 1):
            base = row * columns + column
            faces.append((base, base + 1, base + 1 + columns, base + columns))
    obj = make_mesh(name, vertices, faces, mat, weights, .004, .002, 2)
    CLOTHING.append(obj)
    return obj


def ellipsoid(name, location, scale, mat, bone):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=28, ring_count=14, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(mat)
    for poly in obj.data.polygons:
        poly.use_smooth = True
    bind_mesh(obj, [{bone: 1.0} for _ in obj.data.vertices])
    return obj


def hair_bundle(name, center_x, width, z_end, sway, depth):
    rows = [(1.695, .060, width * .34), (1.610, .102, width * .98),
            (1.500, .138, width * .90), (1.390, .155, width * .72),
            (z_end, depth, width * .18)]
    vertices = []
    columns = 3
    for row, (z, y, row_width) in enumerate(rows):
        progress = row / (len(rows) - 1)
        center = center_x * progress ** .62 + sway * progress ** 1.45
        for column in range(columns):
            t = column / (columns - 1)
            x = center + (t - .5) * row_width
            # Convex cross-section: center sits farther back than edges.
            y_here = y + .009 * math.sin(math.pi * t)
            vertices.append((x, y_here, z - .010 * math.sin(math.pi * t)))
    faces = []
    for row in range(len(rows) - 1):
        for column in range(columns - 1):
            base = row * columns + column
            faces.append((base, base + 1, base + 1 + columns, base + columns))
    return make_mesh(name, vertices, faces, HAIR,
                     [{"mixamorig:Head": 1.0}] * len(vertices), .006, .0025, 2)


def build_character():
    global RIG, BODY, HEAD
    RIG = bpy.data.objects['Armature']
    BODY = bpy.data.objects['model_0_submesh_4']
    HEAD = bpy.data.objects['model_0_submesh_1']
    hide_rig_controls()
    smooth_all()

    # The source body itself is the gap-free moon-white inner shirt and fitted
    # trousers.  Iteration 04 adds a separate short blue jacket over it.
    reassign_continuous_body_materials()
    short_outer_jacket()
    short_cap_sleeve('left')
    short_cap_sleeve('right')
    CLOTHING.append(clean_ellipse_band("Deep-blue continuous waist sash", .835, .895, .169, .102, DEEP))
    CLOTHING.append(clean_ellipse_band("Clear-blue upper sash trim", .882, .904, .172, .104, BLUE))

    # Inner moon-white collar plus two independently modeled blue lapels.  The
    # right lapel is 3 mm farther out so its overlap is unambiguous.
    CLOTHING.append(fitted_ribbon("Moon-white inner collar right",
                  [(-.070, 1.455), (-.044, 1.410), (-.015, 1.360), (.010, 1.315)],
                  [.026, .028, .029, .023], IVORY, .008))
    CLOTHING.append(fitted_ribbon("Moon-white inner collar left",
                  [(.070, 1.455), (.044, 1.410), (.015, 1.360), (-.010, 1.315)],
                  [.027, .029, .030, .024], IVORY, .010))
    CLOTHING.append(fitted_ribbon("Blue left under-lapel",
                  [(-.078, 1.440), (-.045, 1.360), (.005, 1.245), (.060, 1.110), (.105, .950)],
                  [.045, .047, .050, .047, .034], BLUE, .013, .004))
    CLOTHING.append(fitted_ribbon("Blue right over-lapel",
                  [(.078, 1.440), (.045, 1.360), (-.005, 1.245), (-.060, 1.110), (-.105, .950)],
                  [.047, .050, .052, .049, .036], BLUE, .016, .004))

    robe_panel("Blue continuous front-left short skirt", 'left', True, BLUE)
    robe_panel("Blue continuous front-right short skirt", 'right', True, BLUE)
    robe_panel("Blue continuous rear-left short skirt", 'left', False, BLUE)
    robe_panel("Blue continuous rear-right short skirt", 'right', False, BLUE)

    clasp_y = -.108
    CLOTHING.append(ellipsoid("Small jade waist clasp", (0, clasp_y, .866), (.022, .009, .015), JADE, "mixamorig:Hips"))
    CLOTHING.append(ellipsoid("Restrained warm-gold clasp inset", (0, clasp_y - .006, .866), (.007, .004, .007), GOLD, "mixamorig:Hips"))

    # Gentle anime-youth pass: eye/brow feature mesh +5%, flatter brow angle,
    # and slightly softened front nose/jaw projection.  Topology is unchanged.
    features = bpy.data.objects['model_0_submesh_2']
    center_z = sum(vertex.co.z for vertex in features.data.vertices) / len(features.data.vertices)
    for vertex in features.data.vertices:
        vertex.co.x *= 1.05
        vertex.co.z = center_z + (vertex.co.z - center_z) * .86
    features.data.update()
    for vertex in HEAD.data.vertices:
        if vertex.co.y < -.045 and vertex.co.z < 1.640:
            vertex.co.y *= .965
            if vertex.co.z < 1.590:
                vertex.co.x *= .985
    HEAD.data.update()

    # Fitted scalp uses the authored anime head; five curved bundles leave a
    # deliberate gap from the back for later motion and auxiliary hair bones.
    surface_shell(HEAD, "Fitted ink-black scalp",
                  lambda c, p: c.z > 1.665 or c.y > .020 or (c.z > 1.605 and abs(c.x) > .060),
                  HAIR, .004, .002)
    for args in [
        ("Far-left curved hair lock", -.070, .050, 1.275, -.018, .160),
        ("Left curved hair lock", -.038, .058, 1.230, -.010, .172),
        ("Center curved hair lock", 0, .062, 1.185, .005, .180),
        ("Right curved hair lock", .040, .056, 1.245, .014, .170),
        ("Far-right curved hair lock", .072, .046, 1.300, .022, .158),
    ]:
        hair_bundle(*args)
    # Asymmetric, volumetric fringe wedges close to the forehead.
    make_mesh("Asymmetric left forehead fringe",
              [(-.073, -.080, 1.718), (.005, -.083, 1.708), (-.010, -.085, 1.625),
               (-.060, -.082, 1.660), (-.050, -.067, 1.720), (-.004, -.070, 1.704)],
              [(0, 1, 2, 3), (0, 4, 5, 1), (1, 5, 2), (0, 3, 4)], HAIR,
              [{"mixamorig:Head": 1.0}] * 6, .002, .0015, 1)
    make_mesh("Fine right forehead fringe",
              [(.006, -.082, 1.708), (.060, -.078, 1.700), (.048, -.082, 1.650),
               (.020, -.084, 1.675), (.014, -.067, 1.704), (.052, -.065, 1.696)],
              [(0, 1, 2, 3), (0, 4, 5, 1), (1, 5, 2), (0, 3, 4)], HAIR,
              [{"mixamorig:Head": 1.0}] * 6, .002, .0015, 1)
    ellipsoid("Half-up gathered hair", (0, .050, 1.715), (.040, .032, .028), HAIR, "mixamorig:Head")
    ellipsoid("Small jade half-crown", (0, .025, 1.744), (.025, .017, .015), JADE, "mixamorig:Head")


def render_final_views(directory, prefix):
    views = {
        "front": (0, -5.0, .92), "three_quarter": (-3.6, -3.6, .96),
        "side": (-5.0, 0, .92), "back": (0, 5.0, .92),
    }
    for label, location in views.items():
        render(directory / f"{prefix}_{label}.png", location)
        render(directory / f"{prefix}_grey_{label}.png", location, grey=True)


def render_added_clothing_check():
    states = {obj: obj.hide_render for obj in bpy.data.objects if obj.type == 'MESH'}
    for obj in states:
        if obj.name == "V5 neutral review ground":
            continue
        obj.hide_render = obj not in CLOTHING
    render(OUT / "cultivator_handsome_youth_v5_anime_only_added_clothing_grey.png",
           (0, -5.0, .92), grey=True)
    for obj, state in states.items():
        obj.hide_render = state


def set_natural_idle():
    """Lower both arms in armature space for a static silhouette proof."""
    muted = {}
    for name, angle in [
        ("mixamorig:LeftArm", math.radians(72)),
        ("mixamorig:RightArm", math.radians(-72)),
    ]:
        pose_bone = RIG.pose.bones[name]
        muted[name] = [constraint.mute for constraint in pose_bone.constraints]
        for constraint in pose_bone.constraints:
            constraint.mute = True
        pose_bone.rotation_mode = 'XYZ'
        pose_bone.rotation_euler = (0, 0, angle)
    bpy.context.view_layer.update()
    return muted


def clear_natural_idle(muted):
    for pose_bone in RIG.pose.bones:
        pose_bone.matrix_basis.identity()
    for name, states in muted.items():
        for constraint, state in zip(RIG.pose.bones[name].constraints, states):
            constraint.mute = state
    bpy.context.view_layer.update()


def render_idle_evidence():
    muted = set_natural_idle()
    render(OUT / "cultivator_handsome_youth_v5_anime_idle_front.png", (0, -5.0, .92))
    render(OUT / "cultivator_handsome_youth_v5_anime_idle_three_quarter.png", (-3.6, -3.6, .96))
    render(OUT / "cultivator_handsome_youth_v5_anime_idle_back.png", (0, 5.0, .92))
    render(OUT / "cultivator_handsome_youth_v5_anime_2p5d_size6.png",
           (0, -8.0, .92), ortho=6.0, width=1280, height=720)
    render(OUT / "cultivator_handsome_youth_v5_anime_2p5d_size18.png",
           (0, -18.0, .92), ortho=18.0, width=1280, height=720)
    clear_natural_idle(muted)


def export_glb():
    adapter = bpy.data.objects.new("GodotFrontAdapter_-Z", None)
    bpy.context.collection.objects.link(adapter)
    adapter.rotation_euler[2] = math.pi
    RIG.parent = adapter
    bpy.ops.object.select_all(action='DESELECT')
    adapter.select_set(True)
    RIG.select_set(True)
    for obj in bpy.data.objects:
        if obj.type == 'MESH' and len(obj.data.polygons) > 0 and obj.name != "V5 neutral review ground":
            if obj.name.startswith("model_0_submesh_") or obj.parent == RIG or any(m.type == 'ARMATURE' and m.object == RIG for m in obj.modifiers):
                obj.select_set(True)
    bpy.context.view_layer.objects.active = RIG
    bpy.ops.export_scene.gltf(filepath=str(GLB), export_format='GLB', use_selection=True,
                              export_skins=True, export_animations=False, export_apply=False)
    RIG.parent = None
    bpy.data.objects.remove(adapter, do_unlink=True)


def audit_and_write():
    meshes = [obj for obj in bpy.data.objects if obj.type == 'MESH' and len(obj.data.polygons) > 0
              and obj.name != "V5 neutral review ground" and not obj.hide_render]
    weight_audit = []
    for obj in meshes:
        if not (obj.name.startswith("model_0_submesh_") or obj.parent == RIG or any(m.type == 'ARMATURE' and m.object == RIG for m in obj.modifiers)):
            continue
        empty = sum(1 for vertex in obj.data.vertices if sum(item.weight for item in vertex.groups) < .999)
        weight_audit.append({"object": obj.name, "vertices": len(obj.data.vertices),
                             "vertices_below_weight_0_999": empty})
    bones = [bone.name for bone in RIG.data.bones]
    deform = [bone.name for bone in RIG.data.bones if bone.use_deform]
    manifest = {
        "source": {
            "title": "Generic Anime Male", "author": "jonshipman",
            "sketchfab_uid": "f119e8cddf8c4bca9666a885975f9245",
            "license": "CC-BY-4.0", "download_date": "2026-09-19",
            "sha256": hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
            "api_claimed_triangles": 15020, "api_claimed_vertices": 7811,
            "api_claimed_materials": 4, "api_claimed_textures": 4,
        },
        "source_audit": {
            "character_meshes": 4,
            "packed_image_blocks": len([image for image in bpy.data.images if image.packed_file]),
            "source_blender_front": "-Y (verified by eyes, nose, chest and toes)",
        },
        "orientation": {
            "blender_character_front": "-Y",
            "godot_glb_character_front": "-Z",
            "export_contract": "180-degree Z adapter is applied only at GLB export",
        },
        "armature": {
            "name": RIG.name, "bone_count_total": len(bones),
            "deform_bone_count": len(deform), "deform_bones": deform,
            "mixamo_core_present": all(name in bones for name in [
                "mixamorig:Hips", "mixamorig:Spine", "mixamorig:Head",
                "mixamorig:LeftArm", "mixamorig:RightArm",
                "mixamorig:LeftUpLeg", "mixamorig:RightUpLeg"]),
            "rest_pose_preserved": True,
        },
        "weights": {"mesh_audit": weight_audit,
                    "objects_with_incomplete_weights": [entry["object"] for entry in weight_audit if entry["vertices_below_weight_0_999"]]},
        "art_review": {
            "status": "v5 iteration 04 rework awaiting independent rereview",
            "real_animation_tested": False,
            "technical_pass_is_not_visual_pass": True,
            "static_idle_pose_rendered": True,
            "only_added_clothing_grey_rendered": True,
            "hair_auxiliary_bones": "not yet added; five separated curve surfaces retained for a 2-3 segment auxiliary chain next stage",
        },
    }
    files = sorted(path for path in OUT.rglob('*') if path.is_file())
    manifest["file_sha256"] = {str(path.relative_to(OUT)): hashlib.sha256(path.read_bytes()).hexdigest() for path in files}
    (OUT / "build_manifest.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    ledger = f"""# 英俊少年修士 v5（Generic Anime Male）资产台账

日期：2026-09-19

## 来源与许可

- 原作者：jonshipman；资产名：Generic Anime Male。
- Sketchfab UID：`f119e8cddf8c4bca9666a885975f9245`。
- 资产页：https://sketchfab.com/3d-models/generic-anime-male-f119e8cddf8c4bca9666a885975f9245
- 作者页：https://sketchfab.com/jonshipman
- 许可：CC-BY 4.0，https://creativecommons.org/licenses/by/4.0/
- 下载来源：作者在资产页描述中直接提供的 Google Drive 链接；下载日期 2026-09-19。
- 未改原件：`source/generic_anime_male_original.blend`；SHA-256 `{manifest['source']['sha256']}`。
- 官方 v3 API 核验值：15,020 tris、7,811 verts、4 materials、4 textures、可下载；描述为 `Base anime male with Mixamo bones`。

## 本轮改造

连续 body 直接作为无裂缝的月白内衫和深蓝裤靴；独立青蓝短外衫由左右 V 形前开片、背片与完整短袖构成，具有肩线、袖窿和收腰，长度止于自然腰下。左右交领分别建模，右片以额外 3 mm 外偏明确压住左片。腰下仅保留前左、前右、后左、后右四片短摆，根部接入外衫/腰封、正中和侧面留动作开口。所有旧腕环、肩环和单根斜蓝带均已删除。

头发由贴头皮壳、束发根、两束不遮眼前发和五束从同一束发点扇出的弧形后发组成。五束目前仍绑定 Head，但保留独立曲面和拓扑；下一真实动作阶段增加 2–3 段辅助发骨链，当前 manifest 明确记录未完成。

## 工程状态

源文件有 168 骨（含 Mixamo 变形骨与作者控制骨），所有四个角色子网格均有 Armature modifier 和权重；打包图像块数量见 manifest。Blender 正面经眼、鼻、胸与脚尖核验为 `-Y`；GLB 导出用独立 180° 根适配到 Godot `-Z`。

iteration 01、surface-shell debug、iteration 02 与 Reviewer 55/100 的 iteration 03 均完整保留；当前主输出为 iteration 04 返工稿。除 T pose 彩色/灰模四视图外，已输出自然垂臂 idle 正面/三分之四/背面、2.5D size18/size6 与 only-added-clothing 灰模。未上传 Mixamo、未跑真实 walk/run/jump，也未通过复审；技术审计不得冒充审美通过。
"""
    (OUT / "asset_ledger.md").write_text(ledger, encoding="utf-8")
    print(json.dumps(manifest, indent=2, ensure_ascii=False))


def main():
    if "--source-preview" in sys.argv:
        source_preview()
        return
    OUT.mkdir(parents=True, exist_ok=True)
    ITER.mkdir(parents=True, exist_ok=True)
    build_character()
    setup_render()
    bpy.ops.wm.save_as_mainfile(filepath=str(ITER / "cultivator_handsome_youth_v5_anime_iteration_04.blend"), compress=True)
    render_final_views(ITER, "cultivator_handsome_youth_v5_anime_iteration_04")
    render_final_views(OUT, "cultivator_handsome_youth_v5_anime")
    render_added_clothing_check()
    render_idle_evidence()
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND), compress=True)
    export_glb()
    audit_and_write()


if __name__ == "__main__":
    main()
