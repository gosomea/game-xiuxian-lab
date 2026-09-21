#!/usr/bin/env python3
"""Compute the SKINNED world-space bounds of a rigged GLB, and the ground offset.

A skinned mesh ignores its own node transform. The rendered position of vertex v is

    world_v = sum_j  w_j * (G_j * IBM_j * v)

where G_j is joint j's global transform from the node hierarchy and IBM_j its inverse
bind matrix. Reading the mesh's own AABB therefore says nothing about where the character
renders, which is exactly the question the Godot integration needs answered: are the feet
at the actor origin, or is the character offset (and by how much)?

Run:
    python3 tools/art/measure_glb_skinned_bounds.py \
        --glb src/game/actors/swordsman/models/cultivator_tripo_v9.glb \
        --clip idle
"""

from __future__ import annotations

import argparse
import json
import struct
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
COMPONENT_SIZE = {5120: 1, 5121: 1, 5122: 2, 5123: 2, 5125: 4, 5126: 4}
TYPE_COUNT = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT2": 4, "MAT3": 9, "MAT4": 16}


def read_glb(path: Path):
    raw = path.read_bytes()
    total = struct.unpack("<I", raw[8:12])[0]
    offset, doc, blob = 12, None, b""
    while offset < total:
        clen, _ = struct.unpack("<II", raw[offset : offset + 8])
        tag = raw[offset + 4 : offset + 8]
        payload = raw[offset + 8 : offset + 8 + clen]
        if tag == b"JSON":
            doc = json.loads(payload.decode("utf-8"))
        elif tag.startswith(b"BIN"):
            blob = payload
        offset += 8 + clen
    return doc, blob


def accessor(doc, blob, index):
    acc = doc["accessors"][index]
    view = doc["bufferViews"][acc["bufferView"]]
    elem = COMPONENT_SIZE[acc["componentType"]] * TYPE_COUNT[acc["type"]]
    base = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
    stride = view.get("byteStride") or elem
    if stride == elem:
        raw = blob[base : base + elem * acc["count"]]
    else:
        raw = b"".join(
            blob[base + i * stride : base + i * stride + elem] for i in range(acc["count"])
        )
    fmt = {5120: "b", 5121: "B", 5122: "h", 5123: "H", 5125: "I", 5126: "f"}[acc["componentType"]]
    values = struct.unpack(f"<{len(raw) // COMPONENT_SIZE[acc['componentType']]}{fmt}", raw)
    return values


# ---------------------------------------------------------------- small 4x4 matrix math


def identity():
    return [1.0, 0, 0, 0, 0, 1.0, 0, 0, 0, 0, 1.0, 0, 0, 0, 0, 1.0]


def mul(a, b):
    """Row-major 4x4 multiply: result = a * b."""
    out = [0.0] * 16
    for r in range(4):
        for c in range(4):
            out[r * 4 + c] = sum(a[r * 4 + k] * b[k * 4 + c] for k in range(4))
    return out


def from_trs(node: dict):
    if "matrix" in node:
        m = node["matrix"]  # glTF matrices are column-major
        return [m[0], m[4], m[8], m[12],
                m[1], m[5], m[9], m[13],
                m[2], m[6], m[10], m[14],
                m[3], m[7], m[11], m[15]]
    t = node.get("translation", [0.0, 0.0, 0.0])
    q = node.get("rotation", [0.0, 0.0, 0.0, 1.0])
    s = node.get("scale", [1.0, 1.0, 1.0])
    x, y, z, w = q
    rot = [
        1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w), 0.0,
        2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w), 0.0,
        2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y), 0.0,
        0.0, 0.0, 0.0, 1.0,
    ]
    for r in range(3):
        for c in range(3):
            rot[r * 4 + c] *= s[c]
    rot[3], rot[7], rot[11] = t[0], t[1], t[2]
    return rot


