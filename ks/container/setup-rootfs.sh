#!/bin/bash
# Runs INSIDE the nspawn container as root: apt sources, build deps, builder user
set -euxo pipefail
cat > /etc/apt/sources.list <<'SRC'
deb http://tw.archive.ubuntu.com/ubuntu noble main restricted universe
deb http://tw.archive.ubuntu.com/ubuntu noble-updates main restricted universe
deb http://tw.archive.ubuntu.com/ubuntu noble-security main restricted universe
SRC
export DEBIAN_FRONTEND=noninteractive
apt-get update
# Dockerfile + release.yml (build-browser job) deps; clang-18/lld-18 = CI "Set up LLVM"
apt-get install -y --no-install-recommends \
  build-essential make msitools wget unzip rustc \
  python3 python3-dev python3-pip python3-venv \
  git p7zip-full aria2 curl rsync ccache libsqlite3-dev ca-certificates \
  fontconfig xz-utils zstd patch file less procps time tzdata \
  clang-18 lld-18 llvm-18 m4 nasm yasm pkg-config
update-alternatives --install /usr/bin/ld.lld ld.lld /usr/bin/ld.lld-18 100 || true
sed -i 's/^# *en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen && locale-gen
# builder user with the same uid/gid as host kurt so bind-mounted files stay kurt-owned
getent group 1000 >/dev/null || groupadd -g 1000 builder
id builder >/dev/null 2>&1 || useradd -m -u 1000 -g 1000 -s /bin/bash builder
echo 'builder ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/builder; chmod 440 /etc/sudoers.d/builder
echo cfbuild > /etc/hostname
