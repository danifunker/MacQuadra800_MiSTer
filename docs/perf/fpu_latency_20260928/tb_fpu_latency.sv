// FPU latency / issue-interval bench: a short program through wombat_cpu's
// real core, FPU, MMU, 8+8 KB caches and store buffer, as tb_cpu_permute.sv.
// The RAM responder is a fixed-latency model (+latency=N wait clocks per
// transaction), NOT quadra800's SDRAM controller.  ce is tied high, so one
// clk here is one ce-qualified 33 MHz CPU clock.
//
// A word write to $F108 is a cycle stamp: when the bus acknowledges it the
// bench prints the clocks since the previous stamp's acknowledge, and the
// number of exception entries (S_EXC0/_F2/_F3/_F4) and the last vector seen in between.
// $F102 = $600D ends the run, anything else fails it.
// Independently of the stamps, "BODY tag=" lines give the clocks from the
// decode PC reaching the first body instruction to it reaching the closing
// FNOP, so the closing FNOP's wait and the stamp stores are excluded.
`timescale 1ns/1ps
module tb_fpu_latency;
 reg clk=0; always #15 clk=~clk;
 reg nreset=0;
 wire req, wr, instr, walker_req, fault, halted;
 wire [1:0] size;
 wire [31:0] addr, wdata;
 reg ack=0;
 reg [31:0] rdata=0;
 reg [15:0] mem[0:131071];         // 256 KB
 integer latency=3, waitleft=0, cycles=0, j, bytes;
 integer stamp_prev=0, exc_count=0, last_vec=0, trace_lo=-1, trace_hi=-1, trace_c0=-1, trace_c1=-1;
 reg [31:0] trace_pc=0, body_pc=32'hffffffff;
 integer body_t0=0;
 reg [7:0] prev_state=0;
 reg pending=0;
 reg [31:0] saved_addr, saved_data;
 reg [1:0] saved_size;
 reg saved_wr;
 reg [1023:0] path;
 wombat_cpu dut(.clk(clk),.nreset(nreset),.ce(1'b1),.ipl(3'b111),
 .ipl_autovector(1'b1),.berr(1'b0),.stall_hold(1'b0),.dbg_stall_flt(),
 .cache_line_valid(1'b0),.cache_line_tag(28'd0),.cache_line_data(128'd0),
 .store_buffer_ok(1'b1),.bus_req(req),.bus_write(wr),.bus_instr(instr),
 .bus_size(size),.bus_addr(addr),.bus_wdata(wdata),.bus_fc(),
 .bus_ack(ack),.bus_rdata(rdata),.walker_req(walker_req),.walker_we(),
 .walker_addr(),.walker_wdat(),.walker_ack(1'b0),.walker_data(32'd0),
 .walker_berr(1'b0),.snoop_stb(1'b0),.snoop_addr(32'd0),.nresetout(),
 .nmi_ack_toggle(),.cacr_out(),.vbr_out(),.debug_busy(),
 .debug_fault(fault),.debug_halted(halted),.debug_status(),.debug_status2());
 function [15:0] w(input [31:0] a);
  w = (a<262144) ? mem[a>>1] : 16'h0000;
 endfunction
 function is_exc_entry(input [7:0] st);
  is_exc_entry = st==dut.core.S_EXC0 || st==dut.core.S_EXC0_F2 || st==dut.core.S_EXC0_F3 || st==dut.core.S_EXC0_F4;
 endfunction
 function [7:0] readbyte(input integer a);
  if(a<0 || a>=262144) $fatal(1,"RAM read out of range %h pc=%h",a,dut.core.pc_i);
  readbyte = a[0] ? mem[a>>1][7:0] : mem[a>>1][15:8];
 endfunction
 task writebyte(input integer a,input [7:0] value);
  if(a<0 || a>=262144) $fatal(1,"RAM write out of range %h pc=%h",a,dut.core.pc_i);
  if(a[0]) mem[a>>1][7:0]=value; else mem[a>>1][15:8]=value;
 endtask
 initial begin
  if(!$value$plusargs("prog=%s",path)) $fatal(1,"missing +prog");
  if($value$plusargs("latency=%d",latency)) begin end
  if($value$plusargs("tracelo=%h",trace_lo)) begin end
  if($value$plusargs("tracehi=%h",trace_hi)) begin end
  if($value$plusargs("tracec0=%d",trace_c0)) begin end
  if($value$plusargs("tracec1=%d",trace_c1)) begin end
  for(j=0;j<131072;j=j+1) mem[j]=0;
  $readmemh(path,mem);
  repeat(20) @(negedge clk);
  nreset=1;
 end
 always @(posedge clk) if(nreset) begin
  cycles=cycles+1;
  prev_state<=dut.core.state;
  if(is_exc_entry(dut.core.state) && !is_exc_entry(prev_state)) begin
   exc_count=exc_count+1; last_vec=dut.core.exc_vec;
  end
  // +tracelo=/+tracehi= (hex): print each change of the decode PC inside the
  // window (+tracecyc: every clock), or every clock from +tracec0= to +tracec1=
  // (decimal cycles), with the core and FPU states and the core-side memory
  // request (mem_req/instr/write/addr/ack, before the cache)
  if(((dut.core.pc_i!=trace_pc || $test$plusargs("tracecyc")) && dut.core.pc_i>=trace_lo && dut.core.pc_i<trace_hi) ||
     (cycles>=trace_c0 && cycles<=trace_c1))
   $display("TRACE cyc=%0d pc=%h state=%0d fpu_st=%0d req=%0d instr=%0d wr=%0d addr=%h wdata=%h ack=%0d",cycles,dut.core.pc_i,dut.core.state,dut.core.g_fpu.fpu.fst,
            dut.mem_req,dut.mem_instr,dut.mem_write,dut.mem_addr,dut.mem_wdata,dut.mem_ack);
  // Body timing from the decode PC, independent of the stamp stores: the
  // body starts where the decode PC first reaches the instruction after
  // "move.w #1,$F108" and ends where it reaches "fnop; move.w #tag,$F108".
  if(dut.core.pc_i!=trace_pc) begin
   if(dut.core.pc_i==body_pc) body_t0=cycles;
   if(w(dut.core.pc_i)==16'h33fc && w(dut.core.pc_i+2)==16'h0001 &&
      w(dut.core.pc_i+4)==16'h0000 && w(dut.core.pc_i+6)==16'hf108) body_pc=dut.core.pc_i+8;
   if(w(dut.core.pc_i)==16'hf280 && w(dut.core.pc_i+2)==16'h0000 && w(dut.core.pc_i+4)==16'h33fc &&
      w(dut.core.pc_i+6)!=16'h0001 && w(dut.core.pc_i+10)==16'hf108 && body_pc!=32'hffffffff) begin
    $display("BODY tag=%0d clocks=%0d",w(dut.core.pc_i+6),(dut.core.pc_i==body_pc)?0:cycles-body_t0);
    body_pc=32'hffffffff;
   end
  end
  trace_pc=dut.core.pc_i;
  if(walker_req || fault || halted) $fatal(1,"unexpected CPU fault/walker/halt pc=%h",dut.core.pc_i);
  if(cycles>5000000) $fatal(1,"timeout pc=%h",dut.core.pc_i);
  ack<=0;
  if(pending) begin
   if(!req || addr!==saved_addr || (saved_wr && wdata!==saved_data) || wr!==saved_wr || size!==saved_size)
    $fatal(1,"request changed before ack");
   if(waitleft>0) waitleft<=waitleft-1;
   else begin
    pending<=0;ack<=1;
    bytes=saved_size==0?1:(saved_size==1?2:4);
    rdata=0;
    for(j=0;j<bytes;j=j+1) begin
     if(saved_wr) writebyte(saved_addr+j,saved_data>>(8*(bytes-j-1)));
     else rdata=(rdata<<8)|readbyte(saved_addr+j);
    end
    if(saved_wr && saved_addr==32'hf108) begin
     $display("STAMP tag=%0d clocks=%0d exc=%0d vec=%0d",saved_data[15:0],cycles-stamp_prev,exc_count,last_vec);
     stamp_prev=cycles; exc_count=0; last_vec=0;
    end
    if(saved_wr && saved_addr==32'hf102) begin
     if(saved_data[15:0]!=16'h600d) $fatal(1,"guest failure marker %h test=%h pc=%h",saved_data[15:0],mem['hf100>>1],dut.core.pc_i);
     $display("DONE cycles=%0d latency=%0d",cycles,latency);
     $finish;
    end
   end
  end else if(req && !ack) begin
   saved_addr<=addr;saved_data<=wdata;saved_wr<=wr;saved_size<=size;
   pending<=1;waitleft<=latency;
  end
 end
endmodule
