#!/bin/bash
# Paired tb_ap040_program regressions, release CPU macros, base=0b2d265 vs cand=HEAD(3c3ade8)
set -u
S=/home/alans/mister/MacQuadra800_MiSTer/scratch/p251_qual_20260928
export PATH=/home/alans/verilator5/bin:$PATH
VASM=/home/alans/mister/MacQuadra800_fixtures/wombat-vasm/vasmm68k_mot
FLAGS="-DAP040_EXPERIMENTAL_LEA=1 -DAP040_EXPERIMENTAL_PIPELINE=1 -DAP040_EXPERIMENTAL_PIPELINE_LOADS=1 -DAP040_EXPERIMENTAL_PIPELINE_P6=1 -DAP040_EXPERIMENTAL_PIPELINE_PEA=1 -DAP040_EXPERIMENTAL_PIPELINE_STORES=1 -DAP040_EXPERIMENTAL_XSTORE=1 -DAP040_PIPELINE_COMPARE=1 -DAP040_PIPELINE_EARLY_DRAIN=1 -DAP040_PIPELINE_MEMORY_ENTRY=1 -DCACHE_CD_OFF=1 -DCACHE_SMALL=1 -DSIMULATION=1"
rc=0
for v in base cand; do
  R=$S/$v/rtl/ap68040/rtl; T=$S/$v/rtl/ap68040/tb; O=$S/prog/$v; mkdir -p $O
  iverilog -g2012 $FLAGS -I $R -s tb_ap040_program -o $O/prog.vvp $T/tb_ap040_program.v \
    $R/ap040_tg68k_compat.v $R/ap040_core.v $R/ap040_bus16_adapter.v $R/ap040_bus_timeout.v $R/ap040_regfile.v \
    $R/ap040_alu.v $R/ap040_muldiv.v $R/ap040_mmu.v $R/ap040_walker_cdc.v $R/primitives/dpram.v $R/ap040_fpu.v \
    $R/ap040_cache.v $S/$v/rtl/ap68040/experimental/ap040_pipeline_integer.sv > $O/compile.log 2>&1 || { echo "$v compile FAIL"; rc=1; continue; }
  for t in fpu fpu_frames fpu_resume mmu exceptions cache; do
    $VASM -Fbin -m68040 -no-opt -o $O/$t.bin $T/asm/t_$t.s > $O/$t.asm.log 2>&1 || { echo "$v $t asm FAIL"; rc=1; continue; }
    python3 $T/bin2hex.py $O/$t.bin $O/$t.hex
    (cd $O && vvp prog.vvp +prog=$t.hex > $t.log 2>&1)
    res=$(grep -c "ALL TESTS PASSED" $O/$t.log); ph=$(grep -o "phase [0-9] passed ([0-9]* cycles)" $O/$t.log | sed 's/.*(\([0-9]*\) cycles)/\1/' | paste -sd/)
    echo "$v $t pass=$res phases=$ph"; [ "$res" = 1 ] || rc=1
  done
done
exit $rc
