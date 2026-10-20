#!/bin/bash
# Camoufox self-build stages. Runs INSIDE the container as the unprivileged user builder.
# Container view:  /src (ro) = the git repo        /work/camoufox = build tree (repo copy without .git + artifacts)
#                  /work/{mozbuild,ccache,dist}     /opt/ks (ro) = this directory
# usage: ks-build.sh prepare|build|package|all|sync|kspatch|snapshot|newpatch
#   kspatch   make the ks patch stack in the tree equal patches/ks/zz-ks-*.patch (quilt-like, incremental; `build`
#             runs it first). State per tree in /work/camoufox/.ks-state/<srcdir>/ (applied.list + copies).
#   snapshot  kspatch, then commit the whole tree (minus obj-*) into a shadow git repo OUTSIDE the tree
#             (/work/camoufox/.ks-git/<srcdir>.git, tag ks-base). No .git inside the Firefox tree, so mach's
#             VCS detection (source-repo.h -> buildconfig/AppConstants) is unaffected.
#   newpatch  overlay /src/.ks-edit/** onto the tree, `git diff ks-base` -> /work/dist/ks-newpatch/new.patch and
#             check it applies cleanly (fuzz 0 onto ks-base, reverse onto the tree). Driven by ks/new-patch.sh.
set -eo pipefail
. "$HOME/.cargo/env"
export CCACHE_DIR=/work/ccache
export BUILD_TARGET=linux,x86_64
# MOZBUILD_STATE_PATH is NOT exported: mach records it in MOZ_CONFIGURE_OPTIONS (about:buildconfig) and the
# official build does not set it; the default (~/.mozbuild -> /work/mozbuild) is the same directory.
export CARGO_BUILD_JOBS=${CARGO_BUILD_JOBS:-6}
TAG=${KS_TAG:-v156.0.1-beta.36}
J=${KS_JOBS:-12}
ts(){ echo "@@KS $(date '+%F %T') [$1] $2"; }
cd /work/camoufox

