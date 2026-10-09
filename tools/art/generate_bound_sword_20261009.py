#!/usr/bin/env python3
"""Generate the hovering bound sword and the simplified sword-array sword.

Both share the palette of the riding sword (`generate_mountain_realm.py`, stage
`sword`): steel blade, aged-bronze guard, wrapped grip. The riding sword is a
1.8 m standing platform and is not touched here.

Conventions after glTF export (Y up): the tip points along local -Z, the
origin is the centre of the guard, the broad face of the blade faces local +Y
so a level sword reads as a blade from the top-down camera.

Blender --background --factory-startup --python-exit-code 1 \\
    --python tools/art/generate_bound_sword_20261009.py
"""

from __future__ import annotations

import json
import math
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
ART = ROOT / "docs/art/bound_sword_20261009"
COMPANION_GLB = ROOT / "src/game/shared/sword_cast/models/bound_sword.glb"
ARRAY_GLB = ROOT / "src/game/abilities/sword_array/models/array_sword.glb"

# Blender axes: +Y becomes glTF -Z (the tip), +Z becomes glTF +Y.
BLADE_START = 0.02
BLADE_END = 0.66
TIP_END = 0.78
BLADE_WIDTH = (0.050, 0.040)
BLADE_THICKNESS = 0.012
GUARD_SIZE = (0.15, 0.035, 0.035)
GRIP_LENGTH = 0.15
GRIP_RADIUS = 0.016
POMMEL_RADIUS = 0.024


def material(name: str, color: tuple, roughness: float, metallic: float,
             emission: tuple | None = None) -> bpy.types.Material:
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    if emission:
        bsdf.inputs["Emission Color"].default_value = (*emission, 1.0)
        bsdf.inputs["Emission Strength"].default_value = 1.0
    return mat


def blade_mesh(bm: bmesh.types.BMesh, scale: float, sections: int) -> None:
    """Diamond cross-section blade tapering to a point."""
    rings = []
    for index in range(sections + 1):
        t = index / sections
        y = (BLADE_START + (BLADE_END - BLADE_START) * t) * scale
        half_w = (BLADE_WIDTH[0] + (BLADE_WIDTH[1] - BLADE_WIDTH[0]) * t) * 0.5 * scale
        half_t = BLADE_THICKNESS * 0.5 * scale
        rings.append([bm.verts.new((half_w, y, 0.0)), bm.verts.new((0.0, y, half_t)),
                      bm.verts.new((-half_w, y, 0.0)), bm.verts.new((0.0, y, -half_t))])
    for a, b in zip(rings, rings[1:]):
        for k in range(4):
            bm.faces.new((a[k], a[(k + 1) % 4], b[(k + 1) % 4], b[k]))
    apex = bm.verts.new((0.0, TIP_END * scale, 0.0))
    last = rings[-1]
    for k in range(4):
        bm.faces.new((last[k], last[(k + 1) % 4], apex))
    bm.faces.new(tuple(reversed(rings[0])))


def box(bm: bmesh.types.BMesh, center: tuple, size: tuple) -> None:
    result = bmesh.ops.create_cube(bm, size=1.0)
    for vert in result["verts"]:
        vert.co = Vector((vert.co.x * size[0] + center[0], vert.co.y * size[1] + center[1],
                          vert.co.z * size[2] + center[2]))


def cylinder_y(bm: bmesh.types.BMesh, y0: float, y1: float, radius: float, segments: int) -> None:
    bottom, top = [], []
    for k in range(segments):
        angle = 2.0 * math.pi * k / segments
        x, z = radius * math.cos(angle), radius * math.sin(angle)
        bottom.append(bm.verts.new((x, y0, z)))
        top.append(bm.verts.new((x, y1, z)))
    for k in range(segments):
        bm.faces.new((bottom[k], bottom[(k + 1) % segments], top[(k + 1) % segments], top[k]))
    bm.faces.new(tuple(reversed(bottom)))
    bm.faces.new(tuple(top))


def octahedron(bm: bmesh.types.BMesh, center: tuple, radius: float) -> None:
    cx, cy, cz = center
    points = [bm.verts.new((cx + dx * radius, cy + dy * radius, cz + dz * radius))
              for dx, dy, dz in ((1, 0, 0), (0, 1, 0), (-1, 0, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1))]
    ring = points[:4]
    for k in range(4):
        bm.faces.new((ring[k], ring[(k + 1) % 4], points[4]))
        bm.faces.new((ring[(k + 1) % 4], ring[k], points[5]))


