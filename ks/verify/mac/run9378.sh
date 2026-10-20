#!/bin/bash
# start|stop the 9378 TEST instance of ~/ksfox (never touches the launchd 9377 one).
# usage: run9378.sh start <self|official> [label]   |   run9378.sh stop
# start: points the test HOME's camoufox cache at the chosen Camoufox.app, MOZ_LOG host resolution to a file.
set -uo pipefail
E=$HOME/engines/ksfox-156.0.1-beta.36; TH=$HOME/engines/ksfox-test-home; ST=$HOME/engines/ksfox-test-state
C=$TH/Library/Caches/camoufox; PIDF=$ST/ksfox.pid
stop() {
  [ -f "$PIDF" ] && kill "$(cat "$PIDF")" 2>/dev/null
  for i in $(seq 1 40); do lsof -nP -iTCP:9378 -sTCP:LISTEN >/dev/null 2>&1 || break; sleep 0.5; done
  # the test instance's browser runs with TMPDIR=$ST/tmp -> its profile path contains $ST; kill leftovers only
  pkill -f "$ST/tmp" 2>/dev/null; rm -f "$PIDF"; echo stopped
}
case "${1:-}" in
  stop) stop ;;
  start)
    stop >/dev/null
    case "$2" in self) APP=$E/Camoufox.app ;; official) APP=$HOME/Library/Caches/camoufox/Camoufox.app ;; *) echo "self|official"; exit 2 ;; esac
    L=${3:-$2}; mkdir -p "$ST/profiles" "$ST/tmp" "$ST/logs" "$C"; ln -sfn "$APP" "$C/Camoufox.app"; echo '{"version":"156.0.1","release":"beta.36"}' > "$C/version.json"
    rm -rf "$ST/tmp/"* "$ST/profiles/"*
    cd "$HOME/ksfox" || exit 1
    ( exec env -i HOME="$TH" PATH=/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin NODE_ENV=production \
        KSFOX_HOST=0.0.0.0 KSFOX_PORT=9378 KSFOX_ALLOWED_HOSTS=100.106.157.19,127.0.0.1,localhost \
        KSFOX_HOME="$ST" KSFOX_PROFILES_DIR="$ST/profiles" KSFOX_LOG="$ST/logs/requests.log" TMPDIR="$ST/tmp/" \
        MOZ_LOG="nsHostResolver:3,timestamp" MOZ_LOG_FILE="$ST/logs/moz-$L.log" \
        /opt/homebrew/bin/node src/server.js ) > "$ST/logs/ksfox-$L.log" 2>&1 < /dev/null &
    echo $! > "$PIDF"
    for i in $(seq 1 40); do curl -s -m2 http://127.0.0.1:9378/health >/dev/null && break; sleep 0.5; done
    curl -s -m5 http://127.0.0.1:9378/health; echo; echo "app=$(readlink "$C/Camoufox.app")" ;;
  *) echo "usage: $0 start <self|official> [label] | stop"; exit 2 ;;
esac
