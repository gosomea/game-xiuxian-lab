#!/usr/bin/env python3
"""Per-clip minimum/maximum world height of the foot bones, straight from a GLB.

Companion to `tools/art/measure_glb_ground_contact.py`, which is the authoritative check
(skinned mesh, lowest vertex). This one reports the same quantity at the BONE level, which is
what the Godot-side regression test can see.

Having both matters because the two disagree in a way that is easy to misread:

  * the vertex-level low is what "is the character standing on the ground" means;
  * the bone-level toe low also moves with the FOOT ROTATION, so a clip whose swing foot
    points its toe down reads much lower than one with flat feet, even when both are
    correctly grounded. Measured on this asset the six grounded clips span 0.10 m at the
    bone level while the vertex level is 0.000 m for all of them.

So this tool is for reasoning about what the Godot test can and cannot assert, not for
deciding whether the asset is correct. Do not tighten a Godot tolerance using bone numbers
alone.

Run:
    python3 tools/art/measure_glb_foot_bones.py --glb path/model.glb
"""

from __future__ import annotations

import argparse
import json
import struct
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from measure_glb_balance import (  # noqa: E402
    animation_channels,
    apply,
    bone_index,
    read_glb,
    world_matrices,
)

TOE_BONES = (
    ("mixamorig:LeftToeBase", "mixamorig_LeftToeBase", "LeftToeBase"),
    ("mixamorig:RightToeBase", "mixamorig_RightToeBase", "RightToeBase"),
)
ANKLE_BONES = (
    ("mixamorig:LeftFoot", "mixamorig_LeftFoot", "LeftFoot"),
    ("mixamorig:RightFoot", "mixamorig_RightFoot", "RightFoot"),
)


def measure_clip(doc, blob, anim, bones) -> dict:
    """Min/max world Y over the clip for the given bone spellings."""
    animated = animation_channels(doc, blob, anim)
    indices = [i for i in (bone_index(doc, names) for names in bones) if i is not None]
    if not indices:
        return {"error": "no matching bones"}
    count = doc["accessors"][anim["samplers"][0]["input"]]["count"]
    low, high = float("inf"), float("-inf")
    for sample in range(count):
        world = world_matrices(doc, animated, sample)
        for node in indices:
            y = apply(world[node], (0.0, 0.0, 0.0))[1]
            low, high = min(low, y), max(high, y)
    return {"min_y": round(low, 4), "max_y": round(high, 4), "frames": count}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--glb", required=True)
    parser.add_argument("--bones", default="toe", choices=["toe", "ankle"])
    parser.add_argument("--report", default="")
    args = parser.parse_args()

    doc, blob = read_glb(Path(args.glb))
    if doc is None:
        print("no JSON chunk")
        return 1
    bones = TOE_BONES if args.bones == "toe" else ANKLE_BONES
    print(f"{Path(args.glb).name}: {len(doc.get('animations', []))} clip(s), "
          f"bone level ({args.bones})\n")
    print(f"  {'clip':<14}{'min_y':>10}{'max_y':>10}{'frames':>8}")
    report = {"glb": str(args.glb), "bones": args.bones, "clips": {}}
    for anim in doc.get("animations", []):
        name = anim.get("name", "?")
        stats = measure_clip(doc, blob, anim, bones)
        report["clips"][name] = stats
        if "error" in stats:
            print(f"  {name:<14}  ERROR {stats['error']}")
            continue
        print(f"  {name:<14}{stats['min_y']:>+10.4f}{stats['max_y']:>+10.4f}"
              f"{stats['frames']:>8}")
    if args.report:
        Path(args.report).write_text(json.dumps(report, indent=2) + "\n")
        print(f"\nreport {args.report}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
