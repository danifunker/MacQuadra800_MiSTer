// Simulation only: pinned native FFT call/resume and live argument observer.
`define FC dut.cpu.core
bit fft_zone_saved=0,fft_math_pending=0;
int fft_kind=0,fft_resume=0,fft_alloc_calls=0,fft_alloc_returns=0;
int fft_free_calls=0,fft_free_returns=0,fft_primary=0,fft_secondary=0;
int fft_ptrs[3],fft_sizes[3]='{'h808,'h808,'h410};bit fft_freed[3];int fft_free_pointer;
int fft_zone,fft_bklim,fft_freebytes,fft_memtop,fft_calls=0,fft_exptab_calls=0,fft_n_checks=0,fft_scalar_checks=0;
function automatic int fft_u32(input int addr);
    bit[15:0]hi,lo;hi=chip.mem[sdcell(addr,addr[1])];lo=chip.mem[sdcell(addr+2,((addr+2)&2)!=0)];return {hi,lo};
endfunction
function automatic int fft_tap(input int idx);
    int value;value=`FC.regfile.rf_written[idx]?`FC.regfile.bank_a[idx]:0;
    if(`FC.regfile.pend_we && `FC.regfile.pend_waddr==idx)value=`FC.regfile.pend_wdata;
    if(`FC.rf_we && `FC.rf_waddr==idx)value=`FC.rf_wdata;return value;
endfunction
function automatic bit fft_alloc_pc(input int pc);return pc=='h600c96||pc=='h600ccc||pc=='h600d02;endfunction
function automatic bit fft_free_pc(input int pc);return pc=='h600e00||pc=='h600e04||pc=='h600e08;endfunction
function automatic bit[15:0]fft_word(input int pc);return {img[pc],img[pc+1]};endfunction
function automatic bit[15:0]fft_alloc_return_op(input int idx);
    case(idx)0:return 'h2448;1:return 'h2808;default:return 'h2648;endcase
endfunction
function automatic bit[15:0]fft_free_return_op(input int idx);
    case(idx)0:return 'h2044;1:return 'h204b;default:return 'h4cdf;endcase
endfunction
task automatic fft_event(input int pc,input bit[15:0]op,input int a0,input int d0,input int a2,input int a3,input int d7,input bit secondary);
    if(pc>='h600000 && pc<'h600ec8 && op==fft_word(pc))begin
        if(fft_alloc_pc(pc) && op==16'ha11e)begin
            if(secondary||fft_kind!=0||fft_alloc_calls>=3||d0!=fft_sizes[fft_alloc_calls])$fatal(1,"FFT allocation call pairing/size");
            fft_kind=1;fft_resume=pc+2;fft_alloc_calls++;
            $display("FFT_CALL alloc=%0d pc=%h size=%h",fft_alloc_calls,pc,d0);
        end else if(fft_free_pc(pc) && op==16'ha01f)begin
            int found;found=-1;
            if(secondary||fft_kind!=0||fft_free_calls>=3)$fatal(1,"FFT free call pairing");
            for(int x=0;x<3;x++)if(fft_ptrs[x]==a0)found=x;
            if(found!=fft_free_calls||fft_freed[found])$fatal(1,"FFT free pointer/order %h",a0);
            fft_free_pointer=a0;fft_freed[found]=1;fft_kind=2;fft_resume=pc+2;fft_free_calls++;
            $display("FFT_CALL free=%0d pc=%h ptr=%h",fft_free_calls,pc,a0);
        end else if(fft_kind!=0 && pc==fft_resume)begin
            if(d0!=0)$fatal(1,"FFT memory trap error %h at%h",d0,pc);
            if(secondary)fft_secondary++;else fft_primary++;
            if(fft_kind==1)begin
                int index,size;index=fft_alloc_returns;size=fft_sizes[index];
                if(op!=fft_alloc_return_op(index)||a0==0||a0<=fft_zone||a0+size>fft_bklim||a0+size>fft_memtop||(a0<'h642000&&a0+size>'h600000))$fatal(1,"FFT allocated pointer/op bounds %h",a0);
                for(int x=0;x<index;x++)if(a0<fft_ptrs[x]+fft_sizes[x]&&a0+size>fft_ptrs[x])$fatal(1,"FFT allocation overlap");
                fft_ptrs[index]=a0;fft_alloc_returns++;
                $display("FFT_RETURN alloc=%0d pc=%h ptr=%h size=%h error=%h secondary=%0d",fft_alloc_returns,pc,a0,size,d0,secondary);
            end else begin
                if(op!=fft_free_return_op(fft_free_returns))$fatal(1,"FFT free resume opcode");
                fft_free_returns++;
                $display("FFT_RETURN free=%0d pc=%h ptr=%h error=%h secondary=%0d",fft_free_returns,pc,fft_free_pointer,d0,secondary);
            end
            fft_kind=0;
        end else if(pc=='h600d38 && op=='h4eba)begin
            fft_exptab_calls++;if(secondary||fft_exptab_calls!=1)$fatal(1,"FFT FExptab call count");
            $display("FFT_FEXPTAB_CALL count=%0d",fft_exptab_calls);
        end else if(pc=='h6009de && op=='h4e56)begin
            if(secondary||fft_math_pending||fft_alloc_returns!=3)$fatal(1,"FFT native entry pairing");
            fft_calls++;fft_math_pending=1;if(fft_calls>20)$fatal(1,"FFT call count");
            $display("FFT_FFFT_ENTRY count=%0d",fft_calls);
        end else if(pc=='h600a00 && op=='h2a08)begin
            if(!fft_math_pending||a0!='h100||a2!=fft_ptrs[0]||a3!=fft_ptrs[1]||d7!=fft_ptrs[2])$fatal(1,"FFT live N/pointer ABI");
            fft_n_checks++;
        end else if(pc=='h600a1c && op=='hf232 && fft_math_pending)begin
            if(a2!=fft_ptrs[0]||a3!=fft_ptrs[1]||d7!=fft_ptrs[2]||!`FC.g_fpu.fpu.fr_valid[4]||`FC.g_fpu.fpu.fpregs.bank_a[4]!=80'h3ffb_8000000000000000||`FC.g_fpu.fpu.fpregs.bank_b[4]!=80'h3ffb_8000000000000000)$fatal(1,"FFT live scalar/pointer ABI");
            fft_scalar_checks++;fft_math_pending=0;
            $display("FFT_ABI call=%0d N=256 input=%h scratch=%h twiddle=%h scalar=3ffb8000000000000000",fft_calls,a2,a3,d7);
        end
    end
