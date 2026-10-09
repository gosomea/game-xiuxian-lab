#!/usr/bin/env python3
"""Extract exact animation bytes and the shared skeleton from a full cultivator GLB.

The output has no mesh, material, texture or image. No animation is resampled.
This bootstraps a motion library from a retained full export and checks future
animation-only exports against the same shared skeleton contract.
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
from pathlib import Path

from apply_per_clip_ground_offset import read_glb, write_glb


def configure_animation_import(output: Path) -> None:
    project = Path(__file__).resolve().parents[2] / "src"
    try:
        resource = "res://" + output.resolve().relative_to(project).as_posix()
    except ValueError:
        return
    settings = output.with_suffix(output.suffix + ".import")
    if settings.exists():
        if 'importer="animation_library"' not in settings.read_text():
            raise ValueError("existing output import mode is not AnimationLibrary; use a new path")
        return
    settings.write_text('[remap]\n\nimporter="animation_library"\nimporter_version=1\n'
                        'type="AnimationLibrary"\n\n[deps]\n\nsource_file="' + resource + '"\n\n'
                        '[params]\n\nnodes/import_as_skeleton_bones=false\nskins/use_named_skins=true\n'
                        'animation/fps=30\nanimation/trimming=false\nanimation/remove_immutable_tracks=true\n'
                        'animation/import_rest_as_RESET=false\ngltf/naming_version=2\n', encoding="utf-8")


def split(source: Path, output: Path, replace: bool = False) -> dict:
    if source.resolve() == output.resolve():
        raise ValueError("use a new output path; the full exploration export must be retained")
    if output.exists() and not replace:
        raise ValueError("output already exists; use a new version path or --replace for this asset's continuation")
    doc, blob = read_glb(source)
    motion = {k: copy.deepcopy(doc[k]) for k in ("asset", "scene", "scenes", "nodes", "skins", "animations") if k in doc}
    for node in motion["nodes"]:
        node.pop("mesh", None)
        node.pop("skin", None)
    used = {s[k] for a in motion["animations"] for s in a["samplers"] for k in ("input", "output")}
    used.update(s["inverseBindMatrices"] for s in motion.get("skins", []) if "inverseBindMatrices" in s)
    mapping = {old: new for new, old in enumerate(sorted(used))}
    views, accessors, payload = [], [], bytearray()
    for old in sorted(used):
        accessor = copy.deepcopy(doc["accessors"][old])
        if "sparse" in accessor:
            raise ValueError("sparse animation accessors are not supported")
        view = copy.deepcopy(doc["bufferViews"][accessor["bufferView"]])
        start, length = view.get("byteOffset", 0), view["byteLength"]
        payload.extend(b"\0" * (-len(payload) % 4))
        view["buffer"] = 0
        view["byteOffset"] = len(payload)
        view.pop("target", None)
        accessor["bufferView"] = len(views)
        payload.extend(blob[start:start + length])
        views.append(view)
        accessors.append(accessor)
    for animation in motion["animations"]:
        for sampler in animation["samplers"]:
            for key in ("input", "output"):
                sampler[key] = mapping[sampler[key]]
    for skin in motion.get("skins", []):
        if "inverseBindMatrices" in skin:
            skin["inverseBindMatrices"] = mapping[skin["inverseBindMatrices"]]
    motion.update(accessors=accessors, bufferViews=views, buffers=[{"byteLength": len(payload)}])
    output.parent.mkdir(parents=True, exist_ok=True)
    write_glb(output, motion, bytes(payload))
    configure_animation_import(output)
    return {"source": str(source), "output": str(output), "source_bytes": source.stat().st_size,
            "motion_bytes": output.stat().st_size, "clips": sorted(a["name"] for a in motion["animations"]),
            "animation_data_preserved": True, "sha256": hashlib.sha256(output.read_bytes()).hexdigest()}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--report", type=Path)
    parser.add_argument("--replace", action="store_true")
    args = parser.parse_args()
    report = split(args.source, args.output, args.replace)
    text = json.dumps(report, ensure_ascii=False, indent=2) + "\n"
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(text, encoding="utf-8")
    print(text)


if __name__ == "__main__":
    main()
