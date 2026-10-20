#!/usr/bin/env python3
"""Destinations contacted by the candidate binary during an outbound probe, against the official baseline.
usage: outbound-check.py <probe.pcap> <probe.ss> <baseline.txt> [exe-substring=selfbuild]
A connection is attributed to the probe when `ss -tunap` shows it owned by a pid whose /proc/<pid>/exe contains
<exe-substring>; UDP/QUIC flows ss did not catch are 'unattributed' (other VM traffic can land there).
FAIL = a probe-attributed hostname outside every baseline host/suffix. WARN = new host under a known suffix, or an
unattributed new name."""
import collections, os, re, subprocess, sys
pcap, ssf, basef = sys.argv[1:4]; needle = sys.argv[4] if len(sys.argv) > 4 else 'selfbuild'
hosts, suffixes = set(), set()
for l in open(basef):
    f = l.split()
    if len(f) == 2 and f[0] == 'host': hosts.add(f[1])
    if len(f) == 2 and f[0] == 'suffix': suffixes.add(f[1])
out = subprocess.run([sys.executable, os.path.join(os.path.dirname(os.path.abspath(__file__)), 'pcap-dests.py'), pcap],
                     capture_output=True, text=True).stdout
L = open(ssf, errors='replace').read().splitlines()
pid2exe = {m.group(1): m.group(2) for m in (re.match(r'PID (\d+) (\S+)', l) for l in L) if m}
ip2 = collections.defaultdict(set)
for l in L:
    if l.startswith(('tcp', 'udp')) and len(l.split()) > 5:
        ip = l.split()[5].rsplit(':', 1)[0].strip('[]')
        for name, pid in re.findall(r'\(\("([^"]+)",pid=(\d+)', l):
            exe = pid2exe.get(pid, '')
            ip2[ip].add('probe' if needle in exe else ('other-camoufox' if 'camoufox' in exe else name))
fails, warns, rows = [], [], []
for l in out.splitlines():
    if not l[:1].isdigit(): continue
    f = l.split(); ip = f[1]; names = [x for x in f[4:] if not x.startswith('(') and '.' in x]
    owner = ','.join(sorted(ip2.get(ip, {'unattributed'})))
    if 'probe' not in owner and owner != 'unattributed': continue      # someone else's traffic
    rows.append((ip, ' '.join(names) or '(no DNS/SNI name)', owner))
    for n in names:
        if n in hosts: continue
        known_suffix = any(n == s or n.endswith('.' + s) for s in suffixes)
        if 'probe' in owner and not known_suffix: fails.append(n)
        else: warns.append(f'{n} ({owner}{", known suffix" if known_suffix else ""})')
for ip, n, o in rows: print(f'  {ip:<40} {n:<60} <- {o}')
names = sorted({x for _, n, _ in rows for x in n.split() if '.' in x})
print(f'destination names (probe+unattributed): {len(names)}')
for w in sorted(set(warns)): print('WARN new name:', w)
for x in sorted(set(fails)): print('FAIL new destination from candidate binary:', x)
print('outbound:', 'PASS' if not fails else 'FAIL')
sys.exit(1 if fails else 0)
