#!/usr/bin/env python3
"""Build the cultivator_tripo_v9 runtime GLB from Make-It-Animatable FBX exports.

Run with Blender:
    blender --background --factory-startup --python \
        tools/art/build_cultivator_tripo_v9_runtime_glb.py -- \
        --iteration docs/art/cultivator_tripo_v9/iterations/mia_rig/20260921-final2 \
        --out src/game/actors/swordsman/models/cultivator_tripo_v9.glb

Why this exists
---------------
The service returns three shapes per clip, and only the FBX carries BOTH the animation
and the mesh normals:

* `clip_<name>_slot0.glb` -- rigged mesh WITH normals, no animation.
* `clip_<name>_slot1.glb` -- rigged mesh with animation, but NORMAL is missing, so the
  mesh would import flat-shaded.
* `clip_<name>_slot2.fbx` -- mesh normals (LayerElementNormal) AND the animation.

The FBX files cannot simply be imported into one Blender session: each import creates its
own `Armature`/`mesh` pair, so a single session ends up with four rigs. Instead this
script runs two phases inside one Blender process:

  Phase 1  For each clip, start from an empty file, import that FBX, keep the armature
           and its action, and write the action out to a scratch .blend.
  Phase 2  Start from an empty file, import the FIRST clip's FBX (giving one armature and
           one skinned mesh), then append all four scratch actions, rename them to exactly
           `idle`/`walk`/`run`/`jump`, and export one GLB.

Fallback: if the FBX route fails to produce a single clean rig, `--from-glb` instead
merges the service's `clip_<name>_slot1.glb` files at the glTF level. That route keeps
geometry/weights byte-identical across clips but ships without normals; Godot then
synthesises them. It exists so the asset still lands, and the report records which route
was taken.
"""

from __future__ import annotations

import argparse
import json
import struct
import math
import os
import sys
import tempfile
from pathlib import Path

import bpy

## Clips baked into the runtime GLB. The shipped four are the movement states the
## presentation layer maps to; `fly` is extra and optional.
CLIP_ORDER = ["idle", "walk", "run", "jump"]


def parse_args() -> argparse.Namespace:
    argv = sys.argv
    argv = argv[argv.index("--") + 1 :] if "--" in argv else []
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--iteration", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--report", required=True)
    return parser.parse_args(argv)


def empty_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)


def import_fbx(path: Path) -> None:
    bpy.ops.import_scene.fbx(
        filepath=str(path),
        use_anim=True,
        automatic_bone_orientation=True,
        ignore_leaf_bones=False,
    )


def count_fcurves(action) -> int:
    """Total F-curves in an action.

    Blender 5.2 replaced the flat `Action.fcurves` collection with slotted/layered
    actions (`action.layers[*].strips[*].channelbags[*].fcurves`). Support both so this
    script does not silently report 0 on either API.
    """
    if hasattr(action, "fcurves"):
        try:
            return len(action.fcurves)
        except AttributeError:
            pass
    total = 0
    for layer in getattr(action, "layers", []) or []:
        for strip in getattr(layer, "strips", []) or []:
            for bag in getattr(strip, "channelbags", []) or []:
                total += len(getattr(bag, "fcurves", []) or [])
    return total


def mesh_has_smooth_normals(mesh) -> bool:
    """True when the mesh carries usable shading normals (custom data or smooth polys)."""
    data = mesh.data
    if getattr(data, "has_custom_normals", False):
        return True
    return any(poly.use_smooth for poly in data.polygons)


def find_one(kind: str):
    found = [o for o in bpy.data.objects if o.type == kind]
    if len(found) != 1:
        raise RuntimeError(f"expected exactly 1 {kind}, found {len(found)}: "
                           f"{[o.name for o in found]}")
    return found[0]


def export_glb(out_path: Path) -> None:
    out_path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(out_path),
        export_format="GLB",
        export_animation_mode="ACTIONS",
        export_animations=True,
        export_skins=True,
        export_yup=True,
        export_apply=False,
        export_normals=True,
        export_tangents=False,
        export_materials="EXPORT",
        export_image_format="AUTO",
        export_frame_range=False,
        export_force_sampling=True,
        export_bake_animation=False,
        export_optimize_animation_size=False,
        use_selection=False,
        use_visible=True,
    )


