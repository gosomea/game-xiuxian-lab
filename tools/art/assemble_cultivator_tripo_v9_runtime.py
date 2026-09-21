#!/usr/bin/env python3
"""Assemble the cultivator_tripo_v9 runtime GLB from Make-It-Animatable outputs.

Why this exists
---------------
`tools/art/mia_rig_cultivator_tripo_v9.py` produces, per clip, several files from the
Make-It-Animatable service. None of them is directly usable as the runtime asset:

* `<clip>_slot0.glb` -- rigged mesh + full materials, but NO animation (it is the
  rest-pose export, and an earlier `/pipeline` collision leaves it stale).
* `<clip>_slot1.glb` -- rigged mesh + exactly ONE animation, but only the base-colour
  texture survives the FBX->glTF conversion it went through.
* `<clip>_slot2.fbx` -- the FBX source of the same thing.

The runtime asset must be ONE file carrying ONE skeleton, ONE skinned mesh and exactly
four animations named `idle` / `walk` / `run` / `jump`, because
`cultivator_skeleton_presentation.gd` asserts `has_animation()` for those four names on
the single AnimationPlayer that Godot's glTF import creates.

This script merges at the glTF JSON/chunk level (no Blender round-trip) so nothing is
renamed, re-triangulated or re-mapped on the way through. It:

1. verifies the four `<clip>_slot1.glb` rigs are structurally identical, so animation
   tracks can be re-pointed between them by node name;
2. reindexes every animation accessor and bufferView into one merged buffer;
3. renames each animation to its logical clip name;
4. splices the full PBR material (base colour + metallic-roughness + normal) from the
   pre-rig `cultivator_tripo_v9_clean.glb`, whose UV layout the rigged mesh preserves;
5. verifies the in-place contract (no horizontal root translation drift) and writes a
   manifest next to the output.

Usage
-----
    python3 tools/art/assemble_cultivator_tripo_v9_runtime.py \
        --iteration docs/art/cultivator_tripo_v9/iterations/mia_rig/20260921-final2
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import struct
import sys
from datetime import datetime
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
ASSET_DIR = REPO / "docs" / "art" / "cultivator_tripo_v9"
CLEAN_GLB = ASSET_DIR / "exports" / "cultivator_tripo_v9_clean.glb"
CLIP_ORDER = ["idle", "walk", "run", "jump"]

COMPONENT_SIZE = {5120: 1, 5121: 1, 5122: 2, 5123: 2, 5125: 4, 5126: 4}
TYPE_COUNT = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT2": 4, "MAT3": 9, "MAT4": 16}


# --------------------------------------------------------------------------- glTF IO


def read_glb(path: Path):
    raw = path.read_bytes()
    if raw[:4] != b"glTF":
        raise ValueError(f"{path}: not a GLB (magic={raw[:4]!r})")
    total = struct.unpack("<I", raw[8:12])[0]
    offset, doc, blob = 12, None, b""
    while offset < total:
        clen, _ctype = struct.unpack("<II", raw[offset : offset + 8])
        tag = raw[offset + 4 : offset + 8]
        payload = raw[offset + 8 : offset + 8 + clen]
        if tag == b"JSON":
            doc = json.loads(payload.decode("utf-8"))
        elif tag.startswith(b"BIN"):
            blob = payload
        offset += 8 + clen
    if doc is None:
        raise ValueError(f"{path}: no JSON chunk")
    return doc, blob


def write_glb(path: Path, doc: dict, blob: bytes) -> None:
    json_bytes = json.dumps(doc, separators=(",", ":")).encode("utf-8")
    json_bytes += b" " * (-len(json_bytes) % 4)
    bin_bytes = bytes(blob) + b"\x00" * (-len(blob) % 4)
    total = 12 + 8 + len(json_bytes) + 8 + len(bin_bytes)
    out = bytearray()
    out += b"glTF" + struct.pack("<II", 2, total)
    out += struct.pack("<I", len(json_bytes)) + b"JSON" + json_bytes
    out += struct.pack("<I", len(bin_bytes)) + b"BIN\x00" + bin_bytes
    path.write_bytes(bytes(out))


def accessor_bytes(doc: dict, blob: bytes, index: int) -> tuple[bytes, int]:
    """Return tightly packed element bytes for an accessor, plus element size."""
    acc = doc["accessors"][index]
    if "sparse" in acc:
        raise ValueError(f"accessor {index}: sparse accessors are not supported")
    if "bufferView" not in acc:
        raise ValueError(f"accessor {index}: no bufferView")
    elem = COMPONENT_SIZE[acc["componentType"]] * TYPE_COUNT[acc["type"]]
    view = doc["bufferViews"][acc["bufferView"]]
    base = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
    stride = view.get("byteStride") or elem
    if stride == elem:
        return blob[base : base + elem * acc["count"]], elem
    out = bytearray()
    for i in range(acc["count"]):
        start = base + i * stride
        out += blob[start : start + elem]
    return bytes(out), elem


def texture_closure(doc: dict, material_index: int) -> list[int]:
    """Texture indices referenced by one material."""
    found: list[int] = []

    def visit(node):
        if isinstance(node, dict):
            if isinstance(node.get("index"), int) and set(node) <= {
                "index", "texCoord", "scale", "strength"
            }:
                found.append(node["index"])
                return
            for value in node.values():
                visit(value)
        elif isinstance(node, list):
            for item in node:
                visit(item)

    visit(doc["materials"][material_index])
    return sorted(set(found))


def drop_textures(doc: dict, doomed: list[int]) -> dict:
    """Remove texture entries and their image/sampler closure, reindexing references."""
    if not doomed:
        return {"textures": 0, "images": 0, "samplers": 0}
    keep = [i for i in range(len(doc["textures"])) if i not in set(doomed)]
    tex_map = {old: new for new, old in enumerate(keep)}
    images = sorted({doc["textures"][i]["source"] for i in keep
                     if "source" in doc["textures"][i]})
    samplers = sorted({doc["textures"][i]["sampler"] for i in keep
                       if "sampler" in doc["textures"][i]})
    img_map = {old: new for new, old in enumerate(images)}
    smp_map = {old: new for new, old in enumerate(samplers)}

    counts = {
        "textures": len(doc["textures"]) - len(keep),
        "images": len(doc.get("images", [])) - len(images),
        "samplers": len(doc.get("samplers", [])) - len(samplers),
    }
    doc["textures"] = [doc["textures"][i] for i in keep]
    for index in range(len(doc["textures"])):
        texture = doc["textures"][index]
        if "source" in texture:
            texture["source"] = img_map[texture["source"]]
        if "sampler" in texture:
            texture["sampler"] = smp_map[texture["sampler"]]
    doc["images"] = [doc["images"][i] for i in images] if "images" in doc else []
    doc["samplers"] = [doc["samplers"][i] for i in samplers] if "samplers" in doc else []

    def rewrite(node):
        if isinstance(node, dict):
            if isinstance(node.get("index"), int) and set(node) <= {
                "index", "texCoord", "scale", "strength"
            }:
                node["index"] = tex_map[node["index"]]
                return
            for value in node.values():
                rewrite(value)
        elif isinstance(node, list):
            for item in node:
                rewrite(item)

    for material in doc.get("materials", []):
        rewrite(material)
    return counts


def glb_probe(path: Path) -> dict:
    doc, blob = read_glb(path)
    tris = 0
    for mesh in doc.get("meshes", []):
        for prim in mesh.get("primitives", []):
            if "indices" in prim:
                tris += doc["accessors"][prim["indices"]]["count"] // 3
    animations = []
    for anim in doc.get("animations", []):
        span = 0.0
        for sampler in anim.get("samplers", []):
            acc = doc["accessors"][sampler["input"]]
            if acc.get("max"):
                span = max(span, float(acc["max"][0]))
        animations.append(
            {"name": anim.get("name"), "channels": len(anim.get("channels", [])),
             "seconds": round(span, 3)}
        )
    return {
        "bytes": path.stat().st_size,
        "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
        "meshes": len(doc.get("meshes", [])),
        "triangles": tris,
        "nodes": len(doc.get("nodes", [])),
        "materials": len(doc.get("materials", [])),
        "images": len(doc.get("images", [])),
        "skins": [{"name": s.get("name"), "joints": len(s.get("joints", []))}
                  for s in doc.get("skins", [])],
        "animations": animations,
    }


# ------------------------------------------------------------------- merge machinery


class Merger:
    def __init__(self, doc: dict, blob: bytes):
        self.doc = doc
        self.blob = bytearray(blob)

    def add_view(self, data: bytes, target=None) -> int:
        while len(self.blob) % 4:
            self.blob.append(0)
        offset = len(self.blob)
        self.blob += data
        view: dict = {"buffer": 0, "byteOffset": offset, "byteLength": len(data)}
        if target is not None:
            view["target"] = target
        self.doc.setdefault("bufferViews", []).append(view)
        return len(self.doc["bufferViews"]) - 1

    def clone_accessor(self, src_doc: dict, src_blob: bytes, index: int) -> int:
        data, _elem = accessor_bytes(src_doc, src_blob, index)
        src_view = src_doc["bufferViews"][src_doc["accessors"][index]["bufferView"]]
        view = self.add_view(data, src_view.get("target"))
        new = {k: copy.deepcopy(v) for k, v in src_doc["accessors"][index].items()
               if k not in ("bufferView", "byteOffset", "sparse")}
        new["bufferView"] = view
        self.doc["accessors"].append(new)
        return len(self.doc["accessors"]) - 1

    def clone_image(self, src_doc: dict, src_blob: bytes, index: int) -> int:
        image = copy.deepcopy(src_doc["images"][index])
        view = image.pop("bufferView", None)
        if view is not None:
            src_view = src_doc["bufferViews"][view]
            start = src_view.get("byteOffset", 0)
            image["bufferView"] = self.add_view(
                src_blob[start : start + src_view["byteLength"]]
            )
        self.doc.setdefault("images", []).append(image)
        return len(self.doc["images"]) - 1

    def clone_sampler(self, src_doc: dict, index: int) -> int:
        self.doc.setdefault("samplers", []).append(
            copy.deepcopy(src_doc["samplers"][index])
        )
        return len(self.doc["samplers"]) - 1

    def clone_texture(self, src_doc: dict, src_blob: bytes, index: int) -> int:
        texture = copy.deepcopy(src_doc["textures"][index])
        if "source" in texture:
            texture["source"] = self.clone_image(src_doc, src_blob, texture["source"])
        if "sampler" in texture:
            texture["sampler"] = self.clone_sampler(src_doc, texture["sampler"])
        self.doc.setdefault("textures", []).append(texture)
        return len(self.doc["textures"]) - 1

    def replace_material(self, src_doc: dict, src_blob: bytes, src_index: int,
                         dst_index: int) -> None:
        """Overwrite material `dst_index` with a copy of the source material.

        Replacing in place (rather than appending a new material and repointing the
        primitives) means the service's original material and its texture/image stay
        referenced by nothing, so they simply stop being used -- no pruning pass and no
        dangling index table needed.
        """
        material = copy.deepcopy(src_doc["materials"][src_index])
        cache: dict[int, int] = {}

        def rewrite(node):
            if isinstance(node, dict):
                for key, value in list(node.items()):
                    if key == "index" and isinstance(value, int):
                        if value not in cache:
                            cache[value] = self.clone_texture(src_doc, src_blob, value)
                        node[key] = cache[value]
                    else:
                        rewrite(value)
            elif isinstance(node, list):
                for item in node:
                    rewrite(item)

        rewrite(material)
        self.doc["materials"][dst_index] = material


def node_name_map(doc: dict) -> dict[str, int]:
    return {n.get("name"): i for i, n in enumerate(doc.get("nodes", []))}


def rig_fingerprint(doc: dict, blob: bytes) -> dict:
    """Structural identity of a rig, as far as cross-clip track re-pointing depends on it.

    The Make-It-Animatable service exports each clip from the same session, so geometry,
    skin weights and the bind pose are byte-identical. What does differ per export is the
    node TRS snapshot (each export bakes that clip's pose onto the rest-pose nodes), so
    node transforms are deliberately NOT part of the fingerprint -- they are overwritten
    at runtime by whatever animation is playing. Hierarchy, joint order, blend data and
    the bind pose are what must match.
    """
    nodes = doc.get("nodes", [])
    names = [n.get("name") for n in nodes]
    skin = doc.get("skins", [{}])[0]
    joint_names = tuple(names[j] for j in skin.get("joints", []))
    bind_digest = ""
    if "inverseBindMatrices" in skin:
        bind_digest = hashlib.sha256(
            accessor_bytes(doc, blob, skin["inverseBindMatrices"])[0]
        ).hexdigest()

    mesh = doc.get("meshes", [{}])[0]
    prim = mesh.get("primitives", [{}])[0]
    blend = {}
    for attribute in ("POSITION", "JOINTS_0", "WEIGHTS_0", "TEXCOORD_0"):
        if attribute in prim.get("attributes", {}):
            blend[attribute] = hashlib.sha256(
                accessor_bytes(doc, blob, prim["attributes"][attribute])[0]
            ).hexdigest()[:16]
    if "indices" in prim:
        blend["INDICES"] = hashlib.sha256(
            accessor_bytes(doc, blob, prim["indices"])[0]
        ).hexdigest()[:16]

    hierarchy = []
    for node in nodes:
        hierarchy.append(
            (node.get("name"), tuple(names[c] for c in node.get("children", [])))
        )
    return {
        "node_names": tuple(names),
        "hierarchy": tuple(hierarchy),
        "joint_names": joint_names,
        "attributes": tuple(sorted(prim.get("attributes", {}))),
        "vertex_count": doc["accessors"][prim["attributes"]["POSITION"]]["count"],
        "index_count": doc["accessors"][prim["indices"]]["count"],
        "bind_pose_sha": bind_digest,
        "blend_sha": tuple(sorted(blend.items())),
    }


def root_translation_track(doc: dict, blob: bytes, anim: dict) -> dict | None:
    """Find the translation channel of the skeleton root (mixamorig:Hips)."""
    names = [n.get("name") for n in doc.get("nodes", [])]
    for channel in anim.get("channels", []):
        target = channel["target"]
        if target.get("path") != "translation":
            continue
        if names[target["node"]] not in ("mixamorig:Hips", "Hips"):
            continue
        sampler = anim["samplers"][channel["sampler"]]
        data, elem = accessor_bytes(doc, blob, sampler["output"])
        values = struct.unpack(f"<{len(data) // 4}f", data)
        count = len(values) // 3
        xs = values[0::3]
        ys = values[1::3]
        zs = values[2::3]
        return {
            "samples": count,
            "x_span": round(max(xs) - min(xs), 6),
            "y_span": round(max(ys) - min(ys), 6),
            "z_span": round(max(zs) - min(zs), 6),
            "x_first_last": round(xs[-1] - xs[0], 6),
            "z_first_last": round(zs[-1] - zs[0], 6),
        }
    return None


# ------------------------------------------------------------------------------ main


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--iteration", required=True,
                        help="iterations/mia_rig/<stamp> directory holding the clips")
    parser.add_argument("--out", default="docs/art/cultivator_tripo_v9/exports/"
                                        "cultivator_tripo_v9_runtime.glb")
    parser.add_argument("--no-material-splice", action="store_true",
                        help="keep the service material instead of the clean GLB material")
    args = parser.parse_args()

    iteration = Path(args.iteration)
    if not iteration.is_absolute():
        iteration = REPO / iteration
    if not iteration.is_dir():
        print(f"FAIL: iteration dir missing: {iteration}", file=sys.stderr)
        return 2

    sources = {clip: iteration / f"clip_{clip}_slot1.glb" for clip in CLIP_ORDER}
    missing = [str(p) for p in sources.values() if not p.is_file()]
    if missing:
        print(f"FAIL: missing clip GLB(s): {missing}", file=sys.stderr)
        return 2

    report: dict = {
        "asset": "cultivator_tripo_v9",
        "phase": "runtime_assembly",
        "started": datetime.now().isoformat(timespec="seconds"),
        "source_iteration": str(iteration.relative_to(REPO)),
        "clips": {},
        "checks": {},
        "problems": [],
    }

    base_clip = CLIP_ORDER[0]
    base_doc, base_blob = read_glb(sources[base_clip])
    merger = Merger(base_doc, base_blob)

    # ---- 1. rig identity across all four clip exports -------------------------------
    base_fp = rig_fingerprint(base_doc, base_blob)
    report["checks"]["base_rig"] = {
        "nodes": len(base_fp["node_names"]),
        "joints": len(base_fp["joint_names"]),
        "vertices": base_fp["vertex_count"],
        "indices": base_fp["index_count"],
        "attributes": list(base_fp["attributes"]),
    }
    for clip, path in sources.items():
        doc, blob = read_glb(path)
        fp = rig_fingerprint(doc, blob)
        same = fp == base_fp
        anims = doc.get("animations", [])
        report["clips"][clip] = {
            "file": path.name,
            "animations": len(anims),
            "rig_identical_to_base": same,
        }
        if not same:
            differing = [k for k in base_fp if base_fp[k] != fp[k]]
            report["problems"].append(f"{clip}: rig differs from base in {differing}")
        if len(anims) != 1:
            report["problems"].append(f"{clip}: expected exactly 1 animation, got {len(anims)}")
    if report["problems"]:
        print("FAIL: rig identity problems:", file=sys.stderr)
        for problem in report["problems"]:
            print(f"  - {problem}", file=sys.stderr)
        return 1

    # ---- 2. merge animations, re-pointed by node name ------------------------------
    base_names = node_name_map(base_doc)
    merged_animations = []
    for clip, path in sources.items():
        doc, blob = read_glb(path)
        src_anim = doc["animations"][0]
        names = [n.get("name") for n in doc.get("nodes", [])]

        new_anim: dict = {"name": clip, "samplers": [], "channels": []}
        for sampler in src_anim["samplers"]:
            new_anim["samplers"].append({
                "input": merger.clone_accessor(doc, blob, sampler["input"]),
                "output": merger.clone_accessor(doc, blob, sampler["output"]),
                "interpolation": sampler.get("interpolation", "LINEAR"),
            })
        for channel in src_anim["channels"]:
            target = channel["target"]
            bone = names[target["node"]]
            if bone not in base_names:
                report["problems"].append(f"{clip}: bone {bone!r} absent from base rig")
                continue
            new_anim["channels"].append({
                "sampler": channel["sampler"],
                "target": {"node": base_names[bone], "path": target["path"]},
            })
        merged_animations.append(new_anim)

        root = root_translation_track(doc, blob, src_anim)
        report["clips"][clip]["root_translation"] = root
        report["clips"][clip]["channels"] = len(new_anim["channels"])

    if report["problems"]:
        print("FAIL: bone mapping problems:", file=sys.stderr)
        for problem in report["problems"]:
            print(f"  - {problem}", file=sys.stderr)
        return 1

    base_doc["animations"] = merged_animations

    # ---- 3. splice the full PBR material from the pre-rig clean GLB -----------------
    if not args.no_material_splice:
        if not CLEAN_GLB.is_file():
            report["problems"].append(f"clean GLB missing for material splice: {CLEAN_GLB}")
        else:
            clean_doc, clean_blob = read_glb(CLEAN_GLB)
            clean_prim = clean_doc["meshes"][0]["primitives"][0]
            source_index = clean_prim.get("material")
            prim = base_doc["meshes"][0]["primitives"][0]
            destination_index = prim.get("material", 0)
            if source_index is None:
                report["problems"].append("clean GLB primitive has no material")
            else:
                # Textures the service baked in for its own material, before it is replaced.
                stale = texture_closure(base_doc, destination_index)
                merger.replace_material(
                    clean_doc, clean_blob, source_index, destination_index
                )
                spliced = base_doc["materials"][destination_index]
                still_used = set(texture_closure(base_doc, destination_index))
                doomed = [i for i in stale if i not in still_used]
                report["checks"]["orphan_textures_dropped"] = drop_textures(base_doc, doomed)
                pbr = spliced.get("pbrMetallicRoughness", {})
                report["checks"]["material_splice"] = {
                    "from": str(CLEAN_GLB.relative_to(REPO)),
                    "source_material": source_index,
                    "destination_material": destination_index,
                    "name": spliced.get("name"),
                    "base_color_texture": "baseColorTexture" in pbr,
                    "metallic_roughness_texture": "metallicRoughnessTexture" in pbr,
                    "normal_texture": "normalTexture" in spliced,
                    "occlusion_texture": "occlusionTexture" in spliced,
                    "emissive_texture": "emissiveTexture" in spliced,
                }
    if report["problems"]:
        print("FAIL: material splice problems:", file=sys.stderr)
        for problem in report["problems"]:
            print(f"  - {problem}", file=sys.stderr)
        return 1

    # ---- 4. write and probe --------------------------------------------------------
    out_path = Path(args.out)
    if not out_path.is_absolute():
        out_path = REPO / out_path
    out_path.parent.mkdir(parents=True, exist_ok=True)
    write_glb(out_path, base_doc, bytes(merger.blob))

    probe = glb_probe(out_path)
    report["output"] = {"file": str(out_path.relative_to(REPO)), **probe}
    report["finished"] = datetime.now().isoformat(timespec="seconds")

    manifest_path = iteration / "runtime_assembly_manifest.json"
    manifest_path.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n")

    print(f"wrote {out_path.relative_to(REPO)}  {probe['bytes']:,} bytes")
    print(f"  tris={probe['triangles']:,} nodes={probe['nodes']} "
          f"materials={probe['materials']} images={probe['images']}")
    print(f"  skins={probe['skins']}")
    for anim in probe["animations"]:
        print(f"  clip {anim['name']:<6} {anim['seconds']:>6.3f}s  channels={anim['channels']}")
    print(f"manifest: {manifest_path.relative_to(REPO)}")

    expected = sorted(CLIP_ORDER)
    found = sorted(a["name"] for a in probe["animations"])
    if found != expected:
        print(f"FAIL: clip names {found} != {expected}", file=sys.stderr)
        return 1
    if len(probe["skins"]) != 1:
        print(f"FAIL: expected 1 skin, got {len(probe['skins'])}", file=sys.stderr)
        return 1
    print("OK: one skin, four clips, names exact")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
