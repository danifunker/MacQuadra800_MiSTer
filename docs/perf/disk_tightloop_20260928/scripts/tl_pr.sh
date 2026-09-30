#!/usr/bin/env bash
# usage: tl_pr.sh <variant> <n> [nodismiss] -- one Speedometer PR (CPU, Graphics, Disk, Math, Iter 1)
set -u; . "$(dirname "$0")/tl_common.sh"
V=$1; N=$2; D=$T/$V; mkdir -p $D
[ "${3:-}" = nodismiss ] || { ws raw:28; sleep 2; }      # dismiss previous "tests are done"
$S "python3 /media/fat/Scripts/q800tools/vmouse.py home" && sleep 1
ws down:56 raw:19 up:56; sleep 3                          # Cmd-R
bash scripts/grab.sh $D/pr${N}_setup.png >/dev/null
ws raw:28; sleep 4                                        # OK the setup
bash scripts/grab.sh $D/pr${N}_drive.png >/dev/null
( $S 'sh /tmp/armfine.sh 165' > $D/pr${N}_arm.txt & )
sleep 2
$S 'kill -USR2 $(pidof MiSTer)'; sleep 1
echo "pr$N start local $(date +%T) mister $($S date +%s.%N | cut -c1-14)" | tee -a $D/log.txt
ws raw:28                                                 # OK the drive dialog -> tests run
sleep 43
sdprof_since_reset > $D/pr${N}_sdprof.txt
bash scripts/grab.sh $D/pr${N}_done.png >/dev/null
echo "pr$N done-shot $(date +%T)" | tee -a $D/log.txt
tail -1 $D/pr${N}_sdprof.txt
