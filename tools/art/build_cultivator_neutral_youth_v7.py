#!/usr/bin/env python3
"""构建 cultivator_neutral_youth_v7：无仙侠衣装的清俊少年动画底座。

依据 notes/proposed/art/2026-09-19-neutral-youth-animation-base-v7.md。

管线（全部可回读验证）：

  A. 起手：打开未改原件 generic_anime_male_original.blend
     - 删除作者控制骨（103 根非 deform 骨）与控制器显示网格，只留 65 根
       mixamorig 变形骨 + 4 个角色子网格。删除 armature modifier 之外的
       一切约束（原作者用 82 条 COPY_TRANSFORMS/COPY_ROTATION 把 FK 骨
       锁到 control rig；删掉控制骨后这些约束会失效并污染姿态）。
  B. 中性遮挡层：只在原身体子网格 model_0_submesh_4 上，按原始面分区把
     「躯干 / 上肢 / 下肢 / 骨盆」重绘为深靛贴身层，头、颈、手、脚保持
     原表面材质。不新增任何几何：顶点数、边数、面数、包围盒必须逐位不变。
  C. 动作迁移（本轮核心风险）：旧 cultivator_rigged.blend 的 idle/walk/run/jump
     在「同名骨」上不能直接拷贝 —— 审计实测 64 根共有骨里 37 根 rest 局部
     朝向差 >5°，最大 179.3°（LeftHand）。因此按 rest 帧共轭重定向：
         B_new = (L_new)^-1 · L_old · B_old        （见 retarget_basis）
     并在每个整数帧回读骨骼端点的 armature 空间坐标，与源动作逐帧比对。
  D. 导出 GLB：export_yup=True（Blender -Y 正面 → Godot +Z 正面），
     ACTIONS 模式，clips = idle/walk/run/jump。
  E. 回读验证 + 证据渲染 + manifest。
"""

import bpy
import hashlib
import json
import math
import os
import shutil
import struct
import sys
import time
import zlib

import numpy as np
from mathutils import Matrix, Quaternion, Vector

# --- 路径 -------------------------------------------------------------------

ROOT = "/Users/yuqixian/forever-skills/projects/games/game-xiuxian-lab"
SRC_BLEND = os.path.join(
    ROOT, "docs/art/cultivator_neutral_youth_v7/source/generic_anime_male_original.blend")
ANIM_BLEND = os.path.join(ROOT, "docs/art/cultivator_jade/cultivator_rigged.blend")
OUT_DIR = os.path.join(ROOT, "docs/art/cultivator_neutral_youth_v7")
OUT_BLEND = os.path.join(OUT_DIR, "cultivator_neutral_youth_v7.blend")
OUT_GLB = os.path.join(
    ROOT, "src/game/actors/swordsman/models/cultivator_neutral_youth_v7.glb")
TEX_PNG = os.path.join(OUT_DIR, "cultivator_neutral_youth_v7_neutral_body.png")
RUNTIME_NEUTRAL_TEX = os.path.join(
    ROOT,
    "src/game/actors/swordsman/models/"
    "cultivator_neutral_youth_v7_cultivator_neutral_youth_v7_neutral_body.png",
)
RENDER_DIR = os.path.join(OUT_DIR, "renders")
MANIFEST = os.path.join(OUT_DIR, "build_manifest.json")

BODY_SUBMESH = "NY7_Body"
HEAD_SUBMESH = "NY7_Head"
EYE_SUBMESHES = ("NY7_FaceLines", "NY7_Pupils")
CHARACTER_SUBMESHES = (EYE_SUBMESHES[0], HEAD_SUBMESH, EYE_SUBMESHES[1], BODY_SUBMESH)
# 未改原件里的原始子网格名（sanitize_names 之前）。
SOURCE_SUBMESH_NAMES = {
    "model_0_submesh_0": "NY7_FaceLines",
    "model_0_submesh_1": "NY7_Head",
    "model_0_submesh_2": "NY7_Pupils",
    "model_0_submesh_4": "NY7_Body",
}

CLIPS = ("idle", "walk", "run", "jump")

# --- 遮挡层分区常数（armature 空间 = 世界空间，两个对象都在原点且 scale=1）----
#
# 分区判据只用骨骼端点，不用手写魔法数字：
#   Neck  head z = 1.4858     右手腕 x = -0.6588 / 左手腕 x = +0.6587
#   左踝  head z = 0.0751     左膝   z = 0.5043     左髋 z = 0.9549
#
# 边界一律避开关节：颈线落在 Neck 骨中段，腕线落在腕骨之前，踝线落在踝骨之上。
NECK_LINE_Z = 1.4600
NECK_BLEND_Z = 0.0700
WRIST_LINE_ABS_X = 0.6400
WRIST_BLEND_X = 0.0400
ANKLE_LINE_Z = 0.0550
ANKLE_BLEND_Z = 0.0500

# 深靛中性遮挡层。单一色调 + 极轻的上下明度梯度：不做分段条带，避免读成
# 腰封 / 护腕等被明确排除的服装附件（见 note「非目标」）。
GARMENT_RGB = (0x2E / 255.0, 0x3A / 255.0, 0x5C / 255.0)
GARMENT_GRADIENT = 0.07

TEXTURE_SIZE = 2048
DILATE_PIXELS = 8

REPORT = {"steps": [], "asserts": []}


def log(msg):
    print("[v7] " + msg, flush=True)


def record(key, value):
    REPORT[key] = value


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


# --- A. 起手：剥离控制骨 ------------------------------------------------------


def bone_rest_table(armature_object):
    return {b.name: b.matrix_local.copy() for b in armature_object.data.bones}


def bone_parent_table(armature_object):
    return {b.name: (b.parent.name if b.parent else None) for b in armature_object.data.bones}


