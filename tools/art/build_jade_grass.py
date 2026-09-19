# 青玉纸白样板：草簇程序建模。
# blender --background --factory-startup --python tools/art/build_jade_grass.py -- build export
#
# 规格（方向 note §2）：植被深松绿、成组聚散由场景负责，本资产只做单簇（0.35 m 高）。
# 叶片 = 三段变宽四边形，沿长度微弯，绕中心错向排布；单网格便于实例化。

import bmesh
import bpy
import math
import os
import sys

COL_FOLIAGE = (0.024, 0.085, 0.045, 1.0)   # 深松绿（线性，同 process_jade_hunyuan.PALETTE）
ROUGH = 0.9
BLADES = 9
HEIGHT = 0.35
SEGMENTS = 3


def _clear() -> None:
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)


def build() -> None:
    _clear()
    mat = bpy.data.materials.new("Jade_Grass")
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = COL_FOLIAGE
    bsdf.inputs["Roughness"].default_value = ROUGH

    bm = bmesh.new()
    rng = math.radians
    for index in range(BLADES):
        yaw = (index / BLADES) * math.tau + (0.13 if index % 2 else 0.0)
        tilt = rng(14 + (index % 3) * 9)      # 14°–32° 外倾
        lean = rng(6 * ((index % 4) - 1.5))   # 轻微偏向
        height = HEIGHT * (0.75 + 0.25 * ((index * 7) % 5) / 4.0)
        _blade(bm, yaw, tilt, lean, height)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)

    mesh = bpy.data.meshes.new("JadeGrass")
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(mat)
    obj = bpy.data.objects.new("JadeGrass", mesh)
    bpy.context.collection.objects.link(obj)


def _blade(bm, yaw: float, tilt: float, lean: float, height: float) -> None:
    """单叶：沿 +Y 长出再整体绕 Z 旋转；三段四边形，宽度收敛到尖。"""
    from mathutils import Matrix, Vector

    half_widths = [0.011, 0.008, 0.005, 0.0]
    bend = math.tan(math.radians(tilt)) * height
    section_z = [0.0, height * 0.42, height * 0.76, height]
    ring = []
    for seg in range(SEGMENTS + 1):
        t = seg / SEGMENTS
        y = -bend * (t * t)           # 沿 -Y 弯（叶尖回勾）
        z = section_z[seg]
        hw = half_widths[seg]
        ring.append((Vector((-hw, y, z)), Vector((hw, y, z))))
    # 微倾 + 偏向
    tilt_m = Matrix.Rotation(math.radians(tilt * 0.35), 4, "X")
    lean_m = Matrix.Rotation(math.radians(lean), 4, "Z")
    yaw_m = Matrix.Rotation(yaw, 4, "Z")
    local = []
    for left, right in ring:
        for v in (left, right):
            local.append(yaw_m @ lean_m @ tilt_m @ v)
    base = len(bm.verts)
    for v in local:
        bm.verts.new(v)
    bm.verts.ensure_lookup_table()
    for seg in range(SEGMENTS):
        a = base + seg * 2
        bm.faces.new((bm.verts[a], bm.verts[a + 1], bm.verts[a + 3], bm.verts[a + 2]))
    bm.faces.ensure_lookup_table()


def export(glb_path: str) -> None:
    os.makedirs(os.path.dirname(glb_path), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=glb_path, export_yup=True, export_apply=True)


def main() -> None:
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else ["build", "export"]
    root = "/Users/yuqixian/forever-skills/projects/games/game-xiuxian-lab"
    blend = os.path.join(root, "docs/art/jade_paper_sample/jade_grass.blend")
    glb = os.path.join(root, "src/levels/experiments/character_movement/jade_grass.glb")
    if "build" in argv:
        build()
    if "export" in argv:
        bpy.ops.wm.save_as_mainfile(filepath=blend)
        export(glb)
    print("JADE_GRASS_OK objects=%d" % len(bpy.data.objects))


main()
