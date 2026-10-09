#!/usr/bin/env python3
"""Check generated LFS attributes and the actual staged LFS pointers."""

from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "assets"))
from lfs_policy import BASELINE, ROOT, git, policy


def main() -> int:
    root = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else ROOT
    fix = "fix=python3 tools/assets/sync_lfs_attributes.py, then git add .gitattributes and changed assets"
    try:
        expected, required, paths = policy(root)
        attrs = root / ".gitattributes"
        if not attrs.is_file() or attrs.read_text(encoding="utf-8") != expected:
            raise ValueError(f"LFS attributes missing or stale; {fix}")
        baseline = json.loads((root / BASELINE).read_text(encoding="utf-8"))["files"]
        entries = {}
        for line in git(root, "ls-files", "--stage", "-z").split("\0"):
            if line:
                metadata, path = line.split("\t", 1)
                _mode, oid, stage = metadata.split()
                if stage == "0":
                    entries[path] = oid
        for path in entries:
            if Path(path).suffix.lower() == ".blend1" and path not in baseline:
                raise ValueError(f"new automatic Blender backup staged: {path}; fix=git restore --staged -- {path}; keep the editable .blend")
        if ".gitattributes" not in entries or git(root, "cat-file", "blob", entries[".gitattributes"]) != expected:
            raise ValueError(f"staged LFS attributes missing or stale; {fix}")
        for path, oid in entries.items():
            if path not in required:
                continue
            size = int(git(root, "cat-file", "-s", oid).strip())
            pointer = git(root, "cat-file", "blob", oid) if size < 1024 else ""
            if not re.fullmatch(r"version https://git-lfs.github.com/spec/v1\noid sha256:[0-9a-f]{64}\nsize [0-9]+\n", pointer):
                raise ValueError(f"staged asset is not an LFS pointer: {path}; {fix}")
        print(f"OK   verify-lfs-assets — {len(paths)} assets, {len(required)} use LFS; small legacy blobs preserved")
        return 0
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
        print(f"FAIL verify-lfs-assets — {error}; {fix}")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
