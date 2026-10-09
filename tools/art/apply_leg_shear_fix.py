"""Apply the leg-shear correction to the runtime GLB, then re-run per-clip grounding.

Run with Blender:
    blender --background --factory-startup \
        --python tools/art/apply_leg_shear_fix.py -- \
        --glb src/game/actors/swordsman/models/cultivator_tripo_v9.glb \
        --out docs/art/cultivator_leg_shear_20261008/leg_fixed.glb \
        --report docs/art/cultivator_leg_shear_20261008/leg_fix_applied.json
"""
import json
import sys
from pathlib import Path

import bpy

sys.path.insert(0, str(Path(__file__).resolve().parent))
import cultivator_leg_fix  # noqa: E402


def parse_args():
    argv = sys.argv
    argv = argv[argv.index("--") + 1:] if "--" in argv else []
    args = {}
    for i, a in enumerate(argv):
        if a.startswith("--"):
            args[a[2:]] = (argv[i + 1] if i + 1 < len(argv)
                           and not argv[i + 1].startswith("--") else True)
    return args


def main():
    args = parse_args()
    glb = Path(args["glb"])
    out = Path(args.get("out", str(glb)))
    report_path = Path(args.get("report", "docs/art/cultivator_leg_shear_20261008/leg_fix_applied.json"))

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(glb))
    armature = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    scene = bpy.context.scene

    report = {"glb": str(glb), "out": str(out)}
    report["leg_shear"] = cultivator_leg_fix.correct_standing_shear(armature, scene)

    # Export in place, then let the existing pipeline take over: the corrected standing
    # clips reach the ground differently (straightening a slanted leg shortens its
    # vertical reach by ~1.9 cm), so the per-clip ground offset must be re-measured on
    # the NEW poses and re-applied. That step runs in the plain-Python tools, not here.
    bpy.ops.export_scene.gltf(filepath=str(out), export_apply=True)
    report["exported_bytes"] = out.stat().st_size if out.exists() else 0
    report_path.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n")
    print(f"APPLIED failed={report['leg_shear'].get('failed_clips')} -> {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
