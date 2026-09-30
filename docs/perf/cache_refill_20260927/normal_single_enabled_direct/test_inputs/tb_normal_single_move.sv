`timescale 1ns/1ps

// Real-port all-precision FMOVE.S qualification with independent normal-single
// conversion oracle, physical-bank/dependency checks, and excluded-path
// signature comparison. Reuses the normalization bench port scaffold.
module tb_normal_single_move;
reg clk = 0;
always #5 clk = ~clk;
reg nreset=0,ce=1,req=0;
reg[2:0]op_class=2,src_fmt=1,src_r=0,dst_r=0,fm_sel=0;
reg[6:0]opmode=0;reg[95:0]din=0,fm_wdata=0;
reg[1:0]cr_sel=0;reg[31:0]cr_wdata=0,ia_wdata=0;
reg cr_we=0,fm_we=0,bsun_req=0,ia_we=0,fp_reset=0,fsave_ack=0;
reg frestore_idle=0,frestore_unimp=0,pend_capture=0;
reg[7:0]frestore_cusavepc=0;reg frestore_busy=0;
reg[15:0]frestore_cmd1=0;reg[2:0]frestore_flags=0;
reg[95:0]frestore_fpt=0,frestore_et=0;
wire done,accepted,unimp,unsupp,exc_req,frestore_e1_pend;wire[7:0]exc_vec;
wire[95:0]dout;integer checks=0,fast_cases=0,slow_cases=0;
ap040_fpu dut (
    .clk(clk), .nreset(nreset), .ce(ce), .req(req),
    .done(done),.accepted(accepted),.unimp(unimp),.unsupp(unsupp),.exc_req(exc_req),.exc_vec(exc_vec),.dout(dout),
    .frestore_e1_pend(frestore_e1_pend),.op_class(op_class), .opmode(opmode), .src_fmt(src_fmt),
    .src_r(src_r), .dst_r(dst_r), .din(din),
    .cr_sel(cr_sel), .cr_we(cr_we), .cr_wdata(cr_wdata), .bsun_req(bsun_req),
    .ia_we(ia_we), .ia_wdata(ia_wdata), .fm_sel(fm_sel), .fm_we(fm_we),
    .fm_wdata(fm_wdata), .fsave_ack(fsave_ack), .frestore_idle(frestore_idle),
    .frestore_unimp(frestore_unimp), .pend_capture(pend_capture), .frestore_cusavepc(frestore_cusavepc),
    .frestore_et15(1'b0), .frestore_fpt15(1'b0), .frestore_wbt(96'd0),
    .frestore_fpiar(32'd0), .frestore_busy(frestore_busy), .frestore_cmd1(frestore_cmd1),
    .frestore_cmd3(16'd0), .frestore_stag(3'd0), .frestore_dtag(3'd0),
    .frestore_flags(frestore_flags), .frestore_fpt(frestore_fpt), .frestore_et(frestore_et),
    .frestore_grs(3'd0), .frestore_wbte15(1'b0), .fp_reset(fp_reset)
);
function automatic[79:0] canonical(input int regnum);
    return dut.fr_valid[regnum]?dut.fpregs.bank_a[regnum]:80'h7fff_ffffffffffffffff;
endfunction
task tick;
    @(posedge clk);#1;
endtask
task idle;
    @(negedge clk);req=0;cr_we=0;fm_we=0;bsun_req=0;ia_we=0;fp_reset=0;
    fsave_ack=0;frestore_idle=0;frestore_unimp=0;pend_capture=0;
endtask
task reset;
    idle();nreset=0;ce=1;tick();idle();nreset=1;
    // Preserve quotient/accrued fields while clearing status/CC on completion.
    cr_we=1;cr_sel=1;cr_wdata=32'h0540a0f8;tick();idle();
endtask
task control(input[31:0]value);
    cr_we=1;cr_sel=2;cr_wdata=value;tick();idle();
endtask
// Legal req may pulse, remain until accepted, or remain until terminal. It
// drops before the next IDLE edge; indefinitely held req is not a transaction.
task normal(input[31:0]word,input int precision,input int mode,input int holdkind,input bit pause_ce);
    bit sign;reg[7:0]exponent;reg[63:0]mant;reg[14:0]ext_exp;
    reg[79:0]expected;reg[95:0]shadow;reg[31:0]status;
    int enabled_edges,accept_edges;reg[255:0]held;
    reset();control((enable_mask<<8)|(precision<<6)|(mode<<4));
    sign=word[31];exponent=word[30:23];mant={1'b1,word[22:0],40'd0};
    ext_exp=exponent+15'd16256;expected={sign,ext_exp,mant};shadow={sign,ext_exp,16'd0,mant};
    op_class=2;opmode=0;src_fmt=1;dst_r=checks%8;src_r=dst_r;
    // Seed the old destination with an exceptional extended value. FMOVE.S
    // must overwrite it without treating it as an arithmetic input.
    fm_sel=dst_r;fm_we=1;
    case(checks%4)
      0:fm_wdata=96'h7fff_ffff_ffffffffffffffff; // quiet NaN
      1:fm_wdata=96'h7fff_0000_0000000000000001; // signaling NaN
      2:fm_wdata=96'hffff_0000_8000000000000000; // negative quiet NaN
      default:fm_wdata=96'h0000_0000_0000000000000001; // unusual exponent
    endcase
    tick();idle();
    din={word,64'h0123456789abcdef};ia_we=1;ia_wdata=32'h12345678;req=1;
    tick();enabled_edges=1;accept_edges=accepted;
`ifdef CAND
    if(dut.fst!=14)$fatal(1,"eligible candidate not ROUND");fast_cases++;
