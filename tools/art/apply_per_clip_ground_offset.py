#!/usr/bin/env python3
"""Give each animation clip in a runtime GLB its own ground offset.

Why this exists
---------------
The character ships with a "feet at y=0" contract, and the build derives one global offset
from `min(lowest vertex) across the locomotion clips`. That statistic is degenerate: taking
the minimum makes exactly ONE clip touch the ground and leaves every other clip floating by
(its own low - the minimum). Measured on the shipped asset, `run` sat at +0.0168 m while
`idle_guarded`, `meditate` and `sword_ride` sat at +0.0725 m - a 5.6 cm spread that no
headless test catches because it is invisible to everything except a per-clip ground
measurement.

The clips are all posed around the same static root height; what differs is how low each
pose hangs its feet. So the correction genuinely has to be per clip, which means it cannot be
one number in the build report.

What it does
------------
For every animation listed in the measurement report:

  * if the clip already animates the scene-root's translation, every sample's Y is shifted;
  * if it does not (this asset's hand-authored clips have no root translation channel at
    all), a constant translation channel is appended to that animation, so the clip carries
    its own offset instead of inheriting the static root.

The static root translation is deliberately left alone. The presentation layer holds the
AnimationPlayer in MANUAL on an authored state and on the very first frame, where the node's
own static sampler still writes the root; lowering the static root would sink that pose
through the floor while every playing clip stayed correct - an intermittent defect that
self-heals a few frames in, which is the worst kind to debug.

Usage:
    python3 tools/art/measure_glb_ground_contact.py --glb model.glb --report report.json
    python3 tools/art/apply_per_clip_ground_offset.py --glb model.glb --report report.json
"""

from __future__ import annotations

import argparse
import json
import struct
import sys
from pathlib import Path

## Clips that must keep their designed height: an airborne jump and a seated pose are not
## defects. Listed here rather than inferred, so the decision is reviewable.
DEFAULT_SKIP = ["jump"]

COMPONENT_FLOAT = 5126
## The buffer carries animation sampler data, so new bufferViews must NOT declare a `target`
## (glTF 2.0 reserves `target` for vertex/index data, and a validator rejects the mixture).



def read_glb(path: Path):
    raw = path.read_bytes()
    if raw[:4] != b"glTF":
        raise SystemExit(f"{path}: not a GLB")
    total = struct.unpack("<I", raw[8:12])[0]
    cursor, doc, blob = 12, None, b""
    while cursor < total:
        clen, _ = struct.unpack("<II", raw[cursor : cursor + 8])
        tag = raw[cursor + 4 : cursor + 8]
        payload = raw[cursor + 8 : cursor + 8 + clen]
        if tag == b"JSON":
            doc = json.loads(payload.decode("utf-8"))
        elif tag.startswith(b"BIN"):
            blob = payload
        cursor += 8 + clen
    if doc is None:
        raise SystemExit(f"{path}: no JSON chunk")
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


def root_nodes(doc) -> list[int]:
    return list(doc["scenes"][doc.get("scene", 0)]["nodes"])


def find_root_translation_channel(doc, animation, roots):
    for channel in animation.get("channels", []):
        target = channel["target"]
        if target.get("path") == "translation" and target.get("node") in roots:
            return channel
    return None


def shift_channel(doc, blob: bytearray, animation, channel, offset: float) -> int:
    """Add `offset` to the Y of every sample of an existing translation channel."""
    sampler = animation["samplers"][channel["sampler"]]
    accessor = doc["accessors"][sampler["output"]]
    view = doc["bufferViews"][accessor["bufferView"]]
    stride = view.get("byteStride") or 12
    base = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
    for i in range(accessor["count"]):
        at = base + i * stride + 4
        (value,) = struct.unpack_from("<f", blob, at)
        struct.pack_into("<f", blob, at, value + offset)
    for key in ("min", "max"):
        if accessor.get(key):
            accessor[key] = list(accessor[key])
            accessor[key][1] += offset
    return accessor["count"]


