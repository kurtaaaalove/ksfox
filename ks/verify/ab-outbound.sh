#!/bin/bash
# Runs ON THE VM. usage: ab-outbound.sh <label> <bundleDir>   -> ~/camoufox-selfbuild-verify/ab/<label>.{pcap,ss}
set -uo pipefail
L=$1; D=$2; O=~/camoufox-selfbuild-verify/ab; mkdir -p $O; rm -f $O/$L.*
sudo timeout 110 tcpdump -i any -nn -U -w $O/$L.pcap 'not port 22' 2>/dev/null &
( end=$((SECONDS+110)); while [ $SECONDS -lt $end ]; do echo "== $(date +%T.%N)"; sudo ss -tunap 2>/dev/null | grep -v '127.0.0';
    for p in $(pgrep -f camoufox-bin); do echo "PID $p $(sudo readlink /proc/$p/exe 2>/dev/null)"; done; sleep 0.5; done ) > $O/$L.ss 2>&1 &
sleep 2
FP_EXTRA_PREFS="{\"media.gmp.log.dump\":true,\"media.gmp.log.level\":\"All\",\"browser.dom.window.dump.enabled\":true,\"browser.dom.window.dump.file\":\"$O/$L.gmp.log\"}" node ~/camoufox-selfbuild-verify/ab-launch.mjs "$D" 95 :178
wait; sudo chown $(id -u):$(id -g) $O/$L.*
