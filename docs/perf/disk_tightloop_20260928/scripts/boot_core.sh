#!/usr/bin/env bash
# boot_core.sh <variant> <tag> -- load the core via /dev/MiSTer_cmd (box must be at menu/safe screen), wait, screenshot
set -u; . "$(dirname "$0")/tl_common.sh"
V=$1; G=$2; mkdir -p $T/$V
$S 'xxd /media/fat/config/MacQuadra800.CFG | head -1; tr -d "\0" < /media/fat/config/MacQuadra800.s0; echo; echo load_core /media/fat/_Unstable/MacQuadra800.rbf > /dev/MiSTer_cmd; date'
sleep 45; bash scripts/grab.sh $T/$V/${G}_45s.png >/dev/null
sleep 60; bash scripts/grab.sh $T/$V/${G}_105s.png >/dev/null
echo "$T/$V/${G}_45s.png $T/$V/${G}_105s.png"
