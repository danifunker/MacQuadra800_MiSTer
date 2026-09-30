#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
cd "$here/baseline_sim/verilator"
test -x obj_dir/Vemu
test -f run.hda
read -r disk_hash _ < <(sha256sum run.hda)
test "$disk_hash" = 80d8479430a66edae161c2bac6a9563dbb4f6bd0f564ee7849a555c447df8888
test -f quadra800-fastboot.rom.hex
test -f fpu_control_full.txt
test ! -e fpu_timed_profile.tsv
./obj_dir/Vemu --headless --no-cpu-trace --disk run.hda \
  +rom=quadra800-fastboot.rom.hex +ram=0 \
  --control fpu_control_full.txt --cpu-profile fpu_refill_timed_run.tsv \
  --speedometer-observe fpu_timed_observer.log \
  --fpu-timed-profile fpu_timed_profile.tsv \
  --max-cycles 20000000000 \
  +ram_line_model +ram_first_latency=4 +ram_line_publish_delay=2 \
  > fpu_timed_run.log 2>&1
