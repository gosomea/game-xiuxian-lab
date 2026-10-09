#!/usr/bin/env python3
"""Run before git add: register large PNGs and promote modified legacy assets to LFS."""

from __future__ import annotations

import argparse
from pathlib import Path

from lfs_policy import ROOT, policy


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    expected, required, _paths = policy(args.root)
    output = args.root / ".gitattributes"
    if args.check:
        if not output.exists() or output.read_text(encoding="utf-8") != expected:
            print("FAIL LFS attributes stale; fix=python3 tools/assets/sync_lfs_attributes.py, then git add .gitattributes and changed assets")
            return 1
    else:
        output.write_text(expected, encoding="utf-8")
    print(f"OK LFS attributes: {len(required)} new or modified assets require pointers")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
