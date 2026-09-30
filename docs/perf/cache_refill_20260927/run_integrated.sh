#!/usr/bin/env bash
set -euo pipefail

source_dir="$(cd "$(dirname "$0")" && pwd)"
repo="$source_dir"
while [ ! -f "$repo/verilator/tb_memory_path.sv" ]; do
  repo="$(dirname "$repo")"
  if [ "$repo" = / ]; then echo "repository root not found" >&2; exit 1; fi
done
scratch="$repo/scratch/fpu_refill_path_20260927"
cache_source="${1:-$repo/rtl/ap68040/rtl/ap040_cache.v}"
tag="${2:-integrated}"

cd "$repo"
mkdir -p "$scratch"
python3 "$source_dir/make_platform.py" "$scratch/refill_platform.sv"
CCACHE_DISABLE=1 /home/alans/verilator5/bin/verilator --binary --timing -j 8 \
  -Wno-fatal -Wno-WIDTH -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC \
  -Wno-UNSIGNED -Wno-CMPCONST -Wno-DECLFILENAME -Wno-PINMISSING \
  -Wno-UNOPTFLAT -Wno-MULTIDRIVEN +define+SIMULATION=1 \
  +define+AP040_EXPERIMENTAL_XSTORE=1 \
  +incdir+rtl/ap68040/rtl --top-module tb_refill_path \
  --Mdir "$scratch/obj_$tag" -o tb_refill_path \
  "$source_dir/tb_refill_path.sv" "$scratch/refill_platform.sv" \
  verilator/tb_sdram.sv "$cache_source" \
  rtl/ap68040/rtl/primitives/dpram.v rtl/wombat_bus32.sv \
  rtl/sdram_beat32.sv rtl/sdram.sv verilator/altddio_out_stub.v \
  > "$scratch/${tag}_build.log" 2>&1
"$scratch/obj_$tag/tb_refill_path" > "$scratch/${tag}_run.log" 2>&1
python3 "$source_dir/parse_metrics.py" "$scratch/${tag}_run.log"
sha256sum "$cache_source" "$source_dir/tb_refill_path.sv" \
  "$scratch/refill_platform.sv" "$scratch/obj_$tag/tb_refill_path" \
  "$scratch/${tag}_run.log" > "$scratch/${tag}_hashes.sha256"
