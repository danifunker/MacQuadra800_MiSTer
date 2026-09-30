#!/usr/bin/env bash
# dups.sh <variant> <n...> -- timed duplicates; stops at the first one that does not write the whole file
set -u; T=scratch/disk_tightloop_20260928; cd /home/alans/mister/MacQuadra800_MiSTer
V=$1; shift
for n in "$@"; do
  bash $T/tl_dup.sh $V $n > $T/$V/dup${n}_out.txt 2>&1
  t=$(grep -o "mister [0-9.]*" $T/$V/dup${n}_out.txt | cut -d' ' -f2)
  wb=$(tail -1 $T/$V/dup${n}_sdprof.txt | grep -o " write_bytes=[0-9]*" | cut -d= -f2)
  echo "dup$n t0=$t sdprof_write_bytes=$wb $(python3 $T/analyze.py $T/$V/dup${n}_arm.txt $t)"
  [ "${wb:-0}" -ge 3958000 ] || { echo "dup$n INCOMPLETE -- possible hang"; exit 1; }
done
