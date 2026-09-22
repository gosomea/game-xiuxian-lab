#!/usr/bin/env python3
"""Measure a character's side-to-side TILT (roll) and facing (yaw) in a runtime GLB.

Why this exists
---------------
The clip scorer (`tools/art/score_mia_clip.py`) checks the hips yaw bias, which catches a
retarget that turns the character sideways. It does NOT catch a pose that is leaning over
to one side, because a lean leaves the yaw untouched. A character standing visibly crooked
in an isometric view - where world vertical still renders as screen vertical - is a roll
problem, and nothing was measuring it.

This tool reads the actual runtime asset (not the source FBX) and, for each clip, samples
the spine chain and reports how far the upper body leans off the world vertical axis. It
also reports the yaw, so a single run distinguishes "turned" from "leaning".

Reading the number
------------------
The lean is the angle between the hips-to-neck axis and world +Y, in degrees, in the XY
(pitch) and ZY (roll) planes. A symmetric pose leans 0 in both. What matters is the MEAN
over a clip: a walk cycle rocks side to side around zero, while a crooked idle sits at a
steady non-zero roll for the whole clip.
"""

from __future__ import annotations

import argparse
import json
import math
import struct
import sys
from pathlib import Path

COMPONENT_SIZE = {5120: 1, 5121: 1, 5122: 2, 5123: 2, 5125: 4, 5126: 4}
TYPE_COUNT = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--glb", required=True)
    parser.add_argument("--limit-roll-deg", type=float, default=4.0,
                        help="sustained side-tilt allowed (default: %(default)s)")
    parser.add_argument("--limit-pitch-deg", type=float, default=12.0,
                        help="sustained forward-lean allowed (default: %(default)s)")
    parser.add_argument("--report", default="")
    return parser.parse_args()


def read_glb(path: Path):
    data = path.read_bytes()
    total = struct.unpack("<I", data[8:12])[0]
    offset, doc, blob = 12, None, b""
    while offset < total:
        length, _ = struct.unpack("<II", data[offset : offset + 8])
        tag = data[offset + 4 : offset + 8]
        payload = data[offset + 8 : offset + 8 + length]
        if tag == b"JSON":
            doc = json.loads(payload.decode())
        elif tag.startswith(b"BIN"):
            blob = payload
        offset += 8 + length
    return doc, blob


def accessor(doc, blob, index):
    acc = doc["accessors"][index]
    view = doc["bufferViews"][acc["bufferView"]]
    element = COMPONENT_SIZE[acc["componentType"]] * TYPE_COUNT[acc["type"]]
    base = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
    stride = view.get("byteStride") or element
    if stride == element:
        raw = blob[base : base + element * acc["count"]]
    else:
        raw = b"".join(
            blob[base + i * stride : base + i * stride + element] for i in range(acc["count"])
        )
    return struct.unpack(f"<{len(raw) // 4}f", raw), TYPE_COUNT[acc["type"]]


def node_transform(doc, index, animated: dict, sample: int):
    """Local TRS for a node, using the animated value at `sample` when one exists."""
    node = doc["nodes"][index]
    if index in animated:
        trans = animated[index].get("translation")
        rot = animated[index].get("rotation")
        if trans is not None:
            node = {**node, "translation": list(trans[sample])}
        if rot is not None:
            node = {**node, "rotation": list(rot[sample])}
    return node


def quat_to_matrix(q):
    x, y, z, w = q
    xx, yy, zz = x * x, y * y, z * z
    xy, xz, yz = x * y, x * z, y * z
    wx, wy, wz = w * x, w * y, w * z
    return [
        [1 - 2 * (yy + zz), 2 * (xy - wz), 2 * (xz + wy)],
        [2 * (xy + wz), 1 - 2 * (xx + zz), 2 * (yz - wx)],
        [2 * (xz - wy), 2 * (yz + wx), 1 - 2 * (xx + yy)],
    ]


def mat_mul(a, b):
    return [[sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)] for i in range(3)]


def mat_vec(a, v):
    return [sum(a[i][k] * v[k] for k in range(3)) for i in range(3)]


def world_matrices(doc, animated, sample):
    """World 3x3 rotation and origin for every node, walking parents first."""
    parent = {}
    for i, node in enumerate(doc["nodes"]):
        for child in node.get("children", []):
            parent[child] = i

    cache: dict[int, tuple[list, list]] = {}

    def resolve(index):
        if index in cache:
            return cache[index]
        node = node_transform(doc, index, animated, sample)
        local = quat_to_matrix(node.get("rotation", [0, 0, 0, 1]))
        origin = list(node.get("translation", [0, 0, 0]))
        if index in parent:
            prow, porigin = resolve(parent[index])
            world_rot = mat_mul(prow, local)
            world_origin = [porigin[k] + mat_vec(prow, origin)[k] for k in range(3)]
        else:
            world_rot, world_origin = local, origin
        cache[index] = (world_rot, world_origin)
        return cache[index]

    for i in range(len(doc["nodes"])):
        resolve(i)
    return cache, resolve


