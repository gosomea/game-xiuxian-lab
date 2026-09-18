"""Blender 5.2.1 LTS: build the movement courtyard from original procedural geometry.

Run:
  /Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup \
      --python tools/art/generate_movement_garden.py

Produces:
  src/levels/experiments/character_movement/movement_garden.glb  geometry only
  docs/art/movement_garden/movement_garden.blend                 + preview camera/light
  docs/art/movement_garden/garden_preview_surface_clearance.png  Cycles 24 samples, 1200x900
      (the pre-fix render is kept as garden_preview.png / garden_preview_pre_surface_clearance.png)

The selected mesh objects are exported to GLB first; the preview camera, the
area light and the render are added afterwards and stay out of the GLB.

Axes: Blender is Z-up; glTF exports Y-up, so Blender +Y becomes glTF/Godot -Z.
No textures, no downloads, no external assets. Godot builds its own simple
collision proxies; this script exports geometry only.
Removing the factory-startup objects leaves the zero-user material 'Material'
in the saved .blend; it never enters the GLB.
"""
import bpy, math, random
from mathutils import Vector
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'src/levels/experiments/character_movement/movement_garden.glb'
SOURCE = ROOT / 'docs/art/movement_garden'
random.seed(1709)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)

# --- Vertical clearance contract (metres, world Y = Godot up, 2026-09-18 surface-clearance fix) ---
# The terrain collision proxy keeps its top at y = 0. Every stacked horizontal layer keeps its
# underside at least SURFACE_CLEARANCE above the layer it rests on, so no two horizontal faces
# share a depth (z-fighting) and no decoration re-enters its support. The pre-fix layout put the
# terrace top at exactly 0.0 with the sand spanning [-0.0075, +0.0175]; the 50 paving blocks then
# had bottoms at 0.0005 +/- 0.003. See notes/implemented/art/2026-09-18-coplanar-surface-shimmer.md.
SURFACE_CLEARANCE = 0.010
PLINTH_BOTTOM = -0.820
PLINTH_TOP = -0.230
TERRACE_BOTTOM = PLINTH_TOP + SURFACE_CLEARANCE  # -0.220
TERRACE_TOP = TERRACE_BOTTOM + 0.200             # -0.020
SAND_BOTTOM = TERRACE_TOP + SURFACE_CLEARANCE    # -0.010
SAND_TOP = SAND_BOTTOM + 0.030                   # +0.020
PAVING_BOTTOM = SAND_TOP + SURFACE_CLEARANCE     # +0.030, shared base plane of everything on the sand
PAVING_BLOCKS = []                               # filled while building; used by the export self-check
# --- Two audit corrections (2026-09-18 independent audit), vertical geometry only ---
# B-class burying: the scholar rock base keeps the pre-fix visible top (y = 0.970, only ~3 cm below
# the y = 1.0 obstacle proxy top built by movement_garden.gd) while its underside sinks 40 mm below
# the plinth top (-0.230). Centre and Z radius move together; the part is not translated as a whole.
ROCK_BASE_TOP = 0.970
ROCK_BASE_BOTTOM = PLINTH_TOP - 0.040            # -0.270
ROCK_BASE_CENTER = (ROCK_BASE_TOP + ROCK_BASE_BOTTOM) / 2
ROCK_BASE_RADIUS_Z = (ROCK_BASE_TOP - ROCK_BASE_BOTTOM) / 2
# Pavilion column bases keep their current visible top (PAVING_BOTTOM + 0.305 = 0.335) and grow
# downwards until the underside is pinned 20 mm below PAVING_BOTTOM. Randomised paving tops span
# 0.0822..0.0879, so the old underside (0.085) sat 0..3 mm from them; the pinned underside is now
# >= 72 mm below every paving top.
COLUMN_BASE_TOP = PAVING_BOTTOM + 0.305
COLUMN_BASE_BOTTOM = PAVING_BOTTOM - 0.020       # 0.010
COLUMN_BASE_CENTER_Z = (COLUMN_BASE_TOP + COLUMN_BASE_BOTTOM) / 2
COLUMN_BASES = []                                # filled while building; used by the export self-check

def mat(name, color, metallic=0):
    m=bpy.data.materials.new(name);m.diffuse_color=(*color,1);m.use_nodes=True
    bs=m.node_tree.nodes.get('Principled BSDF');bs.inputs['Base Color'].default_value=(*color,1)
    bs.inputs['Roughness'].default_value=.78;bs.inputs['Metallic'].default_value=metallic
    return m

