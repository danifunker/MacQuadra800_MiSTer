#!/usr/bin/env python3
from pathlib import Path
D=Path(__file__).resolve().parent;R=D.parents[1]
s=(R/'scratch/fpu_completion_eligibility_20260928/tb_platform_whet.sv').read_text()
s=s.replace('cycles > 400000000','cycles > 40000000')
s=s.replace('longint fm_clocks=0,','longint native_core[256],native_cache[16];\nlongint native_body=0,native_resource=0,native_rom=0,native_vector11=0,native_unimp=0;\nlongint native_bg=0,native_blockdec=0,native_go=0,native_mrd_fill=0,native_mrd_unacked=0;\nlongint fm_clocks=0,')
s=s.replace('        fm_clocks++;','''        if (dut.cpu.core.state>=256 || dut.cpu.g_cache.cache.cst>=16 ||
            `FMON.fst>=32 || `FMON.r_op>=128) $fatal(1,"native profile index out of range");
        native_core[dut.cpu.core.state]++;
        native_cache[dut.cpu.g_cache.cache.cst]++;
        if(dut.cpu.core.pc_i>=32'h60029a && dut.cpu.core.pc_i<32'h6006a2)native_body++;
        if(dut.cpu.core.pc_i>=32'h600000 && dut.cpu.core.pc_i<32'h600ec8)native_resource++;
        if(dut.cpu.core.pc_i>=32'h40800000 && dut.cpu.core.pc_i<32'h40900000)native_rom++;
        if(dut.cpu.core.pc_i==32'h4088d9fe)native_vector11++;
        if(`FMON.unimp)native_unimp++;
        if(dut.cpu.core.fpu_bg)native_bg++;
        if(dut.cpu.core.state==153 && dut.cpu.core.fpu_bg && !dut.cpu.core.fpu_done)native_blockdec++;
        if(dut.cpu.core.state==160)native_go++;
        if(dut.cpu.core.state==9 && dut.cpu.g_cache.cache.cst==4)begin
            native_mrd_fill++;
            if(!dut.cpu.g_cache.cache.fill_acked)native_mrd_unacked++;
        end
        fm_clocks++;''')
s=s.replace('begin stamp_start = cycles; in_loop = 1; end','begin stamp_start = cycles; in_loop = 1; $display("NATIVE_START fpcr=%08h pc=%08h",`FMON.fpcr,dut.cpu.core.pc_i); end')
s=s.replace('dump_hex("whet_globals.hex", \'h61df90, \'h61dfa3);','dump_hex("native_globals.hex", \'h600ea0, \'h600ec7);')
s=s.replace('dump_hex("whet_code.hex",    \'h600000, \'h600b4d);','dump_hex("native_code.hex", \'h600000, \'h600e9f);\n        dump_hex("native_abi.hex", \'h625000, \'h6251ff);')
s=s.replace('dump_hex("whet_stack.hex",   \'h63fc00, \'h63ffff);','dump_hex("native_stack.hex", \'h63f000, \'h63ffff);')
s=s.replace('        $display("FPU_ELIG_WINDOW', '''        begin
            longint core_sum,cache_sum,fst_sum;
            core_sum=0;cache_sum=0;fst_sum=0;
            for(int x=0;x<256;x++)core_sum+=native_core[x];
            for(int x=0;x<16;x++)cache_sum+=native_cache[x];
            for(int x=0;x<32;x++)fst_sum+=fm_fst[x];
            if(core_sum!=loop_cycles || cache_sum!=loop_cycles || fst_sum!=loop_cycles)$fatal(1,"native histogram totals");
            if(native_body==0 || native_vector11==0 || native_unimp==0)$fatal(1,"native/FPSP coverage absent");
            $display("NATIVE_COVERAGE body=%0d resource=%0d rom=%0d vector11_pc=%0d unimp_pulse_samples=%0d",native_body,native_resource,native_rom,native_vector11,native_unimp);
            $display("NATIVE_OVERLAP bg=%0d blockingdec=%0d go=%0d mrd_fill=%0d mrd_unacked=%0d",native_bg,native_blockdec,native_go,native_mrd_fill,native_mrd_unacked);
            $display("NATIVE_TOTAL clocks=%0d core=%0d cache=%0d fst=%0d",loop_cycles,core_sum,cache_sum,fst_sum);
            for(int x=0;x<256;x++)if(native_core[x])$display("NATIVE_CORE state=%0d samples=%0d",x,native_core[x]);
            for(int x=0;x<16;x++)if(native_cache[x])$display("NATIVE_CACHE state=%0d samples=%0d",x,native_cache[x]);
        end
        $display("FPU_ELIG_WINDOW''')
(D/'tb_platform_whet.sv').write_text(s)