def append_accessor(doc, blob: bytearray, values: list[tuple], type_name: str) -> int:
    """Append a float accessor (and its bufferView) to the GLB, returning its index."""
    component_count = {"SCALAR": 1, "VEC3": 3}[type_name]
    payload = b"".join(struct.pack("<" + "f" * component_count, *v) for v in values)

    # bufferViews must start on a 4-byte boundary; the buffer is float-only so padding with
    # zeros is always safe and keeps the following view aligned.
    while len(blob) % 4:
        blob.append(0)
    byte_offset = len(blob)
    blob.extend(payload)

    doc.setdefault("bufferViews", []).append(
        {
            "buffer": 0,
            "byteOffset": byte_offset,
            "byteLength": len(payload),
        }
    )
    flat = [c for v in values for c in v]
    doc.setdefault("accessors", []).append(
        {
            "bufferView": len(doc["bufferViews"]) - 1,
            "componentType": COMPONENT_FLOAT,
            "count": len(values),
            "type": type_name,
            "min": [min(flat[i::component_count]) for i in range(component_count)],
            "max": [max(flat[i::component_count]) for i in range(component_count)],
        }
    )
    buffer = doc.setdefault("buffers", [{"byteLength": 0}])[0]
    buffer["byteLength"] = len(blob)
    return len(doc["accessors"]) - 1


def append_constant_translation(doc, blob: bytearray, animation, root: int, offset: float,
                                times: list[float]) -> None:
    """Give a clip that has no root translation channel its own constant one."""
    static = list(doc["nodes"][root].get("translation", [0.0, 0.0, 0.0]))
    value = [static[0], static[1] + offset, static[2]]
    input_accessor = append_accessor(doc, blob, [(t,) for t in times], "SCALAR")
    output_accessor = append_accessor(doc, blob, [tuple(value)] * len(times), "VEC3")
    animation.setdefault("samplers", []).append(
        {"input": input_accessor, "output": output_accessor, "interpolation": "LINEAR"}
    )
    animation.setdefault("channels", []).append(
        {
            "sampler": len(animation["samplers"]) - 1,
            "target": {"node": root, "path": "translation"},
        }
    )


def clip_times(doc, blob, animation) -> list[float]:
    """The clip's own time range, taken from any input accessor it already has."""
    for sampler in animation.get("samplers", []):
        accessor = doc["accessors"][sampler["input"]]
        view = doc["bufferViews"][accessor["bufferView"]]
        stride = view.get("byteStride") or 4
        base = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
        values = [
            struct.unpack_from("<f", blob, base + i * stride)[0]
            for i in range(accessor["count"])
        ]
        if values:
            return [values[0], values[-1]]
    return [0.0, 0.0]


def load_offsets(report_path: Path, skip: list[str], override: float | None) -> dict[str, float]:
    """Read the per-clip lift from a ground-contact report, keyed by clip name."""
    data = json.loads(report_path.read_text())
    offsets: dict[str, float] = {}
    for name, entry in data.get("clips", {}).items():
        if name in skip:
            continue
        offsets[name] = override if override is not None else float(entry["lift_needed_m"])
    return offsets


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--glb", required=True)
    parser.add_argument("--report", required=True,
                        help="JSON from tools/art/measure_glb_ground_contact.py")
    parser.add_argument("--skip", nargs="*", default=DEFAULT_SKIP,
                        help="clips that keep their designed height")
    parser.add_argument("--apply", action="store_true",
                        help="write the result; without it, only report what would change")
    parser.add_argument("--out", default="", help="write to this path instead of in place")
    args = parser.parse_args()

    glb = Path(args.glb)
    doc, blob = read_glb(glb)
    buffer = bytearray(blob)
    roots = root_nodes(doc)
    offsets = load_offsets(Path(args.report), args.skip, None)
    root = roots[0]

    print(f"{glb.name}: static root translation {doc['nodes'][root].get('translation')}")
    print(f"  {'clip':<14}{'offset_m':>10}{'target':>26}  samples")
    changed = {}
    for animation in doc.get("animations", []):
        name = animation.get("name", "?")
        if name not in offsets:
            print(f"  {name:<14}{'--':>10}{'skipped (airborne/seated)':>26}")
            continue
        offset = offsets[name]
        channel = find_root_translation_channel(doc, animation, roots)
        if channel is not None:
            count = shift_channel(doc, buffer, animation, channel, offset)
            target = "existing root translation"
        else:
            append_constant_translation(doc, buffer, animation, root, offset,
                                        clip_times(doc, buffer, animation))
            target = "appended constant channel"
            count = 2
        changed[name] = {"offset_m": round(offset, 5), "target": target, "samples": count}
        print(f"  {name:<14}{offset:>+10.5f}{target:>26}  {count}")

    if not changed:
        print("nothing to do")
        return 0

    if not args.apply:
        print("\ndry run - pass --apply to write")
        return 0

    out = Path(args.out) if args.out else glb
    write_glb(out, doc, bytes(buffer))
    print(f"\nwrote {out} ({out.stat().st_size:,} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
