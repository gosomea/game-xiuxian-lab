#!/usr/bin/env python3
"""Blender CLI: create a linked motion source or export its animation-only GLB.

Blender --background --factory-startup --python-exit-code 1 --python
tools/art/cultivator_motion_assets.py -- create-source --shared-source base.blend
--output motion.blend

Use export --source motion.blend --shared-model base.glb --output motion.glb
after editing actions in the linked source. Existing exploration files are never
overwritten unless --replace explicitly names a continuation of that same asset.
"""

from __future__ import annotations

import argparse
import copy
import json
import math
import sys
from pathlib import Path

import bpy

sys.path.insert(0, str(Path(__file__).parent))
from apply_per_clip_ground_offset import read_glb, write_glb
from export_cultivator_aligned_motion_20260927 import CLIPS
from split_cultivator_motion_glb import configure_animation_import


def create_source(shared: Path, output: Path) -> dict:
    bpy.ops.wm.open_mainfile(filepath=str(shared))
    rig = next(obj for obj in bpy.data.objects if obj.type == "ARMATURE")
    meshes = [obj for obj in bpy.data.objects if obj.type == "MESH"
              and any(mod.type == "ARMATURE" for mod in obj.modifiers)]
    if len(meshes) != 1:
        raise ValueError("expected one skinned mesh")
    mesh = meshes[0]
    rig_name, mesh_name, data_name = rig.name, mesh.name, mesh.data.name
    basis = mesh.matrix_basis.copy()
    parent_inverse = mesh.matrix_parent_inverse.copy()
    bpy.context.view_layer.update()
    evaluated = mesh.evaluated_get(bpy.context.evaluated_depsgraph_get())
    original_ground = min((evaluated.matrix_world @ vertex.co).z for vertex in evaluated.data.vertices)
    groups = [group.name for group in mesh.vertex_groups]
    preserve_volume = next(mod.use_deform_preserve_volume for mod in mesh.modifiers if mod.type == "ARMATURE")
    fps, fps_base = bpy.context.scene.render.fps, bpy.context.scene.render.fps_base
    action_names = sorted(action.name for action in bpy.data.actions)
    if set(action_names) != CLIPS:
        raise ValueError(f"expected seven clips, got {action_names}")

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version = 0
    with bpy.data.libraries.load(str(shared), link=False) as (_available, data):
        data.objects = [rig_name]
        data.actions = action_names
    rig = data.objects[0]
    bpy.context.scene.collection.objects.link(rig)
    for action in data.actions:
        action.use_fake_user = True
    with bpy.data.libraries.load(str(shared), link=True) as (_available, linked):
        linked.meshes = [data_name]
    mesh = bpy.data.objects.new(mesh_name, linked.meshes[0])
    bpy.context.scene.collection.objects.link(mesh)
    mesh.parent = rig
    mesh.matrix_parent_inverse = parent_inverse
    mesh.matrix_basis = basis
    for name in groups:
        mesh.vertex_groups.new(name=name)
    modifier = mesh.modifiers.new("Armature", "ARMATURE")
    modifier.object = rig
    modifier.use_deform_preserve_volume = preserve_volume
    rig.animation_data_create()
    rig.animation_data.action = bpy.data.actions["idle"]
    bpy.context.scene.render.fps = fps
    bpy.context.scene.render.fps_base = fps_base
    bpy.context.scene.frame_start = 0
    bpy.context.scene.frame_end = int(bpy.data.actions["idle"].frame_range[1])
    bpy.context.scene.frame_set(0)
    bpy.context.view_layer.update()
    evaluated = mesh.evaluated_get(bpy.context.evaluated_depsgraph_get())
    linked_ground = min((evaluated.matrix_world @ vertex.co).z for vertex in evaluated.data.vertices)
    if abs(linked_ground - original_ground) > 0.00001:
        raise ValueError("linked source changed the standing skinned geometry")
    bpy.context.view_layer.objects.active = rig
    rig.select_set(True)
    output.parent.mkdir(parents=True, exist_ok=True)
    # Save first with an absolute library path, then use a relative path whose
    # base is the actual new source directory. Both saves continue this asset.
    bpy.ops.wm.save_as_mainfile(filepath=str(output))
    mesh.data.library.filepath = bpy.path.relpath(str(shared), start=str(output.parent))
    bpy.ops.wm.save_as_mainfile(filepath=str(output))
    return {"source": str(shared), "output": str(output), "bytes": output.stat().st_size,
            "linked_mesh": mesh.data.name, "library": mesh.data.library.filepath,
            "clips": sorted(action.name for action in bpy.data.actions),
            "local_images": len([image for image in bpy.data.images if image.library is None]),
            "bones": len(rig.data.bones), "standing_sole_m": linked_ground,
            "standing_sole_matches_shared_source": True}


