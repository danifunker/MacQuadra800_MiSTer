#!/usr/bin/env bash
set -euo pipefail

source_dir="$(cd "$(dirname "$0")" && pwd)"
repo="$source_dir"
while [ ! -f "$repo/rtl/ap68040/tb/tb_ap040_cache_snoop.v" ]; do
  repo="$(dirname "$repo")"
  if [ "$repo" = / ]; then echo 'repository root not found' >&2; exit 1; fi
done
cache_source="${1:-$repo/rtl/ap68040/rtl/ap040_cache.v}"
tag="${2:-edge_baseline}"
candidate="${3:-baseline}"
case "$candidate" in
  baseline) candidate_define=() ;;
  candidate) candidate_define=(-DBULK_CANDIDATE) ;;
  *) echo 'third argument must be baseline or candidate' >&2; exit 1 ;;
esac
work="$repo/scratch/fpu_refill_edge_cases_20260927"
mkdir -p "$work"
cd "$repo"
python3 "$source_dir/make_edge.py" "$work/tb_edge_cases.sv"
iverilog -g2012 -DAP040_EXPERIMENTAL_XSTORE "${candidate_define[@]}" \
  -I rtl/ap68040/rtl -s tb_edge_cases -o "$work/${tag}.vvp" \
  "$work/tb_edge_cases.sv" "$cache_source" \
  rtl/ap68040/rtl/primitives/dpram.v > "$work/${tag}_build.log" 2>&1
vvp "$work/${tag}.vvp" > "$work/${tag}_run.log" 2>&1
sha256sum "$cache_source" "$source_dir/make_edge.py" "$source_dir/edge_stim.sv" \
  "$work/tb_edge_cases.sv" "$work/${tag}.vvp" "$work/${tag}_run.log" \
  > "$work/${tag}_hashes.sha256"
tail -n 4 "$work/${tag}_run.log"
