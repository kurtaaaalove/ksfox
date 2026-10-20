#!/bin/bash
# ks/pipeline.sh -- one key for a ks/main change: ks patch stack -> incremental build -> package -> verify ->
# deploy to the crawler VM staging instance (:9376) -> check it there. Stops at the first failing step.
#
#   ks/pipeline.sh                    all steps
#   ks/pipeline.sh --from <step>      resume (state lives in $B/pipeline/)
#   ks/pipeline.sh --only <step>      one step
#   ks/pipeline.sh --no-deploy        stop after the verification steps
# steps: build package bundle buildtester stage fingerprint outbound deploy vmcheck
#
#   build        kspatch (patches/ks stack) + incremental `mach build`, BuildID pinned to the official one
#   package      make package-linux -> work/dist/ks-main-<ver>-<stamp>.zip (+ unpacked bundle-ks for build-tester)
#   bundle       bundle-diff.sh + bundle-check.py vs the official zip (file list, configs, fonts, omni.ja, BuildID, ELF)
#   buildtester  upstream build-tester (8 profiles) in the container; grade/score/failure set == official
#   stage        rsync the bundle to VM ~/camoufox-selfbuild-candidate (+ pristine official ref, test scripts)
#   fingerprint  fp-compare.mjs: ONE camoufox-js config, official/candidate x2, canvas randomisation off; 86 fields
#   outbound     180 s tcpdump+ss cold-start probe of the candidate; destinations vs the official baseline
#   deploy       VM: keep ~/camoufox-selfbuild-prev, swap candidate in, restart camofox-selfbuild, /health
#   vmcheck      from ksic via camofox-ks01-self: health/open/shot/snap/click/js/close; deployed files == candidate;
#                KS-Runtime-Check pages (e.g. about:buildconfig marker) through Playwright on the VM
# Rollback on the VM: rsync -a --delete ~/camoufox-selfbuild-prev/ ~/camoufox-selfbuild/ && sudo systemctl restart camofox-selfbuild
# Never touches :9377 (official, crawld) or :9378 (ksfox).
set -uo pipefail
B=${B:-/home/kurt/camoufox-build}; REPO=$(cd "$(dirname "$0")/.." && pwd); KV=$REPO/ks/verify
CFRUN=${CFRUN:-$B/bin/cfrun}; VM=${KS_VM:-crawler}; HELPER=${KS_HELPER:-$HOME/bin/camofox-ks01-self}
export KS_TAG=${KS_TAG:-v156.0.1-beta.36}; VR=${KS_TAG#v}; V=${VR%-*}; R=${VR#*-}
OFFZIP=${KS_OFFICIAL_ZIP:-$B/official/camoufox-$VR-lin.x86_64.zip}
BASELINE=${KS_OUTBOUND_BASELINE:-$KV/outbound-baseline-${V%%.*}.txt}
PROBE_SECS=${KS_PROBE_SECS:-180}
P=$B/pipeline; mkdir -p "$P"; RUN=$B/runs/pipeline-$(date +%Y%m%d-%H%M%S); mkdir -p "$RUN"
export KS_BUILD_DATE=${KS_BUILD_DATE:-$(unzip -p "$OFFZIP" application.ini | sed -n 's/^BuildID=//p' | tr -d '\r')}
STEPS=(build package bundle buildtester stage fingerprint outbound deploy vmcheck)
FROM=build; ONLY=; NODEPLOY=
while [ $# -gt 0 ]; do case $1 in
  --from) FROM=$2; shift ;; --only) ONLY=$2; shift ;; --no-deploy) NODEPLOY=1 ;;
  *) sed -n '2,25p' "$0"; exit 2 ;; esac; shift; done
exec 9>"$P/.lock"; flock -n 9 || { echo "another pipeline run holds $P/.lock"; exit 1; }

cflog() { # copy the part of /var/log/cfbuild/<unit>.log written since offset $2 into $3
  tail -c +$(( $2 + 1 )) "/var/log/cfbuild/$1.log" > "$3" 2>/dev/null; grep -a '@@KS' "$3" | sed 's/^/  /'; }
