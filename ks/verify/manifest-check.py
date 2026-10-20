#!/usr/bin/env python3
"""Compare a release manifest.json with HEAD. usage: manifest-check.py <manifest.json> <exported-tree>"""
import json, subprocess, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from ci.browser_inputs import source_digest
m = json.load(open(sys.argv[1]))
tree = source_digest(Path(sys.argv[2]))
anc = subprocess.call(['git', 'merge-base', '--is-ancestor', m['commit'], 'HEAD']) == 0
print(f"tag {m['tag']}  commit {m['commit']}  ancestor-of-HEAD={anc}")
print(f"manifest digest {m['source_digest']}  HEAD tree {tree}  " +
      ('MATCH' if tree == m['source_digest'] else 'DIFFERENT (expected only once patches/ks exists)'))
sys.exit(0 if anc else 1)
