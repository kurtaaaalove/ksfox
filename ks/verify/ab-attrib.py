#!/usr/bin/env python3
"""Per-capture destination names attributed to the probe binary. usage: ab-attrib.py <label> [<label> ...]  (reads <label>.pcap/.ss)"""
import re, subprocess, sys, collections
res = {}
for lab in sys.argv[1:]:
    out = subprocess.run(['python3', '../pcap-dests.py', f'{lab}.pcap'], capture_output=True, text=True).stdout
    L = open(f'{lab}.ss', errors='replace').read().splitlines()
    pid2exe = {m.group(1): m.group(2) for m in (re.match(r'PID (\d+) (\S+)', l) for l in L) if m}
    ip2 = collections.defaultdict(set)
    for l in L:
        if l.startswith(('tcp', 'udp')) and len(l.split()) > 5:
            ip = l.split()[5].rsplit(':', 1)[0].strip('[]')
            for name, pid in re.findall(r'\(\("([^"]+)",pid=(\d+)', l):
                exe = pid2exe.get(pid, '')
                ip2[ip].add('probe' if ('selfbuild' in exe if lab.startswith('self') else '.cache/camoufox' in exe) else
                            ('other-camoufox' if 'camoufox' in exe else name))
    names = {}
    for l in out.splitlines():
        if l[:1].isdigit():
            f = l.split(); ip = f[1]; nm = ' '.join(x for x in f[4:] if not x.startswith('(')) or f'({ip})'
            names[nm] = ','.join(sorted(ip2.get(ip, {'udp/quic-unattributed'})))
    res[lab] = names
    print(f'== {lab}'); [print(f'   {k:<60} <- {v}') for k, v in sorted(names.items())]
def probe_set(lab): return {k for k, v in res[lab].items() if 'probe' in v or 'unattributed' in v}
offs = set().union(*[probe_set(l) for l in res if l.startswith('official')])
for lab in res:
    if lab.startswith('self'): print(f'{lab}: names not seen in any official run:', sorted(probe_set(lab) - offs) or 'NONE')
