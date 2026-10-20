#!/bin/bash
# Runs INSIDE the container as builder: rustup + persistent dirs
set -euxo pipefail
ln -sfn /work/mozbuild /home/builder/.mozbuild
if [ ! -x "$HOME/.cargo/bin/rustup" ]; then
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable --profile minimal
fi
. "$HOME/.cargo/env"
rustup target add x86_64-unknown-linux-gnu aarch64-unknown-linux-gnu
rustc --version; cargo --version; python3 --version; clang-18 --version | head -1
cat >> "$HOME/.bashrc" <<'RC'
. "$HOME/.cargo/env"
export CCACHE_DIR=/work/ccache
export BUILD_TARGET=linux,x86_64
RC
