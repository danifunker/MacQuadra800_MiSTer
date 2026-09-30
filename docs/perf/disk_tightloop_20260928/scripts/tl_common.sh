# sourced: common settings for the tight-loop runs
cd /home/alans/mister/MacQuadra800_MiSTer
. scripts/local.env; export MISTER_HOST
T=scratch/disk_tightloop_20260928
S="ssh -n -i $MISTER_SSH_KEY root@$MISTER_HOST"
ws() { python3 scripts/mister_ws.py "$@" >/dev/null; }
sdprof_since_reset() { $S 'awk "/SDPROF RESET/{b=\"\"} {b=b \$0 \"\n\"} END{printf \"%s\", b}" /tmp/sdprof.log'; }
