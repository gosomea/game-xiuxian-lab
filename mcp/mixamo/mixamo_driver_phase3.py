# Mixamo 驱动 · 阶段 3 v3：组装 骨骼角色 + 4 动作 + 袍子权重修正 → GLB。
# 运行：blender --background --factory-startup --python mixamo_driver_phase3.py
#
# 关键实测：Mixamo FBX 以 cm 导入（armature scale 0.01，角色 0.017m）——必须先 ×100
# 并 apply all transforms，切线分类才在米制空间成立。
# 权重修正：袍子（裙/摆缘/前襟）只保留 Hips 权重（跟髋刚性平移），露腿区保留腿链，
# 袖子跟手臂，躯干/头不动。切缝藏于服装结构。

import bpy
from mathutils import Matrix, Vector

DL = "/Users/yuqixian/forever-skills/projects/games/game-xiuxian-lab/mcp/mixamo/downloads"
ROOT = "/Users/yuqixian/forever-skills/projects/games/game-xiuxian-lab"
TEX = f"{ROOT}/src/game/actors/swordsman/models/cultivator_jade_texture_20250901.png"

CLIPS = [
    ("walk_skin.fbx", "walk", True),
    ("idle.fbx", "idle", False),
    ("run.fbx", "run", False),
    ("jump.fbx", "jump", False),
]

F_HIP = 0.46 * 1.75
F_WAIST = 0.56 * 1.75
F_ELBOW = 0.63 * 1.75


def clear():
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)


def normalize_scale(objs):
    """只把骨架 ×100（cm scale 0.01 → 1.0 米制）；网格局部数据已是米，不要动。"""
    for o in objs:
        if o.type == "ARMATURE":
            o.scale = tuple(s * 100.0 for s in o.scale)
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    bpy.ops.object.select_all(action="DESELECT")


def island_class(world_verts):
    """按米制几何特征分类岛 → 权重保留集（骨名后缀）；None = 不动（躯干/头）。"""
    xs = [v.x for v in world_verts]
    zs = [v.z for v in world_verts]
    cx = (min(xs) + max(xs)) / 2
    span = max(xs) - min(xs)
    z0, z1, zmid = min(zs), max(zs), (min(zs) + max(zs)) / 2
    # Mixamo 的解剖学 Left 位于角色局部 +X，Right 位于 -X。这里不能按观察者视角猜左右，
    # 否则会把左侧网格锁到 Right 骨链、右侧网格锁到 Left 骨链。
    side = "Left" if cx >= 0 else "Right"
    if z0 >= F_WAIST - 0.05 and abs(cx) < 0.22:
        return None
    if z1 <= 0.16 and span < 0.22:
        return ["%sUpLeg" % side, "%sLeg" % side, "%sFoot" % side, "%sToeBase" % side]
    if z1 <= F_HIP + 0.12 and span < 0.24:
        return ["%sUpLeg" % side, "%sLeg" % side, "%sFoot" % side, "%sToeBase" % side]
    if zmid >= F_ELBOW and abs(cx) >= 0.19:
        return ["%sArm" % side, "%sForeArm" % side, "%sHand*" % side,
                "%sShoulder" % side]
    if abs(cx) >= 0.19 and zmid >= F_WAIST - 0.05:
        return ["%sArm" % side, "%sForeArm" % side, "%sHand*" % side,
                "%sShoulder" % side]
    if z1 <= F_WAIST + 0.06:
        return ["Hips"]
    return None


def fix_weights_island(obj):
    mesh = obj.data
    world = obj.matrix_world
    verts = [(world @ v.co) for v in mesh.vertices]
    keep_suffixes = island_class(verts)
    if keep_suffixes is None:
        return "keep-all"
    groups = {g.index: g.name for g in obj.vertex_groups}

    def keep_group(name):
        tail = name.split(":")[-1].split("_")[-1].lower()
        for suffix in keep_suffixes:
            wanted = suffix.lower()
            if wanted.endswith("*"):
                if tail.startswith(wanted[:-1]):
                    return True
            elif tail == wanted:
                return True
        return False

    # 回填目标 = 保留集第一顺位骨（袖/腿各自的首骨，袍子=Hips）
    fallback_idx = None
    hips_idx = None
    for idx, name in groups.items():
        tail = name.split(":")[-1].split("_")[-1].lower()
        if tail == "hips":
            hips_idx = idx
        if fallback_idx is None and tail == keep_suffixes[0].rstrip("*").lower():
            fallback_idx = idx
    if fallback_idx is None:
        fallback_idx = hips_idx
    emptied = 0
    for vert in mesh.vertices:
        total_keep = 0.0
        for g in vert.groups:
            name = groups.get(g.group)
            if name is None:
                continue
            if keep_group(name):
                total_keep += g.weight
            else:
                g.weight = 0.0
        if total_keep <= 1e-4:
            if fallback_idx is not None:
                obj.vertex_groups[fallback_idx].add([vert.index], 1.0, "REPLACE")
                emptied += 1
        elif total_keep < 0.999:
            for g in vert.groups:
                name = groups.get(g.group)
                if name and keep_group(name):
                    g.weight = g.weight / total_keep
    used = set()
    for vert in mesh.vertices:
        for g in vert.groups:
            if g.weight > 1e-4:
                used.add(g.group)
    for idx, name in list(groups.items()):
        if idx not in used:
            vg = obj.vertex_groups.get(name)
            if vg:
                obj.vertex_groups.remove(vg)
    return "locked:%s emptied=%d" % ("+".join(keep_suffixes), emptied)


