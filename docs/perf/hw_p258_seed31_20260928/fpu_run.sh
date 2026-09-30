#!/usr/bin/env bash
# usage: run.sh <name> <cmdkey> <waitsecs> <cropbox>
set -u
cd /home/alans/mister/MacQuadra800_MiSTer
. scripts/local.env; export MISTER_HOST
D=scratch/hw_p258_20260928; SP=/tmp/claude-1000/-home-alans-mister-MacQuadra800-MiSTer/d19955f2-a3f0-4952-a162-eb0bab562ed7/scratchpad
N=$1; K=$2; W=$3; BOX=$4
python3 scripts/mister_ws.py raw:28 >/dev/null     # dismiss previous "tests are done"
sleep 2
python3 scripts/mister_ws.py down:56 raw:$K up:56 >/dev/null
sleep 3
bash scripts/grab.sh $D/${N}_setup.png >/dev/null
echo "start $(date +%T) mister $(ssh -n -i $MISTER_SSH_KEY root@$MISTER_HOST date +%T)"
python3 scripts/mister_ws.py raw:28 >/dev/null
sleep $W
bash scripts/grab.sh $D/${N}_done.png >/dev/null
echo "done-shot $(date +%T)"
python3 -c "
from PIL import Image
im=Image.open('$D/${N}_done.png'); b=tuple(int(x) for x in '$BOX'.split(','))
w,h=b[2]-b[0],b[3]-b[1]; im.crop(b).resize((w*3,h*3),Image.NEAREST).save('$SP/${N}_zoom.png')
im.crop((0,0,640,30)).resize((1280,60),Image.NEAREST).save('$SP/${N}_setupchk.png')
"
python3 -c "
from PIL import Image
Image.open('$D/${N}_setup.png').save('$SP/${N}_setup_copy.png')"
