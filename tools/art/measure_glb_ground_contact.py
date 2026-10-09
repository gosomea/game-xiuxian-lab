#!/usr/bin/env python3
"""Report, per clip, how far the character's lowest skinned vertex is above the ground plane.

Why this exists
---------------
The runtime contract for this project's characters is "feet at y=0" - the same contract the
previous two characters (`cultivator_neutral_youth_v7`, `cultivator_rigged`) satisfy, both
measuring 0.0008 m. The build script states it too, and derives a global ground offset from
`min(lowest vertex) across the locomotion clips`.

That `min` is the problem this tool exposes. Taking the minimum over clips makes exactly ONE
clip touch zero and leaves every other clip floating by (its own low - the minimum). Whether
the shipped asset actually rests on the ground is therefore not answerable from the build
report, which only records the value it used; it has to be measured on the exported file.

This measures it on the runtime GLB, per clip, over every frame of every clip, using the
evaluated (skinned) mesh - the mesh's own node transform is meaningless for a skinned mesh.

Run:
    blender --background --factory-startup \
        --python tools/art/measure_glb_ground_contact.py -- \
        --glb src/game/actors/swordsman/models/cultivator_tripo_v9.glb

Reading it: `min_z` near 0 means the character is standing on the ground. A positive value is
a hover, and the printed `lift_needed_m` is exactly the constant Y shift that would fix it.
Clips that are airborne or seated by design are reported but not judged.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import bpy

## Clips that are allowed to leave the ground: jump is airborne by design, meditate is seated
## (its lowest contact is the shin/foot resting on the ground, so it should still be near 0,
## but a small positive value is not the same defect as a standing pose hovering).
AIRBORNE = {"jump"}


def parse_args() -> argparse.Namespace:
    argv = sys.argv
    argv = argv[argv.index("--") + 1 :] if "--" in argv else []
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--glb", "--blend", dest="glb", required=True)
    parser.add_argument("--tolerance", type=float, default=0.02,
                        help="a grounded clip may sit this far (m) above the plane")
    parser.add_argument("--report", default="")
    return parser.parse_args(argv)


def evaluated_min_z(mesh) -> float:
    """Lowest world Z of the SKINNED mesh.

    Uses the evaluated object's matrix_world: the mesh is parented to the armature, so after
    any root shift the original object's matrix_world is stale and would read the pre-shift
    value (the same trap `tools/art/build_cultivator_tripo_v9_runtime_glb.py` documents).
    """
    depsgraph = bpy.context.evaluated_depsgraph_get()
    evaluated = mesh.evaluated_get(depsgraph)
    matrix = evaluated.matrix_world
    return min((matrix @ v.co).z for v in evaluated.data.vertices)


def skinned_mesh(armature):
    """The character mesh: the one deformed by the armature, not any stray prop.

    Matched by ARMATURE modifier rather than "the first mesh in the file". These assets also
    carry an unparented, unmodified `Icosphere`; picking meshes positionally measures that
    instead and reports a uniform, obviously-wrong value.
    """
    for obj in bpy.data.objects:
        if obj.type != "MESH":
            continue
        for modifier in obj.modifiers:
            if modifier.type == "ARMATURE":
                return obj
    return None


def main() -> int:
    args = parse_args()
    path = Path(args.glb)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    if path.suffix.lower() == ".blend":
        bpy.ops.wm.open_mainfile(filepath=str(path.resolve()))
    else:
        bpy.ops.import_scene.gltf(filepath=str(path))

    armature = next((o for o in bpy.data.objects if o.type == "ARMATURE"), None)
    mesh = skinned_mesh(armature)
    if armature is None or mesh is None:
        print(f"{path.name}: no armature / no skinned mesh found")
        return 1
    if armature.animation_data is None:
        armature.animation_data_create()

    scene = bpy.context.scene
    clips = sorted(a.name for a in bpy.data.actions)
    print(f"{path.name}: {len(clips)} clip(s), tolerance {args.tolerance} m\n")
    print(f"  {'clip':<14}{'min_z':>10}{'max_z':>10}{'at_frame':>10}   verdict")

    report = {"glb": str(path), "clips": {}, "problems": []}
    for name in clips:
        action = bpy.data.actions[name]
        armature.animation_data.action = action
        start, end = (int(round(v)) for v in action.frame_range)
        low, high, low_frame = float("inf"), float("-inf"), start
        for frame in range(start, end + 1):
            scene.frame_set(frame)
            value = evaluated_min_z(mesh)
            if value < low:
                low, low_frame = value, frame
            high = max(high, value)
        entry = {
            "min_z": round(low, 4),
            "max_z_min_vertex": round(high, 4),
            "min_z_frame": low_frame,
            "frames": [start, end],
        }
        lift = -low
        problem = None
        if name not in AIRBORNE and abs(low) > args.tolerance:
            problem = (f"lowest vertex rests {low:+.4f} m off the ground "
                       f"(lift_needed_m {lift:+.4f})")
        entry["lift_needed_m"] = round(lift, 4)
        entry["problem"] = problem
        report["clips"][name] = entry
        tag = "OK" if problem is None else "BAD"
        print(f"  {name:<14}{low:>+10.4f}{high:>+10.4f}{low_frame:>10}   {tag}")
        if problem:
            print(f"      ! {problem}")
            report["problems"].append(f"{name}: {problem}")

    print()
    if report["problems"]:
        print(f"FAIL: {len(report['problems'])} grounded clip(s) do not rest on the ground")
    else:
        print("OK: every grounded clip rests on the ground plane")

    if args.report:
        out = Path(args.report)
        out.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n")
        print(f"report {out}")
    return 1 if report["problems"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
