#!/bin/bash
# Runs INSIDE the container as (user-namespaced) root, once: apt sources, every package the build and the
# build-tester need, and the unprivileged builder user. Nothing after this step needs root, so builder gets
# NO sudo rights.
set -euxo pipefail
cat > /etc/apt/sources.list <<'SRC'
deb http://tw.archive.ubuntu.com/ubuntu noble main restricted universe
deb http://tw.archive.ubuntu.com/ubuntu noble-updates main restricted universe
deb http://tw.archive.ubuntu.com/ubuntu noble-security main restricted universe
SRC
export DEBIAN_FRONTEND=noninteractive
apt-get update
# Dockerfile + release.yml build-browser deps; clang-18/lld-18 = CI "Set up LLVM"; watchman = what
# `mach bootstrap` would otherwise sudo-install
apt-get install -y --no-install-recommends \
  build-essential make msitools wget unzip rustc \
  python3 python3-dev python3-pip python3-venv \
  git p7zip-full aria2 curl rsync ccache libsqlite3-dev ca-certificates \
  fontconfig xz-utils zstd patch file less procps time tzdata \
  clang-18 lld-18 llvm-18 m4 nasm yasm pkg-config watchman
# build-tester runtime (.github/actions/prepare-browser) + Node for its esbuild bundle
apt-get install -y --no-install-recommends \
  xvfb xauth libgtk-3-0 libasound2t64 libdbus-glib-1-2 libx11-xcb1 libxcb-shm0 libxcomposite1 libxcursor1 \
  libxdamage1 libxfixes3 libxi6 libxrandr2 libxtst6 libpci3 nodejs npm
update-alternatives --install /usr/bin/ld.lld ld.lld /usr/bin/ld.lld-18 100 || true
sed -i 's/^# *en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen && locale-gen
getent group 1000 >/dev/null || groupadd -g 1000 builder
id builder >/dev/null 2>&1 || useradd -m -u 1000 -g 1000 -s /bin/bash builder
rm -f /etc/sudoers.d/builder          # no sudo for the build user
echo cfbuild > /etc/hostname