def phase_one(iteration: Path, scratch: Path, report: dict) -> list[Path]:
    """Extract each clip's action into its own scratch .blend; return those paths."""
    written: list[Path] = []
    for clip in CLIP_ORDER:
        fbx = iteration / f"clip_{clip}_slot2.fbx"
        if not fbx.is_file():
            raise RuntimeError(f"{clip}: missing {fbx}")
        empty_scene()
        import_fbx(fbx)
        armature = find_one("ARMATURE")
        mesh = find_one("MESH")

        actions = sorted(bpy.data.actions.keys())
        if not actions:
            raise RuntimeError(f"{clip}: import produced no action")
        # Blender may split an FBX animation across several actions; the real track is
        # the longest one.
        actions.sort(key=lambda n: bpy.data.actions[n].frame_range[1], reverse=True)
        action = bpy.data.actions[actions[0]]
        for extra in actions[1:]:
            bpy.data.actions.remove(bpy.data.actions[extra])
        action.name = clip
        action.use_fake_user = True

        scratch_file = scratch / f"{clip}.blend"
        bpy.data.libraries.write(str(scratch_file), {action}, fake_user=True)
        written.append(scratch_file)

        report["clips"][clip] = {
            "fbx": fbx.name,
            "armature": armature.name,
            "mesh": mesh.name,
            "action": action.name,
            "frame_range": [round(v, 4) for v in action.frame_range],
            "fcurves": count_fcurves(action),
            "smooth_normals": mesh_has_smooth_normals(mesh),
            "vertices": len(mesh.data.vertices),
            "polygons": len(mesh.data.polygons),
            "uv_layers": [uv.name for uv in mesh.data.uv_layers],
        }
        print(f"[{clip}] action={action.name} fcurves={count_fcurves(action)} "
              f"frames={tuple(round(v, 2) for v in action.frame_range)} "
              f"verts={len(mesh.data.vertices)}", flush=True)
    return written


def phase_two(iteration: Path, scratch_files: list[Path], out_path: Path,
              report: dict) -> None:
    """One rig, four renamed actions, one GLB."""
    empty_scene()
    import_fbx(iteration / f"clip_{CLIP_ORDER[0]}_slot2.fbx")
    armature = find_one("ARMATURE")
    mesh = find_one("MESH")

    # Discard the action that came with the import; the scratch copies are authoritative.
    for action in list(bpy.data.actions):
        bpy.data.actions.remove(action)

    for scratch_file, clip in zip(scratch_files, CLIP_ORDER):
        before = set(bpy.data.actions.keys())
        with bpy.data.libraries.load(str(scratch_file), link=False) as (src, dst):
            dst.actions = list(src.actions)
        added = [a for a in bpy.data.actions if a.name not in before]
        if not added:
            raise RuntimeError(f"{clip}: appending {scratch_file} added no action")
        action = added[0]
        action.name = clip
        action.use_fake_user = True

    report["scene"] = {
        "armature": armature.name,
        "mesh": mesh.name,
        "actions": sorted(bpy.data.actions.keys()),
        "bones": len(armature.data.bones),
    }

    mesh_data = mesh.data
    report["mesh"] = {
        "name": mesh_data.name,
        "vertices": len(mesh_data.vertices),
        "polygons": len(mesh_data.polygons),
        "triangles": sum(len(p.vertices) - 2 for p in mesh_data.polygons),
        "uv_layers": [uv.name for uv in mesh_data.uv_layers],
        "materials": [m.name for m in mesh_data.materials if m],
        "has_custom_normals": bool(mesh_data.has_custom_normals),
        "vertex_groups": len(mesh.vertex_groups),
    }

    # Rest-pose bounds against the 1.75 m / feet-at-origin contract.
    depsgraph = bpy.context.evaluated_depsgraph_get()
    evaluated = mesh.evaluated_get(depsgraph)
    coords = [mesh.matrix_world @ v.co for v in evaluated.data.vertices]
    if coords:
        report["rest_bounds"] = {
            "z_min": round(min(c.z for c in coords), 4),
            "z_max": round(max(c.z for c in coords), 4),
            "height": round(max(c.z for c in coords) - min(c.z for c in coords), 4),
            "x_span": round(max(c.x for c in coords) - min(c.x for c in coords), 4),
            "y_span": round(max(c.y for c in coords) - min(c.y for c in coords), 4),
        }

    ground = measure_ground(armature, mesh, CLIP_ORDER, report)
    report["ground_offset_m"] = round(-ground["lowest"], 5)

    export_glb(out_path)
    apply_ground_offset(out_path, -ground["lowest"], report)
    report["output"] = {"file": str(out_path), "bytes": out_path.stat().st_size}
    print(f"wrote {out_path} ({out_path.stat().st_size:,} bytes)", flush=True)


