#!/bin/sh
# usage: armsample.sh <seconds>  -- runs ON the MiSTer; 0.2 s samples of Main's io + cpu ticks
P=$(pidof MiSTer); N=$1; i=0
echo "# pid $P  clk_tck=$(getconf CLK_TCK 2>/dev/null)"
echo "# t rchar wchar syscr syscw read_bytes write_bytes cancelled_write_bytes utime stime hda_pos"
while [ $i -lt $N ]; do
  T=$(date +%s.%N | cut -c1-14)
  IO=$(awk '{printf "%s ", $2}' /proc/$P/io)
  ST=$(awk '{print $14, $15}' /proc/$P/stat)
  POS=$(awk 'NR==1{print $2}' /proc/$P/fdinfo/5)
  echo "$T $IO$ST $POS"
  i=$((i+1)); sleep 0.2
done
