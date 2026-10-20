#!/usr/bin/env python3
"""Collect `KS-Runtime-Check: <url> <text>` lines from the ks patch headers into a validated JSON list.
usage: runtime-checks.py <patches/ks dir>  -> stdout [{"url": ..., "text": ..., "patch": ...}]
Patch files are input to the pipeline, not trusted shell: only about:<name> and http(s) URLs without whitespace or
quotes, and short plain-text needles, are accepted; anything else fails the step."""
import json, os, re, sys
URL = re.compile(r'^(about:[a-z][a-z0-9-]{0,40}|https?://[A-Za-z0-9.-]+(:[0-9]{1,5})?(/[A-Za-z0-9._~%/?&=+-]*)?)$')
TEXT = re.compile(r'^[A-Za-z0-9 ._:/()-]{1,80}$')
out, d = [], sys.argv[1]
for n in sorted(os.listdir(d)) if os.path.isdir(d) else []:
    p = os.path.join(d, n)
    if not n.endswith('.patch') or os.path.islink(p): continue
    for line in open(p, encoding='utf-8', errors='replace'):
        if line.startswith(('diff ', '--- ')): break
        m = re.match(r'KS-Runtime-Check:[ \t]*(\S+)[ \t]+(.+?)\s*$', line)
        if not m: continue
        url, text = m.groups()
        if not URL.match(url) or not TEXT.match(text):
            sys.exit(f'{n}: rejected KS-Runtime-Check (url must be about:<name> or http(s), text [A-Za-z0-9 ._:/()-]{{1,80}}): {line.strip()!r}')
        out.append({'url': url, 'text': text, 'patch': n})
print(json.dumps(out))
