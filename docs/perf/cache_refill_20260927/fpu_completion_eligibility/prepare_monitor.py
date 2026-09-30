from pathlib import Path
r=Path(__file__).parent;p=r/'tb_platform_whet.sv';s=p.read_text()
anchor='wire [3:0] wq_used = sdr.wq_wp - sdr.wq_rp_sys;'
monitor='''// Simulation-only completion eligibility measurement. No FPU RTL is modified.
`define FMON dut.cpu.core.g_fpu.fpu
longint fm_clocks=0,fm_fst[32],fm_busy_op[128],fm_round_op[128],fm_round_eligible_op[128];
longint fm_round=0,fm_round_eligible=0,fm_round_reject[10];
longint fm_round_bg=0,fm_round_decwait=0,fm_round_go=0;
longint fm_stdone=0,fm_stdone_disabled=0,fm_stdone_eligible=0;
longint fm_stdone_enabled=0,fm_stdone_sideport=0,fm_stdone_notce=0;
wire fm_sideport = `FMON.cr_we || `FMON.fm_we || `FMON.bsun_req || `FMON.fp_reset ||
    `FMON.frestore_idle || `FMON.frestore_unimp || `FMON.fsave_ack || `FMON.pend_capture;
wire fm_arith_move = (`FMON.r_op==7'h00 || `FMON.r_op==7'h18 || `FMON.r_op==7'h1a ||
    `FMON.r_op==7'h04 || `FMON.r_op==7'h20 || `FMON.r_op==7'h22 ||
    `FMON.r_op==7'h23 || `FMON.r_op==7'h28);
// Exact prec_of(op)==0: FSGL and all explicit FS/FD operations are excluded.
wire fm_prec_extended = `FMON.r_op < 7'h40 && `FMON.r_op != 7'h24 &&
    `FMON.r_op != 7'h27 && `FMON.fpcr[7:6]==2'b00;
wire [9:0] fm_reject = {(!`FMON.nreset || !`FMON.ce),fm_sideport,!fm_arith_move,
    (`FMON.fpcr[15:8]!=0),($signed(`FMON.e_w)>18'sd32766),
    ($signed(`FMON.e_w)<18'sd1),!fm_prec_extended,(`FMON.grs!=0),
    !`FMON.a_m[63],(`FMON.a_t!=2'd0)};
'''
assert s.count(anchor)==1;s=s.replace(anchor,monitor+'\n'+anchor,1)
anchor='\tif (in_loop) begin\n\t\tif (dut.cpu.store_buffer.buffer_req'
mon='''\tif (in_loop) begin
        fm_clocks++;
        fm_fst[`FMON.fst]++;
        if (`FMON.fst!=0) fm_busy_op[`FMON.r_op]++;
        if (`FMON.fst==14) begin
            fm_round++;fm_round_op[`FMON.r_op]++;
            for(int reason=0;reason<10;reason++)if(fm_reject[reason])fm_round_reject[reason]++;
            if(fm_reject==0) begin
                fm_round_eligible++;fm_round_eligible_op[`FMON.r_op]++;
                if(dut.cpu.core.fpu_bg)fm_round_bg++;
                if(dut.cpu.core.state==153 && dut.cpu.core.fpu_bg && !dut.cpu.core.fpu_done)fm_round_decwait++;
                if(dut.cpu.core.state==160)fm_round_go++;
            end
        end
        if(`FMON.fst==17) begin
            fm_stdone++;
            if(`FMON.fpcr[15:8]==0)fm_stdone_disabled++;else fm_stdone_enabled++;
            if(fm_sideport)fm_stdone_sideport++;
            if(!`FMON.nreset || !`FMON.ce)fm_stdone_notce++;
            if(`FMON.fpcr[15:8]==0 && !fm_sideport && `FMON.nreset && `FMON.ce)fm_stdone_eligible++;
        end
\t\tif (dut.cpu.store_buffer.buffer_req'''
assert s.count(anchor)==1;s=s.replace(anchor,mon,1)
anchor='\t\t$display("SDRAM_PROTOCOL_ERRORS %0d", chip.errors + chip_hi.errors);'
report='''        if(fm_clocks!=loop_cycles)$fatal(1,"eligibility monitor/window mismatch %0d != %0d",fm_clocks,loop_cycles);
        $display("FPU_ELIG_WINDOW clocks=%0d sampling=pre_edge_existing_in_loop",fm_clocks);
        $display("FPU_ELIG_ROUND samples=%0d eligible=%0d bg=%0d decode_wait=%0d cpu_go=%0d",fm_round,fm_round_eligible,fm_round_bg,fm_round_decwait,fm_round_go);
        for(int x=0;x<10;x++)$display("FPU_ELIG_ROUND_REJECT reason=%0d samples=%0d",x,fm_round_reject[x]);
        $display("FPU_ELIG_STDONE samples=%0d enables_zero=%0d eligible=%0d enabled=%0d sideport=%0d not_ce_reset=%0d",fm_stdone,fm_stdone_disabled,fm_stdone_eligible,fm_stdone_enabled,fm_stdone_sideport,fm_stdone_notce);
        for(int x=0;x<32;x++)if(fm_fst[x])$display("FPU_ELIG_FST id=%0d samples=%0d",x,fm_fst[x]);
        for(int x=0;x<128;x++)if(fm_busy_op[x])$display("FPU_ELIG_BUSY_OP op=%02h samples=%0d",x,fm_busy_op[x]);
        for(int x=0;x<128;x++)if(fm_round_op[x])$display("FPU_ELIG_ROUND_OP op=%02h samples=%0d eligible=%0d",x,fm_round_op[x],fm_round_eligible_op[x]);
'''
assert s.count(anchor)==1;s=s.replace(anchor,report+anchor,1);p.write_text(s)
p=r/'run_platform_whet.py';s=p.read_text().replace("'-j', '8', '--build-jobs', '8'", "'-j', '2', '--build-jobs', '2'")
s=s.replace("'STOREBUF', 'BRIDGE')", "'STOREBUF', 'BRIDGE', 'FPU_ELIG')")
s=s.replace("print(f'MEMCHECK {n}: ' + ('match' if mine == ref else\n              f'DIFFER ({sum(1 for x, y in zip(mine, ref) if x != y)} bytes of {len(ref)})'))", "print(f'MEMCHECK {n}: ' + ('match' if mine == ref else f'DIFFER ({len(mine)} / {len(ref)} bytes)'))\n        assert mine == ref, f'oracle mismatch {n}'")
s+='''\nassert re.search(r'WHETSTONE_LOOP cycles=17641650\\b',text), 'loop count differs from frozen baseline'
assert 'SDRAM_PROTOCOL_ERRORS 0' in text, 'chip errors'
assert re.search(r'BERR 0\\s+IPL_ASSERTED_CYCLES 0',text), 'bus error or IRQ'
print('FPU_ELIG_QUALIFIED baseline_clocks_match=1 three_memory_oracles_match=1 guest_600D=1 chip_errors=0')
'''
p.write_text(s)
