"""Original articulated right hand. Run with Blender --background --python this file.
Hand frame: X towards thumb, Y from wrist to fingers, Z back of hand.
"""
import bpy, bmesh, json, math, struct
from mathutils import Vector
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
OUT = Path(__file__).resolve().parent
GLB = ROOT/'src/game/shared/sword_cast/models/sword_finger_hand_20261010.glb'
bpy.ops.wm.read_factory_settings(use_empty=True)
scene=bpy.context.scene
scene.render.fps=24
scene.frame_start=1; scene.frame_end=25
arm=bpy.data.armatures.new('SwordFingerRig')
rig=bpy.data.objects.new('SwordFingerRig',arm);scene.collection.objects.link(rig)
bpy.context.view_layer.objects.active=rig;rig.select_set(True)
bpy.ops.object.mode_set(mode='EDIT')
root=arm.edit_bones.new('Wrist');root.head=(0,0,0);root.tail=(0,.064,0)
fingers={
 'Index':(.027,.061,.076,.0090),
 'Middle':(.006,.068,.083,.0093),
 'Ring':(-.015,.064,.072,.0086),
 'Little':(-.032,.054,.057,.0074),
 'Thumb':(.037,.028,.054,.011),
}
chains={}
for name,(x,y,length,radius) in fingers.items():
 direction=Vector((.66,.75,-.10)).normalized() if name=='Thumb' else Vector((0,1,0))
 start=Vector((x,y,0))
 ratios=(.44,.32,.24)
 chain=[]
 for i,ratio in enumerate(ratios):
  bone=arm.edit_bones.new(name+str(i+1));bone.head=start;bone.tail=start+direction*length*ratio
  bone.parent=root if i==0 else arm.edit_bones[chain[-1]];bone.use_connect=i>0
  chain.append(bone.name);start=bone.tail.copy()
 chains[name]=chain
bpy.ops.object.mode_set(mode='OBJECT')
verts=[];faces=[];weights=[];matids=[]
def vert(p,w):
 verts.append(tuple(p));weights.append(w);return len(verts)-1
def loops_mesh(loops):
 for a,b in zip(loops,loops[1:]):
  for i in range(len(a)):faces.append((a[i],a[(i+1)%len(a)],b[(i+1)%len(b)],b[i]));matids.append(0)
 faces.append(tuple(reversed(loops[0])));matids.append(0)
 faces.append(tuple(loops[-1]));matids.append(0)
# Palm loft, small rounded wrist and anatomical width towards the knuckles.
loops=[]
for y,rx,rz,cx in [(-.023,.022,.015,.004),(-.006,.025,.017,.004),(.018,.034,.018,.002),(.044,.039,.016,0),(.061,.034,.013,-.001),(.071,.023,.011,0)]:
 loop=[]
 for i in range(24):
  a=2*math.pi*i/24
  loop.append(vert(Vector((cx+rx*math.cos(a),y,rz*math.sin(a))),{'Wrist':1.0}))
 loops.append(loop)
loops_mesh(loops)
for name,(x,y,length,radius) in fingers.items():
 chain=chains[name];first=arm.bones[chain[0]];axis=(first.tail_local-first.head_local).normalized()
 across=Vector((axis.y,-axis.x,0)).normalized();depth=axis.cross(across).normalized()
 loops=[]
 for j in range(16):
  t=j/15
  distance=length*t
  seg=min(2,0 if t<.44 else 1 if t<.76 else 2)
  w={chain[seg]:1.0}
  for joint,at in enumerate((.44,.76)):
   if abs(t-at)<.08:
    alpha=(t-at+.08)/.16;w={chain[joint]:1-alpha,chain[joint+1]:alpha}
  if t<.10:w={'Wrist':.35*(1-t/.1),chain[0]:.65+.35*(t/.1)}
  taper=1-.25*t
  if t>.88:taper*=math.sqrt(max(.04,1-((t-.88)/.135)**2))
  center=first.head_local+axis*distance
  loop=[]
  for i in range(12):
   a=2*math.pi*i/12
   loop.append(vert(center+across*math.cos(a)*radius*taper+depth*math.sin(a)*radius*.85*taper,w))
  loops.append(loop)
 loops_mesh(loops)
# Thin, rounded nails make the two extended fingertips distinguishable.
for name,(x,y,length,radius) in fingers.items():
 chain=chains[name];bone=arm.bones[chain[-1]]
 axis=(bone.tail_local-bone.head_local).normalized()
 across=Vector((axis.y,-axis.x,0)).normalized()
 center=bone.tail_local-axis*.008+Vector((0,0,radius*.72))
 middle=vert(center+Vector((0,0,.001)),{chain[-1]:1.0})
 ring=[]
 for i in range(16):
  a=2*math.pi*i/16
  ring.append(vert(center+across*math.cos(a)*radius*.60+axis*math.sin(a)*.0065,{chain[-1]:1.0}))
 for i in range(16):faces.append((middle,ring[i],ring[(i+1)%16]));matids.append(1)
