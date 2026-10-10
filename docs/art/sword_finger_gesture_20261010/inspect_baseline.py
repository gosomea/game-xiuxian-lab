import bpy,json
from mathutils import Vector
from pathlib import Path
root=Path(__file__).resolve().parents[3]
bpy.ops.wm.open_mainfile(filepath=str(root/'docs/art/cultivator_upright_motion_20261009/cultivator_upright_motion_20261009.blend'))
rig=next(o for o in bpy.data.objects if o.type=='ARMATURE')
rig.animation_data.action=None
for p in rig.pose.bones:p.matrix_basis.identity()
bpy.context.view_layer.update()
b=rig.data.bones['mixamorig:RightHand'];print('HAND_MATRIX',list(map(list,b.matrix_local)));print('HAND_HEAD_TAIL',list(b.head_local),list(b.tail_local));print('RIG',rig.name,list(map(list,rig.matrix_world)))
for obj in bpy.data.objects:
 if obj.type!='MESH':continue
 group=obj.vertex_groups.get('mixamorig:RightHand')
 if not group:continue
 vs=[v for v in obj.data.vertices if any(g.group==group.index and g.weight>.5 for g in v.groups)]
 coords=[b.matrix_local.inverted()@v.co for v in vs]
 print('MESH',obj.name,'verts',len(obj.data.vertices),'hand',len(vs),'bounds',[[min(p[k] for p in coords),max(p[k] for p in coords)] for k in range(3)],'matrix',list(map(list,obj.matrix_world)))
 print('MATERIALS',[(m.name,[n.type for n in m.node_tree.nodes]) for m in obj.data.materials])
 for m in obj.data.materials:
  for n in m.node_tree.nodes:
   if n.type=='TEX_IMAGE':print('IMAGE',n.image.name,list(n.image.size))
scene=bpy.context.scene;scene.render.engine='BLENDER_EEVEE';scene.render.resolution_x=900;scene.render.resolution_y=700;scene.render.resolution_percentage=100
scene.world=bpy.data.worlds.new('Hand inspection world');scene.world.color=(.22,.22,.22)
hand=rig.matrix_world@b.head_local
bpy.ops.object.camera_add(location=hand+Vector((.15,-.32,.18)));cam=bpy.context.object;cam.rotation_euler=(hand+Vector((-.08,0,0))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.type='ORTHO';cam.data.ortho_scale=.4;scene.camera=cam
bpy.ops.object.light_add(type='AREA',location=hand+Vector((.15,-.2,.5)));bpy.context.object.data.energy=40;bpy.context.object.data.size=.4
out=root/'docs/art/sword_finger_gesture_20261010';out.mkdir(parents=True,exist_ok=True);scene.render.filepath=str(out/'baseline_hand.png');bpy.ops.render.render(write_still=True)
