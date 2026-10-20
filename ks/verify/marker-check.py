#!/usr/bin/env python3
"""Runs ON THE VM. Prove the RUNNING browser carries the ks markers: find processes whose /proc/<pid>/exe is
<bundleDir>/camoufox-bin, take the omni.ja files they have mapped (/proc/<pid>/maps), and look for every
KS-Bundle-Marker text in that mapped omni.ja. usage: marker-check.py <bundleDir> <checks.json>"""
import json, os, sys, zipfile
bundle, checks = os.path.realpath(sys.argv[1]), json.load(open(sys.argv[2]))['markers']
exe = os.path.join(bundle, 'camoufox-bin'); mapped = {}
for pid in filter(str.isdigit, os.listdir('/proc')):
    try:
        if os.readlink(f'/proc/{pid}/exe') != exe: continue
        for l in open(f'/proc/{pid}/maps'):
            path = l.split(None, 5)[5].strip() if len(l.split(None, 5)) == 6 else ''
            if path.endswith('omni.ja') and path.startswith(bundle + '/'): mapped.setdefault(path, set()).add(pid)
    except OSError: pass
if not mapped: sys.exit(f'no running process of {exe} has an omni.ja mapped')
bad = 0
for path, pids in sorted(mapped.items()): print(f'mapped by {len(pids)} running process(es): {path}')
for c in checks:
    omni, _, entry = c['entry'].partition('!')
    path = os.path.join(bundle, omni)
    ok = path in mapped and c['text'].encode() in zipfile.ZipFile(path).read(entry)
    print(('MARKER OK   ' if ok else 'MARKER MISSING ') + f"{c['entry']} {c['text']!r} ({c['patch']})")
    bad += not ok
sys.exit(1 if bad else 0)
