#!/usr/bin/env bash
# speedo_launch.sh <variant> -- double-click the desktop alias, dismiss splash + nag
set -u; . "$(dirname "$0")/tl_common.sh"
V=$1; VM="python3 /media/fat/Scripts/q800tools/vmouse.py"
$S "$VM home m:246,248 0.5 dclick 0.3 up"; sleep 15
$S "$VM home m:190,120 0.3 click 0.3 up"; sleep 4          # click the splash (~318,200)
$S "$VM home m:225,174 0.3"; sleep 1                        # Not Yet (~375,291)
bash scripts/grab.sh $T/$V/nag.png >/dev/null
$S "$VM click 0.3 up"; sleep 4
bash scripts/grab.sh $T/$V/speedo_main.png >/dev/null
echo "$T/$V/nag.png $T/$V/speedo_main.png"