`else
    if(dut.fst!=1)$fatal(1,"baseline missing SRC");slow_cases++;
`endif
    @(negedge clk);ia_we=0;if(holdkind==0 || holdkind==1&&accepted)req=0;
    if(pause_ce)begin
        ce=0;held={dut.fst,dut.a_s,dut.a_e,dut.a_m,dut.grs,dut.e_w,dut.sh_cmd,dut.sh_stag,done};
        repeat(2)begin tick();if(held!={dut.fst,dut.a_s,dut.a_e,dut.a_m,dut.grs,dut.e_w,dut.sh_cmd,dut.sh_stag,done})$fatal(1,"CE hold");end
        @(negedge clk);ce=1;
    end
    while(!done)begin
        tick();enabled_edges++;accept_edges+=accepted;
        if(unimp||unsupp||exc_req||enabled_edges>16)$fatal(1,"normal terminal contract");
        @(negedge clk);if(holdkind==1&&accepted || done)req=0;
    end
`ifdef CAND
    if(enabled_edges!=3)$fatal(1,"candidate normal latency %0d",enabled_edges);
`else
    if(enabled_edges!=5)$fatal(1,"baseline normal latency %0d",enabled_edges);
`endif
    if(dut.fpcr!==((enable_mask<<8)|(precision<<6)|(mode<<4)))$fatal(1,"FPCR changed on memory MOVE");
    if(accept_edges!=1||dut.fst!=0||!dut.fpu_used||!dut.fr_valid[dst_r])$fatal(1,"accepted/done contract");
    if(canonical(dst_r)!==expected || dut.fpregs.bank_b[dst_r]!==expected)$fatal(1,"independent single conversion");
    status=32'h004000f8 | (sign?32'h08000000:0);
    if(dut.fpsr!==status || dut.fpiar!==32'h12345678 || dut.sh_cmd!=={3'b010,3'd1,dst_r,7'd0} || dut.sh_src!==shadow || dut.sh_stag!==0)$fatal(1,"status/FPIAR/shadow");
    tick();if(done)$fatal(1,"done repeated after req dropped");normal_cases++;
    // Immediate dependent register MOVE exercises physical bank read, not
    // just debug mirror result. Register-source path remains unchanged.
    @(negedge clk);src_r=dst_r;dst_r=(dst_r+1)%8;op_class=0;req=1;
    tick();if(dut.fst!=3)$fatal(1,"register-source path changed");@(negedge clk);req=0;
    enabled_edges=1;while(!done)begin tick();enabled_edges++;if(enabled_edges>16)$fatal(1,"dependent timeout");end
    if(dut.fpcr!==((enable_mask<<8)|(precision<<6)|(mode<<4)))$fatal(1,"FPCR changed on dependent MOVE");
    if(canonical(dst_r)!==expected || dut.fpsr!==status)$fatal(1,"dependent physical read");
    idle();tick();checks++;
endtask
task excluded(input[31:0]word,input[6:0]operation,input[31:0]cfgreg,input int side);
    int edges;bit[2:0]terminal;
    reset();control(cfgreg);op_class=2;src_fmt=case_fmt;opmode=operation;dst_r=2;src_r=2;
    din={word,64'd0};req=1;
    case(side)
     1:begin cr_we=1;cr_sel=0;cr_wdata=32'hcafef00d;end
     2:begin fm_we=1;fm_sel=7;fm_wdata=96'h3fff00008000000000000000;end
     3:bsun_req=1;
     4:fp_reset=1;
     5:frestore_idle=1;
     6:frestore_unimp=1;
     7:fsave_ack=1;
     8:pend_capture=1;
    endcase
    tick();edges=1;
    // Same first-state slow route, or synchronous unimplemented signal.
    if(dut.fst==14 && !unimp)$fatal(1,"excluded command fastpath");slow_cases++;
    idle();while(!(done||unimp||unsupp||exc_req))begin tick();edges++;if(edges>1024)$fatal(1,"excluded timeout");end
    $display("SIG word=%h op=%h cfg=%h side=%0d fmt=%0d reg=%h status=%h ctrl=%h iar=%h term=%b%b%b%b vec=%h used=%b cmd=%h stag=%h et=%h fpt=%h",
       word,operation,cfgreg,side,case_fmt,canonical(2),dut.fpsr,dut.fpcr,dut.fpiar,done,unimp,unsupp,exc_req,exc_vec,dut.fpu_used,dut.fstate_cmd1,dut.fstate_stag,dut.fstate_et,dut.fstate_fpt);
    idle();tick();checks++;
endtask
task reset_fill;
    reset();control(0);op_class=2;opmode=0;src_fmt=1;dst_r=0;din={32'h3f800000,64'd0};req=1;tick();
    @(negedge clk);nreset=0;tick();
    if(dut.fst!=0||dut.fr_valid!=0||dut.fpu_used||done||accepted)$fatal(1,"reset during command");
    idle();nreset=1;tick();checks++;
endtask
task restored_pending;
    int edges;
    reset();control(32'h00002000);frestore_unimp=1;frestore_busy=0;frestore_cmd1=16'h4400;frestore_flags=4;
    frestore_et=96'h3fff00008000000000000000;frestore_fpt=96'h400000008000000000000000;tick();idle();
    op_class=2;opmode=0;src_fmt=1;dst_r=1;din={32'hbf800000,64'd0};req=1;tick();idle();
    edges=0;while(!done)begin tick();edges++;if(unimp||unsupp||exc_req||edges>32)$fatal(1,"restored frame incorrectly resignalled/timed out");end
    if(canonical(1)!==80'hbfff8000000000000000 || dut.fstate_unimp)$fatal(1,"restored pending normal result");
    checks++;idle();tick();frestore_flags=0;
endtask
task restore_resume;
    int edges;
    reset();control(32'h00002000);frestore_unimp=1;frestore_busy=1;frestore_cusavepc=8'hfe;
    frestore_cmd1=16'h4000;frestore_flags=0;frestore_et=96'h3fff00008000000000000000;
    frestore_fpt=96'h400000008000000000000000;
    op_class=2;opmode=0;src_fmt=1;dst_r=2;din={32'h40400000,64'd0};req=1;
    tick();if(dut.fst!=5)$fatal(1,"restore resume lost precedence");idle();edges=1;
    while(!done)begin tick();edges++;if(unimp||unsupp||edges>32)$fatal(1,"resume terminal");end
    if(canonical(0)!==80'h3fff8000000000000000)$fatal(1,"restored operand lost");
    $display("SIG_RESTORE result=%h status=%h used=%b",canonical(0),dut.fpsr,dut.fpu_used);
    idle();frestore_busy=0;frestore_cusavepc=0;tick();checks++;
endtask
task restored_e1_pending;
    reset();control(32'h00002000);
    cr_we=1;cr_sel=1;cr_wdata=32'h00002000;tick();idle();
    frestore_unimp=1;frestore_busy=0;frestore_cmd1=16'h4000;frestore_flags=4;
    frestore_et=96'h3fff00008000000000000000;
    frestore_fpt=96'h400000008000000000000000;
    #1;if(!frestore_e1_pend)$fatal(1,"enabled restored E1 pend not asserted");
    tick();if(!dut.fstate_unimp||!dut.fstate_e1)$fatal(1,"restored E1 state not retained");
    if(dut.fstate_et!==frestore_et||dut.fstate_fpt!==frestore_fpt||dut.fstate_cmd1!==frestore_cmd1)$fatal(1,"restored E1 frame fields changed");
    idle();control(0);
    if(frestore_e1_pend)$fatal(1,"restored E1 pend remained enabled after FPCR clear");
    if(!dut.fstate_unimp||!dut.fstate_e1||dut.fstate_et!==frestore_et||dut.fstate_fpt!==frestore_fpt||dut.fstate_cmd1!==frestore_cmd1)$fatal(1,"FPCR clear destroyed restored E1 frame");
    checks++;
endtask
integer sign,exp,frac,mode,precision,enable_i,rep_i;integer enable_mask=8'h20,normal_cases=0;
reg[2:0]case_fmt=1;reg[22:0]fractions[8];reg[31:0]word;reg[31:0]representatives[8];
initial begin
 fractions[0]=0;fractions[1]=1;fractions[2]='h3fffff;fractions[3]='h400000;
 fractions[4]='h400001;fractions[5]='h7ffffe;fractions[6]='h7fffff;fractions[7]='h555555;
 // Workload-mode exhaustive sweep: every normal sign/exponent/fraction
 // boundary sample at the measured FPCR exception enable 0x20.
 enable_mask=8'h20;
 for(precision=0;precision<4;precision++)for(sign=0;sign<2;sign++)for(exp=1;exp<255;exp++)for(frac=0;frac<8;frac++)for(mode=0;mode<4;mode++)begin
  word=(sign<<31)|(exp<<23)|fractions[frac];normal(word,precision,mode,checks%3,checks%257==0);
 end
 // Representative normal boundaries across every exception-enable mask,
 // precision and rounding mode. This separately proves the guard is absent
 // for all 256 enable values without repeating the full 65k sweep.
 representatives[0]=32'h00800000;representatives[1]=32'h00800001;
 representatives[2]=32'h00ffffff;representatives[3]=32'h3f000000;
 representatives[4]=32'h3f800000;representatives[5]=32'h7f000000;
 representatives[6]=32'h7f7ffffe;representatives[7]=32'hff7fffff;
 for(enable_i=0;enable_i<256;enable_i++)for(precision=0;precision<4;precision++)for(mode=0;mode<4;mode++)for(rep_i=0;rep_i<8;rep_i++)begin
   enable_mask=enable_i;normal(representatives[rep_i],precision,mode,(enable_i+rep_i)%3,(enable_i+rep_i)%31==0);
 end
 enable_mask=8'h20;
 excluded(0,0,0,0);excluded(32'h80000000,0,0,0);
 excluded(1,0,0,0);excluded(32'h007fffff,0,0,0);excluded(32'h80000001,0,0,0);
 excluded(32'h7f800000,0,0,0);excluded(32'hff800000,0,0,0);
 excluded(32'h7fc12345,0,0,0);excluded(32'h7f812345,0,0,0);
 // Former precision exclusions are now explicit fast positive cases.
 for(precision=1;precision<4;precision++)normal(32'h3f800000,precision,0,precision%3,1);
 excluded(32'h3f800000,'h18,0,0);excluded(32'h3f800000,'h1a,0,0);
 excluded(32'h3f800000,'h04,0,0);excluded(32'h3f800000,'h22,0,0);
 excluded(32'h3f800000,'h38,0,0);excluded(32'h3f800000,'h3a,0,0);
 excluded(32'h3f800000,'h10,0,0);
 for(mode=1;mode<=8;mode++)excluded(32'h3f800000,0,0,mode);
 for(mode=0;mode<8;mode++)if(mode!=1)begin case_fmt=mode;excluded(32'h3f800000,0,0,10+mode);end
 // Exceptional encodings stay excluded from the shortcut. With all
 // exception enables set, compare trap/status/frame outputs against baseline.
 case_fmt=1;excluded(32'h7fc12345,0,32'h0000ff00,0);excluded(32'h7f812345,0,32'h0000ff00,0);
 excluded(32'h00000000,0,32'h0000ff00,0);excluded(32'h7f800000,0,32'h0000ff00,0);
 reset_fill();restored_pending();restored_e1_pending();restore_resume();
 $display("PASS normal_single checks=%0d normal=%0d fast=%0d slow=%0d",checks,normal_cases,fast_cases,slow_cases);$finish;
end
endmodule
