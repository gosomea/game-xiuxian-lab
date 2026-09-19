#!/usr/bin/env python3
"""Route B preparation: KayKit Rogue_Hooded upstream GLB -> clean static single-mesh T-pose
input for the Mixamo Auto-Rigger (manual marker step).

This script STOPS before upload. It does not touch Mixamo, does not start a browser and
does not run mixamo_driver_phase1.py / phase2 / phase3.

Writes ONLY into --output-dir (default docs/art/kaykit_route_ab/route_b):
  <role>_static.fbx                Mixamo upload input (primary)
  <role>_static.obj/.mtl/.png      Mixamo upload input (fallback) + texture
  <role>_route_b_source.blend      Blender source project (static mesh + preserved cape)
  <role>_tpose_front.png           TRUE T-pose front preview of the upload mesh
  <role>_tpose_3q.png              TRUE T-pose 3/4 preview of the upload mesh
  prepare_manifest.json            bytes/sha256 per output + upstream sha256 + marker notes

The upstream GLB is opened read-only and is never modified or overwritten.

Run:
  blender --background --factory-startup --python mcp/mixamo/kaykit_route_b_prepare.py -- \
      --input docs/art/kaykit_route_ab/upstream/kaykit-adventurers-1.0-672074b/Rogue_Hooded.glb \
      --output-dir docs/art/kaykit_route_ab/route_b
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import sys

import bpy
from mathutils import Vector

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))

# --------------------------------------------------------------------------------------
# Constants from the read-only audit of pinned upstream commit
# 672074b73ba276876a19e8816ecdc5241817ab47 (docs/art/kaykit_route_ab/asset_ledger.md)
# --------------------------------------------------------------------------------------
UPSTREAM_GLB_SHA256 = "93e6e25213009952276d9cf34f5d96a243767334c66f280db0433ddfabb91545"

BODY_PARTS = [
    "Rogue_Body",
    "Rogue_Head_Hooded",
    "Rogue_ArmLeft",
    "Rogue_ArmRight",
    "Rogue_LegLeft",
    "Rogue_LegRight",
]
WEAPON_PARTS = ["Knife", "Knife_Offhand", "1H_Crossbow", "2H_Crossbow", "Throwable"]
CAPE_PART = "Rogue_Cape"
CAPE_COLLECTION = "cape_preserved"
CAPE_REBIND_BONE = "chest"

# Ledger "7 mesh / 4,005 tris" for the character body = 6 skinned parts + the cape.
# The upload mesh is the 6 skinned parts only, so it carries 4,005 - 84 = 3,921 tris.
EXPECTED_UPLOAD_TRIS = 3921          # 6 skinned body parts -> the Mixamo upload mesh
EXPECTED_BODY_PLUS_CAPE_TRIS = 4005  # ledger reading for the whole character body
EXPECTED_CAPE_TRIS = 84
EXPECTED_WEAPON_TRIS = 2030

EXPECTED_ARM_NAME = "upperarm.l"
EXPECTED_HAND_NAME = "hand.l"

FACING_MIN_HALF = 0.30     # nose/face must protrude towards -Y
GROUND_TOL = 5e-3
T_POSE_ARM_TOL_DEG = 2.0
POSE_MATCH_TOL = 1e-3
CENTRE_TOL = 0.05
MIN_PNG_BYTES = 4096
MIN_FBX_BYTES = 4096
MIN_OBJ_BYTES = 1024


class Fail(RuntimeError):
    """Preparation failure."""


def log(msg):
    print("### " + msg, flush=True)


def require(cond, msg):
    if not cond:
        raise Fail(msg)


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def rel(path):
    try:
        return os.path.relpath(path, REPO_ROOT)
    except ValueError:
        return path


# --------------------------------------------------------------------------------------
# Scene helpers
# --------------------------------------------------------------------------------------
def wipe_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def import_open(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    return [o for o in bpy.data.objects if o not in before]


def clear_animation(arm):
    """Drop active action, every NLA strip/track and every pose transform.

    The glTF importer attaches an active action plus one NLA track per clip (76 of them),
    so a naive export would bake a melee-attack pose instead of the rest T-pose.
    """
    ad = arm.animation_data
    names = []
    if ad is not None:
        if ad.action is not None:
            names.append(ad.action.name)
        ad.action = None
        for track in list(ad.nla_tracks):
            for strip in list(track.strips):
                track.strips.remove(strip)
            ad.nla_tracks.remove(track)
    for bone in arm.pose.bones:
        bone.matrix_basis.identity()
    return names


def purge_actions():
    removed = [a.name for a in list(bpy.data.actions)]
    for action in list(bpy.data.actions):
        bpy.data.actions.remove(action)
    return removed


def purge_orphans():
    """Remove orphaned datablocks (armatures left behind after object deletion, etc.).

    Deleting the armature OBJECT does not delete its ARMATURE datablock. Left in place it
    would be re-exported into the .blend and could resurrect an armature on import, which
    would break the "0 armature" contract of the Mixamo upload input.
    """
    removed = {"armatures": [], "actions": [], "meshes": [], "collections": []}
    for datablocks, key in ((bpy.data.armatures, "armatures"),
                            (bpy.data.actions, "actions"),
                            (bpy.data.meshes, "meshes")):
        for block in list(datablocks):
            if block.users == 0:
                removed[key].append(block.name)
                datablocks.remove(block)
    # The glTF importer leaves an empty 'glTF_not_exported' collection behind; drop it so
    # the saved .blend contains only the upload mesh and the preserved cape.
    for coll in list(bpy.data.collections):
        if coll.name != CAPE_COLLECTION and not coll.objects and not coll.children:
            removed["collections"].append(coll.name)
            bpy.data.collections.remove(coll)
    return removed


def evaluated_world_points(obj):
    dg = bpy.context.evaluated_depsgraph_get()
    ev = obj.evaluated_get(dg)
    me = ev.to_mesh()
    try:
        mw = obj.matrix_world
        return [mw @ v.co for v in me.vertices]
    finally:
        ev.to_mesh_clear()


def bounds_of(objs):
    pts = []
    for o in objs:
        pts.extend(evaluated_world_points(o))
    require(pts, "no vertices found while measuring bounds")
    xs = [p.x for p in pts]
    ys = [p.y for p in pts]
    zs = [p.z for p in pts]
    return (min(xs), max(xs)), (min(ys), max(ys)), (min(zs), max(zs))


def triangle_count(obj):
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def bone_rest_vector(arm, name):
    bone = arm.data.bones.get(name)
    require(bone is not None, "armature has no bone %r" % name)
    v = bone.tail_local - bone.head_local
    angle = math.degrees(math.atan2(abs(v.z), math.hypot(v.x, v.y)))
    return v, angle


def select_only(objs, active=None):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = active or (objs[0] if objs else None)


def look_at(obj, target):
    direction = (target - obj.location).normalized()
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def remove_object(obj):
    if obj is not None and obj.name in bpy.data.objects:
        bpy.data.objects.remove(obj, do_unlink=True)


# --------------------------------------------------------------------------------------
# Preconditions
# --------------------------------------------------------------------------------------
def verify_upstream(path):
    require(os.path.isfile(path), "input GLB not found: %s" % path)
    digest = sha256_file(path)
    require(
        digest == UPSTREAM_GLB_SHA256,
        "upstream GLB sha256 mismatch\n  expected %s\n  actual   %s\n"
        "  refusing to run: the pinned upstream file must stay byte-identical"
        % (UPSTREAM_GLB_SHA256, digest),
    )
    return digest


# --------------------------------------------------------------------------------------
# Stage 1: import + true rest pose
# --------------------------------------------------------------------------------------
def stage_import_and_rest_pose(glb_path):
    wipe_scene()
    imported = import_open(glb_path)
    log("imported objects: %d" % len(imported))

    armatures = [o for o in imported if o.type == "ARMATURE"]
    require(len(armatures) == 1, "expected exactly 1 armature, found %d" % len(armatures))
    arm = armatures[0]

    require(any(o.type == "MESH" for o in imported), "no meshes imported")

    ad = arm.animation_data
    nla_before = len(ad.nla_tracks) if ad else 0
    action_before = ad.action.name if ad and ad.action else None
    log("as-imported: active_action=%s nla_tracks=%d" % (action_before, nla_before))
    require(nla_before > 0, "expected importer to attach NLA tracks; upstream layout changed?")
    require(action_before is not None, "expected importer to attach an active action; upstream layout changed?")

    cleared = clear_animation(arm)
    purged = purge_actions()
    require(arm.animation_data is None or arm.animation_data.action is None, "active action survived clearing")
    require(arm.animation_data is None or len(arm.animation_data.nla_tracks) == 0, "NLA tracks survived clearing")
    require(len(bpy.data.actions) == 0, "actions survived purge: %s" % [a.name for a in bpy.data.actions])
    log("cleared active action(s): %s ; purged %d actions" % (cleared, len(purged)))

    bpy.context.view_layer.update()
    return arm, imported


def assert_rest_is_t_pose(arm):
    vec, angle = bone_rest_vector(arm, EXPECTED_ARM_NAME)
    _, hand_angle = bone_rest_vector(arm, EXPECTED_HAND_NAME)
    log("rest %s: %.3f deg from horizontal (len %.4f); %s: %.3f deg"
        % (EXPECTED_ARM_NAME, angle, vec.length, EXPECTED_HAND_NAME, hand_angle))
    require(angle <= T_POSE_ARM_TOL_DEG,
            "rest pose is NOT T-pose: %s is %.2f deg from horizontal (tol %.1f)"
            % (EXPECTED_ARM_NAME, angle, T_POSE_ARM_TOL_DEG))

    pb = arm.pose.bones.get(EXPECTED_ARM_NAME)
    require(pb is not None, "missing pose bone %s" % EXPECTED_ARM_NAME)
    delta = (pb.tail - pb.head) - vec
    require(delta.length < POSE_MATCH_TOL,
            "pose %s does not match its rest vector; pose was not cleared (delta=%.6f)"
            % (EXPECTED_ARM_NAME, delta.length))
    return angle


# --------------------------------------------------------------------------------------
# Stage 2: partition
# --------------------------------------------------------------------------------------
def partition_meshes(imported):
    by_name = {}
    for o in imported:
        if o.type == "MESH":
            by_name.setdefault(o.name, o)

    missing = [n for n in BODY_PARTS if n not in by_name]
    require(not missing, "body parts missing from upstream GLB: %s" % missing)

    body = [by_name[n] for n in BODY_PARTS]

    cape = [o for o in by_name.values() if o.name == CAPE_PART or o.name.lower().endswith("cape")]
    require(len(cape) == 1, "expected exactly 1 cape, got %d: %s" % (len(cape), [o.name for o in cape]))

    weapons = [by_name[n] for n in WEAPON_PARTS if n in by_name]
    require(len(weapons) == 5, "expected 5 weapon/prop parts, got %d: %s"
            % (len(weapons), [o.name for o in weapons]))

    leftovers = [o.name for o in by_name.values()
                 if o not in body and o not in cape and o not in weapons]
    log("body=%s" % [o.name for o in body])
    log("weapons=%s" % [o.name for o in weapons])
    log("cape=%s" % [o.name for o in cape])
    log("other mesh objects (importer extras, expected: Icosphere only): %s" % leftovers)

    body_tris = sum(triangle_count(o) for o in body)
    cape_tris = sum(triangle_count(o) for o in cape)
    weapon_tris = sum(triangle_count(o) for o in weapons)
    log("tris: body=%d cape=%d weapons=%d" % (body_tris, cape_tris, weapon_tris))
    require(body_tris == EXPECTED_UPLOAD_TRIS,
            "upload body tris %d != expected %d" % (body_tris, EXPECTED_UPLOAD_TRIS))
    require(cape_tris == EXPECTED_CAPE_TRIS, "cape tris %d != expected %d" % (cape_tris, EXPECTED_CAPE_TRIS))
    require(weapon_tris == EXPECTED_WEAPON_TRIS, "weapon tris %d != expected %d" % (weapon_tris, EXPECTED_WEAPON_TRIS))
    require(body_tris + cape_tris == EXPECTED_BODY_PLUS_CAPE_TRIS,
            "body+cape tris %d != ledger reading %d" % (body_tris + cape_tris, EXPECTED_BODY_PLUS_CAPE_TRIS))

    return body, weapons, cape, leftovers


def assert_body_uv_material(objs):
    for o in objs:
        require(len(o.data.uv_layers) >= 1, "%s has no UV layer" % o.name)
        require(len(o.material_slots) >= 1, "%s has no material slot" % o.name)
        for slot in o.material_slots:
            require(slot.material is not None, "%s has an empty material slot" % o.name)


# --------------------------------------------------------------------------------------
# Stage 3: cape preservation
# --------------------------------------------------------------------------------------
def preserve_cape(cape_obj, arm):
    """Park the cape in its own collection and record its intended re-bind bone.

    The cape is deliberately NOT part of the Mixamo upload mesh: a rigid chest-bound plane
    would interfere with marker placement and autoweighting. It stays in the source project
    so it can be rigidly bound to chest/spine once the Mixamo rig comes back.
    """
    bounds_before = bounds_of([cape_obj])
    coll = bpy.data.collections.get(CAPE_COLLECTION)
    if coll is None:
        coll = bpy.data.collections.new(CAPE_COLLECTION)
        bpy.context.scene.collection.children.link(coll)

    for c in list(cape_obj.users_collection):
        c.objects.unlink(cape_obj)
    coll.objects.link(cape_obj)

    cape_obj.name = "Rogue_Cape_PRESERVED"
    cape_obj.data.name = "Rogue_Cape_PRESERVED_mesh"

    # De-skin: record origin transform, drop armature deform, keep world placement.
    world = cape_obj.matrix_world.copy()
    for mod in list(cape_obj.modifiers):
        if mod.type == "ARMATURE":
            cape_obj.modifiers.remove(mod)
    cape_obj.parent = None
    cape_obj.matrix_world = world

    cape_obj["route_b_purpose"] = "cape preserved for rigid re-attachment after Mixamo rigging"
    cape_obj["route_b_rebind_bone"] = CAPE_REBIND_BONE
    cape_obj["route_b_rebind_mode"] = "bone parent / rigid (no skinning weights)"
    cape_obj["route_b_in_upload_mesh"] = False
    cape_obj["route_b_source"] = "KayKit Adventurers Rogue_Hooded @ 672074b"

    bounds_after = bounds_of([cape_obj])
    max_bounds_delta = max(
        abs(a - b)
        for before_axis, after_axis in zip(bounds_before, bounds_after)
        for a, b in zip(before_axis, after_axis)
    )
    require(max_bounds_delta <= 1e-6,
            "preserving cape changed its world-space bounds (max delta %.9f)" % max_bounds_delta)

    log("cape preserved -> %r in collection %r (intended re-bind bone: %s)"
        % (cape_obj.name, CAPE_COLLECTION, CAPE_REBIND_BONE))
    return cape_obj, {
        "x": list(bounds_after[0]),
        "y": list(bounds_after[1]),
        "z": list(bounds_after[2]),
        "max_preservation_delta": max_bounds_delta,
    }


# --------------------------------------------------------------------------------------
# Stage 4: flatten body -> single mesh
# --------------------------------------------------------------------------------------
def flatten_body(body, arm, imported, cape_obj, leftovers):
    arm_name = arm.name  # capture before removal: reading .name of a deleted datablock raises
    for o in body:
        for mod in list(o.modifiers):
            if mod.type == "ARMATURE":
                o.modifiers.remove(mod)
        o.vertex_groups.clear()

    for o in list(imported):
        if o in body or o is cape_obj:
            continue
        if o.type in {"ARMATURE", "MESH"}:
            bpy.data.objects.remove(o, do_unlink=True)

    require(arm_name not in bpy.data.objects, "armature object survived removal")
    require(len([o for o in bpy.data.objects if o.type == "ARMATURE"]) == 0, "armature still present")
    orphans = purge_orphans()
    log("purged orphan datablocks: %s" % orphans)
    require(len(bpy.data.armatures) == 0, "armature datablock survived purge")
    require(any("Icosphere" in n for n in leftovers), "expected an importer-made Icosphere to remove")
    require(not any("Icosphere" in o.name for o in bpy.data.objects), "Icosphere survived removal")

    remaining = [o for o in bpy.data.objects if o.type == "MESH"]
    require(len(remaining) == 7, "expected 6 body parts + 1 cape before join, got %d" % len(remaining))

    select_only(body, active=body[0])
    bpy.ops.object.join()
    merged = bpy.context.view_layer.objects.active
    require(merged is not None, "join produced no active object")

    world = merged.matrix_world.copy()
    merged.parent = None
    merged.matrix_world = world

    merged.name = "Rogue_Hooded_static"
    merged.data.name = "Rogue_Hooded_static_mesh"
    log("joined -> %r verts=%d tris=%d uv=%s mats=%s"
        % (merged.name, len(merged.data.vertices), triangle_count(merged),
           [l.name for l in merged.data.uv_layers],
           [s.material.name if s.material else None for s in merged.material_slots]))
    return merged


def assert_prepared_scene(merged, cape_obj):
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    require(len(meshes) == 2, "expected exactly 2 mesh objects (upload mesh + preserved cape), got %d" % len(meshes))
    require(merged in meshes and cape_obj in meshes, "unexpected mesh objects in scene")
    require(len([o for o in bpy.data.objects if o.type == "ARMATURE"]) == 0, "scene must have 0 armatures")
    require(len(bpy.data.armatures) == 0, "scene must have 0 armature datablocks")
    require(len(bpy.data.actions) == 0, "scene must have 0 actions")
    require(merged.parent is None, "upload mesh must not be parented")
    require(len(merged.data.uv_layers) >= 1, "upload mesh must have a UV layer")
    require(len(merged.material_slots) >= 1, "upload mesh must have a material slot")
    for slot in merged.material_slots:
        require(slot.material is not None, "upload mesh has an empty material slot")
    require(not merged.vertex_groups, "upload mesh must have no vertex groups after de-skinning")
    require(len(merged.modifiers) == 0, "upload mesh must have no modifiers")
    require(cape_obj.parent is None, "preserved cape must not be parented after de-skinning")


# --------------------------------------------------------------------------------------
# Stage 5: geometry assertions
# --------------------------------------------------------------------------------------
def assert_geometry(obj):
    (x0, x1), (y0, y1), (z0, z1) = bounds_of([obj])
    width, depth, height = x1 - x0, y1 - y0, z1 - z0
    log("bounds x=[%.4f,%.4f] y=[%.4f,%.4f] z=[%.4f,%.4f]" % (x0, x1, y0, y1, z0, z1))
    log("width=%.4f depth=%.4f height=%.4f" % (width, depth, height))

    require(abs(z0) <= GROUND_TOL, "feet not on ground: min z=%.5f (tol %.4f)" % (z0, GROUND_TOL))
    require(1.0 <= height <= 4.0, "implausible height %.3f m (expected humanoid at metre scale)" % height)
    require(0.5 <= width <= 4.0, "implausible width %.3f m; check unit scale" % width)
    require(depth > 0, "degenerate depth")
    require(abs(x0 + x1) / 2.0 <= CENTRE_TOL, "mesh not centred on x=0 (centre=%.4f)" % ((x0 + x1) / 2.0))

    return {"x": [x0, x1], "y": [y0, y1], "z": [z0, z1],
            "width": width, "depth": depth, "height": height}


def assert_facing_minus_y(obj):
    """The face must protrude towards -Y (character faces -Y, as Mixamo expects)."""
    pts = evaluated_world_points(obj)
    zs = [p.z for p in pts]
    z0, z1 = min(zs), max(zs)
    head_band = z0 + (z1 - z0) * 0.72
    head_pts = [p for p in pts if p.z >= head_band]
    require(head_pts, "no head-band vertices found for facing test")
    ys = sorted(p.y for p in head_pts)
    ymin, ymax = ys[0], ys[-1]
    half_depth = (ymax - ymin) / 2.0
    centre = (ymin + ymax) / 2.0
    front_extent = abs(ymin - centre)
    log("head band: y=[%.4f,%.4f] front_extent=%.4f" % (ymin, ymax, front_extent))
    require(front_extent > FACING_MIN_HALF * half_depth * 0 + FACING_MIN_HALF * 0.05,
            "head band too flat to determine facing (front extent %.4f)" % front_extent)
    # nose should sit clearly on the -Y side of the head-band centre
    require(ymin < centre, "character does not appear to face -Y")
    return {"head_ymin": ymin, "head_ymax": ymax, "head_centre_y": centre}


# --------------------------------------------------------------------------------------
# Stage 6: export
# --------------------------------------------------------------------------------------
def export_fbx(obj, out_path):
    select_only([obj])
    bpy.ops.export_scene.fbx(
        filepath=out_path,
        use_selection=True,
        global_scale=1.0,
        apply_unit_scale=True,
        apply_scale_options="FBX_SCALE_NONE",
        axis_forward="-Z",
        axis_up="Y",
        object_types={"MESH"},
        use_mesh_modifiers=True,
        use_triangles=True,
        use_tspace=False,
        bake_anim=False,
        add_leaf_bones=False,
        path_mode="COPY",
        embed_textures=True,
        mesh_smooth_type="FACE",
        use_metadata=False,
    )
    require(os.path.isfile(out_path), "FBX export reported success but no file at %s" % out_path)
    require(os.path.getsize(out_path) >= MIN_FBX_BYTES,
            "FBX suspiciously small: %d bytes" % os.path.getsize(out_path))
    return out_path


def bind_texture_filepath(out_png):
    """Point the packed GLB texture at a real file so the OBJ/MTL export can reference it.

    The texture arrives packed with no filepath; without this the exported .mtl has no
    map_Kd line and the Mixamo fallback upload would arrive untextured.
    """
    images = [i for i in bpy.data.images if i.size[0] > 0 and i.name != "Render Result"]
    require(images, "no embedded texture image available")
    img = images[0]
    img.filepath_raw = out_png
    img.file_format = "PNG"
    img.save()
    require(os.path.isfile(out_png), "texture PNG was not written to %s" % out_png)
    require(os.path.getsize(out_png) >= MIN_PNG_BYTES,
            "texture PNG suspiciously small: %d bytes" % os.path.getsize(out_png))
    log("texture written: %s %s" % (out_png, tuple(img.size)))
    return img


def export_obj(obj, out_obj):
    select_only([obj])
    bpy.ops.wm.obj_export(
        filepath=out_obj,
        export_selected_objects=True,
        apply_modifiers=True,
        export_uv=True,
        export_normals=True,
        export_materials=True,
        export_triangulated_mesh=True,
        path_mode="COPY",
        forward_axis="NEGATIVE_Z",
        up_axis="Y",
        global_scale=1.0,
    )
    require(os.path.isfile(out_obj), "OBJ export reported success but no file at %s" % out_obj)
    require(os.path.getsize(out_obj) >= MIN_OBJ_BYTES,
            "OBJ suspiciously small: %d bytes" % os.path.getsize(out_obj))
    sidecar = os.path.splitext(out_obj)[0] + ".mtl"
    require(os.path.isfile(sidecar), "OBJ export produced no .mtl next to %s" % out_obj)
    return out_obj, sidecar


def render_previews(out_dir, role, upload_obj, cape_obj):
    """Render TRUE T-pose previews of the exact upload mesh (cape hidden)."""
    cape_was = cape_obj.hide_render
    cape_obj.hide_render = True

    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "TEXTURE"
    scene.display.shading.show_shadows = True
    scene.render.resolution_x = 1024
    scene.render.resolution_y = 1024
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"

    (_, _), (_, _), (z0, z1) = bounds_of([upload_obj])
    centre_z = (z0 + z1) / 2.0
    height = z1 - z0
    radius = height * 2.2

    cam_data = bpy.data.cameras.new("PreviewCam")
    cam = bpy.data.objects.new("PreviewCam", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    cam_data.lens = 60.0

    target = Vector((0.0, 0.0, centre_z))
    written = {}
    try:
        for label, az in (("front", 0.0), ("3q", math.radians(35.0))):
            cam.location = Vector((radius * math.sin(az),
                                   -radius * math.cos(az),
                                   centre_z + height * 0.06))
            look_at(cam, target)
            path = os.path.join(out_dir, "%s_tpose_%s.png" % (role, label))
            scene.render.filepath = path
            bpy.ops.render.render(write_still=True)
            require(os.path.isfile(path), "preview render produced no file: %s" % path)
            require(os.path.getsize(path) >= MIN_PNG_BYTES,
                    "preview %s suspiciously small (%d bytes)" % (path, os.path.getsize(path)))
            written[label] = path
            log("rendered %s preview: %s" % (label, path))
    finally:
        remove_object(cam)
        cape_obj.hide_render = cape_was
    return written


def save_blend(out_dir, role):
    path = os.path.join(out_dir, "%s_route_b_source.blend" % role)
    # Blender would otherwise write a versioned <name>.blend1 backup on re-run, which is
    # not a deliverable and would make repeated runs differ.
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=path)
    require(os.path.isfile(path), "blend save produced no file at %s" % path)
    backup = path + "1"
    if os.path.isfile(backup):
        os.remove(backup)
        log("removed stale blend backup: %s" % backup)
    require(not os.path.isfile(backup), "versioned blend backup still present: %s" % backup)
    log("source project saved: %s" % path)
    return path


# --------------------------------------------------------------------------------------
# Stage 7: independent re-import verification
# --------------------------------------------------------------------------------------
def inspect_reimported(label):
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    arms = [o for o in bpy.data.objects if o.type == "ARMATURE"]
    anims = list(bpy.data.actions)
    nla = sum(len(a.animation_data.nla_tracks) for a in arms if a.animation_data)

    log("%s re-import: objects=%d meshes=%d armatures=%d actions=%d nla=%d"
        % (label, len(bpy.data.objects), len(meshes), len(arms), len(anims), nla))
    require(len(meshes) == 1, "%s: expected exactly 1 mesh, got %d" % (label, len(meshes)))
    require(len(arms) == 0, "%s: expected 0 armatures, got %d" % (label, len(arms)))
    require(len(anims) == 0, "%s: expected 0 actions, got %d %s"
            % (label, len(anims), [a.name for a in anims]))
    require(nla == 0, "%s: expected 0 NLA tracks" % label)

    obj = meshes[0]
    require(len(obj.data.uv_layers) >= 1, "%s: mesh lost its UV layer" % label)
    require(len(obj.material_slots) >= 1, "%s: mesh lost its material slot" % label)
    mats = [s.material for s in obj.material_slots if s.material]
    require(mats, "%s: mesh has no material datablock" % label)

    pts = evaluated_world_points(obj)
    zs = [p.z for p in pts]
    xs = [p.x for p in pts]
    ys = [p.y for p in pts]
    height = max(zs) - min(zs)
    tris = sum(len(p.vertices) - 2 for p in obj.data.polygons)

    log("%s re-import: verts=%d tris=%d z=[%.4f,%.4f] x=[%.4f,%.4f] y=[%.4f,%.4f] height=%.4f uv=%s mats=%s"
        % (label, len(obj.data.vertices), tris, min(zs), max(zs), min(xs), max(xs),
           min(ys), max(ys), height, [l.name for l in obj.data.uv_layers], [m.name for m in mats]))

    require(abs(min(zs)) <= 0.05, "%s: feet not near z=0 (min z=%.5f)" % (label, min(zs)))
    require(1.0 <= height <= 4.0, "%s: implausible height %.3f m" % (label, height))
    require(tris == EXPECTED_UPLOAD_TRIS, "%s: tri count %d != %d" % (label, tris, EXPECTED_UPLOAD_TRIS))

    return {"meshes": len(meshes), "armatures": len(arms), "actions": len(anims),
            "verts": len(obj.data.vertices), "tris": tris,
            "bounds_z": [min(zs), max(zs)], "height": height,
            "uv_layers": len(obj.data.uv_layers), "materials": len(mats)}


def verify_fbx_by_reimport(path):
    wipe_scene()
    bpy.ops.import_scene.fbx(filepath=path)
    return inspect_reimported("FBX")


def verify_obj_by_reimport(path):
    wipe_scene()
    bpy.ops.wm.obj_import(filepath=path)
    return inspect_reimported("OBJ")


# --------------------------------------------------------------------------------------
# Manifest
# --------------------------------------------------------------------------------------
def build_manifest(args, upstream_sha, info, outputs, reimport):
    entries = {}
    for key, path in outputs.items():
        if os.path.isfile(path):
            entries[key] = {"path": rel(path), "bytes": os.path.getsize(path),
                            "sha256": sha256_file(path)}
    return {
        "stage": "route_b_prepare",
        "role": info["role"],
        "stopped_before": "Mixamo upload and manual marker placement (NOT performed here)",
        "blender_version": bpy.app.version_string,
        "script": rel(os.path.abspath(__file__)),
        "command": info["command"],
        "invocation": {
            "role": args.role,
            "skip_previews": args.skip_previews,
        },
        "input": {"path": rel(args.input), "bytes": os.path.getsize(args.input), "sha256": upstream_sha},
        "outputs": entries,
        "mesh": info["mesh"],
        "cape": info["cape"],
        "assertions": info["assertions"],
        "reimport": reimport,
        "manual_markers": [
            {"id": "chin", "label": "chin", "risk": "medium",
             "note": "Hood frames the face; confirm the marker lands on the chin, not the hood rim."},
            {"id": "wrist_l", "label": "left wrist", "risk": "low", "note": "Bracer is exposed."},
            {"id": "wrist_r", "label": "right wrist", "risk": "low", "note": "Bracer is exposed."},
            {"id": "groin", "label": "groin", "risk": "high",
             "note": "Coat hem overlaps the leg tops; find the real gap between the legs, "
                     "not the front-centre of the hem."},
            {"id": "ankle_l", "label": "left ankle", "risk": "low",
             "note": "Must sit BELOW the boot cuff."},
            {"id": "ankle_r", "label": "right ankle", "risk": "low",
             "note": "Must sit BELOW the boot cuff."},
        ],
        "notes": [
            "Cape is NOT part of the upload mesh. It is preserved in the .blend "
            "(collection 'cape_preserved') and must be rigidly re-bound after rigging.",
            "No finger bones upstream; hands are single-bone. Expect no finger animation.",
            "The .blend contains exactly 2 objects: the upload mesh + the preserved cape.",
        ],
    }


# --------------------------------------------------------------------------------------
# Main
# --------------------------------------------------------------------------------------
def parse_args(argv):
    default_input = os.path.join("docs", "art", "kaykit_route_ab", "upstream",
                                 "kaykit-adventurers-1.0-672074b", "Rogue_Hooded.glb")
    default_out = os.path.join("docs", "art", "kaykit_route_ab", "route_b")
    p = argparse.ArgumentParser(
        description="Prepare a clean static single-mesh T-pose Mixamo input from the "
                    "KayKit Rogue_Hooded GLB. Stops before upload/marker placement.")
    p.add_argument("--input", default=default_input,
                   help="upstream Rogue_Hooded.glb, opened read-only (default: %(default)s)")
    p.add_argument("--output-dir", default=default_out,
                   help="directory for all generated artifacts (default: %(default)s)")
    p.add_argument("--role", default="rogue_hooded", help="role slug for output filenames")
    p.add_argument("--skip-previews", action="store_true", help="skip T-pose preview renders")
    args, _unknown = p.parse_known_args(argv)
    return args


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    args = parse_args(argv)
    require(args.role == "rogue_hooded",
            "--role is fixed to 'rogue_hooded': geometry assertions and marker notes "
            "are specific to the pinned Rogue_Hooded source")

    input_path = os.path.abspath(args.input)
    out_dir = os.path.abspath(args.output_dir)
    os.makedirs(out_dir, exist_ok=True)

    log("Blender %s" % bpy.app.version_string)
    log("input  = %s" % input_path)
    log("output = %s" % out_dir)

    upstream_sha = verify_upstream(input_path)

    arm, imported = stage_import_and_rest_pose(input_path)
    arm_angle = assert_rest_is_t_pose(arm)

    body, weapons, cape, leftovers = partition_meshes(imported)
    assert_body_uv_material(body + cape)
    # Capture names now: these objects are deleted during flatten_body(), and reading
    # .name from a removed datablock raises StructRNA-removed.
    weapon_names = [o.name for o in weapons]

    cape_obj, cape_bounds = preserve_cape(cape[0], arm)
    merged = flatten_body(body, arm, imported, cape_obj, leftovers)
    assert_prepared_scene(merged, cape_obj)

    dims = assert_geometry(merged)
    facing = assert_facing_minus_y(merged)

    role = args.role
    fbx_path = os.path.join(out_dir, "%s_static.fbx" % role)
    obj_path = os.path.join(out_dir, "%s_static.obj" % role)
    png_path = os.path.join(out_dir, "%s_static_texture.png" % role)

    export_fbx(merged, fbx_path)
    # Write (and bind) the texture BEFORE the OBJ export, so the .mtl gets a map_Kd line.
    bind_texture_filepath(png_path)
    export_obj(merged, obj_path)

    previews = {} if args.skip_previews else render_previews(out_dir, role, merged, cape_obj)
    blend_path = save_blend(out_dir, role)

    outputs = {
        "fbx": fbx_path,
        "obj": obj_path,
        "mtl": os.path.splitext(obj_path)[0] + ".mtl",
        "texture_png": png_path,
        "blend": blend_path,
    }
    outputs.update({("preview_" + k): v for k, v in previews.items()})

    # Capture every mesh/cape fact BEFORE re-import verification wipes the scene:
    # holding a bpy Object reference across wipe_scene() raises StructRNA-removed.
    mesh_name = merged.name
    mesh_verts = len(merged.data.vertices)
    mesh_tris = triangle_count(merged)
    mesh_uvs = [l.name for l in merged.data.uv_layers]
    mesh_mats = [s.material.name if s.material else None for s in merged.material_slots]
    cape_name = cape_obj.name
    cape_tris = triangle_count(cape_obj)
    # Read the INTENDED re-bind bone from the constant: de-skinning clears parent_bone,
    # so reading it off the object here would record an empty string.
    cape_bone = cape_obj.get("route_b_rebind_bone", CAPE_REBIND_BONE)

    reimport = {
        "fbx": verify_fbx_by_reimport(fbx_path),
        "obj": verify_obj_by_reimport(obj_path),
    }

    info = {
        "role": role,
        "command": "blender --background --factory-startup --python "
                   "mcp/mixamo/kaykit_route_b_prepare.py -- --input %s --output-dir %s%s"
                   % (rel(input_path), rel(out_dir), " --skip-previews" if args.skip_previews else ""),
        "mesh": {
            "name": mesh_name,
            "verts": mesh_verts,
            "tris": mesh_tris,
            "uv_layers": mesh_uvs,
            "materials": mesh_mats,
            "bounds": dims,
            "facing": facing,
            "feet_min_z": dims["z"][0],
        },
        "cape": {
            "preserved_as": cape_name,
            "collection": CAPE_COLLECTION,
            "rebind_bone": cape_bone,
            "rebind_bone_note": "Upstream KayKit bone name; map manually to the equivalent Mixamo chest/spine bone.",
            "rebind_mode": "bone parent / rigid (no skinning weights)",
            "tris": cape_tris,
            "bounds": cape_bounds,
            "in_upload_mesh": False,
        },
        "assertions": {
            "rest_arm_angle_deg": arm_angle,
            "rest_is_t_pose": True,
            "armature_removed": True,
            "actions_purged": True,
            "icosphere_removed": True,
            "weapons_removed": weapon_names,
            "weapon_tris_removed": EXPECTED_WEAPON_TRIS,
            "uv_present": True,
            "material_present": True,
            "feet_on_ground": abs(dims["z"][0]) <= GROUND_TOL,
            "height_m": dims["height"],
        },
    }

    manifest = build_manifest(args, upstream_sha, info, outputs, reimport)
    manifest["previews"] = {k: rel(v) for k, v in previews.items()}
    manifest_path = os.path.join(out_dir, "prepare_manifest.json")
    with open(manifest_path, "w", encoding="utf-8") as fh:
        json.dump(manifest, fh, ensure_ascii=False, indent=2)
        fh.write("\n")

    log("manifest: %s" % manifest_path)
    for key, entry in manifest["outputs"].items():
        log("  %-12s %10d bytes  %s  %s" % (key, entry["bytes"], entry["sha256"][:16], entry["path"]))

    log("ROUTE_B_PREPARE_OK")
    log("STOPPED BEFORE: Mixamo upload / manual marker placement (not performed by this script)")


if __name__ == "__main__":
    try:
        main()
    except Fail as exc:
        log("ROUTE_B_PREPARE_FAILED: %s" % exc)
        raise