def apply(m, v):
    x, y, z = v
    return (
        m[0] * x + m[1] * y + m[2] * z + m[3],
        m[4] * x + m[5] * y + m[6] * z + m[7],
        m[8] * x + m[9] * y + m[10] * z + m[11],
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--glb", required=True)
    parser.add_argument("--clip", default="", help="animation to sample (default: rest pose)")
    parser.add_argument("--time", type=float, default=0.0)
    parser.add_argument("--stride", type=int, default=7, help="sample every Nth vertex")
    args = parser.parse_args()

    path = Path(args.glb)
    if not path.is_absolute():
        path = REPO / path
    doc, blob = read_glb(path)

    nodes = doc["nodes"]
    parents = {}
    for i, node in enumerate(nodes):
        for child in node.get("children", []):
            parents[child] = i

    # An unrigged GLB (the pre-rig clean mesh) has no skin: its vertices are placed by the
    # mesh node's own transform, so there is nothing to skin and no animation to sample.
    if not doc.get("skins"):
        prim = doc["meshes"][0]["primitives"][0]
        positions = accessor(doc, blob, prim["attributes"]["POSITION"])
        vertex_count = doc["accessors"][prim["attributes"]["POSITION"]]["count"]
        node_index = next(
            (i for i, n in enumerate(nodes) if n.get("mesh") is not None), None
        )
        transform = identity()
        if node_index is not None:
            cursor = node_index
            chain = []
            while cursor is not None:
                chain.append(cursor)
                cursor = parents.get(cursor)
            for index in reversed(chain):
                transform = mul(transform, from_trs(nodes[index]))
        lo = [float("inf")] * 3
        hi = [float("-inf")] * 3
        count = 0
        for v in range(0, vertex_count, args.stride):
            p = apply(transform, positions[v * 3 : v * 3 + 3])
            for axis in range(3):
                lo[axis] = min(lo[axis], p[axis])
                hi[axis] = max(hi[axis], p[axis])
            count += 1
        result = {
            "glb": str(path.relative_to(REPO)) if path.is_relative_to(REPO) else str(path),
            "kind": "unskinned",
            "sampled_vertices": count,
            "stride": args.stride,
            "world_min": [round(v, 4) for v in lo],
            "world_max": [round(v, 4) for v in hi],
            "world_size": [round(hi[i] - lo[i], 4) for i in range(3)],
            "feet_y": round(lo[1], 4),
            "head_y": round(hi[1], 4),
            "height_m": round(hi[1] - lo[1], 4),
            "ground_offset_y": round(lo[1], 4),
        }
        print(json.dumps(result, indent=2, ensure_ascii=False))
        return 0

    skin = doc["skins"][0]
    joints = skin["joints"]
    ibm_values = accessor(doc, blob, skin["inverseBindMatrices"])
    ibms = [list(ibm_values[i * 16 : (i + 1) * 16]) for i in range(len(joints))]
    # glTF stores matrices column-major; convert each IBM to row-major.
    ibms = [[m[0], m[4], m[8], m[12],
             m[1], m[5], m[9], m[13],
             m[2], m[6], m[10], m[14],
             m[3], m[7], m[11], m[15]] for m in ibms]

    # Optionally override the joint locals with an animation sample.
    clip_report = None
    if args.clip:
        anim = next((a for a in doc.get("animations", []) if a["name"] == args.clip), None)
        if anim is None:
            print(f"FAIL: no animation named {args.clip!r}", file=sys.stderr)
            return 2
        animated = {}
        for channel in anim["channels"]:
            target = channel["target"]
            sampler = anim["samplers"][channel["sampler"]]
            times = accessor(doc, blob, sampler["input"])
            values = accessor(doc, blob, sampler["output"])
            stride = TYPE_COUNT[doc["accessors"][sampler["output"]]["type"]]
            # Nearest sample at or before the requested time.
            pick = 0
            for i, t in enumerate(times):
                if t <= args.time:
                    pick = i
            animated.setdefault(target["node"], {})[target["path"]] = list(
                values[pick * stride : (pick + 1) * stride]
            )
        # Rebuild node TRS with the animated overrides.
        overridden = []
        for i, node in enumerate(nodes):
            if i in animated:
                merged = dict(node)
                merged.update(animated[i])
                merged.pop("matrix", None)
                overridden.append(from_trs(merged))
            else:
                overridden.append(from_trs(node))

        def global_animated(index: int):
            m = overridden[index]
            cursor = parents.get(index)
            while cursor is not None:
                m = mul(overridden[cursor], m)
                cursor = parents.get(cursor)
            return m

        joint_globals = [global_animated(j) for j in joints]
        clip_report = {"clip": args.clip, "time": args.time}
    else:
        def global_matrix(index: int):
            m = from_trs(nodes[index])
            cursor = parents.get(index)
            while cursor is not None:
                m = mul(from_trs(nodes[cursor]), m)
                cursor = parents.get(cursor)
            return m

        joint_globals = [global_matrix(j) for j in joints]

    # Skinning matrices.
    skin_matrices = [mul(joint_globals[i], ibms[i]) for i in range(len(joints))]

    prim = doc["meshes"][0]["primitives"][0]
    positions = accessor(doc, blob, prim["attributes"]["POSITION"])
    joint_ids = accessor(doc, blob, prim["attributes"]["JOINTS_0"])
    weights = accessor(doc, blob, prim["attributes"]["WEIGHTS_0"])
    vertex_count = doc["accessors"][prim["attributes"]["POSITION"]]["count"]

    lo = [float("inf")] * 3
    hi = [float("-inf")] * 3
    count = 0
    for v in range(0, vertex_count, args.stride):
        px, py, pz = positions[v * 3 : v * 3 + 3]
        acc = [0.0, 0.0, 0.0]
        wsum = 0.0
        for k in range(4):
            w = weights[v * 4 + k]
            if w == 0.0:
                continue
            j = joint_ids[v * 4 + k]
            m = skin_matrices[j]
            tx, ty, tz = apply(m, (px, py, pz))
            acc[0] += w * tx
            acc[1] += w * ty
            acc[2] += w * tz
            wsum += w
        if wsum > 0.0:
            acc = [c / wsum for c in acc]
        for axis in range(3):
            lo[axis] = min(lo[axis], acc[axis])
            hi[axis] = max(hi[axis], acc[axis])
        count += 1

    result = {
        "glb": str(path.relative_to(REPO)) if path.is_relative_to(REPO) else str(path),
        "sampled_vertices": count,
        "stride": args.stride,
        "joints": len(joints),
        "world_min": [round(v, 4) for v in lo],
        "world_max": [round(v, 4) for v in hi],
        "world_size": [round(hi[i] - lo[i], 4) for i in range(3)],
        "feet_y": round(lo[1], 4),
        "head_y": round(hi[1], 4),
        "height_m": round(hi[1] - lo[1], 4),
        "ground_offset_y": round(lo[1], 4),
    }
    if clip_report:
        result.update(clip_report)

    print(json.dumps(result, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
