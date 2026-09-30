#!/bin/sh
# runs ON the MiSTer: install_main.sh <binary in /media/fat> "<env vars>"
set -e
B=$1; E=$2
mount -o remount,rw /
grep -q 'main_env.txt' /etc/inittab || sed -i 's|^::sysinit:/media/fat/MiSTer &$|::sysinit:/usr/bin/env $(cat /media/fat/linux/main_env.txt 2>/dev/null) /media/fat/MiSTer \&|' /etc/inittab
sync; mount -o remount,ro /
grep -n 'media/fat/MiSTer' /etc/inittab
echo "$E" > /media/fat/linux/main_env.txt
cd /media/fat; cp -p "$B" MiSTer.new; chmod +x MiSTer.new; mv MiSTer.new MiSTer; sync
md5sum MiSTer; cat /media/fat/linux/main_env.txt