def prune_control_rig():
    """删除非 deform 控制骨、控制器显示网格、失效约束与遗留 action。"""
    scene = bpy.context.scene
    armature = bpy.data.objects["Armature"]

    helper_meshes = sorted(
        o.name for o in bpy.data.objects
        if o.type == "MESH" and not o.name.startswith("model_0_submesh_"))
    for name in helper_meshes:
        obj = bpy.data.objects.get(name)
        if obj:
            bpy.data.objects.remove(obj, do_unlink=True)

    for obj in list(bpy.data.objects):
        if obj.type == "EMPTY":
            bpy.data.objects.remove(obj, do_unlink=True)

    constraint_count = 0
    for pose_bone in armature.pose.bones:
        for constraint in list(pose_bone.constraints):
            pose_bone.constraints.remove(constraint)
            constraint_count += 1

    bpy.context.view_layer.objects.active = armature
    bpy.ops.object.mode_set(mode="EDIT")
    removed = []
    for edit_bone in list(armature.data.edit_bones):
        if not edit_bone.use_deform:
            removed.append(edit_bone.name)
            armature.data.edit_bones.remove(edit_bone)
    bpy.ops.object.mode_set(mode="OBJECT")

    action_count = len(bpy.data.actions)
    for action in list(bpy.data.actions):
        bpy.data.actions.remove(action)

    scene.frame_set(1)
    for pose_bone in armature.pose.bones:
        pose_bone.matrix_basis.identity()
    bpy.context.view_layer.update()

    remaining = [b.name for b in armature.data.bones]
    log("控制骨剥离：删除 %d 根非 deform 骨、%d 条约束、%d 个临时网格、%d 个遗留 action"
        % (len(removed), constraint_count, len(helper_meshes), action_count))
    record("prune", {
        "removed_helper_meshes": helper_meshes,
        "removed_constraints": constraint_count,
        "removed_actions": action_count,
        "removed_control_bones": len(removed),
        "remaining_bones": len(remaining),
        "remaining_all_deform": all(b.use_deform for b in armature.data.bones),
        "remaining_all_mixamorig": all(n.startswith("mixamorig:") for n in remaining),
    })
    assert len(remaining) == 65, "剥离后应恰好 65 根变形骨，实际 %d" % len(remaining)
    assert all(b.use_deform for b in armature.data.bones), "剥离后仍有非 deform 骨"
    return armature


def sanitize_names(armature):
    """给导出的 GLB 内部命名去掉空格与点号。

    Godot 从 GLB 抽出的 PNG 会直接落到 models/ 并随资产入 Git；源文件里的
    "Diffuse Texture.014" 之类名字会生成带空格的落盘文件名，不便维护。
    """
    renamed = {}
    for image in list(bpy.data.images):
        if " " in image.name or "." in image.name:
            old = image.name
            image.name = "ny7_" + old.replace(" ", "_").replace(".", "_").lower()
            renamed[old] = image.name
    armature.name = "CultivatorNeutralYouthV7"
    armature.data.name = "CultivatorNeutralYouthV7"
    for old, new in SOURCE_SUBMESH_NAMES.items():
        obj = bpy.data.objects.get(old)
        if obj:
            obj.name = new
            obj.data.name = new + "_mesh"
            renamed[old] = new
    log("命名清理：%d 项" % len(renamed))
    record("renamed", renamed)
    return renamed


def enable_pose_translation(armature):
    """断开全部骨骼连接，使 pose location 通道真正生效。

    Blender 对 use_connect=True 的骨骼直接丢弃 pose location 通道。审计实测：
    v7 骨架需要 0.068 m 级的关节补偿平移才能把两套 rest 链对齐，但这些平移
    恰好落在 RightArm / LeftArm / RightShoulder / Spine2 等连接骨上，于是四个
    动作统一残留约 0.068 m 的末端误差（构造侧误差仅 1e-6，见「工程状态」）。
    断开连接只解除「头部焊在父骨尾部」的约束，不移动 rest 位置。
    """
    before = {b.name: (b.head_local.copy(), b.tail_local.copy()) for b in armature.data.bones}
    connected = sorted(b.name for b in armature.data.bones if b.use_connect)
    bpy.context.view_layer.objects.active = armature
    bpy.ops.object.mode_set(mode="EDIT")
    for edit_bone in armature.data.edit_bones:
        edit_bone.use_connect = False
    bpy.ops.object.mode_set(mode="OBJECT")
    bpy.context.view_layer.update()

    moved = 0
    for bone in armature.data.bones:
        head, tail = before[bone.name]
        moved = max(moved, (bone.head_local - head).length, (bone.tail_local - tail).length)
    assert moved < 1e-9, "断开连接改变了 rest 位置（最大 %.3e m）" % moved
    log("断开 %d 根连接骨以启用 pose location；rest 位置最大位移 %.3e m" % (len(connected), moved))
    record("pose_translation_enabled", {
        "disconnected_bones": connected,
        "rest_shift_m": moved,
    })
    return connected


# --- B. 中性遮挡层 -----------------------------------------------------------


def png_read_rgb(path):
    """零依赖 PNG 解码（仅 8bit truecolor/truecolor+alpha，源文件即此格式）。"""
    data = open(path, "rb").read()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", "不是 PNG：%s" % path
    pos = 8
    idat = b""
    width = height = None
    color_type = None
    bit_depth = None
    while pos < len(data):
        length = struct.unpack(">I", data[pos:pos + 4])[0]
        chunk_type = data[pos + 4:pos + 8]
        chunk = data[pos + 8:pos + 8 + length]
        if chunk_type == b"IHDR":
            width, height, bit_depth, color_type = struct.unpack(">IIBB", chunk[:10])
        elif chunk_type == b"IDAT":
            idat += chunk
        elif chunk_type == b"IEND":
            break
        pos += 12 + length
    assert bit_depth == 8 and color_type in (2, 6), "不支持的 PNG 格式 %s/%s" % (bit_depth, color_type)
    channels = 3 if color_type == 2 else 4
    stride = width * channels
    raw = zlib.decompress(idat)
    out = np.zeros((height, stride), dtype=np.uint8)
    previous = np.zeros(stride, dtype=np.uint8)
    cursor = 0
    for y in range(height):
        filter_type = raw[cursor]
        cursor += 1
        line = np.frombuffer(raw[cursor:cursor + stride], dtype=np.uint8).astype(np.int32).copy()
        cursor += stride
        if filter_type == 1:
            for i in range(channels, stride):
                line[i] = (line[i] + line[i - channels]) & 0xFF
        elif filter_type == 2:
            line = (line + previous.astype(np.int32)) & 0xFF
        elif filter_type == 3:
            for i in range(stride):
                left = int(line[i - channels]) if i >= channels else 0
                line[i] = (line[i] + ((left + int(previous[i])) >> 1)) & 0xFF
        elif filter_type == 4:
            for i in range(stride):
                left = int(line[i - channels]) if i >= channels else 0
                up = int(previous[i])
                upper_left = int(previous[i - channels]) if i >= channels else 0
                estimate = left + up - upper_left
                dl = abs(estimate - left)
                du = abs(estimate - up)
                dul = abs(estimate - upper_left)
                predictor = left if (dl <= du and dl <= dul) else (up if du <= dul else upper_left)
                line[i] = (line[i] + predictor) & 0xFF
        out[y] = line.astype(np.uint8)
        previous = line.astype(np.uint8)
    return out.reshape(height, width, channels)


