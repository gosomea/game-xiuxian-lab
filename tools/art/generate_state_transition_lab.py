"""Blender 5.2.1 LTS: build the state-transition trial formation (心境/身法试炼阵).

Run:
  /Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup \
      --python tools/art/generate_state_transition_lab.py

Produces:
  src/levels/experiments/character_movement/state_transition_lab.glb   geometry only
  docs/art/state_transition_lab/state_transition_lab.blend             + preview camera/light
  docs/art/state_transition_lab/trial_preview.png                      Cycles 24 samples, 1200x900

Design contract (matches the Godot scene's local collision assembly):
  - Yin-yang jade disc: main platform, radius 9 m, top face at Blender Z=0.
  - Stone gate wall due north (-Y in Blender = -Z in Godot after the Y-up swap),
    its face slab spanning roughly X in [-4.5, 4.5] at Y = -5.5.
  - Broken bridge due east (+X): two deck spans with a real gap at X in [9.5, 11.5].
  - Floating formation pillars and rune rings around the rim (decoration only).
  Godot builds every collision proxy itself; this script exports geometry only.
  No textures, no downloads, no external assets.

Axes: Blender is Z-up; glTF exports Y-up, so Blender +Y becomes glTF/Godot -Z and
Blender +Z becomes glTF/Godot +Y. The scene therefore reads: north wall at Godot -Z,
broken bridge along Godot +X, disc top face at Godot Y=0.
"""
import bpy, math
from mathutils import Vector
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'src/levels/experiments/character_movement/state_transition_lab.glb'
SOURCE = ROOT / 'docs/art/state_transition_lab'

bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)


def mat(name, color, metallic=0.0, rough=0.78, emission=None, emission_strength=0.0):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*color, 1)
    m.use_nodes = True
    bs = m.node_tree.nodes.get('Principled BSDF')
    bs.inputs['Base Color'].default_value = (*color, 1)
    bs.inputs['Roughness'].default_value = rough
    bs.inputs['Metallic'].default_value = metallic
    if emission is not None:
        bs.inputs['Emission Color'].default_value = (*emission, 1)
        bs.inputs['Emission Strength'].default_value = emission_strength
    return m


def finish(o, name, m, bevel=0.0):
    o.name = name
    o.data.materials.append(m)
    if bevel:
        b = o.modifiers.new('Soft crafted edges', 'BEVEL')
        b.width = bevel
        b.segments = 2
        o.modifiers.new('Weighted corner normals', 'WEIGHTED_NORMAL')
    return o


def box(name, p, s, m, bevel=0.04, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1, location=p)
    o = bpy.context.object
    o.scale = s
    o.rotation_euler = rot
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    return finish(o, name, m, bevel)


def cyl(name, p, r, depth, m, verts=48, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=depth, location=p)
    o = bpy.context.object
    o.rotation_euler = rot
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    return finish(o, name, m, 0.02)


def torus(name, p, major, minor, m, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor,
                                     major_segments=40, minor_segments=10, location=p)
    o = bpy.context.object
    o.rotation_euler = rot
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    return finish(o, name, m, 0.0)


def ring(name, z_center, r_in, r_out, thickness, m, segments=96, bevel=0.0):
    """True annular band: flat top/bottom rings plus inner/outer walls (closed solid).

    The previous rim band was a solid disc whose top face was exactly the disc top,
    so both faced off over 322 m^2 of the same depth plane (ground shimmer).
    """
    verts, faces = [], []
    z0, z1 = z_center - thickness * 0.5, z_center + thickness * 0.5
    for r, z in ((r_in, z0), (r_out, z0), (r_out, z1), (r_in, z1)):
        for i in range(segments):
            a = math.tau * i / segments
            verts.append((math.cos(a) * r, math.sin(a) * r, z))
    for band in range(4):
        b0, b1 = band * segments, ((band + 1) % 4) * segments
        for i in range(segments):
            j = (i + 1) % segments
            faces.append((b0 + i, b0 + j, b1 + j, b1 + i))
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.validate()
    mesh.update()
    o = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(o)
    o.data.materials.append(m)
    if bevel:
        b = o.modifiers.new('Soft crafted edges', 'BEVEL')
        b.width = bevel
        b.segments = 2
    return o


def plate(name, verts, faces, m, thickness=0.0):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    o = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(o)
    o.data.materials.append(m)
    if thickness:
        mod = o.modifiers.new('Ceramic thickness', 'SOLIDIFY')
        mod.thickness = thickness
    return o


