#!/usr/bin/env bash
# Full-machine Speedometer 4.02 FPU run with the passive segment monitor.
# Usage: bash run_fullguest.sh [run_dir_name]   (default fpu_run)
# Launch durable:  systemd-run --user --unit=fpu-subtest-breakdown-20260928 --collect \
#                    bash /abs/path/run_fullguest.sh
set -euo pipefail
S="$(cd "$(dirname "$0")" && pwd)"
R="$S/${1:-fpu_run}"
V="$S/tree/verilator"
FIXTURE=/home/alans/mister/MacQuadra800_fixtures/MacQuadra800-Speedometer402-profile.hda
GOLDEN=80d8479430a66edae161c2bac6a9563dbb4f6bd0f564ee7849a555c447df8888
CONTROL_SHA=33108dcd7af064820bb59ae89f72c77a2f8a62b74bbee73f86bd912c244253e4
ROM_SHA=045c02746b5f15f83132d33c5414f806e7b049f3bfe53a7bd0ecacb8e072d673
[ -e "$R" ] && { echo "refusing: $R exists" >&2; exit 2; }
[ -x "$V/obj_dir/Vemu" ] || { echo "build first: make -C $V V=/home/alans/verilator5/bin/verilator" >&2; exit 2; }
mkdir -p "$R"; cd "$R"
cp "$S/control.txt" control.txt
cp "$V/quadra800-fastboot.rom.hex" rom.hex
cp "$FIXTURE" run.hda
sha() { sha256sum "$1" | cut -d' ' -f1; }
[ "$(sha run.hda)" = "$GOLDEN" ] || { echo "golden disk hash mismatch" >&2; exit 3; }
[ "$(sha control.txt)" = "$CONTROL_SHA" ] || { echo "control hash mismatch" >&2; exit 3; }
[ "$(sha rom.hex)" = "$ROM_SHA" ] || { echo "rom hash mismatch" >&2; exit 3; }
( cd "$S/tree" && find rtl verilator -type f ! -path 'verilator/obj_dir/*' -print0 | sort -z | xargs -0 sha256sum ) > source_manifest.sha256
cat > run.meta.txt <<META
started_utc=$(date -u +%FT%TZ)
host_pid=$$
unit=${INVOCATION_ID:-none}
head_commit=$(cat "$S/HEAD_COMMIT.txt")
binary_sha256=$(sha "$V/obj_dir/Vemu")
monitor_sha256=$(sha "$V/fpu_window_monitor.h")
sim_main_sha256=$(sha "$V/sim_main.cpp")
sim_v_sha256=$(sha "$V/sim.v")
source_manifest_sha256=$(sha source_manifest.sha256)
golden_disk_sha256=$GOLDEN
control_sha256=$CONTROL_SHA
rom_sha256=$ROM_SHA
argv=--headless --no-cpu-trace --disk run.hda +rom=rom.hex +ram=0 --control control.txt --cpu-profile refill.tsv --fpu-window fwm.txt --fpu-window-period 200000 --max-cycles 20000000000 +ram_line_model +ram_first_latency=4 +ram_line_publish_delay=2
META
set +e
timeout 10800 "$V/obj_dir/Vemu" --headless --no-cpu-trace --disk run.hda +rom=rom.hex +ram=0 \
  --control control.txt --cpu-profile refill.tsv --fpu-window fwm.txt --fpu-window-period 200000 \
  --max-cycles 20000000000 +ram_line_model +ram_first_latency=4 +ram_line_publish_delay=2 > run.log 2>&1
rc=$?
set -e
echo "$rc" > exit_status.txt
echo "finished_utc=$(date -u +%FT%TZ) exit=$rc" >> run.meta.txt
