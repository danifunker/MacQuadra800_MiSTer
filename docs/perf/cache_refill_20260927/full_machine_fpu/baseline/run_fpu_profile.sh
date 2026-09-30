#!/usr/bin/env bash
set -u
cd "$(dirname "$0")" || exit 99
rm -f fpu_refill.tsv fpu_refill.log fpu_exit_status.txt
printf 'pid=%s\nstarted_utc=%s\n' "$$" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > fpu_run.meta
./obj_dir/Vemu --headless --no-cpu-trace --disk run.hda \
  +rom=quadra800-fastboot.rom.hex +ram=0 \
  --control fpu_control_full.txt --cpu-profile fpu_refill.tsv \
  --max-cycles 20000000000 \
  +ram_line_model +ram_first_latency=4 +ram_line_publish_delay=2 \
  > fpu_refill.log 2>&1
rc=$?
printf 'exit_status=%s\n' "$rc" >> fpu_run.meta
printf '%s\n' "$rc" > fpu_exit_status.txt.tmp
mv fpu_exit_status.txt.tmp fpu_exit_status.txt
exit "$rc"
