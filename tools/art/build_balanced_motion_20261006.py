#!/usr/bin/env python3
"""Bake a world-space walking balance correction, preserving the original asset.

Blender --background --factory-startup --python tools/art/build_balanced_motion_20261006.py
The input is the self-contained aligned Blender file. Mesh/rest/weights are unchanged.
"""
import json
import math
from pathlib import Path
import sys
import bpy
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'docs/art/cultivator_aligned_motion_20260927/cultivator_aligned_motion_20260927.blend'
OUT = ROOT / 'docs/art/cultivator_balanced_motion_20261006'
GLB = ROOT / 'src/game/actors/swordsman/models/cultivator_balanced_motion_20261006.glb'
sys.path.insert(0, str(Path(__file__).parent))
from export_cultivator_aligned_motion_20260927 import CLIPS, glb_animation_names
from measure_glb_ground_contact import evaluated_min_z, skinned_mesh


def main():
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
    bpy.context.preferences.filepaths.save_version = 0
    rig = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
    mesh = skinned_mesh(rig)
    scene = bpy.context.scene
    assert {a.name for a in bpy.data.actions} == CLIPS
    action = bpy.data.actions['walk']
    rig.animation_data.action = action
    frames = range(math.floor(action.frame_range[0]), math.ceil(action.frame_range[1]) + 1)
    bone = lambda n: rig.pose.bones['mixamorig:' + n]
    world = lambda n: rig.matrix_world @ bone(n).matrix
    records = []
    for f in frames:
        scene.frame_set(f)
        bpy.context.view_layer.update()
        record = {n: world(n).copy() for n in ('Hips', 'LeftUpLeg', 'RightUpLeg', 'LeftFoot', 'RightFoot')}
        record['rig_matrix'] = rig.matrix_world.copy()
        record['basis'] = {b.name: b.matrix_basis.copy() for b in rig.pose.bones}
        records.append(record)
    # The imported cycle's fractional endpoint differs slightly after 24fps
    # resampling. Close the loop explicitly, so wrapping cannot jerk the feet.
    records[-1] = records[0]
    action.name = 'walk_source'
    fresh = bpy.data.actions.new('walk')
    rig.animation_data.action = fresh
    bpy.data.actions.remove(action)
    deltas = [(r['LeftFoot'].translation + r['RightFoot'].translation)/2 - r['Hips'].translation for r in records]
    mean = sum(deltas, Vector())/len(deltas)
    # +world X swings the downward leg toward +Y; this asset faces -Y.
    theta = math.atan2(-mean.y, -mean.z)
    rot = Matrix.Rotation(theta, 4, 'X')
    inverse = rig.matrix_world.inverted()
    offsets, floor_shifts = [], []
    for f, record in zip(frames, records):
        scene.frame_set(f)
        # Imported clips also key the ARMATURE OBJECT ground offset. Carry it
        # into the new action; otherwise selecting another clip leaks its root
        # transform into walk and shifts every walking shoe by a constant.
        rig.matrix_world = record['rig_matrix']
        for channel in ('location', 'rotation_quaternion', 'scale'):
            rig.keyframe_insert(channel, frame=f)
        inverse = rig.matrix_world.inverted()
        # Always start from the captured source pelvis. Inserting keys into a
        # sparse source curve changes evaluation of later frames; reading the
        # already edited hips would accumulate the ground correction.
        for b in rig.pose.bones:
            b.matrix_basis = record['basis'][b.name]
        bone('Hips').matrix = inverse @ record['Hips']
        bpy.context.view_layer.update()
        for side in ('Left', 'Right'):
            thigh = bone(side+'UpLeg')
            original = record[side+'UpLeg']
            pivot = original.translation
            thigh.matrix = inverse @ Matrix.Translation(pivot) @ rot @ Matrix.Translation(-pivot) @ original
            bpy.context.view_layer.update()
            foot = bone(side+'Foot')
            # Keep the authored heel/toe roll, rather than pitching the shoe with the leg.
            shoe = record[side+'Foot'].copy()
            shoe.translation = (rig.matrix_world @ foot.matrix).translation
            foot.matrix = inverse @ shoe
            for b in (thigh, foot):
                b.keyframe_insert('rotation_quaternion', frame=f)
        bpy.context.view_layer.update()
        minimum = evaluated_min_z(mesh)
        hips = bone('Hips')
        hip_world = rig.matrix_world @ hips.matrix
        hip_world.translation.z -= minimum
        hips.matrix = inverse @ hip_world
        for b in rig.pose.bones:
            for channel in ('location', 'rotation_quaternion', 'scale'):
                b.keyframe_insert(channel, frame=f)
        bpy.context.view_layer.update()
        floor_shifts.append(-minimum)
        ankles = (world('LeftFoot').translation + world('RightFoot').translation)/2
        offsets.append((world('Hips').translation-ankles).y)
    # Linear dense keys avoid Bezier overshoot between planted frames.
    for layer in fresh.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                for curve in bag.fcurves:
                    for key in curve.keyframe_points:
                        key.interpolation = 'LINEAR'
    # Re-evaluate the completed dense action before final contact calibration;
    # this includes both object and bone channels, not only manually set matrices.
    contact_before = []
    for f in frames:
        scene.frame_set(f)
        bpy.context.view_layer.update()
        low = evaluated_min_z(mesh)
        contact_before.append(low)
        hips = bone('Hips')
        inverse = rig.matrix_world.inverted()
        m = world('Hips').copy()
        m.translation.z -= low
        hips.matrix = inverse @ m
        hips.keyframe_insert('location', frame=f)
    # Runtime playback follows measured stance speed; other clips retain timing.
    report = {'source': str(SOURCE.relative_to(ROOT)), 'correction_world_x_deg': math.degrees(theta),
              'walk_before_pelvis_to_ankles_y_mean_m': -mean.y,
              'walk_after_pelvis_to_ankles_y_mean_m': sum(offsets)/len(offsets),
              'floor_shift_min_max_m': [min(floor_shifts),max(floor_shifts)],
              'completed_contact_before_min_max_m': [min(contact_before),max(contact_before)],
              'original_fps': scene.render.fps, 'clips': {}}
    for a in bpy.data.actions:
        a.use_fake_user = True
        rig.animation_data.action = a
        first,last=map(round,a.frame_range)
        path=[]
        for f in range(first,last+1):
            scene.frame_set(f)
            path.append({side: list(world(side+'Foot').translation) for side in ('Left','Right')})
        speeds=[]
        for prev,now in zip(path,path[1:]):
            side=min(('Left','Right'),key=lambda side: prev[side][2])
            if now[side][2] <= now['Right' if side=='Left' else 'Left'][2]:
                v=(now[side][1]-prev[side][1])*scene.render.fps
                if v>0: speeds.append(v)
        report['clips'][a.name]={'duration_s':(last-first)/scene.render.fps,
                               'stance_backward_speed_mean_mps':sum(speeds)/len(speeds) if speeds else 0,
                               'stance_backward_speed_median_mps':sorted(speeds)[len(speeds)//2] if speeds else 0}
    # Sparse legacy clips do not key every location/scale channel. Clear the
    # baked walk's residual basis before selecting idle for glTF rest sampling.
    rig.animation_data.action = None
    for b in rig.pose.bones:
        b.matrix_basis = Matrix.Identity(4)
    rig.animation_data.action = bpy.data.actions['idle']
    scene.frame_set(0)
    bpy.context.view_layer.update()
    OUT.mkdir(parents=True,exist_ok=True)
    (OUT/'build_report.json').write_text(json.dumps(report,indent=2)+'\n')
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'cultivator_balanced_motion_20261006.blend'))
    bpy.ops.object.select_all(action='DESELECT')
    rig.select_set(True);mesh.select_set(True);bpy.context.view_layer.objects.active=rig
    bpy.ops.export_scene.gltf(filepath=str(GLB),export_format='GLB',use_selection=True,
        export_animation_mode='ACTIONS',export_animations=True,export_skins=True,
        export_yup=True,export_apply=False,export_normals=True,export_materials='EXPORT',
        export_frame_range=False,export_force_sampling=True,export_bake_animation=False)
    assert glb_animation_names(GLB)==CLIPS
    print(json.dumps(report,indent=2))

if __name__=='__main__': main()
