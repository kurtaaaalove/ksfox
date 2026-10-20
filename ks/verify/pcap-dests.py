#!/usr/bin/env python3
"""Outbound destinations in a pcap (pure python; linktypes EN10MB/SLL/SLL2/RAW).
usage: pcap-dests.py <file.pcap> [local-prefix ...]   (default local: 10. 127. 192.168. 172.16-31 fe80 ::1)
Prints: per destination IP -> names (from DNS answers / TLS SNI), protocols/ports, first-seen; then the DNS qname set."""
import struct, sys, ipaddress, datetime, collections
path = sys.argv[1]
f = open(path, 'rb'); gh = f.read(24)
magic = struct.unpack('<I', gh[:4])[0]
end = '<' if magic in (0xa1b2c3d4, 0xa1b23c4d) else '>'
linktype = struct.unpack(end + 'I', gh[20:24])[0]
def is_local(ip):
    a = ipaddress.ip_address(ip)
    return a.is_private or a.is_loopback or a.is_link_local or a.is_multicast
def qname(buf, off):
    labels = []; jumped = False; o = off; n = 0
    while n < 64:
        n += 1
        if o >= len(buf): break
        l = buf[o]
        if l == 0: o += 1; break
        if l & 0xc0 == 0xc0:
            ptr = ((l & 0x3f) << 8) | buf[o + 1]
            if not jumped: off_end = o + 2
            jumped = True; o = ptr; continue
        labels.append(buf[o + 1:o + 1 + l].decode('ascii', 'replace')); o += 1 + l
    return '.'.join(labels), (off_end if jumped else o)
def parse_dns(p, ip2name, qnames):
    if len(p) < 12: return
    fl, qd, an = struct.unpack('>HHH', p[2:8]); o = 12
    for _ in range(qd):
        name, o = qname(p, o); o += 4
        if not fl & 0x8000: qnames[name] += 1
    for _ in range(an):
        name, o = qname(p, o)
        if o + 10 > len(p): return
        t, c, ttl, rl = struct.unpack('>HHIH', p[o:o + 10]); o += 10
        rd = p[o:o + rl]; o += rl
        if t == 1 and rl == 4: ip2name[str(ipaddress.IPv4Address(rd))].add(name)
        if t == 28 and rl == 16: ip2name[str(ipaddress.IPv6Address(rd))].add(name)
def sni(p):
    try:
        if p[0] != 0x16 or p[5] != 0x01: return None
        o = 9 + 2 + 32; sl = p[o]; o += 1 + sl
        cl = struct.unpack('>H', p[o:o + 2])[0]; o += 2 + cl
        ml = p[o]; o += 1 + ml
        el = struct.unpack('>H', p[o:o + 2])[0]; o += 2; e_end = o + el
        while o + 4 <= e_end:
            et, ln = struct.unpack('>HH', p[o:o + 4]); o += 4
            if et == 0: return p[o + 5:o + 5 + struct.unpack('>H', p[o + 3:o + 5])[0]].decode()
            o += ln
    except Exception: return None
ip2name = collections.defaultdict(set); qnames = collections.Counter()
dests = collections.OrderedDict()
while True:
    h = f.read(16)
    if len(h) < 16: break
    ts, tus, incl, orig = struct.unpack(end + 'IIII', h); d = f.read(incl)
    if linktype == 1: proto = struct.unpack('>H', d[12:14])[0]; pl = d[14:]
    elif linktype == 113: proto = struct.unpack('>H', d[14:16])[0]; pl = d[16:]
    elif linktype == 276: proto = struct.unpack('>H', d[0:2])[0]; pl = d[20:]
    elif linktype in (101, 12): proto = 0x0800 if d[0] >> 4 == 4 else 0x86dd; pl = d
    else: sys.exit(f'linktype {linktype} unsupported')
    if proto == 0x0800:
        ihl = (pl[0] & 0xf) * 4; l4 = pl[9]; src = str(ipaddress.IPv4Address(pl[12:16])); dst = str(ipaddress.IPv4Address(pl[16:20])); seg = pl[ihl:]
    elif proto == 0x86dd:
        l4 = pl[6]; src = str(ipaddress.IPv6Address(pl[8:24])); dst = str(ipaddress.IPv6Address(pl[24:40])); seg = pl[40:]
    else: continue
    if l4 not in (6, 17) or len(seg) < 8: continue
    sp, dp = struct.unpack('>HH', seg[:4])
    if l4 == 17:
        if 53 in (sp, dp): parse_dns(seg[8:], ip2name, qnames); continue
        payload = seg[8:]; flags = None
    else:
        off = (seg[12] >> 4) * 4; flags = seg[13]; payload = seg[off:]
    if is_local(dst) or is_local(src) and not is_local(dst) is False: pass
    if is_local(dst): continue
    key = dst
    e = dests.setdefault(key, {'first': datetime.datetime.fromtimestamp(ts).strftime('%H:%M:%S'), 'ports': set(), 'sni': set(), 'pkts': 0})
    e['ports'].add(('tcp' if l4 == 6 else 'udp') + f'/{dp}'); e['pkts'] += 1
    if l4 == 6 and payload:
        s = sni(payload)
        if s: e['sni'].add(s)
print(f'# {path}  linktype={linktype}')
names = set()
for ip, e in dests.items():
    nm = sorted(e['sni'] | ip2name.get(ip, set()))
    names.update(nm or [f'(no-name){ip}'])
    print(f"{e['first']}  {ip:<40} {','.join(sorted(e['ports'])):<16} pkts={e['pkts']:<5} {' '.join(nm) or '(no DNS/SNI name)'}")
print('# DNS qnames asked:', ' '.join(sorted(qnames)))
print('# DEST-NAMES:', ' '.join(sorted(names)))
