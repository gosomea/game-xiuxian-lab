"""Trial runner: solve the leg shear on a working copy of the runtime GLB.

Run with Blender:
    blender --background --factory-startup \
        --python tools/art/fix_leg_shear_trial.py -- \
        --glb tmp_probe/work.glb --report tmp_probe/leg_fix_report.json
"""
import json
import sys
from pathlib import Path

import bpy

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(Path(__file__).resolve().parent))

import cultivator_leg_fix  # noqa: E402


def parse_args():
    argv = sys.argv
    argv = argv[argv.index("--") + 1:] if "--" in argv else []
    args = {}
    for i, a in enumerate(argv):
        if a.startswith("--"):
            args[a[2:]] = argv[i + 1] if i + 1 < len(argv) and not argv[i + 1].startswith("--") else True
    return args


def main():
    args = parse_args()
    glb = Path(args["glb"])
    report_path = Path(args.get("report", "tmp_probe/leg_fix_report.json"))

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(glb))

    armature = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    scene = bpy.context.scene

    report = cultivator_leg_fix.correct_standing_shear(armature, scene)
    report_path.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n")
    print(f"TRIAL failed_clips={report.get('failed_clips')} report={report_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
