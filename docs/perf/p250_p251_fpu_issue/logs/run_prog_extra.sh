#!/bin/bash
S=/home/alans/mister/MacQuadra800_MiSTer/scratch/p251_qual_20260928
VASM=/home/alans/mister/MacQuadra800_fixtures/wombat-vasm/vasmm68k_mot
rc=0
for v in base cand; do T=$S/$v/rtl/ap68040/tb; O=$S/prog/$v
  for t in integer bitfield_mmu bitfield_cache moves_fc movem_restart atcprobe branch_early loops_irq refill_load lea_d16 lea_fault; do
    $VASM -Fbin -m68040 -no-opt -o $O/$t.bin $T/asm/t_$t.s > $O/$t.asm.log 2>&1 || { echo "$v $t asm FAIL"; rc=1; continue; }
    python3 $T/bin2hex.py $O/$t.bin $O/$t.hex
    (cd $O && vvp prog.vvp +prog=$t.hex > $t.log 2>&1); src=$?
    res=$(grep -c "ALL TESTS PASSED" $O/$t.log); bad=$(grep -Ec 'FATAL:|TEST FAILED' $O/$t.log)
    ph=$(grep -o "phase [0-9] passed ([0-9]* cycles)" $O/$t.log | sed 's/.*(\([0-9]*\) cycles)/\1/' | paste -sd/)
    echo "$v $t rc=$src pass=$res bad=$bad phases=$ph"; [ "$res" = 1 -a "$bad" = 0 -a $src = 0 ] || rc=1
  done
done
exit $rc
