# Build container (systemd-nspawn + user namespace, no Docker)

Host prerequisites: `systemd-container`, `debootstrap` (tested with systemd 249 / Ubuntu 22.04 host).

Layout under `$B` (default `/home/kurt/camoufox-build`):

| Path | Owner | In the container |
|---|---|---|
| `camoufox/` (this git repo) | host user | `/src` **read-only**; `ks/container/` also at `/opt/ks` read-only |
| `rootfs/` (Ubuntu 24.04) | shifted to the userns range (`--private-users=pick`) | `/` |
| `work/camoufox` (repo copy without `.git` + Firefox tree, fonts, obj-*) | container `builder` | `/work/camoufox` rw |
| `work/{mozbuild,ccache,dist}` | container `builder` | `/work/...` rw |
| `/var/log/cfbuild/<unit>.log` | root (written by systemd) | not visible |

Isolation:
- **User namespace**: container root = an unprivileged host uid (`cat /proc/self/uid_map` -> `0 <base> 65536`);
  `builder` (uid 1000 inside) = host uid `<base>+1000`, which owns `work/`.
- `builder` has **no sudo**; every package is installed once by `setup-rootfs.sh`. Units run with `NoNewPrivileges=yes`.
- Only `work/` subdirectories are writable, and `work/` is a host bind mount with `nosuid,nodev` (nspawn 249 has no
  per-bind mount options; the binds inherit the flags). The git repo is read-only inside, so a build script cannot
  plant `.git/hooks` that would later run on the host.
- Logs go to `/var/log/cfbuild/` through systemd, outside the container's view.
- Resource caps per unit: `MemoryMax=24G MemoryHigh=22G MemorySwapMax=0 CPUQuota=1200% CPUWeight=20 Nice=19 IOSchedulingClass=idle`.

```bash
# one-time
sudo debootstrap --variant=minbase --include=ca-certificates,locales,sudo,dbus,systemd \
     noble $B/rootfs http://archive.ubuntu.com/ubuntu /usr/share/debootstrap/scripts/gutsy
sudo systemd-nspawn -q -D $B/rootfs --private-users=pick --private-users-ownership=chown \
     --resolv-conf=copy-uplink --register=no --bind-ro=$B/camoufox/ks/container:/opt/ks /opt/ks/setup-rootfs.sh
mkdir -p $B/work/{camoufox,mozbuild,ccache,dist}
sudo chown -R $(( $(stat -c %u $B/rootfs) + 1000 )):$(( $(stat -c %g $B/rootfs) + 1000 )) $B/work
CFCMD=/opt/ks/setup-builder.sh ks/container/cfrun shell        # rustup as builder

# every build: each stage syncs /src -> /work/camoufox first (artifacts excluded), then runs
ks/container/cfrun prepare     # fonts, Firefox tarball, patches, mach bootstrap   (unit cfbuild-prepare)
ks/container/cfrun build       # ./mach build -j$(cat $B/state/jobs || 12)        (unit cfbuild-build)
ks/container/cfrun package     # make package-linux arch=x86_64 -> work/dist/*.zip
sudo tail -f /var/log/cfbuild/cfbuild-build.log
sudo systemctl stop cfbuild-build                          # one-key kill
CFCMD='id; cat /proc/self/uid_map' ks/container/cfrun shell  # isolation check
```
