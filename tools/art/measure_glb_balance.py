#!/usr/bin/env python3
"""Measure where the pelvis sits horizontally relative to the feet, per clip, in a runtime GLB.

Why this exists
---------------
Phase 8 found the character leaning and corrected it by forcing the **hips->head** axis
upright (`tools/art/cultivator_lean_fix.py`). That fixed the torso, and the check that
verifies it (`tools/art/measure_glb_upright.py`) reports the torso as upright today.

But "is the torso vertical?" and "is the body standing over its feet?" are different
questions, and only the first one was being asked. A character whose torso is straight while
the whole body is sheared back at the hips reads as leaning - the defect is still visible -
and every existing gate says OK, because none of them compares the pelvis to the feet.

So this tool measures the balance question directly: for each sampled frame, the horizontal
distance from the midpoint of the two ankles to the head, to the hips, and to the feet; plus
the height of each. The pair of numbers tells you which correction is missing:

  tilt_hips_to_ankle_deg   the balance number. A standing pose should be small. If this is
                           large while spine_tilt_deg is small, the lean fix straightened the
                           torso on top of a pelvis that is still displaced - the correction
                           was applied one joint too high.
  tilt_hips_to_head_deg    the posture number, the one Phase 8 already reports.

Run:
    python3 tools/art/measure_glb_balance.py \
        --glb src/game/actors/swordsman/models/cultivator_tripo_v9.glb
"""

from __future__ import annotations

import argparse
import json
import math
import struct
import sys
from pathlib import Path

COMPONENT_SIZE = {5120: 1, 5121: 1, 5122: 2, 5123: 2, 5125: 4, 5126: 4}
TYPE_COUNT = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}

## Bone name candidates; the rig is Mixamo-compatible, and Make-It-Animatable may or may not
## keep the "mixamorig:" prefix, so accept both spellings rather than guessing.
HIPS = ("mixamorig:Hips", "mixamorig_Hips", "Hips")
HEAD = ("mixamorig:Head", "mixamorig_Head", "Head")
ANKLES = (
    ("mixamorig:LeftFoot", "mixamorig_LeftFoot", "LeftFoot"),
    ("mixamorig:RightFoot", "mixamorig_RightFoot", "RightFoot"),
)
TOES = (
    ("mixamorig:LeftToeBase", "mixamorig_LeftToeBase", "LeftToeBase"),
    ("mixamorig:RightToeBase", "mixamorig_RightToeBase", "RightToeBase"),
)
## Bones whose translation must NOT be averaged for the foot position: the rig's ankle is the
## joint the ground contract is defined at (see measure_glb_skinned_bounds).
FOOT_JOINTS = ANKLES


def read_glb(path: Path):
    raw = path.read_bytes()
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
    return doc, blob


def accessor(doc, blob, index):
    acc = doc["accessors"][index]
    view = doc["bufferViews"][acc["bufferView"]]
    count = acc["count"]
    ncomp = TYPE_COUNT[acc["type"]]
    stride = view.get("byteStride") or COMPONENT_SIZE[acc["componentType"]] * ncomp
    start = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
    fmt = {5120: "b", 5121: "B", 5122: "h", 5123: "H", 5125: "I", 5126: "f"}[acc["componentType"]]
    out = []
    for i in range(count):
        at = start + i * stride
        out.append(struct.unpack_from("<" + fmt * ncomp, blob, at))
    return out


def identity():
    return [1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0]


def mul(a, b):
    out = [0.0] * 16
    for c in range(4):
        for r in range(4):
            out[c * 4 + r] = sum(a[k * 4 + r] * b[c * 4 + k] for k in range(4))
    return out


def from_trs(node):
    t = node.get("translation", [0.0, 0.0, 0.0])
    r = node.get("rotation", [0.0, 0.0, 0.0, 1.0])
    s = node.get("scale", [1.0, 1.0, 1.0])
    x, y, z, w = r
    rot = [
        1 - 2 * (y * y + z * z), 2 * (x * y + z * w), 2 * (x * z - y * w), 0.0,
        2 * (x * y - z * w), 1 - 2 * (x * x + z * z), 2 * (y * z + x * w), 0.0,
        2 * (x * z + y * w), 2 * (y * z - x * w), 1 - 2 * (x * x + y * y), 0.0,
        0.0, 0.0, 0.0, 1.0,
    ]
    for c in range(3):
        for rw in range(3):
            rot[c * 4 + rw] *= s[c]
    rot[12], rot[13], rot[14] = t[0], t[1], t[2]
    return rot


def apply(m, v):
    x, y, z = v
    return (
        m[0] * x + m[4] * y + m[8] * z + m[12],
        m[1] * x + m[5] * y + m[9] * z + m[13],
        m[2] * x + m[6] * y + m[10] * z + m[14],
    )


def node_transform(doc, index, animated, sample):
    node = doc["nodes"][index]
    if index in animated:
        translations, rotations = animated[index]
        merged = dict(node)
        if translations:
            merged["translation"] = list(translations[min(sample, len(translations) - 1)])
        if rotations:
            merged["rotation"] = list(rotations[min(sample, len(rotations) - 1)])
        return from_trs(merged)
    return from_trs(node)


def world_matrices(doc, animated, sample):
    parents = {}
    for i, node in enumerate(doc["nodes"]):
        for child in node.get("children", []):
            parents[child] = i
    cache = {}

    def world(index):
        if index in cache:
            return cache[index]
        local = node_transform(doc, index, animated, sample)
        parent = parents.get(index)
        cache[index] = mul(world(parent), local) if parent is not None else local
        return cache[index]

    return {i: world(i) for i in range(len(doc["nodes"]))}


