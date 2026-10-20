#!/bin/bash
# Camoufox self-build stages. Runs INSIDE the container as the unprivileged user builder.
# Container view:  /src (ro) = the git repo        /work/camoufox = build tree (repo copy without .git + artifacts)
#                  /work/{mozbuild,ccache,dist}     /opt/ks (ro) = this directory
# usage: ks-build.sh prepare|build|package|all|sync
set -eo pipefail
. "$HOME/.cargo/env"
export CCACHE_DIR=/work/ccache
export BUILD_TARGET=linux,x86_64
export MOZBUILD_STATE_PATH=$HOME/.mozbuild
export CARGO_BUILD_JOBS=${CARGO_BUILD_JOBS:-6}
TAG=${KS_TAG:-v156.0.1-beta.36}
J=${KS_JOBS:-12}
ts(){ echo "@@KS $(date '+%F %T') [$1] $2"; }
cd /work/camoufox

sync() {
  # repo -> build tree. Build artifacts are excluded, so --delete never touches them.
  rsync -a --delete --exclude /.git --exclude '/camoufox-*/' --exclude '/firefox-*' --exclude '/bundle/fonts*' \
        --exclude '/bundle/langpacks/' --exclude '/dist/' --exclude '__pycache__/' --exclude '/camoufox-*.zip' \
        --exclude '/.ks-venv/' --exclude 'node_modules/' --exclude '/.ci-work/' --exclude '*.egg-info/' /src/ /work/camoufox/
  python3 -m ci.release set-build --tag "$TAG"     # release number from the tag (working tree only)
  . ./upstream.sh; SRC=camoufox-${version}-${release}
  ts sync "src_digest=$(python3 -c 'from pathlib import Path; from ci.browser_inputs import source_digest as d; print(d(Path("/src")))') tag=$TAG rustc=$(rustc --version | cut -d' ' -f2)"
}
prepare() {
  ccache -M 20G >/dev/null
  ts fonts start;      make fonts-extract;  python3 scripts/verify-fonts.py; ts fonts end
  ts fetch start;      make setup-minimal;  ts fetch end      # FF source tarball -> extract -> additions
  ts patch start;      make dir;            ts patch end      # apply patches/**/*.patch (fails on any .rej)
  ts bootstrap start;  make mozbootstrap;   ts bootstrap end  # Taskcluster toolchains -> ~/.mozbuild
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
sync
case "${1:-all}" in
  sync) ;; prepare) prepare ;; build) build ;; package) package ;;
  all) prepare; build; package ;;
  *) echo "usage: $0 prepare|build|package|all|sync"; exit 2 ;;
esac