# --- palette -----------------------------------------------------------------
jade = mat('Celadon jade', (.075, .24, .18), rough=.55)
jade_deep = mat('Deep jade inlay', (.03, .12, .10), rough=.42)
stone = mat('Trial pale stone', (.60, .63, .55), rough=.82)
edge = mat('Cut stone edge', (.24, .35, .28), rough=.75)
paper = mat('Ivory paving', (.78, .77, .64), rough=.86)
bronze = mat('Aged bronze', (.51, .34, .09), metallic=.35, rough=.60)
rune = mat('Formation rune glow', (.30, .70, .58), rough=.35,
           emission=(.32, .82, .66), emission_strength=3.2)
rune_dim = mat('Dormant rune', (.16, .30, .27), rough=.60,
               emission=(.18, .42, .36), emission_strength=0.8)
void = mat('Void water', (.10, .14, .18), rough=.25)

# --- yin-yang jade disc (main platform) --------------------------------------
DISC_R = 9.0
DISC_T = 0.5
cyl('Jade disc body', (0, 0, -DISC_T / 2), DISC_R, DISC_T, jade, verts=96)
# Inlaid bronze band: a real annulus whose top face sits 12 mm proud of the disc top
# (0.0) and whose bottom is buried at -0.108. Nothing shares the disc's depth plane.
# 共面叠面会让 322.56 m^2 的盘顶与束带顶互相争深度（地面闪烁），故环带顶面必须在盘面之上。
ring('Jade disc rim band', 0.012 - 0.06, DISC_R - 0.60, DISC_R - 0.02, 0.12, bronze, bevel=0.02)
# Yin-yang inlay: two half discs in opposite tones + two small contrasting eyes.
cyl('Yin half', (0, 0, 0.012), DISC_R * 0.46, 0.03, jade_deep, verts=64)
for sign in (1, -1):
    bpy.ops.mesh.primitive_cylinder_add(vertices=64, radius=DISC_R * 0.23, depth=0.03,
                                        location=(0, sign * DISC_R * 0.23, 0.03))
    o = bpy.context.object
    o.data.materials.append(jade)
    o.name = 'Yang lobe %+d' % sign
cyl('Yin eye', (0, DISC_R * 0.23, 0.05), DISC_R * 0.075, 0.03, jade_deep, verts=32)
cyl('Yang eye', (0, -DISC_R * 0.23, 0.05), DISC_R * 0.075, 0.03, jade, verts=32)
# Eight trigram marks around the rim.
for i in range(8):
    a = math.tau * i / 8
    for k in range(3):
        r = DISC_R * 0.72 - k * 0.62
        torus('Trigram bar %d-%d' % (i, k), (math.cos(a) * r, math.sin(a) * r, 0.03),
              0.30, 0.055, rune_dim, rot=(0, 0, a + math.pi / 2))

# --- stone gate wall due north (Godot -Z) ------------------------------------
GATE_Z = -5.5
for x in (-5.0, 5.0):
    box('Gate pillar', (x, GATE_Z, 1.886), (0.95, 1.05, 3.8), stone, .06)
box('Gate lintel', (0, GATE_Z, 4.05), (11.6, 1.25, 0.7), bronze, .05)
# 墙身底面下沉 12 mm 埋入盘体（竖直构件的接触端盖不与地面共面）。
box('Gate wall slab', (0, GATE_Z, 1.488), (10.0, 0.55, 3.0), stone, .05)
# 装饰门槛：底面下沉 10 mm 埋入盘体，避免与盘顶 y=0 共面（原底面严格等于 0）。
# 各竖直构件的埋入深度彼此错开 2 mm（-10/-12/-14 mm），连埋在盘体内部的端盖也不共面。
box('Gate threshold', (0, GATE_Z + 0.9, 0.08), (10.6, 1.4, 0.18), paper, .04)
for x in (-3.3, -1.1, 1.1, 3.3):
    box('Gate rune strip', (x, GATE_Z + 0.60, 1.5), (0.14, 0.06, 2.2), rune_dim, 0.0)

# --- broken bridge due east (Godot +X) ---------------------------------------
BRIDGE_Z = 0.0
# 可走桥面：碰撞盒顶面保持 y=0（BRIDGE_Y + 0.44/2），可见顶面下沉 5 mm 到 -0.005，
# 与盘顶 y=0 不再共面；不抬高可走面，站立高度与碰撞数值不变。
box('Bridge near span', (7.6, BRIDGE_Z, -0.225), (3.0, 2.6, 0.44), stone, .05)
box('Bridge far span', (13.1, BRIDGE_Z, -0.225), (3.2, 2.6, 0.44), stone, .05)
for x in (6.2, 9.05, 11.65, 14.65):
    box('Bridge rail post', (x, BRIDGE_Z, 0.54), (0.28, 0.28, 1.1), bronze, .04)
