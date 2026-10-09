#!/usr/bin/env python3
"""Audit every original commit against an LFS rewrite and hash all referenced assets.

One-off CLI evidence, not a recurring gate: the original database is an external
migration backup. A changed ordinary blob is allowed only when replaced by an
LFS pointer whose local object has exactly the original Git blob identity.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import re
import subprocess
from pathlib import Path

POINTER = re.compile(rb"version https://git-lfs.github.com/spec/v1\noid sha256:([0-9a-f]{64})\nsize ([0-9]+)\n")


def git(repo: Path, *args: str) -> bytes:
    return subprocess.check_output(["git", "--git-dir=" + str(repo), *args])


def tree(repo: Path, commit: str) -> dict[str, tuple[str, str]]:
    result = {}
    for row in git(repo, "ls-tree", "-rz", commit).split(b"\0"):
        if not row:
            continue
        metadata, path = row.split(b"\t", 1)
        mode, kind, oid = metadata.decode().split()
        if kind != "blob":
            raise ValueError("unsupported non-blob tree entry: " + path.decode())
        result[path.decode()] = (mode, oid)
    return result


def commit_data(repo: Path, commit: str) -> tuple[list[bytes], list[str], bytes]:
    headers, message = git(repo, "cat-file", "commit", commit).split(b"\n\n", 1)
    metadata, parents = [], []
    for line in headers.splitlines():
        if line.startswith(b"parent "):
            parents.append(line[7:].decode())
        elif not line.startswith(b"tree "):
            metadata.append(line)
    return metadata, parents, message


def hash_asset(path: Path, size: int) -> tuple[str, str]:
    if path.stat().st_size != size:
        raise ValueError("LFS object size differs: " + path.name)
    sha1 = hashlib.sha1(("blob %d\0" % size).encode())
    sha256 = hashlib.sha256()
    with path.open("rb") as source:
        while block := source.read(1024 * 1024):
            sha1.update(block)
            sha256.update(block)
    return sha1.hexdigest(), sha256.hexdigest()


def audit(original: Path, current: Path, mapping_file: Path, threshold: int = 5_000_000) -> dict:
    mapping = {}
    for old, new in csv.reader(mapping_file.read_text().splitlines()):
        if not re.fullmatch(r"[0-9a-f]{40}", old) or not re.fullmatch(r"[0-9a-f]{40}", new):
            raise ValueError("invalid commit mapping")
        mapping[old] = new
    old_head = git(original, "rev-parse", "refs/heads/main").decode().strip()
    commits = git(original, "rev-list", "--reverse", old_head).decode().splitlines()
    new_head = mapping.get(old_head, old_head)
    old_blob_ids = set()
    old_trees = {}
    for commit in commits:
        old_trees[commit] = tree(original, commit)
        old_blob_ids.update(oid for mode, oid in old_trees[commit].values())
    sizes = {}
    proc = subprocess.run(["git", "--git-dir=" + str(original),
                           "cat-file", "--batch-check=%(objectname) %(objectsize)"],
                          input="\n".join(old_blob_ids) + "\n", text=True,
                          capture_output=True, check=True)
    for line in proc.stdout.splitlines():
        oid, size = line.split()
        sizes[oid] = int(size)
    lfs_dir = Path(git(current, "rev-parse", "--git-path", "lfs/objects").decode().strip())
    if not lfs_dir.is_absolute():
        lfs_dir = current.parent / lfs_dir
    verified, converted, pointers = {}, {}, {}
    unchanged_entries = changed_entries = checked_entries = 0
    for commit in commits:
        rewritten = mapping.get(commit, commit)
        old_meta, old_parents, old_message = commit_data(original, commit)
        new_meta, new_parents, new_message = commit_data(current, rewritten)
        if old_meta != new_meta or old_message != new_message:
            raise ValueError("commit metadata/message changed: " + commit)
        if [mapping.get(parent, parent) for parent in old_parents] != new_parents:
            raise ValueError("commit parent graph changed: " + commit)
        old_tree, new_tree = old_trees[commit], tree(current, rewritten)
        attrs = lambda p: Path(p).name == ".gitattributes"
        if {p for p in old_tree if not attrs(p)} != {p for p in new_tree if not attrs(p)}:
            raise ValueError("file paths changed: " + commit)
        for path, (mode, oid) in old_tree.items():
            if attrs(path):
                continue
            checked_entries += 1
            new_mode, new_oid = new_tree[path]
            if mode != new_mode:
                raise ValueError("file mode changed: " + path)
            if new_oid not in pointers:
                new_size = int(git(current, "cat-file", "-s", new_oid))
                pointers[new_oid] = POINTER.fullmatch(git(current, "cat-file", "blob", new_oid)) if new_size < 1024 else None
            match = pointers[new_oid]
            if match:
                lfs_oid, lfs_size = match[1].decode(), int(match[2])
                if lfs_oid not in verified:
                    verified[lfs_oid] = hash_asset(lfs_dir / lfs_oid[:2] / lfs_oid[2:4] / lfs_oid, lfs_size)
                blob_oid, content_sha256 = verified[lfs_oid]
                if content_sha256 != lfs_oid:
                    raise ValueError("LFS object SHA-256 differs: " + path)
                if new_oid != oid:
                    if sizes[oid] <= threshold or blob_oid != oid or lfs_size != sizes[oid]:
                        raise ValueError("converted content differs or is below threshold: " + path)
                    converted[oid] = {"sha256": lfs_oid, "size": lfs_size}
                    changed_entries += 1
                else:
                    unchanged_entries += 1
            elif new_oid != oid:
                raise ValueError("ordinary file content changed: " + path)
            elif sizes[oid] > threshold:
                raise ValueError("large ordinary blob was not migrated: " + path)
            else:
                unchanged_entries += 1
    expected_history = {mapping.get(commit, commit) for commit in commits}
    if set(git(current, "rev-list", new_head).decode().splitlines()) != expected_history:
        raise ValueError("rewritten history adds or drops commits")
    return {"old_head": old_head, "rewritten_head": new_head, "commits_checked": len(commits),
            "path_mode_content_entries_checked": checked_entries,
            "unchanged_entries": unchanged_entries, "converted_entries": changed_entries,
            "unique_converted_blobs": len(converted),
            "unique_converted_bytes": sum(item["size"] for item in converted.values()),
            "lfs_objects_hashed": len(verified), "threshold_bytes": threshold,
            "commit_metadata_messages_and_graph_preserved": True,
            "paths_modes_and_content_preserved": True,
            "sha256_and_original_git_blob_identity_verified": True,
            "object_map_sha256": hashlib.sha256(mapping_file.read_bytes()).hexdigest()}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--original-git", type=Path, required=True)
    parser.add_argument("--current-git", type=Path, default=Path(".git"))
    parser.add_argument("--object-map", type=Path, required=True)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    try:
        result = audit(args.original_git.resolve(), args.current_git.resolve(), args.object_map.resolve())
        output = json.dumps(result, indent=2) + "\n"
        if args.report:
            args.report.parent.mkdir(parents=True, exist_ok=True)
            args.report.write_text(output)
        print(output)
        return 0
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print("FAIL migration audit — %s; fix=retain the original backup and inspect the failing commit/object before adoption" % error)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
