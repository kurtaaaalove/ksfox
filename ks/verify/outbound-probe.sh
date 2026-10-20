#!/bin/bash
# Runs ON THE VM. Cold-start outbound probe of one bundle: tcpdump + 0.5 s ss sampler for <seconds>+20 while
# ab-launch.mjs starts the bundle with a fresh camoufox-js config/profile, opens example.com and idles.
# usage: outbound-probe.sh <label> <bundleDir> [seconds=180]   -> ~/camoufox-selfbuild-verify/probe/<label>.{pcap,ss,log}
set -uo pipefail
L=$1; D=$2; S=${3:-180}; V=~/camoufox-selfbuild-verify; O=$V/probe; mkdir -p $O; rm -f $O/$L.*
DISP=$(for d in $(seq 178 199); do [ -e /tmp/.X$d-lock ] || { echo :$d; break; }; done)
sudo timeout $((S + 20)) tcpdump -i any -nn -U -w $O/$L.pcap 'not port 22' 2>/dev/null &
( end=$((SECONDS + S + 20)); while [ $SECONDS -lt $end ]; do echo "== $(date +%T.%N)"; sudo ss -tunap 2>/dev/null | grep -v '127.0.0';
    for p in $(pgrep -f camoufox-bin); do echo "PID $p $(sudo readlink /proc/$p/exe 2>/dev/null)"; done; sleep 0.5; done ) > $O/$L.ss 2>&1 &
sleep 2
node $V/ab-launch.mjs "$D" "$S" "$DISP" > $O/$L.log 2>&1; rc=$?
wait; sudo chown $(id -u):$(id -g) $O/$L.*; cat $O/$L.log; exit $rc
