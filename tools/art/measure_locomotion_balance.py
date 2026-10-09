#!/usr/bin/env python3
"""Measure walking pelvis/ankle balance and loop continuity on an exported GLB.

Blender --background --factory-startup --python tools/art/measure_locomotion_balance.py -- --glb ... --report ...
The mean is a whole-cycle measure; aligning both ankles every frame would erase gait.
"""
import argparse
import json
import math
import sys
from pathlib import Path
import bpy
sys.path.insert(0, str(Path(__file__).resolve().parent))
from measure_glb_ground_contact import evaluated_min_z, skinned_mesh


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--glb','--blend',dest='glb',required=True)
    parser.add_argument('--report',required=True)
    parser.add_argument('--check',action='store_true',help='enforce corrected walking balance and seam tolerances')
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:])
    bpy.ops.wm.read_factory_settings(use_empty=True)
    if Path(args.glb).suffix.lower()=='.blend':
        bpy.ops.wm.open_mainfile(filepath=str(Path(args.glb).resolve()))
    else:
        bpy.ops.import_scene.gltf(filepath=str(Path(args.glb)))
    rig=next(o for o in bpy.data.objects if o.type=='ARMATURE')
    scene=bpy.context.scene
    def point(n):return rig.matrix_world@rig.pose.bones['mixamorig:'+n].head
    rig.animation_data.action=bpy.data.actions['idle'];scene.frame_set(0)
    forward=(point('LeftToeBase')+point('RightToeBase')-point('LeftFoot')-point('RightFoot'))/2
    forward.z=0;forward.normalize()
    action=bpy.data.actions['walk'];rig.animation_data.action=action
    first,last=action.frame_range
    samples=[]
    soles=[]
    mesh=skinned_mesh(rig)
    for index in range(121):
        time=first+(last-first)*index/120
        scene.frame_set(math.floor(time),subframe=time%1)
        ankles=(point('LeftFoot')+point('RightFoot'))/2
        samples.append((ankles-point('Hips')).dot(forward))
        soles.append(evaluated_min_z(mesh))
    scene.frame_set(math.floor(first),subframe=first%1)
    matrices={b.name:(rig.matrix_world@b.matrix).copy() for b in rig.pose.bones}
    scene.frame_set(math.floor(last),subframe=last%1)
    angular=max(math.degrees(matrices[b.name].to_quaternion().rotation_difference((rig.matrix_world@b.matrix).to_quaternion()).angle) for b in rig.pose.bones)
    translation=max((matrices[b.name].translation-(rig.matrix_world@b.matrix).translation).length for b in rig.pose.bones)
    report={'glb':args.glb,'samples':len(samples),'feet_ahead_of_pelvis_mean_m':sum(samples)/len(samples),
            'feet_ahead_range_m':[min(samples),max(samples)],
            'walk_subframe_sole_min_max_m':[min(soles),max(soles)],'loop_seam_max_angle_deg':angular,
            'loop_seam_max_translation_m':translation,'problems':[]}
    if args.check:
        if abs(report['feet_ahead_of_pelvis_mean_m'])>.03:report['problems'].append('walking average pelvis/ankle offset exceeds 3cm')
        if min(soles)<-.02 or max(soles)>.02:report['problems'].append('walking subframe shoe contact exceeds 2cm')
        if angular>.5 or translation>.001:report['problems'].append('walking loop seam exceeds .5deg / 1mm')
    Path(args.report).write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2))
    return bool(report['problems'])

if __name__=='__main__':raise SystemExit(main())
