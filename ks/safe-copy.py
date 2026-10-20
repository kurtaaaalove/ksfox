#!/usr/bin/env python3
"""Copy ONE regular file out of a container-writable tree onto the host without following symlinks.
usage: safe-copy.py <trusted-root> <relpath> <dest>
<trusted-root> must not be writable by the container (e.g. $B/work: the container only sees work/<subdir> binds).
Every component of <relpath> is opened relative to its parent with O_NOFOLLOW (directories with O_DIRECTORY), so a
symlink anywhere in the path -- planted before or swapped in during the copy -- is refused instead of read.
Exit 2 = the file does not exist (ENOENT), 1 = refused."""
import errno, os, stat, sys, tempfile
root, rel, dest = sys.argv[1:4]
parts = rel.split('/')
if rel.startswith('/') or any(p in ('', '.', '..') for p in parts): sys.exit(f'refusing path {rel!r}')
NF = os.O_NOFOLLOW | os.O_CLOEXEC
try:
    fd = os.open(root, os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC)
    for p in parts[:-1]:
        nfd = os.open(p, os.O_RDONLY | os.O_DIRECTORY | NF, dir_fd=fd); os.close(fd); fd = nfd
    f = os.open(parts[-1], os.O_RDONLY | NF | os.O_NONBLOCK, dir_fd=fd)
except OSError as e:
    if e.errno == errno.ENOENT: print(f'{rel}: does not exist', file=sys.stderr); sys.exit(2)
    sys.exit(f'refusing {rel!r}: {e.strerror} (symlink or not a directory in the path?)')
st = os.fstat(f)
if not stat.S_ISREG(st.st_mode): sys.exit(f'refusing {rel!r}: not a regular file')
if st.st_size > 64 << 20: sys.exit(f'refusing {rel!r}: larger than 64 MB')
d = os.path.dirname(os.path.abspath(dest)); os.makedirs(d, exist_ok=True)
tfd, tmp = tempfile.mkstemp(dir=d, prefix='.safe-copy.')
with os.fdopen(tfd, 'wb') as w, os.fdopen(f, 'rb') as r:
    while True:
        b = r.read(1 << 20)
        if not b: break
        w.write(b)
os.chmod(tmp, 0o644); os.replace(tmp, dest)
