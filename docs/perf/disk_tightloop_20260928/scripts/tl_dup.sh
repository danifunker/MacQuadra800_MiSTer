#!/usr/bin/env bash
# usage: tl_dup.sh <variant> <n> -- Cmd-D on the selected Finder item (Photoshop original)
set -u; . "$(dirname "$0")/tl_common.sh"
V=$1; N=$2; D=$T/$V; mkdir -p $D
bash scripts/grab.sh $D/dup${N}_before.png >/dev/null
sleep 3
( $S 'sh /tmp/armfine.sh 175' > $D/dup${N}_arm.txt & )
sleep 2
$S 'kill -USR2 $(pidof MiSTer)'; sleep 1
echo "dup$N cmd-D local $(date +%T.%N | cut -c1-12) mister $($S date +%s.%N | cut -c1-14)" | tee -a $D/log.txt
ws down:56 raw:32 up:56
sleep 44
sdprof_since_reset > $D/dup${N}_sdprof.txt
bash scripts/grab.sh $D/dup${N}_after.png >/dev/null
echo "dup$N after-shot $(date +%T)" | tee -a $D/log.txt
tail -1 $D/dup${N}_sdprof.txt
