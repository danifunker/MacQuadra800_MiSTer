#!/usr/bin/env bash
# Full-machine Speedometer 4.02 guest run on HEAD b2ed1b0 RTL (production, release CPU macros).
# Usage: bash run_guest.sh <fpu|mix|color8>
set -euo pipefail
S=/home/alans/mister/MacQuadra800_MiSTer/scratch/p256_qual_20260928
K=$1; R="$S/${K}_run"; V="$S/cand/verilator"
FIXTURE=/home/alans/mister/MacQuadra800_fixtures/MacQuadra800-Speedometer402-profile.hda
GOLDEN=80d8479430a66edae161c2bac6a9563dbb4f6bd0f564ee7849a555c447df8888
ROM_SHA=045c02746b5f15f83132d33c5414f806e7b049f3bfe53a7bd0ecacb8e072d673
[ -e "$R" ] && { echo "refusing: $R exists" >&2; exit 2; }
mkdir -p "$R"; cd "$R"
cp "$S/controls/$K.txt" control.txt
cp "$V/quadra800-fastboot.rom.hex" rom.hex
cp "$FIXTURE" run.hda
sha() { sha256sum "$1" | cut -d' ' -f1; }
[ "$(sha run.hda)" = "$GOLDEN" ] || { echo "golden disk hash mismatch" >&2; exit 3; }
[ "$(sha rom.hex)" = "$ROM_SHA" ] || { echo "rom hash mismatch" >&2; exit 3; }
{ echo "started_utc=$(date -u +%FT%TZ)"; echo "unit=${INVOCATION_ID:-none}"; echo "head=b2ed1b08f615c51c87389630e2183055f2a8d877";
  echo "vemu_sha256=$(sha $V/obj_dir/Vemu)"; echo "control_sha256=$(sha control.txt)"; echo "core_sha256=$(sha $S/cand/rtl/ap68040/rtl/ap040_core.v)"; echo "fpu_sha256=$(sha $S/cand/rtl/ap68040/rtl/ap040_fpu.v)"; } > run.meta.txt
set +e
timeout 10800 "$V/obj_dir/Vemu" --headless --no-cpu-trace --disk run.hda +rom=rom.hex +ram=0 \
  --control control.txt --cpu-profile refill.tsv \
  --max-cycles 20000000000 +ram_line_model +ram_first_latency=4 +ram_line_publish_delay=2 > run.log 2>&1
rc=$?
set -e
echo "$rc" > exit_status.txt
echo "finished_utc=$(date -u +%FT%TZ) exit=$rc" >> run.meta.txt