stone=mat('Warm limestone',(.59,.62,.51));edge=mat('Cut stone edges',(.24,.35,.28))
paper=mat('Ivory paving',(.78,.77,.64));sand=mat('Raked sand',(.54,.59,.45))
jade=mat('Celadon ceramic',(.075,.24,.18));roof=mat('Jade roof tiles',(.11,.32,.24))
wood=mat('Warm cedar',(.22,.115,.053));gold=mat('Aged bronze',(.51,.34,.09),.35)
rockmat=mat('Scholar rock',(.28,.36,.32));moss=mat('Moss',(.22,.33,.105))
leaf=mat('Bamboo leaves',(.12,.29,.09));stem=mat('Bamboo stems',(.25,.38,.12))
glow=mat('Lantern paper',(.98,.75,.37))

def finish(o,name,m,bevel=0):
    o.name=name;o.data.materials.append(m)
    if bevel:
        b=o.modifiers.new('Soft crafted edges','BEVEL');b.width=bevel;b.segments=2
        n=o.modifiers.new('Weighted corner normals','WEIGHTED_NORMAL')
    return o

def box(name,p,s,m,bevel=.04):
    bpy.ops.mesh.primitive_cube_add(size=1,location=p);o=bpy.context.object;o.scale=s
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    return finish(o,name,m,bevel)

def cyl(name,p,r,depth,m,verts=12):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts,radius=r,depth=depth,location=p)
    return finish(bpy.context.object,name,m,.02)

def sphere(name,p,s,m):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2,radius=1,location=p);o=bpy.context.object;o.scale=s
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    return finish(o,name,m)

box('Floating courtyard plinth',(0,0,(PLINTH_BOTTOM+PLINTH_TOP)/2),(18,14,PLINTH_TOP-PLINTH_BOTTOM),edge,.18)
# Terrace top is 2 cm below y=0 and the sand top 2 cm above it: the collision plane (y=0) sits
# between the two visible surfaces instead of crossing either one.
box('Limestone upper terrace',(0,0,(TERRACE_BOTTOM+TERRACE_TOP)/2),(17.85,13.85,TERRACE_TOP-TERRACE_BOTTOM),stone,.10)
box('Sand garden surface',(0,0,(SAND_BOTTOM+SAND_TOP)/2),(16.9,12.9,SAND_TOP-SAND_BOTTOM),sand,.02)
# Coping bottoms sit on PAVING_BOTTOM, one clearance above the sand top.
for x in (-8.65,8.65):box('Low side coping',(x,0,PAVING_BOTTOM+.16),(.35,13.6,.32),paper,.06)
for y in (-6.65,6.65):box('Low end coping',(0,y,PAVING_BOTTOM+.16),(17.6,.35,.32),paper,.06)
# A broad quiet central path; individual chamfered blocks rather than an engine grid.
for row in range(10):
    for col in range(5):
        x=(col-2)*1.08;y=-5.1+row*1.06
        # Randomness only moves the visible top face: thickness varies while the underside stays
        # pinned to PAVING_BOTTOM, so no draw can dip back into or touch the sand layer.
        thick=.055+random.uniform(-.003,.003)
        o=box('Hand cut paving',(x,y,PAVING_BOTTOM+thick/2),(1.035,1.01,thick),paper,.045)
        o.rotation_euler.z=random.uniform(-.012,.012)
        PAVING_BLOCKS.append(o)
for x in (-6.6,6.6):
    for row in range(6):box('Side stepping stone',(x,-4+row*1.65,PAVING_BOTTOM+.03),(.95,1.1,.06),paper,.09)
# Two visible obstacles match the Godot collision proxies.
# B-class: the rock base is buried 40 mm into the plinth so no horizontal cap is coplanar.
ROCK_BASE = sphere('Scholar rock base',(-4,0,ROCK_BASE_CENTER),(.98,.93,ROCK_BASE_RADIUS_Z),rockmat)
sphere('Scholar rock crest',(-4.2,.05,.95),(.60,.57,.70),rockmat)
sphere('Moss cap',(-4.15,.07,1.50),(.39,.35,.075),moss)
box('Meditation stone',(4,1,PAVING_BOTTOM+.29),(1.96,1.96,.78),stone,.18)
box('Meditation stone top',(4,1,.80),(1.9,1.9,.08),paper,.10)
cyl('Celadon bowl',(4,1,.91),.44,.18,jade,24)
for side in (-1,1):
    for y in (-3.9,3.9):
        x=side*4.8
        box('Lantern footing',(x,y,PAVING_BOTTOM+.12),(.80,.80,.24),stone,.07)
        cyl('Lantern stem',(x,y,.57),.16,.8,edge)
        box('Lantern chamber',(x,y,1.13),(.48,.48,.40),glow,.02)
        for dx in (-.25,.25):
            for dy in (-.25,.25):box('Lantern frame',(x+dx,y+dy,1.15),(.065,.065,.5),wood,.01)
        bpy.ops.mesh.primitive_cone_add(vertices=4,radius1=.57,radius2=.16,depth=.22,rotation=(0,0,math.pi/4),location=(x,y,1.48))
        finish(bpy.context.object,'Stone lantern cap',jade,.025)
        sphere('Lantern finial',(x,y,1.65),(.095,.095,.11),gold)