endtask
always @(posedge clk_sys)begin : fft_dispatch_sample
    bit secondary,before_toggle;int pre_pc,pre_a0,pre_d0,pre_a2,pre_a3,pre_d7;bit[15:0]pre_op;
    before_toggle=`FC.perf_dispatch_toggle;secondary=`FC.pipe_rf_owner&&`FC.pipe_input&&`FC.pipe_ready;
    pre_pc=`FC.pc;pre_op=`FC.epf_data[`FC.epf_head];pre_a0=fft_tap(8);pre_d0=fft_tap(0);pre_a2=fft_tap(10);pre_a3=fft_tap(11);pre_d7=fft_tap(7);
    #1;
    if(nreset && in_loop)begin
        if(!fft_zone_saved)begin
            fft_zone=fft_u32('h118);fft_bklim=fft_u32(fft_zone);fft_freebytes=fft_u32(fft_zone+12);fft_memtop=fft_u32('h108);
            if(fft_zone!=fft_u32('h2aa)||fft_zone!='h3f1890||fft_bklim!='h492078||fft_memtop!='h517754)$fatal(1,"FFT initial heap identity");
            dump_hex("fft_zone_before.hex",fft_zone,fft_zone+63);dump_hex("fft_limit_before.hex",fft_bklim-32,fft_bklim+31);fft_zone_saved=1;
            $display("FFT_HEAP_START zone=%h bkLim=%h free=%h memtop=%h",fft_zone,fft_bklim,fft_freebytes,fft_memtop);
        end
        if(`FC.perf_dispatch_toggle!=before_toggle)begin
            if(secondary)fft_event(pre_pc,pre_op,pre_a0,pre_d0,pre_a2,pre_a3,pre_d7,1);
            else fft_event(`FC.pc_i,`FC.ir,fft_tap(8),fft_tap(0),fft_tap(10),fft_tap(11),fft_tap(7),0);
        end
    end
end
task fft_finish;
    if(!fft_zone_saved||fft_kind!=0||fft_alloc_calls!=3||fft_alloc_returns!=3||fft_free_calls!=3||fft_free_returns!=3||fft_calls!=20||fft_exptab_calls!=1||fft_math_pending||fft_n_checks!=20||fft_scalar_checks!=20)$fatal(1,"FFT lifecycle incomplete");
    for(int x=0;x<3;x++)if(!fft_freed[x])$fatal(1,"FFT unfreed payload");
    if(fft_u32('h118)!=fft_zone||fft_u32('h2aa)!=fft_zone||fft_u32('h108)!=fft_memtop||fft_u32(fft_zone)!=fft_bklim||fft_u32(fft_zone+12)!=fft_freebytes)$fatal(1,"FFT heap scalar restoration");
    dump_hex("fft_zone_after.hex",fft_zone,fft_zone+63);dump_hex("fft_limit_after.hex",fft_bklim-32,fft_bklim+31);
    $display("FFT_TRAPS alloc_calls=%0d alloc_returns=%0d free_calls=%0d free_returns=%0d primary_resumes=%0d secondary_resumes=%0d FFft_calls=%0d FExptab_calls=%0d N_checks=%0d scalar_checks=%0d",fft_alloc_calls,fft_alloc_returns,fft_free_calls,fft_free_returns,fft_primary,fft_secondary,fft_calls,fft_exptab_calls,fft_n_checks,fft_scalar_checks);
    $display("FFT_HEAP_END zone=%h bkLim=%h free=%h memtop=%h",fft_zone,fft_bklim,fft_freebytes,fft_memtop);
endtask
`undef FC
