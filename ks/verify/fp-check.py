#!/usr/bin/env python3
"""Gate on fp-compare.mjs output (same launch config; official-1, self-1, official-2, self-2).
usage: fp-check.py <outdir> [patches/ks dir]
Every fixture field (fp.*) must be identical official vs candidate. A field that also differs between the two
runs of the OFFICIAL binary is per-session noise (e.g. canvas with Gecko's randomisation on) and is reported, not
failed. Fields a ks patch is meant to change are declared with `KS-Fingerprint: <field> ...` in its header."""
import json, os, re, sys
out = sys.argv[1]; pdir = sys.argv[2] if len(sys.argv) > 2 else None
declared = {}
if pdir and os.path.isdir(pdir):
    for n in sorted(os.listdir(pdir)):
        if n.endswith('.patch'):
            for line in open(os.path.join(pdir, n), errors='replace'):
                if line.startswith(('diff ', '--- ')): break
                m = re.match(r'KS-Fingerprint:\s*(.+)', line)
                if m and m.group(1).strip().lower() != 'none':
                    for f in m.group(1).split(): declared[f] = n
def flat(o, p=''):
    if isinstance(o, dict):
        for k, v in o.items(): yield from flat(v, f'{p}.{k}' if p else k)
    else: yield p, json.dumps(o, ensure_ascii=False, sort_keys=True)
runs = {n: dict(flat(json.load(open(f'{out}/{n}.json')))) for n in ('official-1', 'self-1', 'official-2', 'self-2')}
fields = sorted(k for k in runs['official-1'] if k.startswith('fp.'))
noise, bad, ok = [], [], 0
for k in fields:
    o1, o2, s1, s2 = (runs[n].get(k, '<missing>') for n in ('official-1', 'official-2', 'self-1', 'self-2'))
    if o1 == o2 == s1 == s2: ok += 1
    elif o1 != o2: noise.append(k)
    elif k in declared: print(f'  declared by {declared[k]}: {k}: {o1[:60]} -> {s1[:60]}')
    else: bad.append(k); print(f'FAIL {k}: official={o1[:80]} candidate={s1[:80]} | {s2[:80]}')
extra = sorted(k for k in runs['self-1'] if k.startswith('fp.') and k not in runs['official-1'])
for k in extra: bad.append(k); print(f'FAIL field only in candidate: {k}')
print(f'fp fields={len(fields)} identical-in-all-4-runs={ok} per-session-noise={len(noise)} {noise} differing={len(bad)}')
for n in ('official-1', 'self-1'): print(f'  {n}: {runs[n].get("version")} example="{runs[n].get("example.title")}" click={runs[n].get("clicked")}')
print('fingerprint:', 'PASS' if not bad else 'FAIL')
sys.exit(1 if bad else 0)