sync() {
  # repo -> build tree. Build artifacts are excluded, so --delete never touches them.
  rsync -a --delete --exclude /.git --exclude '/camoufox-*/' --exclude '/firefox-*' --exclude '/bundle/fonts*' \
        --exclude '/bundle/langpacks/' --exclude '/dist/' --exclude '__pycache__/' --exclude '/camoufox-*.zip' \
        --exclude '/.ks-venv/' --exclude 'node_modules/' --exclude '/.ci-work/' --exclude '*.egg-info/' \
        --exclude '/.ks-state/' --exclude '/.ks-git/' --exclude '/.ks-edit/' /src/ /work/camoufox/
  python3 -m ci.release set-build --tag "$TAG"     # release number from the tag (working tree only)
  . ./upstream.sh; SRC=camoufox-${version}-${release}
  KST=/work/camoufox/.ks-state/$SRC; KSGIT=/work/camoufox/.ks-git/$SRC.git
  ts sync "src_digest=$(python3 -c 'from pathlib import Path; from ci.browser_inputs import source_digest as d; print(d(Path("/src")))') tag=$TAG rustc=$(rustc --version | cut -d' ' -f2)"
}
prepare() {
  ccache -M 20G >/dev/null
  ts fonts start;      make fonts-extract;  python3 scripts/verify-fonts.py; ts fonts end
  ts fetch start;      rm -rf "$KST" "$KSGIT"; make setup-minimal;  ts fetch end   # FF tarball -> fresh tree
  ts patch start;      make dir;            ts patch end      # apply patches/**/*.patch incl. patches/ks (fails on any .rej)
  ks_record_all                                               # scripts/patch.py applied the ks stack too
  ts bootstrap start;  make mozbootstrap;   ts bootstrap end  # Taskcluster toolchains -> ~/.mozbuild
}
build() {
  kspatch
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
# ---- ks patch stack (patches/ks/zz-ks-NNN-*.patch, applied after every upstream patch) ----
# Same patch(1) flags as scripts/patch.py, plus no .orig litter.
PFLAGS=(-p1 -l --binary --no-backup-if-mismatch)
ks_want() { ( cd /work/camoufox/patches/ks 2>/dev/null && ls -1 zz-ks-*.patch 2>/dev/null | LC_ALL=C sort ) || true; }
ks_body() { awk 'f || /^(diff |--- )/ { f = 1; print }' "$1"; }   # the diff without its KS-* header
ks_record_all() {
  rm -rf "$KST"; mkdir -p "$KST/applied"; : > "$KST/applied.list"
  local n; for n in $(ks_want); do cp "patches/ks/$n" "$KST/applied/$n"; echo "$n" >> "$KST/applied.list"; done
  ts kspatch "recorded after make dir: $(paste -sd' ' "$KST/applied.list")"
}
kspatch() {
  local T=/work/camoufox/$SRC n p i j how
  [ -f "$T/_READY" ] || { echo "no prepared tree $T: run prepare first"; return 1; }
  mkdir -p "$KST/applied"; touch "$KST/applied.list"
  local -a want have; mapfile -t want < <(ks_want); mapfile -t have < "$KST/applied.list"
  i=0   # longest common prefix (same name AND same diff body; header-only edits just refresh the copy) stays
  while [ $i -lt ${#have[@]} ] && [ $i -lt ${#want[@]} ] && [ "${have[$i]}" = "${want[$i]}" ] \
        && cmp -s <(ks_body "$KST/applied/${have[$i]}") <(ks_body "patches/ks/${want[$i]}"); do
    cp "patches/ks/${want[$i]}" "$KST/applied/${want[$i]}"; i=$((i+1)); done
  for ((j=${#have[@]}-1; j>=i; j--)); do          # pop what changed / was removed, newest first
    p=$KST/applied/${have[$j]}
    ( cd "$T" && patch "${PFLAGS[@]}" -R -f --dry-run -s -i "$p" </dev/null ) \
      || { ts kspatch "FAIL cannot un-apply ${have[$j]} (tree changed underneath; re-run prepare)"; return 1; }
    ( cd "$T" && patch "${PFLAGS[@]}" -R -f -s -i "$p" </dev/null )
    rm -f "$p"; sed -i '$d' "$KST/applied.list"; ts kspatch "un-applied ${have[$j]}"
  done
  for ((j=i; j<${#want[@]}; j++)); do              # push the rest, in order
    n=${want[$j]}; p=/work/camoufox/patches/ks/$n
    if ( cd "$T" && patch "${PFLAGS[@]}" --forward --dry-run -i "$p" </dev/null > /tmp/kspatch.out 2>&1 ); then
      ( cd "$T" && patch "${PFLAGS[@]}" --forward -i "$p" </dev/null ); how=applied
    elif ( cd "$T" && patch "${PFLAGS[@]}" -R -f --dry-run -s -i "$p" </dev/null >/dev/null 2>&1 ); then
      how="already in tree (new-patch.sh)"
    else cat /tmp/kspatch.out; ts kspatch "FAIL $n does not apply"; return 1; fi
    cp "$p" "$KST/applied/$n"; echo "$n" >> "$KST/applied.list"; ts kspatch "$how: $n"
  done
  ts kspatch "stack=[$(paste -sd' ' "$KST/applied.list")]"
}
g() { git --git-dir="$KSGIT" --work-tree="/work/camoufox/$SRC" -c user.name=ks -c user.email=ks@localhost \
          -c core.looseCompression=1 -c gc.auto=0 -c advice.detachedHead=false "$@"; }
snapshot() {
  kspatch
  if [ ! -d "$KSGIT" ]; then
    ts snapshot "init shadow repo $KSGIT"
    mkdir -p "$(dirname "$KSGIT")"; git init -q --bare "$KSGIT"; git --git-dir="$KSGIT" config core.bare false
    printf '%s\n' '/obj-*/' '/_READY' '/mozconfig' '/mozconfig.*' '*.orig' '*.rej' '__pycache__/' > "$KSGIT/info/exclude"
    echo '* -text' > "$KSGIT/info/attributes"     # byte-exact: no CRLF normalisation from the tree's .gitattributes
  fi
  ts snapshot "git add (first time: whole tree, later: changed files only)"
  g add -A
  g commit -q --allow-empty --no-verify -m "tree after: $(paste -sd' ' "$KST/applied.list")"
  g tag -f ks-base >/dev/null; ts snapshot "ks-base=$(g rev-parse --short HEAD) files=$(g ls-files | wc -l)"
}
newpatch() {
  local T=/work/camoufox/$SRC O=/work/dist/ks-newpatch f n
  [ -d "$KSGIT" ] || { echo "no shadow repo: run 'ks/new-patch.sh begin' first"; return 1; }
  rm -rf "$O"; mkdir -p "$O"
  if [ -d /src/.ks-edit ]; then        # files edited on the host (ks/new-patch.sh edit <path>)
    ( cd /src/.ks-edit && find . -type f -printf '%P\n' ) | while IFS= read -r f; do
      mkdir -p "$(dirname "$T/$f")"; cat "/src/.ks-edit/$f" > "$T/$f"; echo "overlay $f"; done
  fi
  g add -A
  g diff --cached --no-color --no-ext-diff --no-renames --stat ks-base | tee "$O/stat.txt"
  g diff --cached --no-color --no-ext-diff --no-renames ks-base > "$O/new.patch"
  [ -s "$O/new.patch" ] || { echo "no change against ks-base"; return 3; }
  grep -q '^GIT binary patch' "$O/new.patch" && { echo "binary change: GNU patch (scripts/patch.py) cannot apply it"; return 4; }
  # clean-apply check 1: forward onto ks-base (the tree before the edit), fuzz 0, GNU patch like scripts/patch.py
  mkdir -p "$O/base"
  g diff --cached --no-renames --name-only --diff-filter=MD ks-base > "$O/files.txt"
  [ -s "$O/files.txt" ] && g archive ks-base -- $(cat "$O/files.txt") | tar -x -C "$O/base"
  local rc1=0 rc2=0
  ( cd "$O/base" && patch "${PFLAGS[@]}" --forward --fuzz=0 --dry-run -i "$O/new.patch" </dev/null ) > "$O/check-forward.txt" 2>&1 || rc1=$?
  # clean-apply check 2: the patch reverses cleanly on the edited tree (tree == ks-base + patch)
  ( cd "$T" && patch "${PFLAGS[@]}" -R -f --fuzz=0 --dry-run -i "$O/new.patch" </dev/null ) > "$O/check-reverse.txt" 2>&1 || rc2=$?
  cat "$O/check-forward.txt" "$O/check-reverse.txt"
  if [ $rc1 -ne 0 ] || [ $rc2 -ne 0 ] || grep -Eiq 'offset|fuzz|FAILED|reject|malformed|Only garbage' "$O/check-forward.txt" "$O/check-reverse.txt"; then
    echo "NOT CLEAN (forward rc=$rc1, reverse rc=$rc2)"; return 5; fi
  rm -rf "$O/base"; echo "CLEAN: applies onto ks-base with fuzz 0 and reverses on the tree"
}
sync
case "${1:-all}" in
  sync) ;; prepare) prepare ;; build) build ;; package) package ;;
  kspatch) kspatch ;; snapshot) snapshot ;; newpatch) newpatch ;;
  all) prepare; build; package ;;
  *) echo "usage: $0 prepare|build|package|all|sync|kspatch|snapshot|newpatch"; exit 2 ;;
esac
