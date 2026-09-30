#!/usr/bin/env bash
# usage: pr_run.sh <n> -- one Speedometer Performance Rating run (CPU, Graphics, Disk, Math, Iter 1)
set -u
cd /home/alans/mister/MacQuadra800_MiSTer
. scripts/local.env; export MISTER_HOST
D=scratch/disk_guest_20260928; N=$1
S="ssh -n -i $MISTER_SSH_KEY root@$MISTER_HOST"
python3 scripts/mister_ws.py raw:28 >/dev/null      # dismiss previous "tests are done"
sleep 2
python3 scripts/mister_ws.py down:56 raw:19 up:56 >/dev/null   # Cmd-R
sleep 3
bash scripts/grab.sh $D/pr${N}_setup.png >/dev/null
python3 scripts/mister_ws.py raw:28 >/dev/null      # OK the setup
sleep 4
bash scripts/grab.sh $D/pr${N}_drive.png >/dev/null
( $S 'sh /tmp/armsample.sh 40' > $D/pr${N}_arm.txt & )
sleep 2
echo "start $(date +%T) mister $($S date +%s.%N)"
python3 scripts/mister_ws.py raw:28 >/dev/null      # OK the drive dialog -> tests run
sleep 42
bash scripts/grab.sh $D/pr${N}_done.png >/dev/null
echo "done-shot $(date +%T)"
