#!/usr/bin/env bash
# feel.sh <variant> -- untimed duplicate: ping (build host -> guest, 0.2 s), mid-copy mouse move + 'r' type-select, screenshots
set -u; . "$(dirname "$0")/tl_common.sh"
V=$1; D=$T/$V; VM="python3 /media/fat/Scripts/q800tools/vmouse.py"
ping -i 0.2 -c 25 -W 1 10.3.231.233 > $D/ping_idle.txt 2>&1
$S 'kill -USR2 $(pidof MiSTer)'; sleep 1
( ping -D -i 0.2 -c 75 -W 1 10.3.231.233 > $D/ping_copy.txt 2>&1 & )
sleep 1
echo "feel cmd-D $(date +%T.%N | cut -c1-12)" | tee -a $D/log.txt
ws down:56 raw:32 up:56
( sleep 1.5; ws raw:19; echo "typed r $(date +%T.%N | cut -c1-12)" >> $D/log.txt ) &
( $S "$VM m:100,-60"; echo "mouse moved $(date +%T.%N | cut -c1-12)" >> $D/log.txt ) &
sleep 3.3; bash scripts/grab.sh $D/feel_during.png >/dev/null; echo "grab-during done $(date +%T.%N | cut -c1-12)" >> $D/log.txt
wait; sleep 12
sdprof_since_reset > $D/feel_sdprof.txt
bash scripts/grab.sh $D/feel_after.png >/dev/null
tail -4 $D/log.txt; tail -1 $D/ping_idle.txt; tail -1 $D/ping_copy.txt
