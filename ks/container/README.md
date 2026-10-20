# Build container (systemd-nspawn, no Docker)

Host prerequisites: `systemd-container`, `debootstrap`. Everything lives under one directory `$B`
(default `/home/kurt/camoufox-build`): `rootfs/` (Ubuntu 24.04), `camoufox/` (this repo), `mozbuild/`
(`~/.mozbuild` inside the container: Taskcluster toolchains), `ccache/`, `dist/` (zips), `logs/`, `state/jobs` (-j value).

```bash
# one-time: rootfs + deps + builder user (uid 1000) + rustup
sudo debootstrap --variant=minbase --include=ca-certificates,locales,sudo,dbus,systemd \
     noble $B/rootfs http://archive.ubuntu.com/ubuntu /usr/share/debootstrap/scripts/gutsy
sudo systemd-nspawn -q -D $B/rootfs --resolv-conf=copy-uplink --register=no \
     --bind-ro=$B/camoufox/ks/container:/opt/cfbin /opt/cfbin/setup-rootfs.sh
sudo systemd-nspawn -q -D $B/rootfs --resolv-conf=copy-uplink --register=no --bind=$B:/work \
     --user=builder --chdir=/home/builder --setenv=HOME=/home/builder /work/camoufox/ks/container/setup-builder.sh

# each stage runs in a transient unit: MemoryMax=24G, CPUQuota=1200%, Nice=19, IOSchedulingClass=idle
ks/container/cfrun prepare     # -> unit cfbuild-prepare, log $B/logs/cfbuild-prepare.log
ks/container/cfrun build
ks/container/cfrun package
sudo systemctl stop cfbuild-build   # one-key kill
```

`cfrun` expects `ks-build.sh` at `$B/bin/` (`/work/bin/` in the container); copy the files from this directory there.
