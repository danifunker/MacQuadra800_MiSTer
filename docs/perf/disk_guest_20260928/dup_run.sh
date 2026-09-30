#!/usr/bin/env bash
# usage: dup_run.sh <name> <shots:0|1> -- Cmd-D on the selected Finder item, ARM sampler at 1 s,
# optional screenshot trigger every 1 s (Main writes them; fetched afterwards)
set -u
cd /home/alans/mister/MacQuadra800_MiSTer
. scripts/local.env; export MISTER_HOST
D=scratch/disk_guest_20260928; N=$1; SHOTS=$2
S="ssh -n -i $MISTER_SSH_KEY root@$MISTER_HOST"
HTTP="http://$MISTER_HOST:$MISTER_HTTP_PORT"
bash scripts/grab.sh $D/${N}_before.png >/dev/null
sleep 3
( $S 'sh /tmp/armfine.sh 200' > $D/${N}_arm.txt & )
( $S 'for i in 1 2 3 4 5 6 7 8; do top -b -n 1 | head -6 | tail -3; sleep 4; done' > $D/${N}_top.txt & )
sleep 3
echo "cmd-D local $(date +%T.%N | cut -c1-12) mister $($S date +%s.%N | cut -c1-14)"
python3 scripts/mister_ws.py down:56 raw:32 up:56 >/dev/null
if [ "$SHOTS" = 1 ]; then
  for i in $(seq 1 25); do curl -s -m 2 -X POST "$HTTP/api/screenshots" >/dev/null; echo "shot $i $(date +%T.%N | cut -c1-12)"; sleep 1; done
else
  sleep 38
fi
sleep 6
bash scripts/grab.sh $D/${N}_after.png >/dev/null
echo "after-shot $(date +%T)"
