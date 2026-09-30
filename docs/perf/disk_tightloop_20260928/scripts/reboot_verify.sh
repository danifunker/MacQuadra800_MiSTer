#!/usr/bin/env bash
# reboot the MiSTer, wait for Main, print md5 of running exe + env + sdprof log head
set -u; . "$(dirname "$0")/tl_common.sh"
SS="ssh -o ConnectTimeout=8 -i $MISTER_SSH_KEY root@$MISTER_HOST"
$SS -n 'sync; (sleep 1; reboot) >/dev/null 2>&1 &'
sleep 50
for i in $(seq 1 30); do $SS -n true 2>/dev/null && break; sleep 5; done
sleep 5
$SS -n 'cat /proc/uptime; P=$(pidof MiSTer); md5sum /proc/$P/exe; tr "\0" "\n" < /proc/$P/environ | grep -E "SDPROF|MAC_SD"; head -2 /tmp/sdprof.log 2>&1'
scp -q -i $MISTER_SSH_KEY $T/armfine.sh root@$MISTER_HOST:/tmp/armfine.sh
