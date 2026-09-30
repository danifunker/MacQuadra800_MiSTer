// Prepared direct-port byte oracle. No CPU/MMU/physical RAM timing claim.
// TEST_XFIRST permits candidate phase observation; cache feature macro is XSTORE.
`timescale 1ns/1ps
module tb_xfirst_sideband;
 reg clk=0;always #5 clk=~clk;
 reg reset_n=0,ce=1,req=0,wr=0,instr=0,de=1,ci=0,post=0;
 reg [1:0] size=2;reg [31:0] addr=0,wdata=0;
 reg cinv=0;wire cinv_done,done,mreq,mwr;wire[31:0] data,ma,mw;
 wire[1:0] ms;wire[2:0] mf;
 reg ack=0,err=0;reg[31:0] mr=0;
 reg snoop=0;reg[31:0] sa=0;
 reg line_valid=0;reg[27:0] line_tag=0;reg[127:0] line_data=0;
 reg[7:0] memory[0:65535],oracle[0:65535];
 reg hint_fast=0;reg[31:0] prev_hint=0;
 always @(posedge clk)prev_hint<=addr;
 ap040_cache dut(.clk(clk),.nreset(reset_n),.ce(ce),.ie(1'b1),.de(de),
  .cinv_req(cinv),.cinv_ic(1'b1),.cinv_dc(1'b1),.cinv_done(cinv_done),
  .c_req(req),.c_write(wr),.c_instr(instr),.c_size(size),.c_addr(addr),.c_wdata(wdata),
  .c_fc(instr?3'd6:3'd5),.c_nocache(ci),.c_post_ok(post),.c_post_ok_hint(1'b0),
  .c_hint_addr(addr),.c_hint_instr(instr),.c_hint_ptag(addr[31:10]),
  .c_hint_match(hint_fast && req && !instr && prev_hint==addr),.c_hint_wmatch(1'b0),.c_hint_away(1'b0),
  .c_ihint_addr(addr),.c_ihint_ptag(addr[31:10]),.c_ihint_match(1'b0),.c_ihold(instr && req),
  .c_ack(done),.c_rdata(data),.m_req(mreq),.m_write(mwr),.m_instr(),.m_size(ms),
  .m_addr(ma),.m_wdata(mw),.m_fc(mf),.m_ack(ack),.m_rdata(mr),.m_err(err),
  .m_line_valid(line_valid),.m_line_tag(line_tag),.m_line_data(line_data),.s_stb(snoop),.s_addr(sa));
`ifdef TEST_XFIRST
 localparam IS_CANDIDATE=1;wire phase=dut.xfirst_fill;
