#!/usr/bin/env bash
# Finder Special -> Shut Down (baseline recipe); screenshot of the lit item during the hold, then the halt
set -u; . "$(dirname "$0")/tl_common.sh"
V=$1; VM="python3 /media/fat/Scripts/q800tools/vmouse.py"
$S "$VM home m:111,-10 0.5 down 0.8 m:13,66 8 up" &
sleep 11; bash scripts/grab.sh $T/$V/sd_lit.png >/dev/null; wait
$S "$VM up"
sleep 25; bash scripts/grab.sh $T/$V/halt.png >/dev/null
echo "$T/$V/sd_lit.png $T/$V/halt.png"
