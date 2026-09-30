#!/usr/bin/env bash
# ps_open.sh <variant> -- close the front Finder window (click its title, Cmd-W), then Photoshop alias + Cmd-R
set -u; . "$(dirname "$0")/tl_common.sh"
V=$1; VM="python3 /media/fat/Scripts/q800tools/vmouse.py"
$S "$VM home m:60,20 0.3 click 0.3 up"; sleep 2; ws down:56 raw:17 up:56; sleep 3
$S "$VM home m:28,26 0.4 click 0.3 up"; sleep 2; ws down:56 raw:19 up:56; sleep 5
$S "$VM home"
bash scripts/grab.sh $T/$V/ps_folder.png >/dev/null; echo $T/$V/ps_folder.png
