#!/bin/bash
# Camoufox self-build stages. Runs INSIDE the nspawn container as user builder.
# usage: ks-build.sh prepare|build|package|all
set -eo pipefail
. "$HOME/.cargo/env"
export CCACHE_DIR=/work/ccache
export BUILD_TARGET=linux,x86_64
export MOZBUILD_STATE_PATH=$HOME/.mozbuild
export CARGO_BUILD_JOBS=${CARGO_BUILD_JOBS:-6}
TAG=${KS_TAG:-v156.0.1-beta.36}
J=$(cat /work/state/jobs 2>/dev/null || echo 12)
cd /work/camoufox
. ./upstream.sh 2>/dev/null || true
SRC=camoufox-${version}-${release}
ts(){ echo "$(date '+%F %T') [$1] $2" | tee -a /work/logs/00-timeline.log; }

prepare() {
  ts prepare "set-build $TAG"; python3 -m ci.release set-build --tag "$TAG"
  . ./upstream.sh; SRC=camoufox-${version}-${release}
  ccache -M 20G >/dev/null
  ts fonts start;      make fonts-extract;  python3 scripts/verify-fonts.py; ts fonts end
  ts fetch start;      make setup-minimal;  ts fetch end      # download FF source tarball + extract + additions
  ts patch start;      make dir;            ts patch end      # apply patches/*.patch (fails on any .rej)
  ts bootstrap start;  make mozbootstrap;   ts bootstrap end  # mach bootstrap (Taskcluster toolchains -> ~/.mozbuild)
}
build() {
  ts build "start -j$J CARGO_BUILD_JOBS=$CARGO_BUILD_JOBS"
  python3 -c 'import multibuild; multibuild.setup_linux_sysroots()'
  make set-target
  make unbusy
  ( cd "$SRC" && ./mach build -j"$J" )
  ts build end; ccache -s | head -20 || true
}
package() {
  ts package start
  make package-linux arch=x86_64
  mkdir -p /work/dist && mv -v camoufox-*-lin.x86_64.zip /work/dist/
  ts package end
}
case "${1:-all}" in
  prepare) prepare ;; build) build ;; package) package ;;
  all) prepare; build; package ;;
  *) echo "usage: $0 prepare|build|package|all"; exit 2 ;;
esac