def sample_bilinear(image_rgb, u, v):
    """u/v 为 Blender UV（v=0 在图像底部）；image_rgb 行 0 为图像顶部。"""
    height, width = image_rgb.shape[:2]
    x = np.clip(u, 0.0, 1.0) * (width - 1)
    y = (1.0 - np.clip(v, 0.0, 1.0)) * (height - 1)
    x0 = np.floor(x).astype(np.int64)
    y0 = np.floor(y).astype(np.int64)
    x1 = np.clip(x0 + 1, 0, width - 1)
    y1 = np.clip(y0 + 1, 0, height - 1)
    fx = (x - x0)[:, None]
    fy = (y - y0)[:, None]
    c00 = image_rgb[y0, x0].astype(np.float64)
    c10 = image_rgb[y0, x1].astype(np.float64)
    c01 = image_rgb[y1, x0].astype(np.float64)
    c11 = image_rgb[y1, x1].astype(np.float64)
    return (c00 * (1 - fx) * (1 - fy) + c10 * fx * (1 - fy)
            + c01 * (1 - fx) * fy + c11 * fx * fy)


def smoothstep(edge0, edge1, value):
    if edge1 == edge0:
        return np.where(value >= edge1, 1.0, 0.0)
    t = np.clip((value - edge0) / (edge1 - edge0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def garment_weight(centers):
    """每个面被遮挡层覆盖的比例：1=遮挡层，0=保留原表面材质。

    颈部 / 腕部 / 踝部各有一条 smoothstep 过渡带，边界都落在骨中段，
    不压关节，避免在肩肘髋膝踝处形成硬边。
    """
    x = centers[:, 0]
    z = centers[:, 2]

    # 颈线以上（头）露原表面材质；颈线以下覆盖。
    neck_cover = 1.0 - smoothstep(NECK_LINE_Z, NECK_LINE_Z + NECK_BLEND_Z, z)
    # 腕线以外（手）露原表面材质。
    wrist_cover = 1.0 - smoothstep(WRIST_LINE_ABS_X, WRIST_LINE_ABS_X + WRIST_BLEND_X, np.abs(x))
    # 踝线以下（脚）露原表面材质。
    ankle_cover = smoothstep(ANKLE_LINE_Z, ANKLE_LINE_Z + ANKLE_BLEND_Z, z)

    return np.clip(neck_cover * wrist_cover * ankle_cover, 0.0, 1.0)


def build_garment_texture(body_object, source_image_rgb, source_uv_name):
    mesh = body_object.data
    mesh.calc_loop_triangles()
    world = body_object.matrix_world
    uv_layer = mesh.uv_layers[source_uv_name].data

    base_rgb = GARMENT_RGB
    zs = np.array([(world @ v.co).z for v in mesh.vertices])
    z_min, z_max = float(zs.min()), float(zs.max())

    triangle_count = len(mesh.loop_triangles)
    loop_uv = np.zeros((len(mesh.loops), 2), dtype=np.float64)
    for index, item in enumerate(uv_layer):
        loop_uv[index, 0] = item.uv[0]
        loop_uv[index, 1] = item.uv[1]

    tri_loops = np.zeros((triangle_count, 3), dtype=np.int64)
    tri_centers = np.zeros((triangle_count, 3), dtype=np.float64)
    for index, triangle in enumerate(mesh.loop_triangles):
        tri_loops[index] = triangle.loops
        tri_centers[index] = world @ triangle.center

    cover = garment_weight(tri_centers)

    # 原表面材质采样（保留颈部/手/脚的原始皮肤与细节）。
    source_rgb = sample_bilinear(source_image_rgb, loop_uv[:, 0], loop_uv[:, 1]) / 255.0

    # 遮挡层颜色：单一深靛 + 极轻的自下而上明度梯度。
    height_t = np.clip((tri_centers[:, 2] - z_min) / max(z_max - z_min, 1e-6), 0.0, 1.0)
    garment = np.zeros((triangle_count, 3), dtype=np.float64)
    for channel in range(3):
        shade = 1.0 - GARMENT_GRADIENT * 0.5 + GARMENT_GRADIENT * height_t
        garment[:, channel] = base_rgb[channel] * shade

    loop_colours = np.zeros((len(mesh.loops), 3), dtype=np.float64)
    filled = np.zeros(len(mesh.loops), dtype=bool)
    for index in range(triangle_count):
        loops = tri_loops[index]
        weight = cover[index]
        colour = garment[index] * weight + source_rgb[loops].mean(axis=0) * (1.0 - weight)
        loop_colours[loops] = colour
        filled[loops] = True
    assert filled.all(), "存在未被任何三角形引用的 loop"

    pixels = rasterize(mesh, tri_loops, loop_colours, TEXTURE_SIZE)
    return pixels, cover, tri_centers, garment


def rasterize(mesh, tri_loops, loop_colours, size):
    uv = np.zeros((len(mesh.loops), 2), dtype=np.float64)
    for index, item in enumerate(mesh.uv_layers.active.data):
        uv[index, 0] = item.uv[0]
        uv[index, 1] = item.uv[1]

    buffer = np.zeros((size, size, 3), dtype=np.float64)
    coverage = np.zeros((size, size), dtype=bool)

    for triangle_index in range(tri_loops.shape[0]):
        loops = tri_loops[triangle_index]
        pts = uv[loops] * size
        # 图像第 0 行 = 顶部，UV v=0 在底部 -> 翻转
        ys = (size - pts[:, 1])
        xs = pts[:, 0]
        x_min = max(int(math.floor(xs.min() - 1)), 0)
        x_max = min(int(math.ceil(xs.max() + 1)), size - 1)
        y_min = max(int(math.floor(ys.min() - 1)), 0)
        y_max = min(int(math.ceil(ys.max() + 1)), size - 1)
        if x_max < x_min or y_max < y_min:
            continue
        grid_x, grid_y = np.meshgrid(
            np.arange(x_min, x_max + 1) + 0.5, np.arange(y_min, y_max + 1) + 0.5)
        x0, y0 = xs[0], ys[0]
        x1, y1 = xs[1], ys[1]
        x2, y2 = xs[2], ys[2]
        denominator = (y1 - y2) * (x0 - x2) + (x2 - x1) * (y0 - y2)
        if abs(denominator) < 1e-12:
            continue
        weight0 = ((y1 - y2) * (grid_x - x2) + (x2 - x1) * (grid_y - y2)) / denominator
        weight1 = ((y2 - y0) * (grid_x - x2) + (x0 - x2) * (grid_y - y2)) / denominator
        weight2 = 1.0 - weight0 - weight1
        inside = (weight0 >= -0.02) & (weight1 >= -0.02) & (weight2 >= -0.02)
        if not inside.any():
            continue
        colour = (weight0[..., None] * loop_colours[loops[0]]
                  + weight1[..., None] * loop_colours[loops[1]]
                  + weight2[..., None] * loop_colours[loops[2]])
        target = buffer[y_min:y_max + 1, x_min:x_max + 1]
        mask = coverage[y_min:y_max + 1, x_min:x_max + 1]
        target[inside] = colour[inside]
        mask[inside] = True

    # 向外扩张，避免 mipmap / 双线性采样在 UV 岛边缘吸到黑色背景。
    filled = coverage.copy()
    for _ in range(DILATE_PIXELS):
        grown = filled.copy()
        for shift_y, shift_x in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            rolled = np.roll(buffer, (shift_y, shift_x), axis=(0, 1))
            rolled_filled = np.roll(filled, (shift_y, shift_x), axis=(0, 1))
            fillable = (~grown) & rolled_filled
            grown |= fillable
            buffer[fillable] = rolled[fillable]
        filled = grown
    buffer[~filled] = np.array(GARMENT_RGB, dtype=np.float64)
    return np.clip(buffer, 0.0, 1.0)


def write_texture(pixels, path):
    image = bpy.data.images.new("neutral_body", width=pixels.shape[1],
                                height=pixels.shape[0], alpha=False, float_buffer=False)
    flat = np.concatenate(
        [pixels[::-1], np.ones((pixels.shape[0], pixels.shape[1], 1))], axis=2).astype(np.float32)
    image.pixels.foreach_set(flat.ravel())
    image.filepath_raw = path
    image.file_format = "PNG"
    image.save()
    bpy.data.images.remove(image)
    return path


def build_garment_material(texture_path):
    image = bpy.data.images.load(texture_path, check_existing=False)
    image.name = "neutral_body"
    image.pack()

    material = bpy.data.materials.new("NY7_Neutral")
    material.use_nodes = True
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    nodes.clear()
    output = nodes.new("ShaderNodeOutputMaterial")
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    texture = nodes.new("ShaderNodeTexImage")
    texture.image = image
    bsdf.inputs["Roughness"].default_value = 0.68
    bsdf.inputs["Metallic"].default_value = 0.0
    if "Specular IOR Level" in bsdf.inputs:
        bsdf.inputs["Specular IOR Level"].default_value = 0.25
    links.new(texture.outputs["Color"], bsdf.inputs["Base Color"])
    links.new(bsdf.outputs["BSDF"], output.inputs["Surface"])
    output.location = (300, 0)
    bsdf.location = (0, 0)
    texture.location = (-320, 0)
    return material


def apply_garment():
    body = bpy.data.objects[BODY_SUBMESH]
    source_material = body.material_slots[0].material
    source_image_node = None
    for node in source_material.node_tree.nodes:
        if node.type == "TEX_IMAGE" and node.outputs["Color"].links:
            for link in node.outputs["Color"].links:
                if link.to_socket.name == "Base Color":
                    source_image_node = node
    assert source_image_node is not None, "找不到源身体材质的 Base Color 贴图"

    image = source_image_node.image
    source_rgb = np.array(image.pixels[:], dtype=np.float32).reshape(
        image.size[1], image.size[0], 4)[..., :3] * 255.0
    source_uv_name = body.data.uv_layers[0].name
    vertices_before = len(body.data.vertices)
    polygons_before = len(body.data.polygons)
    bbox_before = [Vector(corner) for corner in body.bound_box]
    world_bbox_before = [body.matrix_world @ corner for corner in bbox_before]

    pixels, cover, centers, garment = build_garment_texture(body, source_rgb, source_uv_name)
    write_texture(pixels, TEX_PNG)
    material = build_garment_material(TEX_PNG)

    for slot in list(body.material_slots):
        slot.material = None
    while body.material_slots:
        body.material_slots[0].material = None
        bpy.context.view_layer.objects.active = body
        body.active_material_index = 0
        bpy.ops.object.material_slot_remove()
    body.data.materials.append(material)

    world_bbox_after = [body.matrix_world @ Vector(corner) for corner in body.bound_box]
    delta = max((a - b).length for a, b in zip(world_bbox_after, world_bbox_before))

    covered = int((cover > 0.999).sum())
    exposed = int((cover < 0.001).sum())
    blended = int(len(cover) - covered - exposed)

    # 「禁止裸露敏感部位」：躯干与骨盆区内不允许存在露皮肤的面。
    sensitive_mask = ((centers[:, 2] > ANKLE_LINE_Z + ANKLE_BLEND_Z)
                      & (centers[:, 2] < NECK_LINE_Z)
                      & (np.abs(centers[:, 0]) < WRIST_LINE_ABS_X))
    sensitive_exposed = int((cover[sensitive_mask] < 0.999).sum())

    log("遮挡层：%d 面，覆盖 %d / 过渡 %d / 露皮肤 %d，躯干+骨盆露皮肤 %d"
        % (len(cover), covered, blended, exposed, sensitive_exposed))
    record("garment", {
        "submesh": BODY_SUBMESH,
        "faces": int(len(cover)),
        "faces_covered": covered,
        "faces_blended": blended,
        "faces_skin": exposed,
        "sensitive_faces_exposed": sensitive_exposed,
        "colour_srgb": "#%02X%02X%02X" % tuple(int(round(c * 255)) for c in GARMENT_RGB),
        "texture": os.path.relpath(TEX_PNG, ROOT),
        "texture_size": [TEXTURE_SIZE, TEXTURE_SIZE],
        "vertices_before": vertices_before,
        "vertices_after": len(body.data.vertices),
        "polygons_before": polygons_before,
        "polygons_after": len(body.data.polygons),
        "world_bbox_delta_m": delta,
    })
    assert sensitive_exposed == 0, "躯干或骨盆存在裸露面：%d" % sensitive_exposed
    assert len(body.data.vertices) == vertices_before, "遮挡层不得改变顶点数"
    assert len(body.data.polygons) == polygons_before, "遮挡层不得改变面数"
    assert delta < 1e-6, "遮挡层不得改变轮廓（包围盒位移 %.9f）" % delta


# --- C. 动作重定向 -----------------------------------------------------------


def read_legacy_actions():
    bpy.ops.wm.open_mainfile(filepath=ANIM_BLEND)
    armature = bpy.data.objects["CultivatorRig"]
    rest = bone_rest_table(armature)
    parents = bone_parent_table(armature)

    actions = {}
    for action in bpy.data.actions:
        curves = channelbag_fcurves(action)
        if not curves:
            continue
        samples = {}
        for curve in curves:
            if not curve.data_path.startswith('pose.bones["'):
                continue
            bone = curve.data_path.split('"')[1]
            prop = curve.data_path.rsplit(".", 1)[-1]
            if prop not in ("location", "rotation_quaternion", "scale"):
                continue
            key = (bone, prop, curve.array_index)
            first, last = int(round(action.frame_range[0])), int(round(action.frame_range[1]))
            frames = np.arange(first, last + 1)
            values = np.array([curve.evaluate(float(f)) for f in frames], dtype=np.float64)
            samples[key] = values
        actions[action.name] = {
            "frames": (int(round(action.frame_range[0])), int(round(action.frame_range[1]))),
            "samples": samples,
        }
    return {"rest": rest, "parents": parents, "actions": actions}


def channelbag_fcurves(action):
    try:
        return list(action.fcurves)
    except Exception:
        pass
    curves = []
    for layer in action.layers:
        for strip in layer.strips:
            for channelbag in strip.channelbags:
                curves.extend(channelbag.fcurves)
    return curves


def local_rest(rest, parent, name):
    """该骨相对父骨的 rest 帧；父骨为 None 时即 armature 空间 rest。"""
    return rest[parent].inverted() @ rest[name] if parent else rest[name]


def hierarchy_order(parents):
    """父骨先于子骨的遍历顺序。"""
    order = []
    pending = sorted(parents)
    while pending:
        progressed = False
        for name in list(pending):
            parent = parents[name]
            if parent is None or parent in order:
                order.append(name)
                pending.remove(name)
                progressed = True
        assert progressed, "骨骼层级存在环"
    return order


def rest_frame_tables(rest, parents, order):
    return {name: local_rest(rest, parents[name], name) for name in order}


def armature_pose_chain(order, parents, local, basis):
    """由 pose basis 自根向下累乘出 armature 空间的骨骼姿态矩阵。"""
    posed = {}
    for name in order:
        parent = parents[name]
        parent_matrix = posed[parent] if parent else Matrix.Identity(4)
        posed[name] = parent_matrix @ local[name] @ basis[name]
    return posed


def import_actions(armature, legacy):
    rest_new = bone_rest_table(armature)
    parents_new = bone_parent_table(armature)
    rest_old = legacy["rest"]
    parents_old = legacy["parents"]

    order = hierarchy_order(parents_new)
    # 源骨架的 deform 父级链：删掉控制骨后，旧文件里相邻两骨之间可能原本隔着
    # Ctrl_* 骨（审计实测 RightArm -> Ctrl_ForeArm_FK_Right -> RightForeArm），
    # 因此旧链必须走 OLD_PAR 自己的父级，不能借用新骨架的父级。
    parents_old_chain = {name: parents_old.get(name) for name in order}
    assert set(parents_old_chain) == set(order), "两套骨架的变形骨集合不一致"
    order_old = hierarchy_order(parents_old_chain)
    assert set(order_old) == set(order), "源骨架变形链的骨集合与目标不一致"
    local_new = rest_frame_tables(rest_new, parents_new, order)
    local_old_chain = {n: local_rest(rest_old, parents_old_chain[n], n) for n in order}
    mismatched_parents = sorted(
        n for n in order if parents_old_chain[n] != parents_new[n])
    record("parentage", {
        "bones": len(order),
        "deform_parent_mismatch": mismatched_parents,
    })
    if mismatched_parents:
        log("源/目标 deform 父级不同的骨（%d 根）：%s"
            % (len(mismatched_parents), mismatched_parents))

    summary = {}
    for clip in CLIPS:
        source = legacy["actions"][clip]
        first, last = source["frames"]
        frames = list(range(first, last + 1))
        count = len(frames)
        samples = source["samples"]

        # 源动作的 pose basis（旧骨架），逐帧对齐到同一整数帧表。
        basis_loc = {}
        basis_quat = {}
        for name in order:
            locations = np.zeros((count, 3), dtype=np.float64)
            for axis in range(3):
                values = samples.get((name, "location", axis))
                if values is not None and len(values) == count:
                    locations[:, axis] = values
            quaternions = np.zeros((count, 4), dtype=np.float64)
            quaternions[:, 0] = 1.0
            for axis in range(4):
                values = samples.get((name, "rotation_quaternion", axis))
                if values is not None and len(values) == count:
                    quaternions[:, axis] = values
            basis_loc[name] = locations
            basis_quat[name] = quaternions

        new_loc = {name: np.zeros((count, 3)) for name in order}
        new_quat = {name: np.zeros((count, 4)) for name in order}
        for frame_index in range(count):
            # 1) 源动作按「变形骨链」自根累乘，得到每根骨的 armature 空间姿态。
            #    不依赖旧骨架里父骨是不是 Ctrl_*，也不用骨长/rest 朝向一致的假设。
            basis_old = {}
            for name in order:
                basis_old[name] = Matrix.Translation(
                    Vector(basis_loc[name][frame_index])) @ (
                    Quaternion(basis_quat[name][frame_index]).to_matrix().to_4x4())
            posed_old = armature_pose_chain(
                order_old, parents_old_chain, local_old_chain, basis_old)

            # 2) 反解目标骨架的 pose basis：由 armature 空间姿态与父骨已求出的
            #    姿态退回本骨的局部姿态，再除以本地 rest 帧。
            pose_new = {}
            for name in order:
                parent = parents_new[name]
                parent_pose = pose_new[parent] if parent else Matrix.Identity(4)
                converted = local_new[name].inverted() @ (
                    parent_pose.inverted() @ posed_old[name])
                location = converted.to_translation()
                quaternion = converted.to_quaternion()
                # 四元数双覆盖：to_quaternion() 的符号是任意的，相邻帧符号相反会让
                # 分量线性插值穿过原点，姿态被放大成米级偏移（run 实测 2.18 m）。
                if frame_index and quaternion.dot(Quaternion(new_quat[name][frame_index - 1])) < 0.0:
                    quaternion = -quaternion
                new_loc[name][frame_index] = location
                new_quat[name][frame_index] = (quaternion.w, quaternion.x,
                                               quaternion.y, quaternion.z)
                pose_new[name] = parent_pose @ local_new[name] @ (
                    Matrix.Translation(location) @ quaternion.to_matrix().to_4x4())

        action = bpy.data.actions.new(clip)
        action.use_fake_user = True
        armature.animation_data_create()
        armature.animation_data.action = action
        # 先用 keyframe_insert 建出 action 的 layer/strip/slot/channelbag 结构，
        # 再把每个通道的点清空重写为完整帧表 —— 否则 insert 留下的单个点会与
        # 目标序列首尾相接，插值穿过中间所有值，姿态被放大成数米级偏移。
        for name in order:
            pose_bone = armature.pose.bones[name]
            pose_bone.rotation_mode = "QUATERNION"
            pose_bone.location = Vector(new_loc[name][0])
            pose_bone.rotation_quaternion = Quaternion(new_quat[name][0])
            pose_bone.keyframe_insert(data_path="location", frame=frames[0], group=name)
            pose_bone.keyframe_insert(data_path="rotation_quaternion", frame=frames[0], group=name)

        channel_count = 0
        for curve in channelbag_fcurves(action):
            bone = curve.data_path.split('"')[1]
            prop = curve.data_path.rsplit(".", 1)[-1]
            index = curve.array_index
            if prop == "location":
                values = new_loc[bone][:, index]
            elif prop == "rotation_quaternion":
                values = new_quat[bone][:, index]
            else:
                raise AssertionError("意外的通道 %s" % curve.data_path)
            while len(curve.keyframe_points):
                curve.keyframe_points.remove(curve.keyframe_points[0], fast=True)
            curve.keyframe_points.add(count)
            for i in range(count):
                keyframe = curve.keyframe_points[i]
                keyframe.co = (float(frames[i]), float(values[i]))
                keyframe.interpolation = "LINEAR"
            curve.update()
            channel_count += 1
        assert channel_count == len(order) * 7, (
            "通道数 %d 应为 %d" % (channel_count, len(order) * 7))
        action.use_frame_range = True
        action.frame_start = float(frames[0])
        action.frame_end = float(frames[-1])
        armature.animation_data.action = None

        # 逐帧回读：新骨架的 armature 空间骨骼端点应与源动作一致。
        summary[clip] = verify_action(
            armature, clip, legacy, order, parents_new, parents_old_chain)
        log("动作 %s：%d 帧，最大端点误差 %.6f m @ %s（半帧 %.6f m @ %s）" % (
            clip, count, summary[clip]["max_endpoint_error_m"],
            summary[clip]["max_endpoint_error_at"],
            summary[clip]["max_subframe_endpoint_error_m"],
            summary[clip]["max_subframe_endpoint_error_at"]))
    return summary, order


def _sample_channel(samples, name, prop, axis, offset, default):
    """源动作在任意帧的通道值；源只有逐帧整数关键帧，故线性插值。"""
    values = samples.get((name, prop, axis))
    if values is None:
        return default
    low = int(math.floor(offset))
    high = min(low + 1, len(values) - 1)
    low = max(low, 0)
    weight = offset - low
    return float(values[low] * (1.0 - weight) + values[high] * weight)


def verify_action(armature, clip, legacy, order, parents_new, parents_old_chain):
    """把新 action 求值回旧骨架的等价姿态，比较骨骼 armature 空间端点。

    迁移以 armature 空间姿态为标准形（见 import_actions 第 1/2 步），因此正确
    迁移时新旧两条变形骨链的每根骨端点都应重合；这里独立重建两侧矩阵做对照，
    不依赖骨名、rest 朝向或骨长一致的假设。
    """
    action = bpy.data.actions[clip]
    armature.animation_data.action = action
    rest_new = bone_rest_table(armature)
    rest_old = legacy["rest"]
    source = legacy["actions"][clip]
    first, last = source["frames"]
    frames = list(range(first, last + 1))
    samples = source["samples"]

    order_old = hierarchy_order(parents_old_chain)
    local_new = rest_frame_tables(rest_new, parents_new, order)
    local_old = {n: local_rest(rest_old, parents_old_chain[n], n) for n in order}
    # 骨长取源骨架：迁移后每根骨的端点都应与源动作在同一位置。
    bone_length = {n: float(local_old[n].to_3x3().col[1].length) for n in order}

    worst = 0.0
    worst_bone = ""
    worst_subframe = 0.0
    worst_subframe_bone = ""
    # 整数帧必须逐位一致（迁移正确性）；半帧用于暴露插值区间问题
    # （分量为线性插值，与球面插值的固有差异单独记录，不与正确性混用同一阈值）。
    check_frames = []
    for frame in frames:
        check_frames.append(float(frame))
        if frame != frames[-1]:
            check_frames.append(frame + 0.5)

    for frame in check_frames:
        bpy.context.scene.frame_set(int(math.floor(frame)), subframe=frame - math.floor(frame))
        bpy.context.view_layer.update()
        basis_new = {n: armature.pose.bones[n].matrix_basis.copy() for n in order}
        posed_new = armature_pose_chain(order, parents_new, local_new, basis_new)
        offset = frame - first
        basis_old = {}
        for name in order:
            location = np.array([
                _sample_channel(samples, name, "location", axis, offset, 0.0) for axis in range(3)])
            quaternion = np.array([
                _sample_channel(samples, name, "rotation_quaternion", axis, offset,
                                1.0 if axis == 0 else 0.0) for axis in range(4)])
            norm = np.linalg.norm(quaternion)
            if norm > 1e-9:
                quaternion = quaternion / norm
            basis_old[name] = Matrix.Translation(Vector(location)) @ (
                Quaternion(quaternion).to_matrix().to_4x4())
        posed_old = armature_pose_chain(
            order_old, parents_old_chain, local_old, basis_old)
        for name in order:
            head_new = posed_new[name].to_translation()
            tail_new = posed_new[name] @ Vector((0.0, bone_length[name], 0.0))
            head_old = posed_old[name].to_translation()
            tail_old = posed_old[name] @ Vector((0.0, bone_length[name], 0.0))
            error = max((head_new - head_old).length, (tail_new - tail_old).length)
            is_integer = abs(frame - round(frame)) < 1e-9
            if is_integer and error > worst:
                worst = error
                worst_bone = "%s@%.1f" % (name, frame)
            elif not is_integer and error > worst_subframe:
                worst_subframe = error
                worst_subframe_bone = "%s@%.1f" % (name, frame)
    armature.animation_data.action = None
    return {
        "frames": [first, last],
        "checked_samples": len(check_frames),
        "max_endpoint_error_m": worst,
        "max_endpoint_error_at": worst_bone,
        "max_subframe_endpoint_error_m": worst_subframe,
        "max_subframe_endpoint_error_at": worst_subframe_bone,
    }


# --- D. 导出 -----------------------------------------------------------------


def export_glb(armature):
    selection = [armature] + [bpy.data.objects[name] for name in CHARACTER_SUBMESHES]
    bpy.ops.object.select_all(action="DESELECT")
    for item in selection:
        item.select_set(True)
    bpy.context.view_layer.objects.active = armature
    for action in bpy.data.actions:
        action.use_fake_user = True
    bpy.ops.export_scene.gltf(
        filepath=OUT_GLB,
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_apply=False,
        export_skins=True,
        export_animations=True,
        export_animation_mode="ACTIONS",
        export_bake_animation=False,
        export_optimize_animation_size=False,
        export_def_bones=False,
        export_leaf_bone=False,
        export_image_format="AUTO",
    )


def read_glb(path):
    data = open(path, "rb").read()
    magic, version, total = struct.unpack("<III", data[:12])
    assert magic == 0x46546C67, "不是 GLB"
    cursor = 12
    payload = None
    binary = None
    while cursor < total:
        length, chunk_type = struct.unpack("<II", data[cursor:cursor + 8])
        chunk = data[cursor + 8:cursor + 8 + length]
        if chunk_type == 0x4E4F534A:
            payload = json.loads(chunk)
        elif chunk_type == 0x004E4942:
            binary = chunk
        cursor += 8 + length
    return payload, binary, data


def verify_glb():
    payload, binary, raw = read_glb(OUT_GLB)
    names = [animation["name"] for animation in payload.get("animations", [])]
    skins = payload.get("skins", [])
    meshes = payload.get("meshes", [])
    result = {
        "bytes": len(raw),
        "sha256": sha256(OUT_GLB),
        "animations": names,
        "animation_channel_counts": {
            animation["name"]: len(animation["channels"]) for animation in payload["animations"]},
        "skins": [{"name": skin.get("name"), "joints": len(skin["joints"])} for skin in skins],
        "meshes": [{"name": mesh.get("name"),
                    "primitives": len(mesh["primitives"])} for mesh in meshes],
        "materials": [material.get("name") for material in payload.get("materials", [])],
        "images": [image.get("name") for image in payload.get("images", [])],
        "scene_roots": [
            payload["nodes"][index].get("name") for index in payload["scenes"][0]["nodes"]],
        "attributes": sorted({
            key for mesh in meshes for primitive in mesh["primitives"]
            for key in primitive["attributes"]}),
    }
    return result


# --- E. 证据渲染 -------------------------------------------------------------


def setup_render_scene():
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 720
    scene.render.resolution_y = 1080
    scene.render.film_transparent = False
    scene.view_settings.view_transform = "Standard"
    if scene.world is None:
        scene.world = bpy.data.worlds.new("World")
    scene.world.use_nodes = True
    background = scene.world.node_tree.nodes.get("Background")
    if background:
        background.inputs[0].default_value = (0.62, 0.64, 0.66, 1.0)
        background.inputs[1].default_value = 1.1

    camera_data = bpy.data.cameras.new("EvidenceCamera")
    camera_data.type = "ORTHO"
    camera = bpy.data.objects.new("EvidenceCamera", camera_data)
    scene.collection.objects.link(camera)
    scene.camera = camera

    key = bpy.data.lights.new("EvidenceKey", "SUN")
    key.energy = 3.0
    key_object = bpy.data.objects.new("EvidenceKey", key)
    scene.collection.objects.link(key_object)
    key_object.rotation_euler = (math.radians(58), 0.0, math.radians(35))

    fill = bpy.data.lights.new("EvidenceFill", "SUN")
    fill.energy = 1.6
    fill_object = bpy.data.objects.new("EvidenceFill", fill)
    scene.collection.objects.link(fill_object)
    fill_object.rotation_euler = (math.radians(68), 0.0, math.radians(-140))

    plane = bpy.data.meshes.new("EvidenceFloor")
    import bmesh  # noqa: F401  (标准库里已随 Blender 提供)
    floor = bpy.data.objects.new("EvidenceFloor", plane)
    scene.collection.objects.link(floor)
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=6.0)
    bm.to_mesh(plane)
    bm.free()
    floor_material = bpy.data.materials.new("EvidenceFloorMat")
    floor_material.use_nodes = True
    floor_material.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (
        0.55, 0.56, 0.53, 1.0)
    plane.materials.append(floor_material)
    return camera, camera_data


def render_shot(camera, camera_data, name, azimuth_deg, elevation_deg, ortho, focus_z, distance=6.0):
    center_x = 0.0
    center_y = 0.0
    angle = math.radians(azimuth_deg)
    elevation = math.radians(elevation_deg)
    direction = Vector((math.sin(angle) * math.cos(elevation),
                        -math.cos(angle) * math.cos(elevation),
                        math.sin(elevation)))
    camera.location = Vector((center_x, center_y, focus_z)) + direction * distance
    camera.rotation_euler = (-direction).to_track_quat("-Z", "Y").to_euler()
    camera_data.ortho_scale = ortho
    bpy.context.scene.render.filepath = os.path.join(RENDER_DIR, name + ".png")
    bpy.ops.render.render(write_still=True)


def render_evidence(armature):
    os.makedirs(RENDER_DIR, exist_ok=True)
    camera, camera_data = setup_render_scene()
    height = 1.945
    shot_list = [
        ("v7_rig_front", 0.0, 0.0, height * 1.10, height * 0.5),
        ("v7_rig_back", 180.0, 0.0, height * 1.10, height * 0.5),
        ("v7_rig_side", 90.0, 0.0, height * 1.10, height * 0.5),
        ("v7_rig_three_quarter", 40.0, 0.0, height * 1.10, height * 0.5),
        ("v7_rig_head", 0.0, 6.0, height * 0.34, height - height * 0.115),
        ("v7_rig_feet", 0.0, 22.0, height * 0.30, height * 0.055),
    ]
    for name, azimuth, elevation, ortho, focus in shot_list:
        render_shot(camera, camera_data, name, azimuth, elevation, ortho, focus)

    armature.animation_data_create()
    for clip in CLIPS:
        armature.animation_data.action = bpy.data.actions[clip]
        range_first = int(bpy.data.actions[clip].frame_start)
        range_last = int(bpy.data.actions[clip].frame_end)
        picks = sorted({range_first, range_first + (range_last - range_first) // 3,
                        range_first + 2 * (range_last - range_first) // 3, range_last})
        for frame in picks[:2]:
            bpy.context.scene.frame_set(frame)
            render_shot(camera, camera_data, "v7_pose_%s_f%03d" % (clip, frame), 32.0, 4.0,
                        height * 1.10, height * 0.5)
    armature.animation_data.action = None
    bpy.context.scene.frame_set(1)


# --- 主流程 ------------------------------------------------------------------


def main():
    start = time.time()
    os.makedirs(OUT_DIR, exist_ok=True)
    os.makedirs(RENDER_DIR, exist_ok=True)

    record("source_blend", os.path.relpath(SRC_BLEND, ROOT))
    record("source_sha256", sha256(SRC_BLEND))
    record("animation_source_blend", os.path.relpath(ANIM_BLEND, ROOT))
    record("animation_source_sha256", sha256(ANIM_BLEND))

    log("读取旧四动作骨架（动作迁移源）")
    legacy = read_legacy_actions()
    record("legacy_actions", {
        name: {"frames": list(data["frames"]),
               "bones": len({key[0] for key in data["samples"]})}
        for name, data in legacy["actions"].items()})
    record("legacy_bones", len(legacy["rest"]))

    log("打开未改原件 " + os.path.basename(SRC_BLEND))
    bpy.ops.wm.open_mainfile(filepath=SRC_BLEND)
    bpy.context.scene.render.fps = 30
    armature = prune_control_rig()
    enable_pose_translation(armature)
    sanitize_names(armature)
    apply_garment()
    # Godot 4.6 会把 GLB 内嵌图像映射到这个稳定的源码路径，并让导入场景按
    # UID 引用它。显式保留同一 PNG，避免清理导入缓存后只剩 `.import` 边车、
    # 首次扫描退回文本路径并报告 `invalid UID`。
    shutil.copyfile(TEX_PNG, RUNTIME_NEUTRAL_TEX)
    record("runtime_neutral_texture", {
        "path": os.path.relpath(RUNTIME_NEUTRAL_TEX, ROOT),
        "sha256": sha256(RUNTIME_NEUTRAL_TEX),
    })

    log("重定向 idle/walk/run/jump")
    summary, order = import_actions(armature, legacy)
    record("retarget", {
        "method": "B_new = (L_new)^-1 . L_old . B_old  (rest-frame conjugation)",
        "bones": len(order),
        "clips": summary,
    })
    for clip, data in summary.items():
        assert data["max_endpoint_error_m"] < 1e-4, (
            "%s 整数帧端点误差 %.6f m 超过阈值，动作迁移不可信"
            % (clip, data["max_endpoint_error_m"]))
        assert data["max_subframe_endpoint_error_m"] < 0.15, (
            "%s 半帧端点误差 %.6f m 超过阈值" % (clip, data["max_subframe_endpoint_error_m"]))

    # 回到中性帧再保存/导出
    armature.animation_data.action = None
    for pose_bone in armature.pose.bones:
        pose_bone.matrix_basis.identity()
    bpy.context.view_layer.update()

    log("导出 GLB")
    export_glb(armature)
    glb = verify_glb()
    record("glb", glb)
    log("GLB 回读：skins=%s animations=%s" % (glb["skins"], glb["animations"]))
    assert len(glb["skins"]) == 1, "GLB 必须只有 1 个 skin"
    assert glb["skins"][0]["joints"] == 65, "GLB skin 应有 65 个 joint"
    assert set(glb["animations"]) == set(CLIPS), "GLB clip 集合不符：%s" % glb["animations"]
    assert glb["materials"], "GLB 缺少材质"

    log("渲染证据")
    render_evidence(armature)

    for name in ("EvidenceCamera", "EvidenceKey", "EvidenceFill", "EvidenceFloor"):
        obj = bpy.data.objects.get(name)
        if obj:
            bpy.data.objects.remove(obj, do_unlink=True)

    bpy.ops.wm.save_as_mainfile(filepath=OUT_BLEND)
    record("blend", os.path.relpath(OUT_BLEND, ROOT))
    record("blend_sha256", sha256(OUT_BLEND))
    record("elapsed_seconds", round(time.time() - start, 1))

    with open(MANIFEST, "w") as handle:
        json.dump(REPORT, handle, indent=1, ensure_ascii=False, sort_keys=True)
    log("完成，用时 %.1fs" % (time.time() - start))


main()