def weighted_center_x(obj, group_name):
    group = obj.vertex_groups.get(group_name)
    assert group is not None, "缺少权重组 %s" % group_name
    weighted_sum = 0.0
    weight_total = 0.0
    for vert in obj.data.vertices:
        weight = next((item.weight for item in vert.groups
                       if item.group == group.index), 0.0)
        weighted_sum += vert.co.x * weight
        weight_total += weight
    assert weight_total > 1e-3, "权重组为空 %s" % group_name
    return weighted_sum / weight_total, weight_total


def validate_limb_sides(obj):
    """防止观察者左右与 Mixamo 解剖学左右再次互换，并确保手指链未被裁掉。"""
    checks = [
        ("mixamorig:LeftArm", 1.0),
        ("mixamorig:LeftHand", 1.0),
        ("mixamorig:LeftHandIndex1", 1.0),
        ("mixamorig:LeftUpLeg", 1.0),
        ("mixamorig:RightArm", -1.0),
        ("mixamorig:RightHand", -1.0),
        ("mixamorig:RightHandIndex1", -1.0),
        ("mixamorig:RightUpLeg", -1.0),
    ]
    evidence = []
    for group_name, expected_sign in checks:
        center_x, total = weighted_center_x(obj, group_name)
        assert center_x * expected_sign > 0.02, (
            "%s 权重位于错误身体侧 x=%.4f" % (group_name, center_x))
        evidence.append("%s:x=%.3f,w=%.1f" % (group_name, center_x, total))
    print("LIMB_SIDE_CHECK " + " ".join(evidence), flush=True)


def main():
    clear()
    main_arm = None
    for filename, clip, is_skin in CLIPS:
        before = set(bpy.data.objects)
        bpy.ops.import_scene.fbx(filepath=f"{DL}/{filename}")
        objs = [o for o in bpy.data.objects if o not in before]
        normalize_scale(objs)
        arm = next((o for o in objs if o.type == "ARMATURE"), None)
        anim = next((a for a in bpy.data.actions if "mixamo" in a.name.lower()), None)
        if arm is None or anim is None:
            print("SKIP", filename, flush=True)
            continue
        if main_arm is None:
            main_arm = arm
            main_arm.name = "CultivatorRig"
            anim.name = clip
            anim.use_fake_user = True
            # 蒙皮网格：拆岛 → 权重修正 → 合并
            mesh = next((o for o in objs if o.type == "MESH"), None)
            if mesh is None:
                print("NO_MESH", filename, flush=True)
                continue
            bpy.ops.object.select_all(action="DESELECT")
            mesh.select_set(True)
            bpy.context.view_layer.objects.active = mesh
            bpy.ops.object.mode_set(mode="EDIT")
            bpy.ops.mesh.select_all(action="SELECT")
            bpy.ops.mesh.separate(type="LOOSE")
            bpy.ops.object.mode_set(mode="OBJECT")
            islands = [o for o in bpy.data.objects if o.type == "MESH" and o.select_get()]
            print("ISLANDS", len(islands), flush=True)
            for island in islands:
                result = fix_weights_island(island)
                print("  ISLAND", island.name, result, flush=True)
            bpy.ops.object.select_all(action="DESELECT")
            for island in islands:
                island.select_set(True)
            bpy.context.view_layer.objects.active = islands[0]
            bpy.ops.object.join()
            islands[0].name = "CultivatorJade"
        else:
            anim.name = clip
            anim.use_fake_user = True
            for o in objs:
                bpy.data.objects.remove(o, do_unlink=True)

    # 尺寸校验
    for obj in bpy.data.objects:
        if obj.type == "MESH":
            zs = [(obj.matrix_world @ Vector(c)).z for c in obj.bound_box]
            h = max(zs) - min(zs)
            print("HEIGHT %.3f" % h, flush=True)
            assert 1.4 < h < 2.1, "角色高度异常 %.3f" % h
            validate_limb_sides(obj)

    # 贴图
    try:
        image = bpy.data.images.load(TEX, check_existing=True)
        for mat in bpy.data.materials:
            if not mat.use_nodes:
                continue
            bsdf = mat.node_tree.nodes.get("Principled BSDF")
            if bsdf is None:
                continue
            tex_node = mat.node_tree.nodes.new("ShaderNodeTexImage")
            tex_node.image = image
            mat.node_tree.links.new(tex_node.outputs["Color"], bsdf.inputs["Base Color"])
    except Exception as e:
        print("TEX_ERR", str(e)[:80], flush=True)

    bpy.ops.wm.save_as_mainfile(
        filepath=f"{ROOT}/docs/art/cultivator_jade/cultivator_rigged.blend")
    bpy.ops.export_scene.gltf(
        filepath=f"{ROOT}/src/game/actors/swordsman/models/cultivator_rigged.glb",
        export_yup=True, export_apply=False,
        export_animation_mode="ACTIONS",
        export_skins=True)
    print("RIGGED_GLB_OK actions=%s" % sorted(a.name for a in bpy.data.actions), flush=True)


main()
