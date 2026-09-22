#!/usr/bin/env python3
"""Apply `correct_clip_lean.py` to every clip of an iteration, then report the results.

Run with the repo's Python (not Blender):
    python3 tools/art/correct_iteration_lean.py --iteration docs/.../20260921-ship7 \
        --out docs/.../20260921-ship7-lean --target-lean-deg 1.6

Why a driver
------------
Each clip needs its own Blender process (Blender's Python state does not survive a second
import cleanly), and the per-clip numbers have to be collected into one place so the whole
set can be reviewed at a glance. This script runs the corrector once per clip, fails loudly
if any clip did not converge, and prints a summary table.

Target lean
-----------
Not zero. A figure standing perfectly plumb reads as stiff, and the hips->head axis is not
anatomically vertical to begin with: the hip joint sits behind the spine, so "upright and
relaxed" measures a couple of degrees of apparent backward lean even when the posture is
correct. `--target-lean-deg 1.6` was chosen from the corrected renders - enough to keep the
posture from looking rigid while removing the 12-degree lean that was visible in game.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
BLENDER = "/Applications/Blender.app/Contents/MacOS/Blender"

## Clips the runtime asset ships. Kept explicit so a new clip cannot be silently skipped.
DEFAULT_CLIPS = ["idle", "walk", "run", "jump", "idle_guarded", "meditate", "sword_ride"]

## Clips that are NOT standing and must not be planted upright: a seated pose is supposed to
## fold, and forcing its hips->head axis vertical would break the pose.
SEATED_CLIPS = {"meditate"}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--iteration", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--clips", default=",".join(DEFAULT_CLIPS))
    parser.add_argument("--target-lean-deg", type=float, default=1.6)
    parser.add_argument("--skip", default="", help="comma-separated clips to copy unchanged")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    source_dir = Path(args.iteration)
    if not source_dir.is_absolute():
        source_dir = REPO / source_dir
    out_dir = Path(args.out)
    if not out_dir.is_absolute():
        out_dir = REPO / out_dir
    out_dir.mkdir(parents=True, exist_ok=True)

    clips = [c.strip() for c in args.clips.split(",") if c.strip()]
    skip = {c.strip() for c in args.skip.split(",") if c.strip()}

    results = {}
    failed = []
    print(f"iteration {source_dir.name} -> {out_dir.name}")
    print(f"target lean {args.target_lean_deg:+.2f} deg, {len(clips)} clip(s)")
    print()

    for clip in clips:
        src = source_dir / f"clip_{clip}_slot2.fbx"
        dst = out_dir / f"clip_{clip}_slot2.fbx"
        if not src.is_file():
            print(f"  {clip:<14} MISSING {src.name}")
            failed.append(f"{clip}: source missing")
            continue

        if clip in skip or clip in SEATED_CLIPS:
            reason = "requested" if clip in skip else "seated pose - must not be planted upright"
            with open(src, "rb") as fh_in, open(dst, "wb") as fh_out:
                while True:
                    chunk = fh_in.read(8 << 20)
                    if not chunk:
                        break
                    fh_out.write(chunk)
            results[clip] = {"copied_unchanged": True, "reason": reason}
            print(f"  {clip:<14} copied unchanged ({reason})")
            continue

        report = out_dir / f"lean_{clip}.json"
        cmd = [
            BLENDER, "--background", "--factory-startup",
            "--python", str(REPO / "tools/art/correct_clip_lean.py"),
            "--",
            "--input", str(src),
            "--output", str(dst),
            "--target-lean-deg", str(args.target_lean_deg),
            "--report", str(report),
        ]
        proc = subprocess.run(cmd, capture_output=True, text=True)
        if proc.returncode != 0 or not report.is_file():
            tail = (proc.stderr or proc.stdout).strip().splitlines()[-3:]
            print(f"  {clip:<14} FAILED (exit {proc.returncode}): {' | '.join(tail)}")
            failed.append(f"{clip}: corrector exited {proc.returncode}")
            continue

        stats = json.loads(report.read_text())
        results[clip] = stats
        ok = "ok " if stats.get("converged") else "WARN"
        print(f"  {clip:<14} {ok} {stats['lean_before_deg']:+7.2f} -> "
              f"{stats['lean_after_deg']:+7.2f} deg "
              f"(target {stats['target_lean_deg']:+.2f}, residual "
              f"{stats['residual_deg']:+.2f}, {len(stats.get('refinement_passes', []))} pass)")

    summary = {
        "iteration": str(source_dir),
        "output": str(out_dir),
        "target_lean_deg": args.target_lean_deg,
        "clips": results,
        "failed": failed,
    }
    summary_path = out_dir / "lean_summary.json"
    summary_path.write_text(json.dumps(summary, indent=2, ensure_ascii=False) + "\n")

    print()
    if failed:
        print(f"FAIL: {len(failed)} clip(s) did not complete")
        for item in failed:
            print(f"  ! {item}")
        return 1
    converged = sum(1 for s in results.values() if s.get("converged"))
    unchanged = sum(1 for s in results.values() if s.get("copied_unchanged"))
    print(f"OK: {converged} corrected, {unchanged} intentionally unchanged, 0 failed")
    print(f"summary {summary_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
