#!/bin/sh
# run_diff.sh <tree root with rtl/ap68040> <label> [berr]
# Runs t_fsave_diff.s on tb_ap040_program with the release AP040 macros and
# writes <label>.tags (the stamp-port word stream, one per line, with its
# phase) and <label>.cycles (the same with cycle deltas) to $FSD_OUT
# (default scratch/fsave_diff/).  "berr" builds the
# bench variant whose one-shot data bus error sits at $5040 and is armed only
# by a BERRCTL write.  Compare two runs with diff.
set -eu
T=$(cd "$1" && pwd); L=$2; V=${3:-}
HERE=$(cd "$(dirname "$0")" && pwd)
R=$(cd "$HERE/../../.." && pwd)
VASM=${VASM:-/home/alans/mister/MacQuadra800_fixtures/wombat-vasm/vasmm68k_mot}
W=${FSD_WORK:-/tmp/fsd}_$L; rm -rf "$W"; mkdir -p "$W"
O=${FSD_OUT:-$R/scratch/fsave_diff}; mkdir -p "$O"
RTL=$T/rtl/ap68040/rtl
cp "$R/rtl/ap68040/tb/tb_ap040_program.v" "$W/tb.v"
if [ "$V" = berr ]; then
	# the bus error moves to $5040, and reset no longer arms it (the
	# first berr_armed <= 1 is the reset one; the BERRCTL write arms)
	sed -i "s/(addr_out\[15:0\] == 16'hF140)/(addr_out[15:0] == 16'h5040)/; 0,/^\t\tberr_armed <= 1;$/s//\t\tberr_armed <= 0;/" "$W/tb.v"
	grep -q "16'h5040" "$W/tb.v"; [ "$(grep -c 'berr_armed <= 1;' "$W/tb.v")" = 1 ]
fi
FL="-DAP040_EXPERIMENTAL_LEA=1 -DAP040_EXPERIMENTAL_PIPELINE=1 -DAP040_EXPERIMENTAL_PIPELINE_LOADS=1 -DAP040_EXPERIMENTAL_PIPELINE_P6=1 -DAP040_EXPERIMENTAL_PIPELINE_PEA=1 -DAP040_EXPERIMENTAL_PIPELINE_STORES=1 -DAP040_EXPERIMENTAL_XSTORE=1 -DAP040_PIPELINE_COMPARE=1 -DAP040_PIPELINE_EARLY_DRAIN=1 -DAP040_PIPELINE_MEMORY_ENTRY=1 -DCACHE_CD_OFF=1 -DCACHE_SMALL=1 -DSIMULATION=1"
iverilog -g2012 $FL -I "$RTL" -s tb_ap040_program -o "$W/prog.vvp" "$W/tb.v" \
  $RTL/ap040_tg68k_compat.v $RTL/ap040_core.v $RTL/ap040_bus16_adapter.v $RTL/ap040_bus_timeout.v $RTL/ap040_regfile.v \
  $RTL/ap040_alu.v $RTL/ap040_muldiv.v $RTL/ap040_mmu.v $RTL/ap040_walker_cdc.v $RTL/primitives/dpram.v $RTL/ap040_fpu.v \
  $RTL/ap040_cache.v "$T/rtl/ap68040/experimental/ap040_pipeline_integer.sv"
cd "$W"
$VASM -Fbin -m68040 -no-opt -o t.bin "$HERE/t_fsave_diff.s" >/dev/null
python3 "$R/rtl/ap68040/tb/bin2hex.py" t.bin t.hex
vvp prog.vvp +prog=t.hex > run.log 2>&1 || true
awk '/phase [0-9] passed/{p++} /STAMP tag=/{sub(/.*tag=/,""); split($0,a," "); print p, a[1]}' run.log > "$O/$L.tags"
awk '/phase [0-9] passed/{p++} /STAMP tag=/{sub(/.*tag=/,""); print p, $0}' run.log > "$O/$L.cycles"
echo "$L: $(wc -l < "$O/$L.tags") words; $(grep -o 'phase [0-9] passed ([0-9]* cycles)' run.log | tr '\n' ' ')$(grep -c 'ALL TESTS PASSED' run.log) pass"