def part(name: str, build, mat: bpy.types.Material) -> bpy.types.Object:
    bm = bmesh.new()
    build(bm)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    for poly in mesh.polygons:
        poly.use_smooth = False
    mesh.materials.append(mat)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def join(objects: list[bpy.types.Object], name: str) -> bpy.types.Object:
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    joined = bpy.context.view_layer.objects.active
    joined.name = name
    joined.data.name = name
    return joined


def export(obj: bpy.types.Object, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.export_scene.gltf(filepath=str(path), export_format="GLB", use_selection=True,
                              export_yup=True, export_apply=True, export_materials="EXPORT",
                              export_animations=False)


def stats(obj: bpy.types.Object) -> dict:
    mesh = obj.data
    mesh.calc_loop_triangles()
    points = [obj.matrix_world @ v.co for v in mesh.vertices]
    low = [min(p[i] for p in points) for i in range(3)]
    high = [max(p[i] for p in points) for i in range(3)]
    return {
        "triangles": len(mesh.loop_triangles),
        "materials": [m.name for m in mesh.materials],
        # Reported in glTF axes: x, y (up), z (tip at negative z).
        "bounds_gltf_m": {
            "x": [round(low[0], 4), round(high[0], 4)],
            "y": [round(low[2], 4), round(high[2], 4)],
            "z": [round(-high[1], 4), round(-low[1], 4)],
        },
    }


def main() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    steel = material("Bound blade steel", (0.62, 0.66, 0.68), 0.32, 0.85)
    bronze = material("Bound aged bronze", (0.51, 0.34, 0.09), 0.42, 0.35)
    wrap = material("Bound hilt wrap", (0.58, 0.52, 0.36), 0.8, 0.0)
    jade = material("Array jade steel", (0.70, 0.82, 0.78), 0.3, 0.6, emission=(0.10, 0.28, 0.24))

    companion = join([
        part("Blade", lambda bm: blade_mesh(bm, 1.0, 4), steel),
        part("Guard", lambda bm: box(bm, (0.0, 0.0, 0.0), GUARD_SIZE), bronze),
        part("Grip", lambda bm: cylinder_y(bm, -0.0175, -0.0175 - GRIP_LENGTH, GRIP_RADIUS, 8), wrap),
        part("Pommel", lambda bm: octahedron(bm, (0.0, -0.0175 - GRIP_LENGTH - POMMEL_RADIUS * 0.7, 0.0),
                                             POMMEL_RADIUS), bronze),
    ], "BoundSword")
    array = join([
        part("ArrayBlade", lambda bm: blade_mesh(bm, 0.9, 1), jade),
        part("ArrayGuard", lambda bm: box(bm, (0.0, 0.0, 0.0), (0.12, 0.03, 0.03)), jade),
        part("ArrayGrip", lambda bm: box(bm, (0.0, -0.085, 0.0), (0.026, 0.14, 0.026)), jade),
    ], "ArraySword")

    bpy.context.view_layer.update()
    report = {"bound_sword": stats(companion), "array_sword": stats(array)}
    export(companion, COMPANION_GLB)
    export(array, ARRAY_GLB)
    # Side by side only for the preview and the saved source.
    array.location.x = 0.4
    bpy.context.view_layer.update()

    ART.mkdir(parents=True, exist_ok=True)
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=str(ART / "bound_sword_20261009.blend"))
    render_preview(companion, array)
    (ART / "build_report.json").write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n")
    print(json.dumps(report, indent=2))


def render_preview(companion: bpy.types.Object, array: bpy.types.Object) -> None:
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 900
    scene.render.resolution_y = 520
    scene.render.film_transparent = False
    scene.world = bpy.data.worlds.new("SwordStudio")
    scene.world.color = (0.22, 0.22, 0.23)
    scene.view_settings.view_transform = "AgX"
    camera_data = bpy.data.cameras.new("SwordCamera")
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = 1.2
    camera = bpy.data.objects.new("SwordCamera", camera_data)
    scene.collection.objects.link(camera)
    scene.camera = camera
    # Straight down with the blades running left to right.
    camera.location = (0.2, 0.29, 2.0)
    camera.rotation_euler = (0.0, 0.0, math.radians(90))
    for name, location, energy in (("Key", (-1.0, -0.5, 2.0), 40), ("Fill", (1.2, 1.0, 1.5), 20)):
        data = bpy.data.lights.new(name, type="AREA")
        data.energy = energy
        data.size = 2.0
        light = bpy.data.objects.new(name, data)
        scene.collection.objects.link(light)
        light.location = location
        light.rotation_euler = (Vector((0.2, 0.3, 0.0)) - Vector(location)).to_track_quat("-Z", "Y").to_euler()
    scene.render.filepath = str(ART / "preview.png")
    bpy.ops.render.render(write_still=True)


if __name__ == "__main__":
    main()