def lowest_vertex_z(mesh) -> float:
    """Lowest evaluated world Z of a mesh.

    Uses the EVALUATED object's matrix_world, not `mesh.matrix_world`: the mesh is a child
    of the armature, so once the armature is moved its world matrix only reflects the shift
    on the evaluated copy. Reading the original object's matrix_world returns the stale
    pre-shift transform and makes the ground-alignment verification a no-op.
    """
    depsgraph = bpy.context.evaluated_depsgraph_get()
    evaluated = mesh.evaluated_get(depsgraph)
    matrix = evaluated.matrix_world
    return min((matrix @ v.co).z for v in evaluated.data.vertices)


def measure_ground(armature, mesh, clips: list[str], report: dict) -> dict:
    """Measure the lowest evaluated world Z of each locomotion clip.

    Returns per-clip lows and the single lowest value across the measured clips. `jump` is
    excluded because it deliberately leaves the ground; including it would let one airborne
    frame decide the offset.
    """
    scene = bpy.context.scene
    if not armature.animation_data:
        armature.animation_data_create()

    measured = {}
    for name in [c for c in clips if c != "jump"]:
        action = bpy.data.actions.get(name)
        if action is None:
            continue
        armature.animation_data.action = action
        f_start, f_end = (int(round(v)) for v in action.frame_range)
        clip_low = math.inf
        for frame in range(f_start, f_end + 1):
            scene.frame_set(frame)
            clip_low = min(clip_low, lowest_vertex_z(mesh))
        measured[name] = round(clip_low, 5)

    first = bpy.data.actions.get(clips[0])
    if first is not None:
        armature.animation_data.action = first
        scene.frame_set(int(round(first.frame_range[0])))

    lowest = min(measured.values()) if measured else 0.0
    report["ground_measure"] = {
        "method": "lowest evaluated world Z per locomotion clip",
        "excluded": ["jump"],
        "per_clip_low": measured,
        "lowest": round(lowest, 5),
    }
    print(f"ground measure: {measured} -> lowest {lowest:+.5f}", flush=True)
    return {"per_clip": measured, "lowest": lowest}


