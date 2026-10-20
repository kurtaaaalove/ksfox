#!/usr/bin/env python3
"""Extract a zip that came out of the build container (untrusted) on the host, refusing anything that could write
outside <dest> or plant a link: absolute names, '..' components, symlinks / any non-regular non-directory member,
duplicate names, names that resolve outside dest. Permissions are clamped to rwx bits (no setuid/setgid/sticky).
usage: safe-unzip.py <zip> <dest>      (dest must not exist yet, or be an empty directory)"""
import os, stat, sys, zipfile
src, dest = sys.argv[1], sys.argv[2]
os.makedirs(dest, exist_ok=True)
if os.listdir(dest): sys.exit(f'refusing: {dest} is not empty')
root = os.path.realpath(dest)
z = zipfile.ZipFile(src)
seen = set()
def die(msg): sys.exit(f'refusing {src}: {msg}')
for i in z.infolist():
    n = i.filename
    if n in seen: die(f'duplicate member {n!r}')
    seen.add(n)
    if n.startswith('/') or '\\' in n or '\0' in n or os.path.isabs(n): die(f'absolute/odd name {n!r}')
    parts = [p for p in n.split('/') if p]
    if any(p in ('.', '..') for p in parts): die(f'dot component in {n!r}')
    mode = (i.external_attr >> 16) & 0xFFFF
    kind = stat.S_IFMT(mode)
    if kind not in (0, stat.S_IFREG, stat.S_IFDIR): die(f'{n!r} is not a regular file or directory (mode {mode:o})')
    target = os.path.realpath(os.path.join(root, *parts))
    if target != root and not target.startswith(root + os.sep): die(f'{n!r} resolves outside {dest}')
for i in z.infolist():
    parts = [p for p in i.filename.split('/') if p]
    out = os.path.join(root, *parts)
    mode = (i.external_attr >> 16) & 0o777
    if i.is_dir():
        os.makedirs(out, exist_ok=True); continue
    os.makedirs(os.path.dirname(out), exist_ok=True)
    if os.path.islink(os.path.dirname(out)) or os.path.lexists(out): sys.exit(f'refusing: {out} exists or parent is a link')
    fd = os.open(out, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, 'wb') as f, z.open(i) as r:
        while True:
            b = r.read(1 << 20)
            if not b: break
            f.write(b)
    os.chmod(out, mode or 0o644)
print(f'extracted {len(z.infolist())} members of {os.path.basename(src)} into {dest}')
