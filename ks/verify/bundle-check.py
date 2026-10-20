#!/usr/bin/env python3
"""Gate for a ks/main bundle against the official release (both unpacked).
usage: bundle-check.py <officialDir> <candidateDir> <patches/ks dir> [--prev <previousCandidateDir>] [--buildid <14 digits>]

PASS requires:
  * identical file list;
  * every non-ELF file outside omni.ja/fonts identical, except *.ini whose only difference is the BuildID line;
  * fonts/ and fontconfig/ identical;
  * omni.ja and browser/omni.ja: an entry may differ only if
      - it is a known build-environment entry (buildconfig.html, AppConstants, RFPTargetConstants) AND the
        difference disappears after normalising build paths / BuildIDs (and ks marker lines), or
      - a ks patch declares it with `KS-Bundle-Diff: <omni>!<entry>` (and then it MUST differ);
  * application.ini BuildID == --buildid (default: the official one) -> "BuildID aligned".
ELF files are reported (identical / BuildID strings), and with --prev compared with the previous candidate,
which shows whether a patch touched native code at all."""
import argparse, difflib, hashlib, os, re, sys, zipfile

ap = argparse.ArgumentParser()
ap.add_argument('off'); ap.add_argument('cand'); ap.add_argument('patches')
ap.add_argument('--prev'); ap.add_argument('--buildid')
a = ap.parse_args()
fail = []
def FAIL(msg): fail.append(msg); print('FAIL', msg)

# declarations from patch headers
declared, markers = {}, {}
for n in sorted(os.listdir(a.patches)) if os.path.isdir(a.patches) else []:
    if not n.endswith('.patch'): continue
    for line in open(os.path.join(a.patches, n), encoding='utf-8', errors='replace'):
        if line.startswith(('diff ', '--- ')): break
        m = re.match(r'KS-Bundle-Diff:\s*(\S+)', line)
        if m: declared[m.group(1)] = n
        m = re.match(r'KS-Bundle-Marker:\s*(\S+)\s+(.+)', line)
        if m: markers[m.group(1)] = (m.group(2).strip(), n)

def files(d):
    out = []
    for r, ds, fs in os.walk(d):
        for f in fs + [x for x in ds if os.path.islink(os.path.join(r, x))]:
            out.append(os.path.relpath(os.path.join(r, f), d))
    return set(out)
def sha(p):
    h = hashlib.sha256()
    with open(p, 'rb') as f:
        for b in iter(lambda: f.read(1 << 20), b''): h.update(b)
    return h.hexdigest()
def is_elf(p):
    try:
        with open(p, 'rb') as f: return f.read(4) == b'\x7fELF'
    except OSError: return False
BID = re.compile(rb'(?<!\d)20\d{12}(?!\d)')
def ini_bid(p):
    m = re.search(r'^BuildID=(\d+)', open(p).read(), re.M); return m.group(1) if m else None

fo, fc = files(a.off), files(a.cand)
fc.discard('version.json'); fo.discard('version.json')   # written at install time, not part of a release zip
print(f'## file list: official={len(fo)} candidate={len(fc)}', 'IDENTICAL' if fo == fc else 'DIFFERENT')
for x in sorted(fo - fc)[:20]: FAIL(f'missing in candidate: {x}')
for x in sorted(fc - fo)[:20]: FAIL(f'extra in candidate: {x}')

print('## non-ELF files outside omni.ja')
elf, nfont = [], 0
for rel in sorted(fo & fc):
    po, pc = os.path.join(a.off, rel), os.path.join(a.cand, rel)
    if os.path.islink(po) or os.path.isdir(po): continue
    if rel.endswith('omni.ja'): continue
    if is_elf(po): elf.append(rel); continue
    if rel.startswith(('fonts/', 'fontconfig/')):
        nfont += 1
        if sha(po) != sha(pc): FAIL(f'font/fontconfig differs: {rel}')
        continue
    if sha(po) == sha(pc): continue
    if rel.endswith('.ini'):
        strip = lambda p: [l for l in open(p).read().splitlines() if not l.startswith('BuildID=')]
        if strip(po) == strip(pc):
            print(f'  {rel}: BuildID only  official={ini_bid(po)} candidate={ini_bid(pc)}'); continue
    FAIL(f'non-ELF file differs: {rel}')
print(f'  fonts+fontconfig: {nfont} files', 'IDENTICAL' if not any('font' in f for f in fail) else 'DIFFER')

print('## omni.ja entries')
KNOWN_ENV = {'omni.ja!chrome/toolkit/content/global/buildconfig.html', 'omni.ja!modules/AppConstants.sys.mjs',
             'omni.ja!modules/RFPTargetConstants.sys.mjs'}
def norm(t):
    t = re.sub(r'/home/runner/work/camoufox/camoufox/|/work/camoufox/', '<SRCROOT>/', t)
    t = re.sub(r'/home/(runner|builder)/', '<HOME>/', t)
    t = re.sub(r'toolchains/[^/]+-x86_64-unknown-linux-gnu', 'toolchains/<TC>', t)
    t = re.sub(r' MOZBUILD_STATE_PATH=\S+', '', t)
    t = BID.sub(b'<BUILDID>', t.encode()).decode()
    return [l for l in t.splitlines() if 'ks-build' not in l]