`else
 localparam IS_CANDIDATE=0;wire phase=1'b0;
`endif
 function automatic[31:0] expected(input integer a,input integer sz);
  reg[31:0] result;integer n;begin result=0;n=sz==0?1:sz==1?2:4;
   for(integer b=0;b<n;b++)result=(result<<8)|oracle[a+b];expected=result;end
 endfunction
 function automatic[127:0] retained(input integer a);
  reg[127:0] result;begin result=0;for(integer b=0;b<16;b++)result=(result<<8)|memory[(a&65520)+b];retained=result;end
 endfunction
 // A latched, single outstanding physical cache request. Fields cannot
 // change/drop while an issued request is pending, even if CE is stopped.
 reg bus_active=0;reg[31:0] bus_addr,bus_wdata;reg[1:0] bus_size;reg bus_write;
 reg[2:0] bus_fc;integer delay_left=0,delay_setting=4,reads=0,writes=0;
 reg publish=0;integer publish_base=0;
 reg error_arm=0;integer error_word=0;integer errors_seen=0,issued_requests=0;reg error_with_ack=0;
 always @(posedge clk)begin
  if(!reset_n)begin bus_active<=0;ack<=0;err<=0;line_valid<=0;end
  else begin
   if(bus_active && !ack && !err && (!mreq || {ma,ms,mwr,mw,mf}!=={bus_addr,bus_size,bus_write,bus_wdata,bus_fc}))
    $fatal(1,"physical issued request changed/abandoned");
   if(ce)begin
    ack<=0;err<=0;
    if(bus_active)begin
     if(delay_left!=0)delay_left<=delay_left-1;
     else begin
      bus_active<=0;
      if(error_arm && !bus_write && (bus_addr&65532)==error_word)begin err<=1;ack<=error_with_ack;errors_seen++;end
      else begin
       ack<=1;mr=0;
       for(integer b=0;b<(bus_size==0?1:bus_size==1?2:4);b++)begin
        if(bus_write)memory[bus_addr+b]=bus_wdata>>(8*((bus_size==0?1:bus_size==1?2:4)-b-1));
        else mr=(mr<<8)|memory[bus_addr+b];
       end
       if(bus_write)begin writes++;if(line_tag==bus_addr[31:4])line_valid<=0;end
       else begin
        reads++;
        if(publish && (bus_addr&65520)==publish_base)begin line_tag<=bus_addr[31:4];line_data<=retained(bus_addr);line_valid<=1;end
       end
      end
     end
    end else if(mreq && !ack && !err)begin
     issued_requests++;bus_active<=1;bus_addr<=ma;bus_size<=ms;bus_write<=mwr;bus_wdata<=mw;bus_fc<=mf;delay_left<=delay_setting;
     $display("PHASE_BUS addr=%08h size=%0d write=%0d fc=%0d phase=%0d cnt=%0d",ma,ms,mwr,mf,phase,dut.fill_cnt);
    end
   end
  end
 end
 integer phases=0,critical_issued=0,local_words=0,publications=0,local_fallbacks=0,poison_passes=0;
 integer phase_errors=0,acks=0,cases=0,expected_way=-1,external_tail_requests=0;
 integer coverage[0:15];integer held_faults=0,error_ack_overlaps=0,cinv_completions=0;
 integer case_phase=0,case_local=0,case_pub=0,case_fallback=0,case_poison=0,case_error=0;
 // Scenario IDs: residency, victims, loss, DMA, delayed, critical-error,
 // second-critical-error, excluded, prevalid, error-line, late-error,
 // posted-order, CINV, reset, wrong-tag, ACK+error.
 task automatic scenario(input integer id);
  begin coverage[id]++;cases++;
   $display("PHASE_CASE id=%0d count=%0d entries=%0d local_words=%0d publications=%0d fallbacks=%0d poison=%0d errors=%0d",id,coverage[id],phases-case_phase,local_words-case_local,publications-case_pub,local_fallbacks-case_fallback,poison_passes-case_poison,phase_errors-case_error);
   case_phase=phases;case_local=local_words;case_pub=publications;
   case_fallback=local_fallbacks;case_poison=poison_passes;case_error=phase_errors;
  end
 endtask
 reg last_phase=0;reg[31:0] original_addr;reg[1:0] original_size;
 always @(posedge clk)begin
  if(!reset_n)last_phase=0;
  else begin
   if(phase && !last_phase)begin
    phases++;original_addr=addr;original_size=size;
    if(expected_way>=0 && dut.r_way!=expected_way)$fatal(1,"first-fill replacement way mismatch");
   end
   if(phase)begin
    if(!req || wr || instr || addr!==original_addr || size!==original_size || dut.r_addr!==original_addr || dut.r_bank)
     $fatal(1,"first-fill original operand ownership changed");
    if(done || dut.fill_acked)$fatal(1,"premature operand ACK during first fill");
    if(dut.ci_inv_pend || dut.store_inv_lost)$fatal(1,"first-fill owed invalidation invariant");
    if(dut.tag_we && dut.inv_wren && dut.tag_widx==dut.inv_idx)$fatal(1,"tag write collision");
    if(dut.ctag_ram.wren_a!==dut.ctag_ram_i.wren_a || dut.ctag_ram.wren_b!==dut.ctag_ram_i.wren_b)
     $fatal(1,"mirror tag controls disagree");
    if(dut.cst==4 && dut.fill_cnt!=0 && (mreq || dut.r_issued))begin
     external_tail_requests++;$fatal(1,"external first-line nonoperand tail request");
    end
    if(dut.cst==4 && mreq && (ma!=={original_addr[31:2],2'b0} || ms!=2 || mf!=5 || mwr))
     $fatal(1,"first-fill external request not requested aligned word");
    if(ce)begin
     if(dut.cst==4 && mreq && !dut.r_issued)critical_issued++;
     if(dut.cst==4 && dut.fill_cnt!=0 && dut.fill_line_match)local_words++;
     if(dut.cst==5)begin
      if(dut.fill_snooped || dut.snoop_fill_row || dut.inv_wren)poison_passes++;
      else publications++;
     end
     if(dut.cst==2 && !dut.snoop_wr)begin
      if(!dut.fill_err_inv || !dut.inv_wren || dut.inv_idx!=dut.r_row)$fatal(1,"fallback failed victim row cleanup");
      local_fallbacks++;
     end
     if(dut.cst==4 && err)phase_errors++;
    end
   end
   if(ce && ack && err)error_ack_overlaps++;
   if(ce && done && req && !err)acks++;
   last_phase=phase;
  end
 end
 task automatic drain;
  integer guard;begin guard=0;
   while(dut.cst!=0 || mreq || bus_active || ack || err)begin @(negedge clk);guard++;if(guard>5000)$fatal(1,"drain timeout");end
  end
 endtask
 task automatic access(input bit write_op,input integer a,input integer sz,input[31:0] payload);
  integer guard,start_acks;reg[31:0] want;begin
   @(negedge clk);req=1;wr=write_op;addr=a;size=sz;wdata=payload;guard=0;start_acks=acks;
   begin:wait_ack
    forever begin @(posedge clk);guard++;
     if(err)$fatal(1,"unexpected fault address=%08h",a);
     if(done && ce)begin
      want=expected(a,sz);if(!write_op && data!==want)$fatal(1,"operand bytes a=%08h size=%0d got=%08h want=%08h",a,sz,data,want);
      disable wait_ack;
     end
     if(guard>5000)$fatal(1,"operand timeout");
    end
   end
   @(negedge clk);req=0;wr=0;@(negedge clk);
   if(acks-start_acks!=1)$fatal(1,"duplicate/missing operand ACK");
  end
 endtask
 task automatic cold(input integer base,input integer residency);
  begin
   @(negedge clk);reset_n=0;req=0;wr=0;instr=0;ce=1;ci=0;de=1;post=0;cinv=0;snoop=0;error_arm=0;error_with_ack=0;publish=0;line_valid=0;expected_way=-1;
   repeat(3)@(negedge clk);reset_n=1;drain();
   if(residency&1)begin access(0,base,2,0);drain();end
   if(residency&2)begin access(0,base+16,2,0);drain();end
  end
 endtask
 task automatic check_line(input integer base,input bit must_hit);
  integer reads_before;begin drain();reads_before=reads;
   for(integer w=0;w<4;w++)begin access(0,base+4*w,2,0);drain();end
   if(must_hit && reads!=reads_before)$fatal(1,"installed line missed base=%08h",base);
  end
 endtask
 task automatic dma(input integer a,input bit freeze);
  begin
   @(negedge clk);if(freeze)ce=0;
   oracle[a]=oracle[a]^8'h5a;memory[a]=oracle[a];sa=a;snoop=1;
   if(line_tag==(a>>4))line_valid=0;
   repeat(2)@(negedge clk);snoop=0;ce=1;
  end
 endtask
 task automatic await_stage(input integer stage);
  begin
   if(IS_CANDIDATE)begin
    if(stage==4)wait(phase && dut.cst==5);
    else wait(phase && dut.cst==4 && dut.fill_cnt==stage);
   end else wait(req && dut.cst==6);
  end
 endtask
 // Hold the original request through error cleanup. No qualified ACK or
 // new physical request is legal until withdrawal; raw PASS ACK is allowed
 // only when the same edge has m_err, matching the wrapper error qualification.
 task automatic fault_access(input integer a,input integer aligned_fault);
  integer guard,start_acks,held_issued;begin
   error_arm=1;error_word=aligned_fault;start_acks=acks;
   @(negedge clk);req=1;wr=0;addr=a;size=2;guard=0;
   while(!err)begin @(posedge clk);guard++;
    if(done && ce && !err)$fatal(1,"faulting operand acknowledged");
    if(guard>5000)$fatal(1,"fault not reached");end
   @(negedge clk);held_issued=issued_requests;
   repeat(8)begin @(negedge clk);
    if(!dut.err_hold || mreq || issued_requests!=held_issued || (done && !err))
     $fatal(1,"held fault was reissued/acknowledged or lost err_hold");
   end
   held_faults++;
   req=0;error_arm=0;error_with_ack=0;
   @(negedge clk); // one enabled posedge observes withdrawal and clears err_hold
   drain();
   if(acks!=start_acks)$fatal(1,"fault counted operand ACK");
   if(phase || dut.err_hold)$fatal(1,"fault phase/hold not released");
   // Retry only after the old request was withdrawn and error cleanup drained.
   access(0,a,2,0);drain();
  end
 endtask
 integer base,residency,form,way,mode,stage,start_phase,start_pub,start_fallback,start_errors,start_cinv,start_critical;
 initial begin
  for(integer c=0;c<16;c++)coverage[c]=0;
  for(integer i=0;i<65536;i++)begin memory[i]=(i*13+7)&255;oracle[i]=memory[i];end
  // Residency, crossing offset/size, set/tag wrap and both hint modes.
  for(mode=0;mode<2;mode++)for(residency=0;residency<4;residency++)for(form=0;form<4;form++)begin
   base=form==3?16'h1ff0:16'h4000;hint_fast=mode;cold(base,residency);
   publish=1;publish_base=base;start_phase=phases;
   access(0,base+(form==3?15:13+form),form==3?1:2,0);drain();
   if(IS_CANDIDATE && !(residency&1) && phases!=start_phase+1)$fatal(1,"missing first-fill coverage");
   check_line(base,IS_CANDIDATE || (residency&1));check_line(base+16,IS_CANDIDATE || (residency&1));scenario(0);
  end
  // All four live replacement victims; verify their old data after reuse.
  for(way=0;way<4;way++)begin
   base=16'h1000;hint_fast=0;cold(base,2);
   for(integer tag=1;tag<=4+way;tag++)begin access(0,base+tag*16'h800,2,0);drain();end
   expected_way=way;publish=1;publish_base=base;access(0,base+14,2,0);drain();expected_way=-1;
   check_line(base,IS_CANDIDATE);check_line(base+16,1);
   for(integer tag=1;tag<=4+way;tag++)check_line(base+tag*16'h800,0);scenario(1);
  end
  // Retained-line absent or lost at each unissued local tail slot.
  for(stage=0;stage<4;stage++)begin
   base=16'h5000;cold(base,2);
   for(integer tag=1;tag<=4;tag++)begin access(0,base+tag*16'h800,2,0);drain();end
   publish=stage!=0;publish_base=base;start_fallback=local_fallbacks;
   fork
    access(0,base+14,2,0);
    begin if(stage!=0 && IS_CANDIDATE)begin await_stage(stage);@(negedge clk);line_valid=0;publish=0;end end
   join
   drain();if(IS_CANDIDATE && local_fallbacks!=start_fallback+1)$fatal(1,"missing local-loss cleanup/fallback");
   check_line(base,0);check_line(base+16,0);
   for(integer tag=1;tag<=4;tag++)check_line(base+tag*16'h800,0);scenario(2);
  end
  // First/next/unrelated row DMA across every fill/TAGW edge, CE pause.
  for(mode=0;mode<3;mode++)for(stage=0;stage<5;stage++)begin
   base=16'h6000;cold(base,2);publish=1;publish_base=base;
   fork
    access(0,base+14,2,0);
    begin await_stage(stage);dma(mode==0?base+14:mode==1?base+16:base+16'h100,stage==1);end
   join
   drain();check_line(base,0);check_line(base+16,0);scenario(3);
  end
  // Sideband arriving after a critical request was already issued.
  base=16'h7000;cold(base,2);publish=0;start_critical=critical_issued;
  fork
   access(0,base+14,2,0);
   begin if(IS_CANDIDATE)begin wait(phase && dut.r_issued);@(negedge clk);line_tag=base>>4;line_data=retained(base);line_valid=1;end end
  join
  drain();if(IS_CANDIDATE && critical_issued!=start_critical+1)$fatal(1,"delayed retained line abandoned critical beat");
  check_line(base,IS_CANDIDATE);scenario(4);
  // Critical-word error; old victim cache rows cannot retain overwritten data.
  base=16'h8000;cold(base,2);
  for(integer tag=1;tag<=4;tag++)begin access(0,base+tag*16'h800,2,0);drain();end
  fault_access(base+14,base+12);
  for(integer tag=1;tag<=4;tag++)check_line(base+tag*16'h800,0);scenario(5);
  // Existing second-line critical error after successful first publication.
  base=16'ha000;cold(base,IS_CANDIDATE?0:1);publish=1;publish_base=base;
  fault_access(base+14,base+16);check_line(base,0);check_line(base+16,0);scenario(6);
  // Excluded paths do not enter the new phase; ordinary data/I-bank unaffected.
  for(mode=0;mode<7;mode++)begin
   base=16'hb000;cold(base,0);start_phase=phases;
   case(mode)
    0:begin ci=1;access(0,base+14,2,0);end
    1:begin de=0;access(0,base+14,2,0);end
    2:begin instr=1;access(0,base+12,2,0);end
    3:access(0,base+15,0,0);
    4:access(0,base+14,1,0);
    5:access(0,base+12,2,0);
    6:access(0,base+5,2,0);
   endcase
   drain();if(phases!=start_phase)$fatal(1,"excluded path entered first phase");scenario(7);
  end
  // Matching line valid before critical issuance: no external first beat needed.
  base=16'hc000;cold(base,2);publish=0;start_critical=critical_issued;line_tag=base>>4;line_data=retained(base);line_valid=1;
  access(0,base+14,2,0);drain();
  if(IS_CANDIDATE && critical_issued!=start_critical)$fatal(1,"prevalid line issued an unnecessary critical request");
  check_line(base,IS_CANDIDATE);scenario(8);
  // A qualified critical bus fault wins even if a matching line appears after issuance.
  base=16'hc800;cold(base,2);publish=0;
  fork
   fault_access(base+14,base+12);
   begin if(IS_CANDIDATE)begin wait(phase && dut.r_issued);@(negedge clk);line_tag=base>>4;line_data=retained(base);line_valid=1;end end
  join
  check_line(base,0);scenario(9);
  // Existing second-line tail fault arrives only after the crossing pair ACK.
  base=16'hd000;cold(base,IS_CANDIDATE?0:1);publish=1;publish_base=base;
  start_errors=errors_seen;error_arm=1;error_word=base+20;access(0,base+14,2,0);drain();error_arm=0;
  if(phase || dut.err_hold || errors_seen!=start_errors+1)$fatal(1,"second-line late error missing or changed first-phase/hold");
  check_line(base,0);check_line(base+16,0);scenario(10);
  // Posted store before a cold crossing read, then another after its completion.
  base=16'he000;cold(base,0);post=1;publish=1;publish_base=base;
  oracle[base+14]=8'ha1;oracle[base+15]=8'hb2;oracle[base+16]=8'hc3;oracle[base+17]=8'hd4;
  access(1,base+14,2,32'ha1b2c3d4);access(0,base+14,2,0);drain();
  oracle[base+16]=8'h11;oracle[base+17]=8'h22;oracle[base+18]=8'h33;oracle[base+19]=8'h44;
  access(1,base+16,2,32'h11223344);drain();access(0,base+14,2,0);drain();scenario(11);
  // CINV during the pending first phase; no CE manipulation or premature ACK.
  base=16'hf000;cold(base,2);publish=1;publish_base=base;start_cinv=cinv_completions;
  fork
   access(0,base+14,2,0);
   begin await_stage(1);@(negedge clk);cinv=1;wait(cinv_done);cinv_completions++;@(negedge clk);cinv=0;end
  join
  drain();if(cinv_completions==start_cinv)$fatal(1,"CINV completion not exercised");
  // CINV may sweep before the held operand replays/refills. Check values only:
  // no claim that the original first publication survived the sweep.
  check_line(base,0);check_line(base+16,0);scenario(12);
  // Reset cancels the pending unit request and sweeps partial/victim state.
  if(IS_CANDIDATE)begin
   base=16'hf800;cold(base,2);publish=1;publish_base=base;
   @(negedge clk);req=1;wr=0;addr=base+14;size=2;
   await_stage(1);@(negedge clk);reset_n=0;req=0;
   repeat(3)@(negedge clk);reset_n=1;drain();
   if(phase)$fatal(1,"reset did not clear first phase");
   access(0,base+14,2,0);drain();check_line(base,1);scenario(13);
  end else begin cold(16'hf800,0);access(0,16'hf80e,2,0);drain();scenario(13);end
  // A valid retained line with wrong physical tag must not install its poison.
  base=16'he800;cold(base,2);publish=0;line_tag=(base+16'h100)>>4;
  line_data=~retained(base);line_valid=1;start_fallback=local_fallbacks;
  access(0,base+14,2,0);drain();
  if(IS_CANDIDATE && local_fallbacks!=start_fallback+1)$fatal(1,"wrong-tag line consumed or fallback absent");
  check_line(base,0);check_line(base+16,0);scenario(14);
  // Error wins over simultaneous physical ACK, including retained-line arrival.
  base=16'hec00;cold(base,2);publish=0;error_with_ack=1;
  fork
   fault_access(base+14,base+12);
   begin if(IS_CANDIDATE)begin wait(phase && dut.r_issued);@(negedge clk);
    line_tag=base>>4;line_data=retained(base);line_valid=1;end end
  join
  check_line(base,0);scenario(15);
  for(integer c=0;c<16;c++)$display("PHASE_COVERAGE id=%0d count=%0d",c,coverage[c]);
  if(cases!=73 || held_faults!=4 || error_ack_overlaps!=1)$fatal(1,"scenario/fault coverage missing");
  if(IS_CANDIDATE && (phases==0 || local_words==0 || publications==0 || local_fallbacks<5 || phase_errors==0 || poison_passes==0 || critical_issued==0))
   $fatal(1,"required phase coverage missing");
  $display("XFIRST_PHASE PASS candidate=%0d cases=%0d phase_entries=%0d critical_issued=%0d local_words=%0d publications=%0d local_fallbacks=%0d poisoned_publications=%0d phase_errors=%0d operand_acks=%0d external_tail_requests=%0d held_faults=%0d error_ack_overlaps=%0d cinv_completions=%0d",IS_CANDIDATE,cases,phases,critical_issued,local_words,publications,local_fallbacks,poison_passes,phase_errors,acks,external_tail_requests,held_faults,error_ack_overlaps,cinv_completions);
  $finish;
 end
 initial begin #100000000;$fatal(1,"global bounded timeout");end
endmodule
