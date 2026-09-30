// Simulation-only, exact native tEsT call/resume observer. No RTL edits.
`define MC dut.cpu.core
reg matrix_zone_saved=0;
int matrix_kind=0, matrix_resume=0, matrix_alloc_calls=0,matrix_alloc_returns=0;
int matrix_free_calls=0,matrix_free_returns=0,matrix_primary=0,matrix_secondary=0;
int matrix_ptrs[123];bit matrix_freed[123];int matrix_free_pointer;
int matrix_zone,matrix_bklim,matrix_freebytes,matrix_memtop;
function automatic int matrix_u32(input int addr);
    bit[15:0] hi,lo;
    hi=chip.mem[sdcell(addr,addr[1])];lo=chip.mem[sdcell(addr+2,((addr+2)&2)!=0)];
    return {hi,lo};
endfunction
function automatic int matrix_tap(input int idx);
    int value;
    value=`MC.regfile.rf_written[idx]?`MC.regfile.bank_a[idx]:0;
    if(`MC.regfile.pend_we && `MC.regfile.pend_waddr==idx)value=`MC.regfile.pend_wdata;
    if(`MC.rf_we && `MC.rf_waddr==idx)value=`MC.rf_wdata;
    return value;
endfunction
function automatic bit matrix_alloc_pc(input int pc);
    return pc=='h60018c || pc=='h6001ae || pc=='h6001d0;
endfunction
function automatic bit matrix_free_pc(input int pc);
    return pc=='h600260 || pc=='h600270 || pc=='h600280;
endfunction
function automatic bit[15:0] matrix_word(input int pc);
    return {img[pc],img[pc+1]};
endfunction
task automatic matrix_event(input int pc,input bit[15:0]op,input int a0,input int d0,input bit secondary);
    if(pc>='h600000 && pc<'h600ec8 && op==matrix_word(pc))begin
        if(matrix_alloc_pc(pc) && op==16'ha31e)begin
            if(secondary || matrix_kind!=0 || matrix_alloc_calls>=123 || d0!='ha4)$fatal(1,"matrix allocation call pairing");
            matrix_kind=1;matrix_resume=pc+2;matrix_alloc_calls++;
            $display("MATRIX_CALL alloc=%0d pc=%h size=%h",matrix_alloc_calls,pc,d0);
        end else if(matrix_free_pc(pc) && op==16'ha01f)begin
            int found;found=-1;
            if(secondary || matrix_kind!=0 || matrix_free_calls>=123)$fatal(1,"matrix free call pairing");
            for(int x=0;x<123;x++)if(matrix_ptrs[x]==a0)found=x;
            if(found<0 || matrix_freed[found])$fatal(1,"matrix free pointer not live %h",a0);
            matrix_free_pointer=a0;matrix_freed[found]=1;
            matrix_kind=2;matrix_resume=pc+2;matrix_free_calls++;
            $display("MATRIX_CALL free=%0d pc=%h ptr=%h",matrix_free_calls,pc,a0);
        end else if(matrix_kind!=0 && pc==matrix_resume)begin
            if(d0!=0)$fatal(1,"matrix memory trap error %h at%h",d0,pc);
            if(secondary)matrix_secondary++;else matrix_primary++;
            if(matrix_kind==1)begin
                if(op!=16'h3243 || a0==0 || a0<=matrix_zone || a0+'ha4>matrix_bklim ||
                   a0+'ha4>matrix_memtop || (a0<'h642000 && a0+'ha4>'h600000))$fatal(1,"matrix allocated pointer bounds %h",a0);
                for(int x=0;x<matrix_alloc_returns;x++)if(a0<matrix_ptrs[x]+'ha4 && a0+'ha4>matrix_ptrs[x])$fatal(1,"matrix allocation overlap");
                matrix_ptrs[matrix_alloc_returns]=a0;matrix_alloc_returns++;
                $display("MATRIX_RETURN alloc=%0d pc=%h ptr=%h error=%h secondary=%0d",matrix_alloc_returns,pc,a0,d0,secondary);
            end else begin
                if(!((pc=='h600262 || pc=='h600272)&&op==16'h3043) && !(pc=='h600282 && op==16'h5243))$fatal(1,"matrix free resume opcode");
                matrix_free_returns++;
                $display("MATRIX_RETURN free=%0d pc=%h ptr=%h error=%h secondary=%0d",matrix_free_returns,pc,matrix_free_pointer,d0,secondary);
            end
            matrix_kind=0;
        end
    end
endtask
// Snapshot secondary admission BEFORE edge; primary PC/op AFTER NBA. A0/D0
// forwarding includes both regfile pend and current core RF write, as in the
// reviewed attempt2 adapter. Resume opcodes cannot write D0;3243 writes A1.
always @(posedge clk_sys)begin : matrix_dispatch_sample
    bit secondary,before_toggle;int pre_pc,pre_a0,pre_d0;bit[15:0]pre_op;
    before_toggle=`MC.perf_dispatch_toggle;
    secondary=`MC.pipe_rf_owner && `MC.pipe_input && `MC.pipe_ready;
    pre_pc=`MC.pc;pre_op=`MC.epf_data[`MC.epf_head];pre_a0=matrix_tap(8);pre_d0=matrix_tap(0);
    #1;
    if(nreset && in_loop)begin
        if(!matrix_zone_saved)begin
            matrix_zone=matrix_u32('h118);matrix_bklim=matrix_u32(matrix_zone);
            matrix_freebytes=matrix_u32(matrix_zone+12);matrix_memtop=matrix_u32('h108);
            if(matrix_zone!=matrix_u32('h2aa) || matrix_zone!='h3f1890 || matrix_bklim!='h492078 || matrix_memtop!='h517754)$fatal(1,"matrix initial heap identity");
            dump_hex("matrix_zone_before.hex",matrix_zone,matrix_zone+63);
            dump_hex("matrix_limit_before.hex",matrix_bklim-32,matrix_bklim+31);
            matrix_zone_saved=1;
            $display("MATRIX_HEAP_START zone=%h bkLim=%h free=%h memtop=%h",matrix_zone,matrix_bklim,matrix_freebytes,matrix_memtop);
        end
        if(`MC.perf_dispatch_toggle!=before_toggle)begin
            if(secondary)matrix_event(pre_pc,pre_op,pre_a0,pre_d0,1);
            else matrix_event(`MC.pc_i,`MC.ir,matrix_tap(8),matrix_tap(0),0);
        end
    end
end
task matrix_finish;
    if(!matrix_zone_saved || matrix_kind!=0 || matrix_alloc_calls!=123 || matrix_alloc_returns!=123 || matrix_free_calls!=123 || matrix_free_returns!=123)$fatal(1,"matrix trap lifecycle incomplete");
    for(int x=0;x<123;x++)begin
        int addr;addr='h63ffea-'ha4*(1+x/41)+(x%41)*4;
        if(!matrix_freed[x] || matrix_u32(addr)!=matrix_ptrs[x])$fatal(1,"matrix pointer table mismatch index%0d at%h got%h expected%h",x,addr,matrix_u32(addr),matrix_ptrs[x]);
    end
    if(matrix_u32('h118)!=matrix_zone || matrix_u32('h2aa)!=matrix_zone || matrix_u32('h108)!=matrix_memtop || matrix_u32(matrix_zone)!=matrix_bklim || matrix_u32(matrix_zone+12)!=matrix_freebytes)$fatal(1,"matrix heap scalar restoration");
    dump_hex("matrix_zone_after.hex",matrix_zone,matrix_zone+63);
    dump_hex("matrix_limit_after.hex",matrix_bklim-32,matrix_bklim+31);
    $display("MATRIX_TRAPS alloc_calls=%0d alloc_returns=%0d free_calls=%0d free_returns=%0d primary_resumes=%0d secondary_resumes=%0d",matrix_alloc_calls,matrix_alloc_returns,matrix_free_calls,matrix_free_returns,matrix_primary,matrix_secondary);
    $display("MATRIX_HEAP_END zone=%h bkLim=%h free=%h memtop=%h ptr_tables=match",matrix_zone,matrix_bklim,matrix_freebytes,matrix_memtop);
endtask
`undef MC
