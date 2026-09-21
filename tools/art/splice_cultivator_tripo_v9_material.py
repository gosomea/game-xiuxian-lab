#!/usr/bin/env python3
"""Splice the full PBR material into a rigged cultivator_tripo_v9 runtime GLB.

Run after `tools/art/build_cultivator_tripo_v9_runtime_glb.py`:

    python3 tools/art/splice_cultivator_tripo_v9_material.py \
        --glb docs/art/cultivator_tripo_v9/exports/cultivator_tripo_v9_runtime_blender.glb

Why this exists
---------------
The Blender FBX->GLB export keeps the mesh, skeleton, normals and all four actions, but the
FBX material only carries a base-colour map. The authoritative full PBR set lives in the
pre-rig `cultivator_tripo_v9_clean.glb` (base colour + metallic-roughness + normal), whose
UV layout the rigged mesh preserves because it descends from the same clean mesh.

This writes the result in place and records what it changed.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from assemble_cultivator_tripo_v9_runtime import (  # noqa: E402
    CLEAN_GLB,
    REPO,
    Merger,
    drop_textures,
    glb_probe,
    read_glb,
    texture_closure,
    write_glb,
)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--glb", required=True, help="runtime GLB to patch in place")
    parser.add_argument("--clean", default=str(CLEAN_GLB),
                        help="source of the authoritative PBR material")
    parser.add_argument("--report", default="", help="optional JSON report path")
    args = parser.parse_args()

    target = Path(args.glb)
    if not target.is_absolute():
        target = REPO / target
    clean = Path(args.clean)
    if not clean.is_absolute():
        clean = REPO / clean
    if not target.is_file():
        print(f"FAIL: missing {target}", file=sys.stderr)
        return 2
    if not clean.is_file():
        print(f"FAIL: missing {clean}", file=sys.stderr)
        return 2

    doc, blob = read_glb(target)
    clean_doc, clean_blob = read_glb(clean)
    merger = Merger(doc, blob)

    prim = doc["meshes"][0]["primitives"][0]
    destination_index = prim.get("material", 0)
    source_index = clean_doc["meshes"][0]["primitives"][0].get("material")
    if source_index is None:
        print("FAIL: clean GLB primitive has no material", file=sys.stderr)
        return 1

    stale = texture_closure(doc, destination_index)
    merger.replace_material(clean_doc, clean_blob, source_index, destination_index)
    spliced = doc["materials"][destination_index]
    still_used = set(texture_closure(doc, destination_index))
    dropped = drop_textures(doc, [i for i in stale if i not in still_used])

    write_glb(target, doc, bytes(merger.blob))

    probe = glb_probe(target)
    pbr = spliced.get("pbrMetallicRoughness", {})
    report = {
        "asset": "cultivator_tripo_v9",
        "phase": "material_splice",
        "target": str(target.relative_to(REPO)) if target.is_relative_to(REPO) else str(target),
        "source": str(clean.relative_to(REPO)) if clean.is_relative_to(REPO) else str(clean),
        "material": {
            "name": spliced.get("name"),
            "base_color_texture": "baseColorTexture" in pbr,
            "metallic_roughness_texture": "metallicRoughnessTexture" in pbr,
            "normal_texture": "normalTexture" in spliced,
            "occlusion_texture": "occlusionTexture" in spliced,
            "emissive_texture": "emissiveTexture" in spliced,
            "metallic_factor": pbr.get("metallicFactor"),
            "roughness_factor": pbr.get("roughnessFactor"),
        },
        "orphan_textures_dropped": dropped,
        "output": probe,
    }

    print(f"patched {target.name}  {probe['bytes']:,} bytes")
    print(f"  materials={probe['materials']} images={probe['images']} "
          f"tris={probe['triangles']:,}")
    print(f"  base={report['material']['base_color_texture']} "
          f"mr={report['material']['metallic_roughness_texture']} "
          f"normal={report['material']['normal_texture']}")
    print(f"  dropped orphans: {dropped}")
    for anim in probe["animations"]:
        print(f"  clip {anim['name']:<6} {anim['seconds']:>6.3f}s channels={anim['channels']}")

    if args.report:
        path = Path(args.report)
        if not path.is_absolute():
            path = REPO / path
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n")
        print(f"report {path}")

    if not report["material"]["normal_texture"]:
        print("FAIL: normal texture did not land", file=sys.stderr)
        return 1
    expected = {"idle", "walk", "run", "jump"}
    found = {a["name"] for a in probe["animations"]}
    if found != expected:
        print(f"FAIL: clips {sorted(found)} != {sorted(expected)}", file=sys.stderr)
        return 1
    print("OK: full PBR material with four clips intact")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
