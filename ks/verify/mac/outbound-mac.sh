#!/bin/bash
# 180 s outbound observation of the 9378 test instance WITHOUT sudo (no tcpdump on this Mac):
#  - lsof every 2 s over the browser processes (TMPDIR=$ST/tmp marks them) -> remote IP:port set
#  - MOZ_LOG nsHostResolver (set by run9378.sh) -> host names the browser resolved
# flow inside the window: /start -> open example.com -> screenshot -> close session -> idle until 180 s
# usage: outbound-mac.sh <label>
set -uo pipefail
L=$1; ST=$HOME/engines/ksfox-test-state; O=$ST/out-$L; mkdir -p "$O"; B=http://${KSFOX_TEST_IP:-100.106.157.19}:9378; U=ksout-$L
( end=$((SECONDS+180)); while [ $SECONDS -lt $end ]; do
    R=$(pgrep -f "$ST/tmp" | paste -sd' ' -)
    P=$(ps -A -o pid=,ppid= | awk -v r="$R" 'BEGIN{n=split(r,a," ");for(i=1;i<=n;i++)k[a[i]]=1}{p[NR]=$1;q[NR]=$2}
        END{do{c=0;for(i=1;i<=NR;i++)if(!(p[i] in k)&&(q[i] in k)){k[p[i]]=1;c=1}}while(c);s="";for(x in k)s=s (s?",":"") x;print s}')
    [ -n "$R" ] && lsof -nP -a -p "$P" -i 2>/dev/null | awk 'NR>1{print $1, $8, $9}'
    sleep 2; done ) > "$O/lsof.txt" 2>&1 &
SP=$!
curl -s -m60 -X POST $B/start -H 'content-type: application/json' -d "{\"userId\":\"$U\"}" > "$O/start.json"
curl -s -m60 -X POST $B/tabs/open -H 'content-type: application/json' -d "{\"userId\":\"$U\",\"url\":\"https://example.com/\"}" > "$O/open.json"
T=$(/usr/bin/python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("tabId",""))' "$O/open.json")
curl -s -m60 -o "$O/shot.png" "$B/tabs/$T/screenshot?userId=$U"
curl -s -m60 -X DELETE "$B/sessions/$U" > "$O/close.json"
wait $SP
grep -h -o -E 'Resolving host \[[^]]*\]|host \[[^]]*\]' "$ST"/logs/moz-$L.log* 2>/dev/null | sed -E 's/.*\[([^]]*)\].*/\1/' | tr 'A-Z' 'a-z' | sort | uniq -c | sort -rn > "$O/hosts.txt"
awk '$2 ~ /TCP|UDP/ {print $2, $3}' "$O/lsof.txt" | sed -E 's/^.*->//' | sort | uniq -c | sort -rn > "$O/remotes.txt"
echo "== $L open: $(cut -c1-120 "$O/open.json")"; echo "shot=$(wc -c < "$O/shot.png")B"
echo "== hosts (MOZ_LOG)"; cat "$O/hosts.txt"; echo "== remote endpoints (lsof)"; grep -- '->' "$O/lsof.txt" | awk '{print $3}' | sed 's/.*->//' | sort | uniq -c | sort -rn | head -30