# Open pavilion sits at the back, clear of the central six-metre movement area.
box('Pavilion platform',(0,5.20,PAVING_BOTTOM+.14),(5.4,2.9,.28),stone,.10)
for x in (-2.15,2.15):
    for y in (4.05,6.15):
        COLUMN_BASES.append(box('Pavilion column base',(x,y,COLUMN_BASE_CENTER_Z),(.44,.44,COLUMN_BASE_TOP-COLUMN_BASE_BOTTOM),paper,.04))
        cyl('Cedar pavilion column',(x,y,1.65),.13,2.6,wood)
for y in (4.05,6.15):box('Pavilion crossbeam',(0,y,2.88),(4.7,.20,.22),wood,.03)
# Curved roof, explicit strips to show ceramic courses and lifted eaves.
for i in range(16):
    x0=-2.75+i*5.5/16;x1=x0+5.5/16-.018
    verts=[]
    for x in (x0,x1):
        for j in range(13):
            dy=-1.85+j*3.7/12
            z=3.04+.85*(1-abs(dy)/1.85)+.20*(abs(dy)/1.85)**5
            verts.append((x,5.12+dy,z))
    faces=[(j,j+1,14+j,13+j) for j in range(12)]
    mesh=bpy.data.meshes.new('Ceramic curved course');mesh.from_pydata(verts,[],faces);mesh.update()
    o=bpy.data.objects.new('Curved jade roof tile',mesh);bpy.context.collection.objects.link(o);o.data.materials.append(roof)
    mod=o.modifiers.new('Ceramic thickness','SOLIDIFY');mod.thickness=.075
box('Roof ridge',(0,5.12,3.96),(5.65,.16,.16),gold,.05)
# Bamboo groves frame the sides without hiding the player at the front.
for cx,cy in [(-7.2,3.8),(7.2,3.8),(-7.0,-1.8),(7.0,-2.8)]:
    sphere('Moss planting bed',(cx,cy,PAVING_BOTTOM+.02),(.95,.90,.13),moss)
    for k in range(4):
        x=cx+random.uniform(-.55,.55);y=cy+random.uniform(-.5,.5);h=random.uniform(1.8,2.8)
        cyl('Bamboo culm',(x,y,PAVING_BOTTOM-.01+h/2),.043,h,stem,8)
        for j in range(1,5):
            z=h*j/5;cyl('Bamboo joint',(x,y,z),.052,.035,jade,8)
            if j>1:
                for sign in (-1,1):
                    o=sphere('Pointed bamboo leaf',(x+sign*.22,y+.08,z+.1),(.34,.055,.09),leaf)
                    o.rotation_euler=(0,sign*-.3,random.uniform(-.6,.6))
# --- Pre-export self-check: the export only runs if the built geometry satisfies the contract. ---
# Absolute floor from the coplanar-shimmer note; the nominal step is SURFACE_CLEARANCE.
FLOOR=.002
assert abs(PLINTH_TOP-TERRACE_BOTTOM)>=SURFACE_CLEARANCE
assert abs(TERRACE_TOP-SAND_BOTTOM)>=SURFACE_CLEARANCE
assert abs(SAND_TOP-PAVING_BOTTOM)>=SURFACE_CLEARANCE-1e-12
assert TERRACE_TOP<SAND_BOTTOM<SAND_TOP<PAVING_BOTTOM
# Check the vertices actually generated, not the nominal formulas: every paving block must keep one
# shared underside plane on PAVING_BOTTOM while its top varies.
def _z_span(o):
    zs=[(o.matrix_world @ v.co).z for v in o.data.vertices]
    return min(zs),max(zs)
