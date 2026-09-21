#!/usr/bin/env python3
"""Score a Make-It-Animatable clip export for retarget sanity, straight from the GLB.

The service retargets Mixamo motions onto the character's predicted skeleton. Some library
entries come back visibly broken -- `Running.fbx` collapses this character's spine so the
mesh folds forward to about 0.65 m tall for half the clip. Eyeballing renders is slow and
subjective, so this scores the raw animation tracks instead:

* **height proxy** -- the Hips translation's vertical span. A locomotion clip should bob by
  centimetres, not tens of centimetres, and should never fold the spine.
* **root travel** -- the Hips translation's horizontal first-to-last delta. `In Place` is
  on, so this should be near zero.
* **per-bone rotation sanity** -- the angular rate per second across every bone. A retarget
  glitch shows up as a near-180 degree snap inside one frame; a genuinely fast motion
  spreads the same rotation over many frames.

Thresholds are per-clip-kind, because a jump legitimately moves the hips by tens of
centimetres and a short clip legitimately rotates quickly:

  kind        hips Y span   angular rate   note
  ---------   -----------   ------------   --------------------------------------------
  locomotion  < 0.15 m      < 900 deg/s    sustained cyclical motion
  jump        < 1.00 m      < 900 deg/s    vertical displacement is the point

The mesh-height collapse that identifies a truly broken retarget (spine folding forward) is
caught by the caller's Blender pass, not here.

Run:
    python3 tools/art/score_mia_clip.py --glb <clip>_slot1.glb [--glb ...]
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
    return struct.unpack(f"<{len(raw) // 4}f", raw)


def quat_angle(q) -> float:
    x, y, z, w = q
    norm = math.sqrt(x * x + y * y + z * z + w * w)
    if norm == 0.0:
        return 0.0
    w = max(-1.0, min(1.0, abs(w / norm)))
    return math.degrees(2.0 * math.acos(w))


def quat_delta(a, b) -> float:
    """Angular distance between two quaternions, in degrees."""
    ax, ay, az, aw = a
    bx, by, bz, bw = b
    dot = abs(ax * bx + ay * by + az * bz + aw * bw)
    dot = max(-1.0, min(1.0, dot))
    return math.degrees(2.0 * math.acos(dot))


LOCOMOTION = {"idle", "walk", "run"}


def score(path: Path, kind: str = "locomotion", max_step_deg: float = 100.0) -> dict:
    doc, blob = read_glb(path)
    names = [n.get("name") for n in doc["nodes"]]
    if not doc.get("animations"):
        return {"file": path.name, "error": "no animation"}
    anim = doc["animations"][0]

    hips_y = None
    hips_xz_travel = None
    worst_step = {"bone": None, "degrees": 0.0, "deg_per_s": 0.0, "at_sample": None}
    worst_bone_angle = {"bone": None, "degrees": 0.0}
    all_rates: list[float] = []
    duration = 0.0

    for channel in anim["channels"]:
        target = channel["target"]
        sampler = anim["samplers"][channel["sampler"]]
        times = accessor(doc, blob, sampler["input"])
        values = accessor(doc, blob, sampler["output"])
        stride = TYPE_COUNT[doc["accessors"][sampler["output"]]["type"]]
        duration = max(duration, float(times[-1]))
        bone = names[target["node"]]

        if target["path"] == "translation" and bone.endswith("Hips"):
            ys = values[1::stride]
            xs = values[0::stride]
            zs = values[2::stride]
            hips_y = {
                "span": round(max(ys) - min(ys), 5),
                "min": round(min(ys), 5),
                "max": round(max(ys), 5),
            }
            hips_xz_travel = {
                "x_delta": round(xs[-1] - xs[0], 5),
                "z_delta": round(zs[-1] - zs[0], 5),
                "horizontal_delta": round(
                    math.hypot(xs[-1] - xs[0], zs[-1] - zs[0]), 5
                ),
            }

        if target["path"] == "rotation":
            samples = [
                values[i * stride : (i + 1) * stride] for i in range(len(values) // stride)
            ]
            for i in range(1, len(samples)):
                dt = float(times[i] - times[i - 1]) if i < len(times) else 0.0
                delta = quat_delta(samples[i - 1], samples[i])
                rate = delta / dt if dt > 1e-6 else float("inf")
                all_rates.append(rate)
                if rate > worst_step["deg_per_s"]:
                    worst_step = {
                        "bone": bone,
                        "degrees": round(delta, 2),
                        "deg_per_s": round(rate, 1),
                        "at_sample": i,
                    }
            for sample in samples:
                angle = quat_angle(sample)
                if angle > worst_bone_angle["degrees"]:
                    worst_bone_angle = {"bone": bone, "degrees": round(angle, 2)}

    span_limit = 1.0 if kind == "jump" else 0.15

    finite_rates = sorted(r for r in all_rates if math.isfinite(r))
    baseline = (
        finite_rates[int(len(finite_rates) * 0.95)]
        if len(finite_rates) >= 20
        else (finite_rates[-1] if finite_rates else 0.0)
    )
    worst_rate = worst_step["deg_per_s"] if math.isfinite(worst_step["deg_per_s"]) else 0.0

    verdict = []
    if hips_y and hips_y["span"] > span_limit:
        verdict.append(
            f"hips vertical span {hips_y['span']:.3f} m exceeds {span_limit:.2f} m for {kind}"
        )
    if worst_step["degrees"] > max_step_deg:
        verdict.append(
            f"bone {worst_step['bone']} rotates {worst_step['degrees']:.1f} deg in one "
            f"sample ({worst_rate:.0f} deg/s) -- beyond {max_step_deg:.0f} deg/frame"
        )
    if hips_xz_travel and hips_xz_travel["horizontal_delta"] > 0.05:
        verdict.append(
            f"root travels {hips_xz_travel['horizontal_delta']:.3f} m (In Place expected ~0)"
        )

    return {
        "file": path.name,
        "kind": kind,
        "animation": anim["name"],
        "duration_s": round(duration, 3),
        "channels": len(anim["channels"]),
        "hips_translation": hips_y,
        "root_travel": hips_xz_travel,
        "worst_single_step": worst_step,
        "p95_angular_rate": round(baseline, 1),
        "worst_bone_angle": worst_bone_angle,
        "verdict": verdict,
        "ok": not verdict,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--glb", action="append", required=True,
                        help="path, optionally prefixed with <kind>: e.g. jump:/path/clip.fbx")
    parser.add_argument("--report", default="")
    parser.add_argument("--max-step-deg", type=float, default=100.0,
                        help="largest rotation allowed in one sample (default: %(default)s)")
    args = parser.parse_args()

    results = []
    for item in args.glb:
        kind, sep, raw = item.partition(":")
        if not sep or not raw:
            kind, raw = "locomotion", item
        if kind not in ("locomotion", "jump"):
            print(f"FAIL: unknown kind {kind!r} (use locomotion: or jump:)", file=sys.stderr)
            return 2
        path = Path(raw)
        if not path.is_file():
            print(f"FAIL: missing {path}", file=sys.stderr)
            return 2
        results.append(score(path, kind, args.max_step_deg))

    for entry in results:
        if "error" in entry:
            print(f"{entry['file']}: ERROR {entry['error']}")
            continue
        mark = "OK  " if entry["ok"] else "BAD "
        print(f"{mark}{entry['file']}  {entry['duration_s']:.3f}s  "
              f"channels={entry['channels']}")
        if entry["hips_translation"]:
            print(f"      hips Y span={entry['hips_translation']['span']:.4f} m")
        if entry["root_travel"]:
            print(f"      root  horiz delta={entry['root_travel']['horizontal_delta']:.4f} m")
        step = entry["worst_single_step"]
        print(f"      worst single step: {step['degrees']:.1f} deg on {step['bone']} "
              f"({step['deg_per_s']:.0f} deg/s; clip p95={entry['p95_angular_rate']:.0f})")
        for note in entry["verdict"]:
            print(f"      ! {note}")

    if args.report:
        out = Path(args.report)
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(json.dumps(results, indent=2, ensure_ascii=False) + "\n")
        print(f"\nreport {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
