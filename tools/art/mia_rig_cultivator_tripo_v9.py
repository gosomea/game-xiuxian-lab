#!/usr/bin/env python3
"""Drive the local Make-It-Animatable Gradio service to auto-rig cultivator_tripo_v9.

Why this exists
---------------
Mixamo Auto-Rigger could not finish processing an upload for this character (three
formats, three sizes, all stuck on "Your character is processing"). The locally
deployed Make-It-Animatable service replaces that route. It accepts `.glb`, so the
full-quality 599,417-triangle clean mesh is rigged directly -- no low-poly proxy and
no weight-transfer step.

Contract
--------
* Input : docs/art/cultivator_tripo_v9/exports/cultivator_tripo_v9_clean.glb
          (single mesh, UVs, metre scale, feet at Blender z=0, front -Y)
* Output: docs/art/cultivator_tripo_v9/iterations/mia_rig/<stamp>/
          - <prefix>_slotN.glb / .fbx   (every file the service returns)
          - mia_run_manifest.json       (params, bytes, sha256, GLB structure probe)

The service is stateful per client session: `/pipeline` performs the rig AND the
first animation, then `/vis_blender` re-uses that session's rig for further clips.
Both calls must therefore share one Client instance, and every clip for one final
asset must come from ONE run so all clips share the same skin weights.

Usage
-----
    python3 tools/art/mia_rig_cultivator_tripo_v9.py --base-url http://127.0.0.1:7860/
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import struct
import sys
import time
from datetime import datetime
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
ASSET_DIR = REPO / "docs" / "art" / "cultivator_tripo_v9"
INPUT_GLB = ASSET_DIR / "exports" / "cultivator_tripo_v9_clean.glb"
OUT_ROOT = ASSET_DIR / "iterations" / "mia_rig"

# Make-It-Animatable's own bundled Mixamo library; exact dropdown values.
CLIPS = [
    ("idle", "Idle.fbx"),
    ("walk", "Walking.fbx"),
    ("run", "Running.fbx"),
    ("jump", "Jump.fbx"),
]


def sanitize_proxy_env() -> None:
    """The host exports NO_PROXY with a bracketed IPv6 literal httpx cannot parse."""
    for key in ("NO_PROXY", "no_proxy"):
        value = os.environ.get(key, "")
        if "[" in value or "]" in value:
            os.environ[key] = ",".join(
                part for part in value.split(",") if "[" not in part and "]" not in part
            )
    for key in ("NO_PROXY", "no_proxy"):
        parts = [p for p in os.environ.get(key, "").split(",") if p]
        for host in ("127.0.0.1", "localhost"):
            if host not in parts:
                parts.append(host)
        os.environ[key] = ",".join(parts)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def as_path(value):
    """Gradio returns either a str path or a FileData-ish object."""
    if value is None:
        return None
    if isinstance(value, str):
        return Path(value) if "/" in value or value.endswith((".glb", ".fbx", ".blend")) else None
    for attr in ("path", "name"):
        found = getattr(value, attr, None)
        if isinstance(found, str):
            return Path(found)
    if isinstance(value, dict) and isinstance(value.get("path"), str):
        return Path(value["path"])
    return None


def probe_glb(path: Path) -> dict:
    """Read a GLB's JSON chunk to record what the service actually produced."""
    try:
        raw = path.read_bytes()
    except OSError as exc:
        return {"probe_error": str(exc)}
    if raw[:4] != b"glTF":
        return {"probe_error": f"not glTF (magic={raw[:4]!r})"}
    total = struct.unpack("<I", raw[8:12])[0]
    offset, doc = 12, None
    while offset < total:
        clen, _ctype = struct.unpack("<II", raw[offset : offset + 8])
        tag = raw[offset + 4 : offset + 8]
        if tag == b"JSON":
            doc = json.loads(raw[offset + 8 : offset + 8 + clen].decode("utf-8"))
            break
        offset += 8 + clen
    if doc is None:
        return {"probe_error": "no JSON chunk"}
    tris = 0
    for mesh in doc.get("meshes", []):
        for prim in mesh.get("primitives", []):
            if "indices" in prim:
                tris += doc["accessors"][prim["indices"]]["count"] // 3
    animations = []
    for anim in doc.get("animations", []):
        span = None
        for sampler in anim.get("samplers", []):
            acc = doc["accessors"][sampler["input"]]
            if acc.get("max"):
                span = round(float(acc["max"][0]), 3)
                break
        animations.append(
            {"name": anim.get("name"), "channels": len(anim.get("channels", [])), "seconds": span}
        )
    return {
        "meshes": len(doc.get("meshes", [])),
        "triangles": tris,
        "nodes": len(doc.get("nodes", [])),
        "images": len(doc.get("images", [])),
        "materials": len(doc.get("materials", [])),
        "skins": [
            {"name": s.get("name"), "joints": len(s.get("joints", []))}
            for s in doc.get("skins", [])
        ],
        "animations": animations,
    }


