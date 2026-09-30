#!/usr/bin/env bash
# bench.sh <name> <cmdkey> <waitsecs> [table] -- dismiss previous alert, open a Speedometer setup (Cmd-key), start, wait, screenshot
set -u; . "$(dirname "$0")/tl_common.sh"
N=$1; K=$2; W=$3; D=$T/run
ws raw:28; sleep 2
ws down:56 raw:$K up:56; sleep 3
bash scripts/grab.sh $D/${N}_setup.png >/dev/null
echo "$N start local $(date +%T) mister $($S date +%T)" | tee -a $D/log.txt
ws raw:28
sleep $W
bash scripts/grab.sh $D/${N}_done.png >/dev/null
echo "$N done-shot $(date +%T)" | tee -a $D/log.txt
if [ "${4:-}" = table ]; then ws raw:28; sleep 2; bash scripts/grab.sh $D/${N}_table.png >/dev/null; fi