assert len(PAVING_BLOCKS)==50,'expected 50 hand cut paving blocks, built %d' % len(PAVING_BLOCKS)
_bottoms=[round(_z_span(o)[0],6) for o in PAVING_BLOCKS]
_tops=[round(_z_span(o)[1],6) for o in PAVING_BLOCKS]
assert len(set(_bottoms))==1,'paving undersides are not one fixed plane: %s' % sorted(set(_bottoms))
assert abs(_bottoms[0]-PAVING_BOTTOM)<1e-6,(_bottoms[0],PAVING_BOTTOM)
assert _bottoms[0]-SAND_TOP>=FLOOR,'paving underside re-enters the sand layer'
assert min(_tops)>_bottoms[0],'paving tops must stay above the fixed underside'
# The two audit corrections, also read back from the generated vertices rather than the formulas.
assert len(COLUMN_BASES)==4,'expected 4 pavilion column bases, built %d' % len(COLUMN_BASES)
_rb_lo,_rb_hi=_z_span(ROCK_BASE)
assert abs(_rb_hi-ROCK_BASE_TOP)<1e-6,('scholar rock base visible top drifted',_rb_hi,ROCK_BASE_TOP)
assert _rb_lo<=PLINTH_TOP-0.020,('scholar rock base underside buried less than 20 mm into the plinth',_rb_lo,PLINTH_TOP)
_cb_lo=min(_z_span(o)[0] for o in COLUMN_BASES)
_cb_hi=max(_z_span(o)[1] for o in COLUMN_BASES)
assert abs(_cb_lo-COLUMN_BASE_BOTTOM)<1e-6,('pavilion column base underside not pinned to PAVING_BOTTOM-0.02',_cb_lo,COLUMN_BASE_BOTTOM)
assert abs(_cb_hi-COLUMN_BASE_TOP)<1e-6,('pavilion column base visible top moved',_cb_hi,COLUMN_BASE_TOP)
assert _cb_lo<=PAVING_BOTTOM-0.020+1e-6,('pavilion column base underside above PAVING_BOTTOM-0.02',_cb_lo)
assert min(_tops)-_cb_lo>=FLOOR,('pavilion column base underside too close to a paving top',min(_tops)-_cb_lo)
print('PAVING_REAL bottom=%.6f top_span=(%.6f, %.6f) distinct_tops=%d' % (
    _bottoms[0],min(_tops),max(_tops),len(set(_tops))))
print('ROCK_BASE_REAL bottom=%.6f top=%.6f plinth_top=%.6f' % (_rb_lo,_rb_hi,PLINTH_TOP))
print('COLUMN_BASE_REAL bottom=%.6f top=%.6f count=%d paving_top_min=%.6f gap=%.6f' % (
    _cb_lo,_cb_hi,len(COLUMN_BASES),min(_tops),min(_tops)-_cb_lo))
print('LAYER_CLEARANCE_M',SURFACE_CLEARANCE,'terrace_top',round(TERRACE_TOP,4),
      'sand_span',(round(SAND_BOTTOM,4),round(SAND_TOP,4)),'paving_bottom',round(PAVING_BOTTOM,4))

# Export geometry only. Godot creates deliberately simple collision proxies separately.
OUT.parent.mkdir(parents=True,exist_ok=True);SOURCE.mkdir(parents=True,exist_ok=True)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.export_scene.gltf(filepath=str(OUT),export_format='GLB',use_selection=True,export_apply=True)
# Preview camera and lighting are source-only, not exported into the runtime scene.
scene=bpy.context.scene
bpy.ops.object.camera_add(location=(17,-22,19));camera=bpy.context.object
camera.rotation_euler=(Vector((0,0,.6))-camera.location).to_track_quat('-Z','Y').to_euler()
camera.data.type='ORTHO';camera.data.ortho_scale=25;scene.camera=camera
bpy.ops.object.light_add(type='AREA',location=(-6,-9,15));bpy.context.object.data.energy=2200;bpy.context.object.data.shape='DISK';bpy.context.object.data.size=12
scene.world.color=(.55,.58,.48);scene.render.engine='CYCLES';scene.cycles.samples=24
scene.render.resolution_x=1200;scene.render.resolution_y=900;scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG';scene.render.filepath=str(SOURCE/'garden_preview_surface_clearance.png')
# save_version=0: the script must not spawn movement_garden.blend1 / .blend11 backups each run
# (archived copies are registered in the asset ledger instead).
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/'movement_garden.blend'))
bpy.ops.render.render(write_still=True)
print('GARDEN_EXPORTED',OUT)
print('MESHES',sum(o.type=='MESH' for o in scene.objects))
