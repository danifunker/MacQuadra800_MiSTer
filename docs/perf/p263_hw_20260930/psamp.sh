#!/bin/sh
# psamp.sh <seconds> -- runs ON the MiSTer: once a second, daemon rchar and ttyS1 counters (read-only; does not open ttyS1)
N=$1; i=0
while [ $i -lt $N ]; do
  P=$(pidof mister_printerd)
  R=$(awk '/rchar/{print $2}' /proc/$P/io 2>/dev/null)
  L=$(grep '^1:' /proc/tty/driver/serial | sed 's/.*tx/tx/')
  echo "$(date +%T) pid=$P rchar=$R $L"
  i=$((i+1)); sleep 1
done
