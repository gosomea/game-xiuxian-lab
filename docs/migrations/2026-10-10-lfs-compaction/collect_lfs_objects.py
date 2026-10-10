#!/usr/bin/env python3
"""Collect only approved, unreferenced LFS objects after a verified rewrite."""
import hashlib, json, re, subprocess
from pathlib import Path
root=Path.cwd()
evidence=root/'docs/migrations/2026-10-10-lfs-compaction'
plan=json.loads((evidence/'plan.json').read_text())
pattern=re.compile(rb'version https://git-lfs.github.com/spec/v1\noid sha256:([0-9a-f]{64})\nsize ([0-9]+)\n')
ids=[row.split(' ',1)[0] for row in subprocess.check_output(['git','rev-list','--objects','--all']).decode().splitlines()]
checks=subprocess.run(['git','cat-file','--batch-check=%(objectname) %(objecttype) %(objectsize)'],input='\n'.join(ids)+'\n',text=True,capture_output=True,check=True).stdout.splitlines()
small=[r.split()[0] for r in checks if r.split()[1]=='blob' and int(r.split()[2])<1024]
raw=subprocess.run(['git','cat-file','--batch'],input=('\n'.join(small)+'\n').encode(),capture_output=True,check=True).stdout
pos=0
required={}
for _ in small:
    end=raw.index(b'\n',pos)
    oid,kind,size=raw[pos:end].decode().split()
    size=int(size)
    content=raw[end+1:end+1+size]
    pos=end+size+2
    m=pattern.fullmatch(content)
    if m: required[m[1].decode()]=int(m[2])
media=root/'.git/lfs/objects'
cache={p.name:p for p in media.rglob('*') if p.is_file() and re.fullmatch('[0-9a-f]{64}',p.name)}
for oid,size in required.items():
    p=cache[oid]
    if p.stat().st_size!=size: raise RuntimeError('Retained object size mismatch: '+oid)
    digest=hashlib.sha256()
    with p.open('rb') as source:
        while block:=source.read(1024*1024): digest.update(block)
    if digest.hexdigest()!=oid: raise RuntimeError('Retained SHA-256 mismatch: '+oid)
selected={o['oid']:o['bytes'] for o in plan['candidate_objects']}
if set(selected).intersection(required): raise RuntimeError('Removal would delete referenced objects')
for oid,size in selected.items():
    if cache[oid].stat().st_size!=size: raise RuntimeError('Approved object size mismatch: '+oid)
before=sum(p.stat().st_size for p in cache.values())
for oid in selected: cache[oid].unlink()
after=sum(p.stat().st_size for oid,p in cache.items() if oid not in selected)
result={'retained_history_objects_hashed':len(required),'retained_history_bytes':sum(required.values()),
        'sha256_and_sizes_verified':True,'approved_unreferenced_objects_removed':len(selected),
        'removed_bytes':sum(selected.values()),'cache_before_bytes':before,'cache_after_bytes':after,
        'cache_after_GiB':after/2**30,'unselected_unreferenced_objects_retained':len(set(cache)-set(selected)-set(required))}
(evidence/'lfs-audit.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps(result,indent=2))
