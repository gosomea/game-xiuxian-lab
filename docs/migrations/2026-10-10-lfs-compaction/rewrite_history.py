#!/usr/bin/env python3
"""One-off approved path removal, with an independent full-tree audit before ref updates."""
import hashlib
import json
import os
import subprocess
import tempfile
from pathlib import Path

ROOT = Path.cwd()
EVIDENCE = ROOT / 'docs/migrations/2026-10-10-lfs-compaction'
plan = json.loads((EVIDENCE / 'plan.json').read_text())
removed = set(plan['remove_paths'])

def git(*args, input=None, env=None):
    return subprocess.check_output(['git', *args], input=input, env=env)

def tree(commit):
    result = {}
    for row in git('ls-tree', '-rz', commit).split(b'\0'):
        if row:
            metadata, path = row.split(b'\t', 1)
            result[path.decode()] = metadata
    return result

refs = {row.split()[0]: row.split()[1] for row in git('for-each-ref', '--format=%(refname) %(objectname)').decode().splitlines()}
for ref, oid in refs.items():
    if git('cat-file', '-t', oid).strip() not in (b'commit', b'tree'):
        raise RuntimeError('Unsupported ref object: ' + ref)
    if removed.intersection(tree(oid)):
        raise RuntimeError('Removal would change current ref tip: ' + ref)
commits = git('rev-list', '--reverse', '--topo-order', '--all').decode().splitlines()
mapping = {}
trees = {}
metadata = {}
with tempfile.TemporaryDirectory(prefix='xiuxian-history-index-') as temporary:
    environment = dict(os.environ, GIT_INDEX_FILE=str(Path(temporary) / 'index'))
    for old in commits:
        raw = git('cat-file', 'commit', old)
        headers, message = raw.split(b'\n\n', 1)
        lines = headers.splitlines()
        if any(line.startswith((b'gpgsig ', b'gpgsig-sha256 ', b'mergetag ')) for line in lines):
            raise RuntimeError('Signed commit/tag needs separate handling: ' + old)
        old_tree = next(line[5:].decode() for line in lines if line.startswith(b'tree '))
        if old_tree not in trees:
            git('read-tree', old_tree, env=environment)
            git('update-index', '--force-remove', '-z', '--stdin', input=b'\0'.join(p.encode() for p in sorted(removed)) + b'\0', env=environment)
            trees[old_tree] = git('write-tree', env=environment).decode().strip()
        replacement = []
        for line in lines:
            if line.startswith(b'tree '):
                replacement.append(b'tree ' + trees[old_tree].encode())
            elif line.startswith(b'parent '):
                replacement.append(b'parent ' + mapping[line[7:].decode()].encode())
            else:
                replacement.append(line)
        transformed = b'\n'.join(replacement) + b'\n\n' + message
        mapping[old] = git('hash-object', '-t', 'commit', '-w', '--stdin', input=transformed).decode().strip()
        metadata[old] = (lines, message)

# Audit the actual stored Git objects rather than trusting index operations.
removed_entries = preserved_entries = 0
for old in commits:
    new = mapping[old]
    original = tree(old)
    rewritten = tree(new)
    expected = {p: mode_oid for p, mode_oid in original.items() if p not in removed}
    if rewritten != expected:
        raise RuntimeError('Path/mode/blob audit failed: ' + old)
    removed_entries += len(original) - len(expected)
    preserved_entries += len(expected)
    old_lines, old_message = metadata[old]
    new_headers, new_message = git('cat-file', 'commit', new).split(b'\n\n', 1)
    new_lines = new_headers.splitlines()
    non_graph = lambda lines: [line for line in lines if not line.startswith((b'tree ', b'parent '))]
    old_parents = [line[7:].decode() for line in old_lines if line.startswith(b'parent ')]
    new_parents = [line[7:].decode() for line in new_lines if line.startswith(b'parent ')]
    if non_graph(old_lines) != non_graph(new_lines) or old_message != new_message or [mapping[p] for p in old_parents] != new_parents:
        raise RuntimeError('Metadata/message/parent audit failed: ' + old)
for ref, old in refs.items():
    if tree(old) != tree(mapping.get(old, old)):
        raise RuntimeError('Ref tip changed: ' + ref)
actual_history = set(git('rev-list', *sorted({mapping.get(o, o) for o in refs.values()})).decode().splitlines())
if actual_history != set(mapping.values()) or len(set(mapping.values())) != len(commits):
    raise RuntimeError('Commit count or closure changed')
transaction = ['start'] + ['update ' + ref + ' ' + mapping.get(old, old) + ' ' + old for ref, old in refs.items()] + ['prepare', 'commit']
git('update-ref', '--stdin', input=('\n'.join(transaction) + '\n').encode())
(EVIDENCE / 'commit-map.json').write_text(json.dumps(mapping, indent=2) + '\n')
result = {'commits_checked': len(commits), 'preserved_path_mode_blob_entries': preserved_entries,
          'removed_entries': removed_entries, 'removed_exact_paths': len(removed),
          'all_metadata_messages_parent_graph_preserved': True, 'all_ref_tips_unchanged': True,
          'before_refs': refs, 'after_refs': {ref: mapping.get(old, old) for ref, old in refs.items()},
          'script_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}
(EVIDENCE / 'rewrite-audit.json').write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps({k: v for k, v in result.items() if k not in ('before_refs', 'after_refs')}, indent=2))
