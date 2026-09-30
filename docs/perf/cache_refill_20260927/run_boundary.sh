#!/usr/bin/env bash
set -euo pipefail

source_dir="$(cd "$(dirname "$0")" && pwd)"
repo="$source_dir"
while [ ! -f "$repo/rtl/ap68040/tb/tb_ap040_cache_snoop.v" ]; do
  repo="$(dirname "$repo")"
  if [ "$repo" = / ]; then echo "repository root not found" >&2; exit 1; fi
done
scratch="$repo/scratch/fpu_refill_path_20260927"
cache_source="${1:-$repo/rtl/ap68040/rtl/ap040_cache.v}"
tag="${2:-boundary_baseline}"
extra_define=()
if [ "${3:-}" = candidate ]; then extra_define=(-DBULK_CANDIDATE); fi

mkdir -p "$scratch"
cd "$repo"
python3 "$source_dir/make_boundary.py" "$scratch/tb_bulk_boundary.sv"
iverilog -g2012 -DAP040_EXPERIMENTAL_XSTORE "${extra_define[@]}" \
  -I rtl/ap68040/rtl -s tb_bulk_boundary -o "$scratch/${tag}.vvp" \
  "$scratch/tb_bulk_boundary.sv" "$cache_source" \
  rtl/ap68040/rtl/primitives/dpram.v > "$scratch/${tag}_build.log" 2>&1
vvp "$scratch/${tag}.vvp" > "$scratch/${tag}_run.log" 2>&1
sha256sum "$cache_source" "$source_dir/boundary_stim.sv" \
  "$scratch/tb_bulk_boundary.sv" "$scratch/${tag}.vvp" \
  "$scratch/${tag}_run.log" > "$scratch/${tag}_hashes.sha256"