vm_fixture_up() { ssh "$VM" 'V=~/camoufox-selfbuild-verify; curl -sf -m 2 http://127.0.0.1:9395/fp.html -o /dev/null && exit 0
  ss -ltn | grep -q "127.0.0.1:9395 " && { echo "port 9395 busy with something else"; exit 1; }
  cd $V/www && setsid nohup python3 -m http.server 9395 --bind 127.0.0.1 > $V/http.log 2>&1 < /dev/null & echo $! > $V/http.pid
  sleep 1; curl -sf -m 2 http://127.0.0.1:9395/fp.html -o /dev/null'; }
vm_fixture_down() { ssh "$VM" 'f=~/camoufox-selfbuild-verify/http.pid; [ -f $f ] && kill $(cat $f) 2>/dev/null; rm -f $f' >/dev/null 2>&1; }
vm_display() { ssh "$VM" 'for d in $(seq 177 199); do [ -e /tmp/.X$d-lock ] || { echo :$d; exit; }; done'; }

step_build() {
  local o; o=$(stat -c %s /var/log/cfbuild/cfbuild-build.log 2>/dev/null || echo 0)
  echo "KS_BUILD_DATE=$KS_BUILD_DATE  stack: $(cd "$REPO/patches/ks" 2>/dev/null && ls zz-ks-*.patch 2>/dev/null | paste -sd' ')"
  CFWAIT=1 "$CFRUN" build; local rc=$?; cflog cfbuild-build "$o" "$RUN/cfbuild-build.log"; return $rc; }
step_package() {
  local o rc z; o=$(stat -c %s /var/log/cfbuild/cfbuild-package.log 2>/dev/null || echo 0)
  CFWAIT=1 "$CFRUN" package; rc=$?; cflog cfbuild-package "$o" "$RUN/cfbuild-package.log"; [ $rc -eq 0 ] || return $rc
  z=ks-main-$VR-$(date +%m%d-%H%M).zip
  CFCMD="set -e; cd /work/dist; mv camoufox-$VR-lin.x86_64.zip $z; ls -1t ks-main-*.zip | tail -n +3 | xargs -r rm -v
         rm -rf bundle-ks; mkdir bundle-ks; cd bundle-ks; LANG=C.UTF-8 unzip -q ../$z || [ \$? -le 1 ]" "$CFRUN" shell || return 1
  echo "$z" > "$P/last-zip"; ls -la "$B/work/dist/$z"; }
step_bundle() {
  local zip=$B/work/dist/$(cat "$P/last-zip")
  [ -d "$P/self" ] && { rm -rf "$P/prev"; mv "$P/self" "$P/prev"; }
  bash "$KV/bundle-diff.sh" "$OFFZIP" "$zip" "$P" > "$RUN/bundle-diff.txt" 2>&1
  grep -E 'IDENTICAL|DIFF |omni.ja:' "$RUN/bundle-diff.txt" | sed 's/^/  /'
  for d in off self; do echo "{\"version\":\"$V\",\"release\":\"$R\"}" > "$P/$d/version.json"; done
  python3 "$KV/bundle-check.py" "$P/off" "$P/self" "$REPO/patches/ks" --prev "$P/prev" --buildid "$KS_BUILD_DATE"; }
step_buildtester() {
  CFCMD="/opt/ks/build-tester.sh ks /work/dist/bundle-ks" "$CFRUN" shell > "$RUN/build-tester.log" 2>&1
  grep -E 'OVERALL|exit=' "$RUN/build-tester.log" | sed 's/^/  /'
  python3 "$KV/bt-compare.py" "$B/work/dist/bt-official/build-tester-result.json" "$B/work/dist/bt-ks/build-tester-result.json"; }
step_stage() {
  ssh "$VM" 'mkdir -p ~/camoufox-selfbuild-verify/www ~/camoufox-selfbuild-verify/probe
    [ -d ~/camoufox-selfbuild-candidate ] || cp -a ~/camoufox-selfbuild ~/camoufox-selfbuild-candidate
    [ -d ~/camoufox-official-ref ] || cp -a ~/.cache/camoufox ~/camoufox-official-ref' || return 1
  rsync -a --delete --stats "$P/self/" "$VM:camoufox-selfbuild-candidate/" > "$RUN/rsync-candidate.txt" || return 1
  grep -E 'Total transferred file size|Literal data|Total file size' "$RUN/rsync-candidate.txt" | sed 's/^/  /'
  rsync -a --delete --checksum "$P/off/" "$VM:camoufox-official-ref/" || return 1      # pristine official, not ~/.cache
  rsync -a "$KV/fp-compare.mjs" "$KV/ab-launch.mjs" "$KV/outbound-probe.sh" "$KV/runtime-check.mjs" "$VM:camoufox-selfbuild-verify/" &&
  rsync -a "$KV/fp.html" "$VM:camoufox-selfbuild-verify/www/"; }
step_fingerprint() {
  vm_fixture_up || return 1; local d; d=$(vm_display)
  ssh "$VM" "cd ~/camoufox-selfbuild-verify && rm -rf fp-ks && FP_EXTRA_PREFS='{\"privacy.fingerprintingProtection\":false,\"privacy.baselineFingerprintingProtection\":false}' \
    node fp-compare.mjs fp-ks ~/camoufox-official-ref ~/camoufox-selfbuild-candidate http://127.0.0.1:9395/fp.html $d" || return 1
  rsync -a "$VM:camoufox-selfbuild-verify/fp-ks/" "$RUN/fp-ks/" && python3 "$KV/fp-check.py" "$RUN/fp-ks" "$REPO/patches/ks"; }
step_outbound() {
  ssh "$VM" "bash ~/camoufox-selfbuild-verify/outbound-probe.sh self-ks ~/camoufox-selfbuild-candidate $PROBE_SECS" || return 1
  rsync -a "$VM:camoufox-selfbuild-verify/probe/self-ks.*" "$RUN/" && python3 "$KV/outbound-check.py" "$RUN/self-ks.pcap" "$RUN/self-ks.ss" "$BASELINE"; }
step_deploy() {
  ssh "$VM" 'set -e
    rsync -a --delete ~/camoufox-selfbuild/ ~/camoufox-selfbuild-prev/
    rsync -a --delete ~/camoufox-selfbuild-candidate/ ~/camoufox-selfbuild/
    rm -f ~/camofox-selfbuild-svc/home/.cache/camoufox/{version.json,properties.json,fontconfig,camoufox-bin}
    sudo systemctl restart camofox-selfbuild
    for i in $(seq 40); do curl -sf -m 2 127.0.0.1:9376/health | grep -q "\"ok\":true" && break; sleep 1; done
    systemctl is-active camofox-selfbuild; curl -s -m 5 127.0.0.1:9376/health; echo'; }
step_vmcheck() {
  vm_fixture_up || return 1
  local u=ks-pipeline-$$ t out rc=0 d c
  export CAMOFOX_SHOT_DIR=$RUN/shots CAMOFOX_TIMEOUT=60
  chk() { local n=$1; shift; out=$("$@" 2>&1); local r=$?; printf '  %-6s rc=%s %s\n' "$n" $r "$(echo "$out" | tr '\n' ' ' | cut -c1-150)"
          echo "$out" > "$RUN/vm-$n.txt"; [ $r -eq 0 ] || rc=1; }
  chk health "$HELPER" health
  chk open   "$HELPER" open $u http://127.0.0.1:9395/fp.html; t=$(sed -n 's/^tabId=//p' "$RUN/vm-open.txt")
  chk shot   "$HELPER" shot $u "$t"
  chk snap   "$HELPER" snap $u "$t"
  chk click  "$HELPER" click $u "$t" '#btn'
  chk js     "$HELPER" js $u "$t" "document.getElementById('clicked').textContent + ' | ' + navigator.userAgent"
  chk open2  "$HELPER" open $u https://example.com/
  chk close  "$HELPER" close $u
  grep -q 'yes' "$RUN/vm-js.txt" || { echo "  js/click result unexpected"; rc=1; }
  echo "  deployed files vs verified candidate:"
  ( cd "$P/self" && sha256sum camoufox-bin libxul.so omni.ja browser/omni.ja application.ini ) > "$RUN/sha-local.txt"
  ssh "$VM" 'cd ~/camoufox-selfbuild && sha256sum camoufox-bin libxul.so omni.ja browser/omni.ja application.ini' > "$RUN/sha-vm.txt"
  if diff -q "$RUN/sha-local.txt" "$RUN/sha-vm.txt" >/dev/null; then echo "    sha256 identical (5 files)"; else echo "    MISMATCH"; rc=1; fi
  ssh "$VM" 'for p in $(pgrep -u crawler -f camofox-selfbuild-svc 2>/dev/null) $(pgrep -f "camoufox-selfbuild/camoufox-bin"); do readlink /proc/$p/exe; done | sort | uniq -c | sed "s/^/    running: /"'
  c=$(sed -n 's/^KS-Runtime-Check:[[:space:]]*//p' "$REPO"/patches/ks/zz-ks-*.patch 2>/dev/null | tr '\n' ' ')
  if [ -n "$c" ]; then d=$(vm_display); echo "  runtime checks: $c"
    ssh "$VM" "cd ~/camoufox-selfbuild-verify && node runtime-check.mjs ~/camoufox-selfbuild $d $c" | sed 's/^/    /'; [ ${PIPESTATUS[0]} -eq 0 ] || rc=1; fi
  return $rc; }

trap vm_fixture_down EXIT
started=; total0=$(date +%s)
printf '%-12s %8s  %s\n' step seconds result > "$RUN/summary.txt"
for s in "${STEPS[@]}"; do
  [ "$s" = "$FROM" ] && started=1; [ -n "$started" ] || continue
  [ -n "$ONLY" ] && [ "$s" != "$ONLY" ] && continue
  [ -n "$NODEPLOY" ] && [[ $s == deploy || $s == vmcheck ]] && continue
  echo "=== [$s] $(date '+%F %T')"; t0=$(date +%s)
  "step_$s" 2>&1 | tee "$RUN/$s.out"; rc=${PIPESTATUS[0]}; dt=$(( $(date +%s) - t0 ))
  printf '%-12s %8s  %s\n' "$s" "$dt" "$([ $rc -eq 0 ] && echo ok || echo "FAILED rc=$rc")" >> "$RUN/summary.txt"
  if [ $rc -ne 0 ]; then cat "$RUN/summary.txt"; echo "PIPELINE STOPPED at step '$s' (rc=$rc). Log: $RUN/$s.out"; exit 1; fi
done
printf '%-12s %8s\n' total $(( $(date +%s) - total0 )) >> "$RUN/summary.txt"
cat "$RUN/summary.txt"; echo "PIPELINE OK. Logs: $RUN"