mesh=bpy.data.meshes.new('ArticulatedRightHand');mesh.from_pydata(verts,[],faces);mesh.update()
bm=bmesh.new();bm.from_mesh(mesh);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(mesh);bm.free()
obj=bpy.data.objects.new('ArticulatedRightHand',mesh);scene.collection.objects.link(obj)
mat=bpy.data.materials.new('Warm skin');mat.diffuse_color=(.67,.47,.39,1);mat.use_nodes=True
bsdf=mat.node_tree.nodes.get('Principled BSDF');bsdf.inputs['Base Color'].default_value=(.67,.47,.39,1);bsdf.inputs['Roughness'].default_value=.66
obj.data.materials.append(mat)
nail=bpy.data.materials.new('Natural nails');nail.diffuse_color=(.83,.70,.62,1);nail.use_nodes=True
nail.node_tree.nodes.get('Principled BSDF').inputs['Base Color'].default_value=(.83,.70,.62,1)
nail.node_tree.nodes.get('Principled BSDF').inputs['Roughness'].default_value=.42
obj.data.materials.append(nail)
for i,p in enumerate(mesh.polygons):p.material_index=matids[i]
for p in mesh.polygons:p.use_smooth=True
for bone in arm.bones:
 group=obj.vertex_groups.new(name=bone.name)
 for i,w in enumerate(weights):
  if bone.name in w and w[bone.name]>.0001:group.add([i],w[bone.name],'REPLACE')
mod=obj.modifiers.new('Finger skin','ARMATURE');mod.object=rig;obj.parent=rig
# Refine each original mesh, retaining a small editable source.
sub=obj.modifiers.new('Smooth silhouette','SUBSURF');sub.levels=1;sub.render_levels=1
rig.animation_data_create()
for frame,gesture in [(1,0),(25,1)]:
 scene.frame_set(frame)
 for name,chain in chains.items():
  for i,bname in enumerate(chain):
   p=rig.pose.bones[bname];p.rotation_mode='XYZ'
   relaxed=[-.14,-.18,-.12][i]
   curl=relaxed
   spread=0.0
   if name in ['Ring','Little']:curl=[-1.55,-1.40,-.6][i]*gesture+relaxed*(1-gesture)
   elif name=='Thumb':curl=[-.40,-.75,-.35][i]*gesture+relaxed*(1-gesture);spread=.95*gesture if i==0 else 0
   else:
    curl=-.025*gesture+relaxed*(1-gesture)
    # Close the two sword fingers at their tips while keeping their separate joints.
    spread=(.055 if name=='Index' else -.005)*gesture if i==0 else 0
   p.rotation_euler=(curl,0,spread)
   p.keyframe_insert('rotation_euler',frame=frame,group=bname)
rig.animation_data.action.name='gesture'
for layer in rig.animation_data.action.layers:
 for strip in layer.strips:
  for bag in strip.channelbags:
   for fc in bag.fcurves:
    for key in fc.keyframe_points:key.interpolation='LINEAR'
scene.frame_set(1)
# Save editable source before adding preview-only camera and lights.
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'sword_finger_hand_20261010.blend'))
bpy.ops.object.select_all(action='DESELECT');rig.select_set(True);obj.select_set(True);bpy.context.view_layer.objects.active=rig
bpy.ops.export_scene.gltf(filepath=str(GLB),export_format='GLB',use_selection=True,export_animation_mode='ACTIONS',export_animations=True,export_skins=True,export_yup=True,export_apply=True,export_normals=True,export_materials='EXPORT',export_frame_range=False,export_force_sampling=True,export_bake_animation=False)
# Structure readback is independent of Blender's scene.
data=GLB.read_bytes();n=struct.unpack_from('<I',data,12)[0];g=json.loads(data[20:20+n])
report={'source':str(OUT.relative_to(ROOT)/'sword_finger_hand_20261010.blend'),'export':str(GLB.relative_to(ROOT)),'bones':[b.name for b in arm.bones],'animations':[a['name'] for a in g.get('animations',[])],'skin_joint_count':[len(s['joints']) for s in g['skins']],'vertices':len(verts),'faces':len(faces),'hand_frame':'X thumb side / Y fingers / Z back','original':True}
(OUT/'build_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
scene.render.engine='BLENDER_EEVEE';scene.render.resolution_x=800;scene.render.resolution_y=650;scene.render.resolution_percentage=100
scene.world=bpy.data.worlds.new('PreviewWorld');scene.world.color=(.1,.13,.15)
bpy.ops.object.camera_add(location=(.24,.22,.32));cam=bpy.context.object;cam.rotation_euler=(Vector((0,.06,0))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.type='ORTHO';cam.data.ortho_scale=.23;scene.camera=cam
bpy.ops.object.light_add(type='AREA',location=(.1,.1,.4));bpy.context.object.data.energy=10;bpy.context.object.data.size=.3
for label,frame in [('relaxed',1),('sword_fingers',25)]:
 scene.frame_set(frame);scene.render.filepath=str(OUT/(label+'.png'));bpy.ops.render.render(write_still=True)
print('HAND_EXPORT',report)