def measure_clip(doc, blob, anim, limits) -> dict:
    names = [n.get("name") for n in doc["nodes"]]
    hips = next((i for i, n in enumerate(names) if n and n.endswith("Hips")), None)
    neck = next(
        (i for i, n in enumerate(names) if n and ("Neck" in n or "Head" in n)), None
    )
    if hips is None or neck is None:
        return {"error": "missing Hips or Neck/Head node"}

    animated: dict[int, dict] = {}
    samples = 0
    for channel in anim["channels"]:
        target = channel["target"]
        values, stride = accessor(doc, blob, anim["samplers"][channel["sampler"]]["output"])
        count = len(values) // stride
        samples = max(samples, count)
        store = animated.setdefault(target["node"], {})
        store[target["path"]] = [values[i * stride : (i + 1) * stride] for i in range(count)]

    rolls, pitches, yaws = [], [], []
    for sample in range(samples):
        cache, _ = world_matrices(doc, animated, sample)
        hips_rot, hips_pos = cache[hips]
        _, neck_pos = cache[neck]

        axis = [neck_pos[k] - hips_pos[k] for k in range(3)]
        length = math.sqrt(sum(v * v for v in axis))
        if length < 1e-9:
            continue
        axis = [v / length for v in axis]

        # Lean measured against world vertical directly: the neck-to-hips direction should be
        # nearly +Y for an upright figure. This avoids relying on any bone's local convention.
        pitches.append(math.degrees(math.asin(max(-1.0, min(1.0, -axis[2])))))
        rolls.append(math.degrees(math.asin(max(-1.0, min(1.0, axis[0])))))

        up = mat_vec(hips_rot, [0.0, 1.0, 0.0])
        yaws.append(math.degrees(math.atan2(up[0], up[2])))

    def summary(values):
        return {
            "mean_deg": round(sum(values) / len(values), 2),
            "min_deg": round(min(values), 2),
            "max_deg": round(max(values), 2),
            "span_deg": round(max(values) - min(values), 2),
        }

    roll = summary(rolls)
    pitch = summary(pitches)
    verdict = []
    if abs(roll["mean_deg"]) > limits["roll"]:
        verdict.append(
            f"body leans {roll['mean_deg']:+.1f} deg sideways (limit {limits['roll']:.0f}) "
            f"-- the figure is standing crooked"
        )
    if abs(pitch["mean_deg"]) > limits["pitch"]:
        verdict.append(
            f"body leans {pitch['mean_deg']:+.1f} deg forward/back (limit {limits['pitch']:.0f})"
        )
    return {
        "name": anim["name"],
        "samples": samples,
        "roll": roll,
        "pitch": pitch,
        "yaw": summary(yaws),
        "verdict": verdict,
    }


def main() -> int:
    args = parse_args()
    glb = Path(args.glb)
    if not glb.is_file():
        print(f"FAIL: missing {glb}", file=sys.stderr)
        return 2
    doc, blob = read_glb(glb)
    limits = {"roll": args.limit_roll_deg, "pitch": args.limit_pitch_deg}

    report = {"file": glb.name, "clips": {}, "problems": []}
    print(f"{glb.name}: {len(doc.get('animations', []))} clip(s)")
    print(f"  limits: roll {limits['roll']:.0f} deg, pitch {limits['pitch']:.0f} deg (mean over clip)")
    print()
    print(f"  {'clip':<14}{'roll mean':>11}{'pitch mean':>12}{'yaw mean':>10}   verdict")
    for anim in doc.get("animations", []):
        stats = measure_clip(doc, blob, anim, limits)
        report["clips"][anim["name"]] = stats
        if "error" in stats:
            print(f"  {anim['name']:<14}  ERROR {stats['error']}")
            report["problems"].append(f"{anim['name']}: {stats['error']}")
            continue
        tag = "OK" if not stats["verdict"] else "BAD"
        print(
            f"  {anim['name']:<14}{stats['roll']['mean_deg']:>+10.2f} "
            f"{stats['pitch']['mean_deg']:>+11.2f} {stats['yaw']['mean_deg']:>+9.2f}   {tag}"
        )
        for problem in stats["verdict"]:
            print(f"      ! {problem}")
            report["problems"].append(f"{anim['name']}: {problem}")

    print()
    if report["problems"]:
        print(f"FAIL: {len(report['problems'])} problem(s)")
    else:
        print("OK: every clip stands upright within limits")

    if args.report:
        out = Path(args.report)
        out.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n")
        print(f"report {out}")
    return 1 if report["problems"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
