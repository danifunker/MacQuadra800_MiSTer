#!/bin/bash
set -u
printf 'pid=%s\nstarted_utc=%s\n' "$$" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > color8_run.meta
./Vemu --headless --no-cpu-trace --disk run.hda +rom=quadra800-fastboot.rom.hex +ram=0 --control color8_control_full.txt --cpu-profile color8_refill.tsv --max-cycles 20000000000 +ram_line_model +ram_first_latency=4 +ram_line_publish_delay=2 > color8_refill.log 2>&1
status=$?
printf 'exit_status=%s\nfinished_utc=%s\n' "$status" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> color8_run.meta
exit "$status"
