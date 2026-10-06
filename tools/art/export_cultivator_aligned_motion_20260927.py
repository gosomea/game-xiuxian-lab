#!/usr/bin/env python3
"""Export a seven-clip character from its self-contained Blender source.

Run with Blender --background --factory-startup --python this_file.py.
An optional ``-- --output /tmp/probe.glb`` validates an export without replacing
the runtime asset.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import struct
import sys

import bpy


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "docs/art/cultivator_aligned_motion_20260927/cultivator_aligned_motion_20260927.blend"
RUNTIME = ROOT / "src/game/actors/swordsman/models/cultivator_aligned_motion_20260927.glb"
CLIPS = {"idle", "walk", "run", "jump", "idle_guarded", "meditate", "sword_ride"}


def glb_animation_names(path: Path) -> set[str]:
    with path.open("rb") as handle:
        header = handle.read(12)
        magic, version, length = struct.unpack("<4sII", header)
        assert magic == b"glTF" and version == 2 and length == path.stat().st_size
        chunk_length, chunk_type = struct.unpack("<I4s", handle.read(8))
        assert chunk_type == b"JSON"
        document = json.loads(handle.read(chunk_length))
    return {animation["name"] for animation in document["animations"]}


def main() -> None:
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, default=SOURCE)
    parser.add_argument("--output", type=Path, default=RUNTIME)
    args = parser.parse_args(argv)

    bpy.ops.wm.open_mainfile(filepath=str(args.source))
    actions = {action.name for action in bpy.data.actions}
    assert actions == CLIPS, f"Expected seven clips, got {sorted(actions)}"
    rigs = [obj for obj in bpy.data.objects if obj.type == "ARMATURE"]
    meshes = [obj for obj in bpy.data.objects if obj.type == "MESH"
              and any(mod.type == "ARMATURE" for mod in obj.modifiers)]
    assert len(rigs) == len(meshes) == 1
    assert len(rigs[0].data.bones) == 22
    for image in bpy.data.images:
        if image.source == "FILE":
            assert image.packed_file is not None, f"Unpacked texture: {image.name}"

    bpy.ops.object.select_all(action="DESELECT")
    rigs[0].select_set(True)
    meshes[0].select_set(True)
    bpy.context.view_layer.objects.active = rigs[0]
    args.output.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(args.output), export_format="GLB", use_selection=True,
        export_animation_mode="ACTIONS", export_animations=True,
        export_skins=True, export_yup=True, export_apply=False,
        export_normals=True, export_materials="EXPORT",
        export_frame_range=False, export_force_sampling=True,
        export_bake_animation=False,
    )
    exported = glb_animation_names(args.output)
    assert exported == CLIPS, f"Export lost clips: {sorted(exported)}"
    print(f"Exported {args.output}: {sorted(exported)}, 22 bones")


if __name__ == "__main__":
    main()