appconst = {}
for om in ('omni.ja', 'browser/omni.ja'):
    zo, zc = zipfile.ZipFile(os.path.join(a.off, om)), zipfile.ZipFile(os.path.join(a.cand, om))
    eo = {i.filename: zo.read(i) for i in zo.infolist()}; ec = {i.filename: zc.read(i) for i in zc.infolist()}
    if set(eo) != set(ec): FAIL(f'{om}: entry list differs (+{len(set(ec)-set(eo))} -{len(set(eo)-set(ec))})')
    diff = sorted(k for k in set(eo) & set(ec) if eo[k] != ec[k])
    print(f'  {om}: {len(eo)} entries, {len(diff)} differ')
    for k in diff:
        key = f'{om}!{k}'
        to, tc = eo[k].decode('utf-8', 'replace'), ec[k].decode('utf-8', 'replace')
        resid = [l for l in difflib.unified_diff(norm(to), norm(tc), lineterm='', n=0) if l[:1] in '+-' and l[:3] not in ('+++', '---')]
        if key in declared:
            print(f'    {k}: declared by {declared[key]}')
            for l in difflib.unified_diff(to.splitlines(), tc.splitlines(), lineterm='', n=0):
                if l[:1] in '+-' and l[:3] not in ('+++', '---') and 'ks-build' in l: print('      ', l[:160])
        elif key in KNOWN_ENV and not resid:
            print(f'    {k}: build path / BuildID only')
        else:
            FAIL(f'{key} differs (not declared by any ks patch)')
            for l in resid[:8]: print('      ', l[:200])
        if k == 'modules/AppConstants.sys.mjs':
            appconst = {w: re.search(r'MOZ_BUILDID: "(\d+)"', t).group(1) for w, t in (('official', to), ('candidate', tc))}
    for key, n in declared.items():
        o, _, k = key.partition('!')
        if o == om and k in eo and eo[k] == ec.get(k): FAIL(f'{key} declared by {n} but identical to official (patch not in bundle?)')
    for key, (needle, n) in markers.items():
        o, _, k = key.partition('!')
        if o == om:
            ok = needle.encode() in ec.get(k, b'')
            print(f'    marker {needle!r} in {k}:', 'present' if ok else 'MISSING')
            if not ok: FAIL(f'marker {needle!r} missing from {key} ({n})')

print('## BuildID')
bo, bc = ini_bid(os.path.join(a.off, 'application.ini')), ini_bid(os.path.join(a.cand, 'application.ini'))
want = a.buildid or bo
print(f'  application.ini official={bo} candidate={bc} ->', 'ALIGNED' if bc == want else 'NOT aligned')
if bc != want: FAIL(f'application.ini BuildID {bc} != {want}')
print(f'  platform.ini   official={ini_bid(os.path.join(a.off, "platform.ini"))} candidate={ini_bid(os.path.join(a.cand, "platform.ini"))}')
if appconst: print(f'  AppConstants.MOZ_BUILDID official={appconst["official"]} candidate={appconst["candidate"]}')

from collections import Counter
def estrings(p):
    t = open(p, 'rb').read()
    t = re.sub(rb'/home/runner/work/camoufox/camoufox/|/work/camoufox/', b'<SRC>/', t)
    t = re.sub(rb'/home/(runner|builder)/', b'<HOME>/', t)
    t = re.sub(rb'toolchains/[\w.-]+?-x86_64-unknown-linux-gnu', b'toolchains/<TC>', t)
    return Counter(BID.sub(b'<BUILDID>', x) for x in re.findall(rb'[\x20-\x7e]{6,}', t))
print('## ELF files')
same = [e for e in elf if sha(os.path.join(a.off, e)) == sha(os.path.join(a.cand, e))]
print(f'  identical to official: {len(same)}/{len(elf)}')
for e in sorted(set(elf) - set(same)):
    po, pc = os.path.join(a.off, e), os.path.join(a.cand, e)
    ids = lambda p: sorted(set(x.decode() for x in BID.findall(open(p, 'rb').read()) if x.startswith(b'2026')))
    print(f'  {e:<28} size official={os.path.getsize(po)} candidate={os.path.getsize(pc)} buildid-strings official={ids(po)} candidate={ids(pc)}')
    # printable strings after normalising build paths / toolchain dir / BuildIDs: what is left besides code layout
    so, sc = estrings(po), estrings(pc)
    resid = (so - sc) + (sc - so)
    print(f'  {"":<28} strings residual after path/BuildID normalisation: {sum(resid.values())}'
          + (f'  e.g. {[x[:80] for x in list(resid)[:3]]}' if resid else ''))
if a.prev and os.path.isdir(a.prev):
    sp = [e for e in elf if os.path.exists(os.path.join(a.prev, e)) and sha(os.path.join(a.prev, e)) == sha(os.path.join(a.cand, e))]
    print(f'  vs previous candidate ({a.prev}): identical {len(sp)}/{len(elf)}; changed: {sorted(set(elf) - set(sp))}')
print('bundle-check:', 'PASS' if not fail else f'FAIL ({len(fail)})')
sys.exit(1 if fail else 0)
