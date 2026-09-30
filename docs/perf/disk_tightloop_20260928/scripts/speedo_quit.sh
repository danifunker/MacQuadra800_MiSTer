#!/usr/bin/env bash
set -u; . "$(dirname "$0")/tl_common.sh"
V=$1; VM="python3 /media/fat/Scripts/q800tools/vmouse.py"
ws raw:28; sleep 2; ws down:56 raw:16 up:56; sleep 3
$S "$VM home m:162,129 0.5"; bash scripts/grab.sh $T/$V/quit_ptr.png >/dev/null
echo $T/$V/quit_ptr.png
