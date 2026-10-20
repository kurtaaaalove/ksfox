#!/bin/bash
# Host-side progress logger for cfbuild-* units. Every 10 min: load, memory, unit state, disk, last log line.
# Load guard: load1 > 20 on two consecutive samples -> CPUQuota 800% on the active unit + state/jobs=8.
B=/home/kurt/camoufox-build; L=$B/logs/progress.log; hi=0
end=$(( $(date +%s) + ${MAXSEC:-18000} ))
while [ ! -f $B/state/stop-progress ] && [ $(date +%s) -lt $end ]; do
  load1=$(cut -d' ' -f1 /proc/loadavg)
  units=$(systemctl list-units 'cfbuild-*' --state=active --no-legend --plain 2>/dev/null | awk '{print $1}' | xargs)
  {
    echo "=== $(date '+%F %T') load=$(cut -d' ' -f1-3 /proc/loadavg) units=[${units}] jobs=$(cat $B/state/jobs)"
    free -h | sed -n 2,3p
    for u in $units; do systemctl show $u -p MemoryCurrent -p CPUUsageNSec | xargs; done
    du -sh $B/camoufox/camoufox-*/obj-* 2>/dev/null; df -h / | tail -1
    for u in $units; do tail -c 2000 $B/logs/$u.log | tr '\r' '\n' | grep -v '^\s*$' | tail -2 | cut -c1-220; done
  } >> $L
  if awk "BEGIN{exit !($load1 > 20)}"; then hi=$((hi+1)); else hi=0; fi
  if [ $hi -ge 2 ] && [ "$(cat $B/state/jobs)" != 8 ]; then
    echo 8 > $B/state/jobs
    for u in $units; do sudo systemctl set-property --runtime $u CPUQuota=800%; done
    echo "!!! $(date '+%F %T') load guard: load1=$load1 twice >20 -> CPUQuota=800%, next build -j8" >> $L
  fi
  sleep ${INTERVAL:-600}
done