def dump_slots(result, dest: Path, manifest: list, prefix: str) -> None:
    """Persist every file-ish slot of one Gradio call; record the rest honestly."""
    if not isinstance(result, (list, tuple)):
        result = [result]
    for slot, value in enumerate(result):
        label = f"{prefix}_slot{slot}"
        src = as_path(value)
        if src is None or not src.is_file():
            manifest.append(
                {
                    "label": label,
                    "status": "non_file",
                    "value_type": type(value).__name__,
                    "value_repr": repr(value)[:300],
                }
            )
            continue
        target = dest / f"{label}{src.suffix or '.bin'}"
        shutil.copy2(src, target)
        entry = {
            "label": label,
            "status": "ok",
            "file": target.name,
            "bytes": target.stat().st_size,
            "sha256": sha256(target),
        }
        if target.suffix.lower() == ".glb":
            entry["glb"] = probe_glb(target)
        manifest.append(entry)
        print(f"  saved {target.name}  {target.stat().st_size:,} bytes", flush=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--base-url",
        default=os.environ.get("MIA_BASE_URL", "http://127.0.0.1:7860/"),
        help="Make-It-Animatable Gradio root (default: %(default)s)",
    )
    parser.add_argument(
        "--stamp",
        default=datetime.now().strftime("%Y%m%d-%H%M%S"),
        help="Output subdirectory name under iterations/mia_rig/",
    )
    parser.add_argument(
        "--clips",
        default=",".join(name for name, _ in CLIPS),
        help="Comma-separated logical clip names to produce, in order.",
    )
    parser.add_argument(
        "--map",
        default="",
        help="Override logical->library animation, e.g. 'run=Run.fbx,walk=Walk.fbx'. "
             "Needed because some library entries retarget badly (Running.fbx collapses "
             "this character's spine); the driver tries alternatives instead.",
    )
    args = parser.parse_args()

    sanitize_proxy_env()
    from gradio_client import Client, handle_file

    if not INPUT_GLB.is_file():
        print(f"FAIL: input mesh missing: {INPUT_GLB}", file=sys.stderr)
        return 2

    wanted = [c.strip() for c in args.clips.split(",") if c.strip()]
    by_name = dict(CLIPS)
    for pair in (p.strip() for p in args.map.split(",") if p.strip()):
        logical, _, library = pair.partition("=")
        if logical not in by_name:
            print(f"FAIL: --map logical clip {logical!r} not one of {list(by_name)}",
                  file=sys.stderr)
            return 2
        if not library:
            print(f"FAIL: --map entry {pair!r} needs <logical>=<library.fbx>",
                  file=sys.stderr)
            return 2
        by_name[logical] = library
    unknown = [c for c in wanted if c not in by_name]
    if unknown:
        print(f"FAIL: unknown clip(s) {unknown}; known={list(by_name)}", file=sys.stderr)
        return 2
    if not wanted:
        print("FAIL: no clips requested", file=sys.stderr)
        return 2

    dest = OUT_ROOT / args.stamp
    dest.mkdir(parents=True, exist_ok=True)

    manifest: dict = {
        "asset": "cultivator_tripo_v9",
        "phase": "mia_auto_rig",
        "service": "Make-It-Animatable (Gradio)",
        "base_url": args.base_url,
        "started": datetime.now().isoformat(timespec="seconds"),
        "input": {
            "file": str(INPUT_GLB.relative_to(REPO)),
            "bytes": INPUT_GLB.stat().st_size,
            "sha256": sha256(INPUT_GLB),
        },
        "params": {
            "remove_fingers": True,
            "input_rest_pose": "No",
            "input_rest_parts": [],
            "input_is_gs": False,
            "opacity_threshold": 0.01,
            "use_normal": False,
            "weight_post_processing": True,
            "bone_vis": "LeftArm",
            "reset_to_rest": True,
            "retarget": True,
            "in_place": True,
        },
        "clip_library_names": {k: by_name[k] for k in wanted},
        "files": [],
        "timings_s": {},
    }

    print(f"connecting to {args.base_url} ...", flush=True)
    client = Client(args.base_url, verbose=False)
    print(f"  ok, {len(client.endpoints)} endpoints", flush=True)

    # The Animation File input expects a server-side FileData, not a library name.
    # `/lambda_3(<name>)` materialises a bundled library clip to disk and returns
    # its path; re-wrap it as a FileData so the pipeline accepts it.
    resolved: dict[str, object] = {}

    def resolve_animation(name: str):
        if name in resolved:
            return resolved[name]
        got = client.predict(name, api_name="/lambda_3")
        if not isinstance(got, (list, tuple)):
            got = [got]
        path = as_path(got[0])
        if path is None or not path.is_file():
            raise RuntimeError(f"could not resolve animation {name!r} -> {got!r}")
        resolved[name] = handle_file(str(path))
        print(f"  resolved {name} ({path.stat().st_size:,} bytes)", flush=True)
        return resolved[name]

    # Step 1 -- rig the clean mesh. The service keeps the rig in this client session.
    # `/pipeline` both rigs and attaches a first clip, but it is a generator whose API
    # result is component-update markers rather than downloadable files. Rig only, then
    # fetch EVERY clip through `/vis_blender` so all four come back the same shape.
    rig_anim = resolve_animation(by_name[wanted[0]])
    print(f"[rig] /pipeline  rig only ({by_name[wanted[0]]}) ...", flush=True)
    t0 = time.time()
    result = client.predict(
        handle_file(str(INPUT_GLB)),  # Input 3D Model  (api name: "progress")
        True,                      # No Fingers
        "No",                      # Input Rest Pose
        [],                        # Input Rest Parts
        False,                     # Input is GS
        0.01,                      # Opacity Threshold
        False,                     # Use Normal
        True,                      # Weight Post-Processing
        "LeftArm",                 # Bone Name of Weight Visualization
        True,                      # Reset to Rest
        rig_anim,                  # Animation File (resolved FileData)
        True,                      # Retarget Animation to Character
        True,                      # In Place
        api_name="/pipeline",
    )
    manifest["timings_s"]["pipeline"] = round(time.time() - t0, 2)
    print(f"  done in {manifest['timings_s']['pipeline']}s", flush=True)
    dump_slots(result, dest, manifest["files"], "pipeline")

    # Step 2 -- every clip, including the first, through the same rigged session.
    for index, logical in enumerate(wanted, start=1):
        anim = resolve_animation(by_name[logical])
        print(
            f"[{index}/{len(wanted)}] /vis_blender  clip '{logical}' "
            f"({by_name[logical]}) ...",
            flush=True,
        )
        t0 = time.time()
        clip_result = client.predict(
            True,    # Reset to Rest
            True,    # No Fingers
            "No",    # Input Rest Pose
            [],      # Input Rest Parts
            anim,    # Animation File (resolved FileData)
            True,    # Retarget
            True,    # In Place
            api_name="/vis_blender",
        )
        manifest["timings_s"][f"clip_{logical}"] = round(time.time() - t0, 2)
        print(f"  done in {manifest['timings_s'][f'clip_{logical}']}s", flush=True)
        dump_slots(clip_result, dest, manifest["files"], f"clip_{logical}")

    manifest["finished"] = datetime.now().isoformat(timespec="seconds")
    manifest["output_dir"] = str(dest.relative_to(REPO))
    manifest_path = dest / "mia_run_manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n")

    ok = sum(1 for f in manifest["files"] if f["status"] == "ok")
    print(f"\nmanifest: {manifest_path.relative_to(REPO)}")
    print(f"files ok: {ok}/{len(manifest['files'])}")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