for x in (7.0, 9.0):
    box('Bridge rail bar', (x, BRIDGE_Z - 1.15, 0.95), (1.7, 0.12, 0.12), bronze, .03)
    box('Bridge rail bar', (x, BRIDGE_Z + 1.15, 0.95), (1.7, 0.12, 0.12), bronze, .03)
for x in (13.0,):
    box('Bridge rail bar', (x, BRIDGE_Z - 1.15, 0.95), (1.7, 0.12, 0.12), bronze, .03)
    box('Bridge rail bar', (x, BRIDGE_Z + 1.15, 0.95), (1.7, 0.12, 0.12), bronze, .03)
# Splintered stubs at the break so the gap reads as a broken span, not a missing mesh.
for z in (-1.05, 0.0, 1.05):
    box('Broken deck stub', (9.35, z, -0.20), (0.7, 0.7, 0.40), stone, .03, rot=(0.06, 0.10, 0.0))
    box('Broken deck stub far', (11.75, z, -0.20), (0.7, 0.7, 0.40), stone, .03, rot=(0.05, -0.09, 0.0))

# --- floating formation pillars and rune rings (decoration only) -------------
PILLARS = [
    (7.4, -7.4, 3.1, 2.6), (-7.4, -7.4, 4.0, 3.0), (-7.4, 7.4, 3.4, 2.4),
    (7.4, 7.4, 4.4, 3.2), (0.0, -8.6, 5.2, 2.8), (0.0, 8.6, 3.8, 2.6),
]
for index, (x, z, y, height) in enumerate(PILLARS):
    cyl('Formation pillar', (x, z, y), 0.55, height, stone, verts=12)
    cyl('Pillar cap', (x, z, y + height / 2 + 0.11), 0.72, 0.24, bronze, verts=12)
    torus('Pillar rune ring', (x, z, y + 0.5), 0.86, 0.07, rune)
    torus('Pillar upper ring', (x, z, y - 0.6), 0.70, 0.055, rune_dim)
    cyl('Pillar ember', (x, z, y - height / 2 - 0.16), 0.30, 0.14, rune, verts=16)

# --- outer void ring + distant formation halo --------------------------------
torus('Void rim', (0, 0, -0.42), DISC_R + 1.1, 0.22, stone)
torus('Outer formation halo', (0, 0, -0.9), DISC_R + 4.2, 0.10, rune_dim)
bpy.ops.mesh.primitive_cylinder_add(vertices=96, radius=DISC_R + 5.0, depth=0.3,
                                    location=(0, 0, -1.6))
bpy.context.object.name = 'Void pool'
bpy.context.object.data.materials.append(void)

# --- export geometry only ----------------------------------------------------
OUT.parent.mkdir(parents=True, exist_ok=True)
SOURCE.mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.export_scene.gltf(filepath=str(OUT), export_format='GLB',
                          use_selection=True, export_apply=True)

# --- preview camera / light / render (source only, never exported) -----------
scene = bpy.context.scene
bpy.ops.object.camera_add(location=(2, -19, 22))
camera = bpy.context.object
camera.rotation_euler = (Vector((0, 0, 0.4)) - camera.location).to_track_quat('-Z', 'Y').to_euler()
camera.data.type = 'ORTHO'
camera.data.ortho_scale = 40
scene.camera = camera
bpy.ops.object.light_add(type='AREA', location=(-8, -12, 18))
bpy.context.object.data.energy = 9000
bpy.context.object.data.shape = 'DISK'
bpy.context.object.data.size = 18
bpy.ops.object.light_add(type='AREA', location=(12, 10, 14))
bpy.context.object.data.energy = 4200
bpy.context.object.data.shape = 'DISK'
bpy.context.object.data.size = 20
bpy.ops.object.light_add(type='SUN', location=(0, 0, 20))
bpy.context.object.data.energy = 1.6
bpy.context.object.rotation_euler = (0.6, 0.2, 0.4)
scene.world.color = (.42, .46, .48)
scene.render.engine = 'CYCLES'
scene.cycles.samples = 24
scene.render.resolution_x = 1200
scene.render.resolution_y = 900
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = 'PNG'
scene.render.filepath = str(SOURCE / 'trial_preview.png')
# save_version=0：覆盖保存时不轮转 .blend1，防止未来重跑静默覆盖历史探索资产备份。
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE / 'state_transition_lab.blend'))
bpy.ops.render.render(write_still=True)
print('TRIAL_EXPORTED', OUT)
print('MESHES', sum(o.type == 'MESH' for o in scene.objects))
