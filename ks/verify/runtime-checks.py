#!/usr/bin/env python3
"""Collect the VM-side checks from the ks patch headers into one validated JSON document.
usage: runtime-checks.py <patches/ks dir>  -> stdout {"pages": [...], "markers": [...]}
  KS-Runtime-Check: <http(s) url> <text>        a page the deployed browser opens (Playwright) must show <text>
  KS-Bundle-Marker: <omni>!<entry> <text>       the omni.ja the RUNNING browser has mapped must contain <text>
Patch files are input to the pipeline, not trusted shell: only plain http(s) URLs, plain entry paths and short
plain-text needles are accepted; anything else fails the step. (about: pages are not accepted: Playwright's
Juggler never commits a navigation to privileged about: pages in Camoufox, page.goto just times out.)"""
import json, os, re, sys
URL = re.compile(r'^https?://[A-Za-z0-9.-]+(:[0-9]{1,5})?(/[A-Za-z0-9._~%/?&=+-]*)?$')
ENTRY = re.compile(r'^(browser/)?omni\.ja![A-Za-z0-9._/-]{1,200}$')
TEXT = re.compile(r'^[A-Za-z0-9 ._:/()-]{1,80}$')
pages, markers, d = [], [], sys.argv[1]
for n in sorted(os.listdir(d)) if os.path.isdir(d) else []:
    p = os.path.join(d, n)
    if not n.endswith('.patch') or os.path.islink(p): continue
    for line in open(p, encoding='utf-8', errors='replace'):
        if line.startswith(('diff ', '--- ')): break
        for key, rx, dest, field in (('KS-Runtime-Check', URL, pages, 'url'), ('KS-Bundle-Marker', ENTRY, markers, 'entry')):
            m = re.match(key + r':[ \t]*(\S+)[ \t]+(.+?)\s*$', line)
            if not m: continue
            a, text = m.groups()
            if not rx.match(a) or not TEXT.match(text) or '..' in a:
                sys.exit(f'{n}: rejected {key} (see runtime-checks.py for the accepted form): {line.strip()!r}')
            dest.append({field: a, 'text': text, 'patch': n})
print(json.dumps({'pages': pages, 'markers': markers}))
