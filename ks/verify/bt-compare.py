#!/usr/bin/env python3
"""Compare two build-tester-result.json files: grade, score and the SET of failed checks.
usage: bt-compare.py <official.json> <candidate.json>   exit 0 = same grade, same score, same failure set"""
import json, sys

def failures(d):
    out = set()
    def walk(o, path):
        if isinstance(o, dict):
            if o.get('passed') is False:
                out.add(path + '/' + str(o.get('name', '?')))
            for k, v in o.items():
                if k not in ('expected', 'actual'): walk(v, f'{path}.{k}')
        elif isinstance(o, list):
            for v in o: walk(v, path)
    for p in d.get('profiles', []):
        walk(p.get('results', {}), p['profile'].get('name', '?'))
        walk(p.get('matchResults', []), p['profile'].get('name', '?') + '.match')
    walk(d.get('crossProfile', {}), 'cross')
    return out

a, b = (json.load(open(f)) for f in sys.argv[1:3])
fa, fb = failures(a), failures(b)
print(f"official : grade {a['overallGrade']} {a['totalPassed']}/{a['totalChecks']} failures={len(fa)}")
print(f"candidate: grade {b['overallGrade']} {b['totalPassed']}/{b['totalChecks']} failures={len(fb)}")
for x in sorted(fa - fb): print('  fixed in candidate :', x)
for x in sorted(fb - fa): print('  NEW failure        :', x)
same = (a['overallGrade'], a['totalPassed'], a['totalChecks']) == (b['overallGrade'], b['totalPassed'], b['totalChecks']) and fa == fb
print('build-tester:', 'SAME (grade, score, failure set)' if same else 'DIFFERENT')
sys.exit(0 if same else 1)
