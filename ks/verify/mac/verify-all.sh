#!/bin/bash
# Mac-side verification run (nohup'd): engine setup -> fingerprint A/B -> 9378 with the self-built engine +
# 180 s outbound -> 9378 left up for the ksic smoke test, auto-stopped after 25 min as a safety net.
# usage: verify-all.sh <zip> <sha256>
set -uo pipefail
cd ~/engines/ksfox-verify
V=~/engines/ksfox-verify; Z=$1; SHA=$2
idle() { curl -s -m5 http://127.0.0.1:9377/health | grep -q '"activeTabs":0,"activeSessions":0'; }
waitidle() { for i in $(seq 1 60); do idle && return 0; echo "9377 busy, waiting ($i)"; sleep 30; done; return 1; }
echo "@@ $(date +%T) setup"; ./setup-engine.sh "$Z" "$SHA" || exit 1
pgrep -f 'http.server 9395' >/dev/null || ( exec /usr/bin/python3 -m http.server 9395 --bind 127.0.0.1 ) > http.log 2>&1 < /dev/null &
sleep 1
APP=~/engines/ksfox-156.0.1-beta.36/Camoufox.app
echo "@@ $(date +%T) fp default prefs"; waitidle
rm -rf fp-default fp-nornd
/opt/homebrew/bin/node fp-compare-mac.mjs fp-default "$APP" http://127.0.0.1:9395/fp.html
/usr/bin/python3 -I fp-diff.py fp-default/official-1.json fp-default/official-2.json fp-default/self-1.json fp-default/self-2.json | tail -12
echo "@@ $(date +%T) fp canvas-randomisation off"; waitidle
FP_EXTRA_PREFS='{"privacy.fingerprintingProtection":false,"privacy.baselineFingerprintingProtection":false}' \
  /opt/homebrew/bin/node fp-compare-mac.mjs fp-nornd "$APP" http://127.0.0.1:9395/fp.html
/usr/bin/python3 -I fp-diff.py fp-nornd/official-1.json fp-nornd/official-2.json fp-nornd/self-1.json fp-nornd/self-2.json | tail -12
echo "@@ $(date +%T) 9378 self + outbound"; waitidle
./run9378.sh start self self-a | cut -c1-400
./outbound-mac.sh self-a
echo "@@ $(date +%T) 9378 up for smoke"; ./run9378.sh start self smoke | cut -c1-300
( sleep 1500; ./run9378.sh stop; pkill -f 'http.server 9395' ) > autostop.log 2>&1 < /dev/null &
echo "@@ $(date +%T) done"