def animation_channels(doc, blob, anim):
    """Collect per-node (translations, rotations) for a clip, keyed by node index."""
    animated = {}
    for channel in anim["channels"]:
        target = channel["target"]
        path = target.get("path")
        if path not in ("translation", "rotation"):
            continue
        values = accessor(doc, blob, anim["samplers"][channel["sampler"]]["output"])
        translations, rotations = animated.get(target["node"], ([], []))
        if path == "translation":
            translations = values
        else:
            rotations = values
        animated[target["node"]] = (translations, rotations)
    return animated


def bone_index(doc, names):
    """Resolve a bone node index by any accepted spelling, matching the node NAME field."""
    lowered = {
        str(node.get("name", "")).lower(): i for i, node in enumerate(doc["nodes"])
    }
    for name in names:
        if name.lower() in lowered:
            return lowered[name.lower()]
    return None


def sample_points(doc, blob, anim, name):
    """Return (mean world position of the named bone over the clip, frame count)."""
    animated = animation_channels(doc, blob, anim)
    node = bone_index(doc, name)
    if node is None:
        return None
    times = accessor(doc, blob, anim["samplers"][0]["input"])
    frames = len(times)
    if frames == 0:
        return None
    total = [0.0, 0.0, 0.0]
    for sample in range(frames):
        world = world_matrices(doc, animated, sample)
        pos = apply(world[node], (0.0, 0.0, 0.0))
        total = [total[k] + pos[k] for k in range(3)]
    return [v / frames for v in total], frames


def measure(doc, blob, anim) -> dict:
    hips = sample_points(doc, blob, anim, HIPS)
    head = sample_points(doc, blob, anim, HEAD)
    ankles = [sample_points(doc, blob, anim, names) for names in ANKLES]
    ankles = [a for a in ankles if a]
    if hips is None or head is None or not ankles:
        return {"error": "missing hips/head/ankle bone"}
    foot = [sum(a[0][k] for a in ankles) / len(ankles) for k in range(3)]

    def tilt(anchor, top):
        dz = top[1] - anchor[1]
        dx, dy = top[0] - anchor[0], top[2] - anchor[2]
        horiz = math.hypot(dx, dy)
        return math.degrees(math.atan2(horiz, max(dz, 1e-6))), horiz

    hips_to_ankle, hips_horiz = tilt(foot, hips[0])
    hips_to_head, head_horiz = tilt(hips[0], head[0])
    return {
        "frames": hips[1],
        "tilt_hips_to_ankle_deg": round(hips_to_ankle, 2),
        "hips_over_feet_offset_m": round(hips_horiz, 4),
        "tilt_hips_to_head_deg": round(hips_to_head, 2),
        "head_over_hips_offset_m": round(head_horiz, 4),
        "hips_y": round(hips[0][1], 4),
        "feet_y": round(foot[1], 4),
        "head_y": round(head[0][1], 4),
    }


SEATED = {"meditate"}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--glb", required=True)
    parser.add_argument("--limit-balance-deg", type=float, default=6.0,
                        help="standing clips whose pelvis sits this far off the feet are flagged")
    parser.add_argument("--report", default="")
    args = parser.parse_args()

    path = Path(args.glb)
    doc, blob = read_glb(path)
    if doc is None:
        print(f"{path}: no JSON chunk")
        return 1

    print(f"{path.name}: {len(doc.get('animations', []))} clip(s)")
    print("  A standing pose keeps the pelvis over the feet; the torso can be straight while")
    print("  the whole body is sheared, which is what tilt_hips_to_ankle_deg catches.\n")
    print(f"  {'clip':<14}{'hips-over-feet':>15}{'tilt':>9}{'torso tilt':>12}"
          f"{'feet_y':>9}{'hips_y':>9}   verdict")

    report = {"glb": str(path), "clips": {}, "problems": []}
    for anim in doc.get("animations", []):
        name = anim.get("name", "?")
        stats = measure(doc, blob, anim)
        report["clips"][name] = stats
        if "error" in stats:
            print(f"  {name:<14}  ERROR {stats['error']}")
            report["problems"].append(f"{name}: {stats['error']}")
            continue
        problems = []
        if name not in SEATED and abs(stats["tilt_hips_to_ankle_deg"]) > args.limit_balance_deg:
            problems.append(
                f"pelvis sits {stats['hips_over_feet_offset_m']:.3f} m off the feet "
                f"({stats['tilt_hips_to_ankle_deg']:+.2f} deg)")
        if abs(stats["feet_y"]) > 0.02:
            problems.append(f"feet rest {stats['feet_y']:+.4f} m off the ground plane")
        tag = "OK" if not problems else "BAD"
        print(f"  {name:<14}{stats['hips_over_feet_offset_m']:>14.4f}m"
              f"{stats['tilt_hips_to_ankle_deg']:>+8.2f} "
              f"{stats['tilt_hips_to_head_deg']:>+11.2f} "
              f"{stats['feet_y']:>+8.4f} {stats['hips_y']:>+8.4f}   {tag}")
        for problem in problems:
            print(f"      ! {problem}")
            report["problems"].append(f"{name}: {problem}")

    print()
    if report["problems"]:
        print(f"FAIL: {len(report['problems'])} problem(s)")
    else:
        print("OK: every standing clip keeps the pelvis over its feet and rests on the ground")

    if args.report:
        out = Path(args.report)
        out.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n")
        print(f"report {out}")
    return 1 if report["problems"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
