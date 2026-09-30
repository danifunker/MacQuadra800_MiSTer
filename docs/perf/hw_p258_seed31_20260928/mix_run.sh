#!/usr/bin/env bash
# usage: mix.sh <name> <waitsecs>   (expects no dialog up)
set -u
cd /home/alans/mister/MacQuadra800_MiSTer
. scripts/local.env; export MISTER_HOST
D=scratch/hw_p258_20260928; SP=/tmp/claude-1000/-home-alans-mister-MacQuadra800-MiSTer/d19955f2-a3f0-4952-a162-eb0bab562ed7/scratchpad
N=$1; W=$2
python3 scripts/mister_ws.py down:56 raw:48 up:56 >/dev/null
sleep 3
bash scripts/grab.sh $D/${N}_setup.png >/dev/null
echo "start $(date +%T) mister $(ssh -n -i $MISTER_SSH_KEY root@$MISTER_HOST date +%T)"
python3 scripts/mister_ws.py raw:28 >/dev/null
sleep $W
bash scripts/grab.sh $D/${N}_done.png >/dev/null
echo "done-shot $(date +%T)"
python3 scripts/mister_ws.py raw:28 >/dev/null
sleep 2
bash scripts/grab.sh $D/${N}_table.png >/dev/null
python3 -c "
from PIL import Image
im=Image.open('$D/${N}_table.png'); im.crop((0,40,340,300)).resize((1020,780),Image.NEAREST).save('$SP/${N}_zoom.png')
Image.open('$D/${N}_setup.png').crop((125,100,515,300)).save('$SP/${N}_setupcrop.png')
"