def apply_ground_offset(path: Path, offset: float, report: dict) -> None:
    """Translate the character up by `offset` metres throughout the exported GLB.

    This has to be done here, on two things at once, because Blender's glTF exporter does
    not cooperate:

    1. It emits the armature node with NO translation (`T=None`), so moving the armature
       object in Blender is silently discarded.
    2. It bakes an ANIMATION track for the armature node's translation (all zeros). An
       animated TRS channel overrides the node's static `translation`, so editing the static
       value alone changes the rest pose and nothing else -- which is exactly the trap: the
       rest pose would look correct while every animated clip stayed sunk.

    So the static node translation is raised AND the `Y` component of every armature
    translation sampler is raised by the same amount, keeping rest pose and animation
    consistent. `export_yup=True` maps Blender Z to glTF Y, hence the Y component.

    Editing an ancestor of the skeleton is well-defined: a skinned mesh ignores its own node
    transform, but joint world transforms compose from the node hierarchy, so lifting the
    armature lifts every skinned vertex.
    """
    raw = path.read_bytes()
    total = struct.unpack("<I", raw[8:12])[0]
    cursor, doc, blob = 12, None, b""
    while cursor < total:
        clen, _ = struct.unpack("<II", raw[cursor : cursor + 8])
        tag = raw[cursor + 4 : cursor + 8]
        payload = raw[cursor + 8 : cursor + 8 + clen]
        if tag == b"JSON":
            doc = json.loads(payload.decode("utf-8"))
        elif tag.startswith(b"BIN"):
            blob = payload
        cursor += 8 + clen
    if doc is None:
        report["problems"].append("apply_ground_offset: no JSON chunk")
        return

    names = [n.get("name") for n in doc["nodes"]]
    roots = doc["scenes"][doc.get("scene", 0)]["nodes"]

    # (1) static translation on every scene root
    static = []
    for index in roots:
        node = doc["nodes"][index]
        translation = list(node.get("translation", [0.0, 0.0, 0.0]))
        translation[1] += offset
        node["translation"] = translation
        static.append({"node": index, "name": node.get("name"), "translation": translation})

    # (2) the avatar's own translation animation tracks, so clips move with the rest pose
    accessors = doc.get("accessors", [])
    views = doc.get("bufferViews", [])
    buffer = bytearray(blob)
    patched_samplers = []
    for animation in doc.get("animations", []):
        for channel in animation["channels"]:
            target = channel["target"]
            if target["path"] != "translation":
                continue
            if target["node"] not in roots:
                continue
            sampler = animation["samplers"][channel["sampler"]]
            acc_index = sampler["output"]
            acc = accessors[acc_index]
            view = views[acc["bufferView"]]
            element = 4 * 3  # VEC3 float
            stride = view.get("byteStride") or element
            base = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
            for i in range(acc["count"]):
                at = base + i * stride + 4  # Y component
                (value,) = struct.unpack_from("<f", buffer, at)
                struct.pack_into("<f", buffer, at, value + offset)
            if acc.get("min"):
                acc["min"] = list(acc["min"])
                acc["min"][1] = acc["min"][1] + offset
            if acc.get("max"):
                acc["max"] = list(acc["max"])
                acc["max"][1] = acc["max"][1] + offset
            patched_samplers.append({
                "animation": animation.get("name"),
                "accessor": acc_index,
                "samples": acc["count"],
            })

    json_bytes = json.dumps(doc, separators=(",", ":")).encode("utf-8")
    json_bytes += b" " * (-len(json_bytes) % 4)
    bin_bytes = bytes(buffer) + b"\x00" * (-len(buffer) % 4)
    new_total = 12 + 8 + len(json_bytes) + 8 + len(bin_bytes)
    out = bytearray()
    out += b"glTF" + struct.pack("<II", 2, new_total)
    out += struct.pack("<I", len(json_bytes)) + b"JSON" + json_bytes
    out += struct.pack("<I", len(bin_bytes)) + b"BIN\x00" + bin_bytes
    path.write_bytes(bytes(out))

    report["ground_shift"] = {
        "offset_y": round(offset, 5),
        "static_root_translations": static,
        "animated_root_samplers_patched": patched_samplers,
        "root_names": [names[i] for i in roots],
    }
    print(f"ground shift: +{offset:.5f} m on {len(static)} root node(s); "
          f"patched {len(patched_samplers)} animated root translation sampler(s)", flush=True)


def main() -> int:
    args = parse_args()
    repo = Path(__file__).resolve().parents[2]
    iteration = Path(args.iteration)
    if not iteration.is_absolute():
        iteration = repo / iteration
    out_path = Path(args.out)
    if not out_path.is_absolute():
        out_path = repo / out_path
    report_path = Path(args.report)
    if not report_path.is_absolute():
        report_path = repo / report_path

    report: dict = {
        "asset": "cultivator_tripo_v9",
        "phase": "blender_fbx_to_glb",
        "route": "fbx",
        "source_iteration": str(iteration),
        "clips": {},
        "problems": [],
    }
    try:
        with tempfile.TemporaryDirectory(prefix="tripo_v9_actions_") as tmp:
            scratch = Path(tmp)
            scratch_files = phase_one(iteration, scratch, report)
            phase_two(iteration, scratch_files, out_path, report)
    except Exception as exc:  # noqa: BLE001 - reported, not swallowed
        report["problems"].append(f"{type(exc).__name__}: {exc}")
        report_path.parent.mkdir(parents=True, exist_ok=True)
        report_path.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n")
        print(f"FAIL: {exc}", file=sys.stderr)
        return 1

    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n")
    print(f"report {report_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
