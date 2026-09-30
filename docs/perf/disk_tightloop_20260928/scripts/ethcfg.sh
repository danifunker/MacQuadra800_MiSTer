#!/usr/bin/env bash
# ethcfg.sh on|off -- set the Ethernet OSD bit (CFG byte 0 bit 6) with the guest halted; keeps the other bits
set -u; . "$(dirname "$0")/tl_common.sh"
case $1 in on) B='\x40';; off) B='\x00';; esac
$S "cd /media/fat/config; cp -p MacQuadra800.CFG /tmp/CFG.bak; printf '$B' | dd of=MacQuadra800.CFG bs=1 count=1 conv=notrunc 2>/dev/null; sync; xxd MacQuadra800.CFG | head -1"
