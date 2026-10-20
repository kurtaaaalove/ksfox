#!/usr/bin/env python3
"""Flatten fixture JSONs and diff them. usage: fp-diff.py A.json B.json [C.json D.json ...]
Prints per-field equality across all files; a field differing between runs of the SAME binary is 'noise'."""
import json, sys
def flat(o, p=''):
    if isinstance(o, dict):
        for k, v in o.items(): yield from flat(v, f'{p}.{k}' if p else k)
    elif isinstance(o, list): yield p, json.dumps(o, ensure_ascii=False)
    else: yield p, json.dumps(o, ensure_ascii=False)
docs = [(f, dict(flat(json.load(open(f))))) for f in sys.argv[1:]]
keys = sorted(set().union(*[d.keys() for _, d in docs]))
diff = 0
for k in keys:
    vals = [d.get(k, '<missing>') for _, d in docs]
    if len(set(vals)) > 1:
        diff += 1
        print(f'DIFF {k}: ' + ' | '.join(v[:90] for v in vals))
print(f'fields={len(keys)} differing={diff} files={[f for f, _ in docs]}')