def node_contract(doc: dict) -> dict:
    parents = {child: i for i, node in enumerate(doc["nodes"]) for child in node.get("children", [])}
    required = {i for i, node in enumerate(doc["nodes"]) if node.get("name", "").startswith("mixamorig:")}
    # The armature object transform affects every bone too; validate all ancestors.
    for bone in list(required):
        while bone in parents:
            bone = parents[bone]
            required.add(bone)
    return {doc["nodes"][i]["name"]: (doc["nodes"][parents[i]]["name"] if i in parents else None,
            doc["nodes"][i].get("translation", [0, 0, 0]),
            doc["nodes"][i].get("rotation", [0, 0, 0, 1]), doc["nodes"][i].get("scale", [1, 1, 1]))
            for i in required}


def export_motion(source: Path, shared_model: Path, output: Path) -> dict:
    bpy.ops.wm.open_mainfile(filepath=str(source))
    rig = next(obj for obj in bpy.data.objects if obj.type == "ARMATURE")
    if set(action.name for action in bpy.data.actions) != CLIPS:
        raise ValueError("motion source must contain the seven registered clips")
    if not any(obj.type == "MESH" and obj.data.library is not None for obj in bpy.data.objects):
        raise ValueError("motion source must reference its shared mesh library")
    bpy.ops.object.select_all(action="DESELECT")
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    output.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=str(output), export_format="GLB", use_selection=True,
                              export_animation_mode="ACTIONS", export_animations=True,
                              export_skins=True, export_yup=True, export_apply=False,
                              export_materials="NONE", export_frame_range=False,
                              export_force_sampling=True, export_bake_animation=False)
    doc, blob = read_glb(output)
    shared, shared_blob = read_glb(shared_model)
    if any(doc.get(key) for key in ("meshes", "materials", "textures", "images")):
        raise ValueError("animation export unexpectedly contains geometry or images")
    expected, actual = node_contract(shared), node_contract(doc)
    if expected.keys() != actual.keys():
        raise ValueError("exported bones differ from the shared model")
    for name, reference in expected.items():
        candidate = actual[name]
        if reference[0] != candidate[0] or any(not math.isclose(a, b, abs_tol=1e-5)
                for ref, value in zip(reference[1:], candidate[1:]) for a, b in zip(ref, value)):
            raise ValueError(f"shared rest/hierarchy differs at {name}; use a new shared model version")
    # Blender's armature-only glTF has no skin consumer. Retain the shared skin
    # declaration so Godot recognizes the same Skeleton3D and track paths.
    node_ids = {node["name"]: i for i, node in enumerate(doc["nodes"])}
    payload = bytearray(blob[:doc["buffers"][0]["byteLength"]])
    skins = []
    for shared_skin in shared["skins"]:
        skin = copy.deepcopy(shared_skin)
        skin["joints"] = [node_ids[shared["nodes"][i]["name"]] for i in skin["joints"]]
        if "skeleton" in skin:
            skin["skeleton"] = node_ids[shared["nodes"][skin["skeleton"]]["name"]]
        accessor = copy.deepcopy(shared["accessors"][skin["inverseBindMatrices"]])
        view = copy.deepcopy(shared["bufferViews"][accessor["bufferView"]])
        start = view.get("byteOffset", 0)
        payload.extend(b"\0" * (-len(payload) % 4))
        view["buffer"] = 0
        view["byteOffset"] = len(payload)
        payload.extend(shared_blob[start:start + view["byteLength"]])
        accessor["bufferView"] = len(doc["bufferViews"])
        doc["bufferViews"].append(view)
        skin["inverseBindMatrices"] = len(doc["accessors"])
        doc["accessors"].append(accessor)
        skins.append(skin)
    doc["skins"] = skins
    doc["buffers"][0]["byteLength"] = len(payload)
    write_glb(output, doc, bytes(payload))
    configure_animation_import(output)
    return {"source": str(source), "shared_model": str(shared_model), "output": str(output),
            "bytes": output.stat().st_size, "bones": sum(name.startswith("mixamorig:") for name in actual),
            "clips": sorted(a["name"] for a in doc["animations"]), "rest_contract_matches": True}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("operation", choices=("create-source", "export"))
    parser.add_argument("--source", type=Path)
    parser.add_argument("--shared-source", type=Path)
    parser.add_argument("--shared-model", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--report", type=Path)
    parser.add_argument("--replace", action="store_true")
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
    args.output = args.output.resolve()
    inputs = [p.resolve() for p in (args.source, args.shared_source, args.shared_model) if p]
    if args.output in inputs or args.output.exists() and not args.replace:
        raise ValueError("output already exists or aliases an input; use a new version path")
    if args.operation == "create-source":
        if not args.shared_source:
            parser.error("create-source requires --shared-source")
        report = create_source(args.shared_source.resolve(), args.output)
    else:
        if not args.source or not args.shared_model:
            parser.error("export requires --source and --shared-model")
        report = export_motion(args.source.resolve(), args.shared_model.resolve(), args.output)
    text = json.dumps(report, ensure_ascii=False, indent=2) + "\n"
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(text, encoding="utf-8")
    print(text)


if __name__ == "__main__":
    main()
