// Passive native Whetstone monitor. Invoked first in the existing sys posedge block.
longint unsigned np_tick=0, np_edges=0;
longint unsigned np_joint[4][4][32],np_op[4][4][128],np_bg[4][4];
longint unsigned np_pc[4],np_cpu[4],np_fst[32];
longint unsigned np_wait[2][4][4][32],np_occ[2];
longint unsigned np_hist[2][4][5][3][4][65];
longint unsigned np_group_n[2][4][5][3][4],np_group_sum[2][4][5][3][4],np_group_max[2][4][5][3][4];
longint unsigned np_whole_n[2],np_whole_sum[2],np_max[2],np_partial_n[2],np_partial_sum[2];
longint unsigned np_starts[2],np_ends[2],np_touched[2],np_faults[2],np_diag[2],np_dropped[2];
longint unsigned np_ever[2][4],np_bypass[2][2];
typedef struct packed {
 bit active, first_window, touched, busy_seen, dec_seen, bypassed;
 logic [31:0] addr, pc;
 logic instr, write;
 logic [1:0] size;
 logic [2:0] fc;
 int pc_region,addr_region,kind,policy;
 longint unsigned start_edge,window_edges;
} np_episode_t;
np_episode_t np_e[2];
`include "resource_read_monitor.svh"
function automatic int np_pc_region(input logic [31:0] a);
 if(a>=32'h40800000 && a<32'h40900000)return 0;
 if(a>=32'h60029a && a<32'h6006a2)return 1;
 if(a>=32'h600000 && a<32'h600ec8)return 2;
 return 3;
endfunction
function automatic int np_address_region(input logic [31:0] a);
 if(a>=32'h40800000 && a<32'h40900000)return 0;
 if(a>=32'h600000 && a<32'h600ec8)return 1;
 if(a>=32'h600ec8 && a<32'h640000)return 2;
 if(a<32'h40000000)return 3;
 return 4;
endfunction
function automatic int np_cpu_region;
 if(dut.cpu.core.state==9)return 0;
 if(dut.cpu.core.state==153 && dut.cpu.core.fpu_bg && !dut.cpu.core.fpu_done)return 1;
 if(dut.cpu.core.state==160)return 2;
 return 3;
endfunction
initial begin
 foreach(np_joint[a,b,c])np_joint[a][b][c]=0;
 foreach(np_op[a,b,c])np_op[a][b][c]=0;
 foreach(np_bg[a,b])np_bg[a][b]=0;
 foreach(np_wait[p,a,b,c])np_wait[p][a][b][c]=0;
 foreach(np_hist[p,a,b,c,d,e])np_hist[p][a][b][c][d][e]=0;
 foreach(np_group_n[p,a,b,c,d])begin np_group_n[p][a][b][c][d]=0;np_group_sum[p][a][b][c][d]=0;np_group_max[p][a][b][c][d]=0;end
 foreach(np_pc[a])np_pc[a]=0;
 foreach(np_cpu[a])np_cpu[a]=0;
 foreach(np_fst[a])np_fst[a]=0;
 for(int p=0;p<2;p++)begin
  np_e[p]='0;np_occ[p]=0;np_whole_n[p]=0;np_whole_sum[p]=0;np_max[p]=0;
  np_partial_n[p]=0;np_partial_sum[p]=0;np_starts[p]=0;np_ends[p]=0;
  np_touched[p]=0;np_faults[p]=0;np_diag[p]=0;np_dropped[p]=0;
  for(int a=0;a<4;a++)np_ever[p][a]=0;
  for(int a=0;a<2;a++)np_bypass[p][a]=0;
 end
end
// Reset is outside the native window. Never discard an active episode silently.
always @(negedge nreset) begin
 if(in_loop || np_e[0].active || np_e[1].active)$fatal(1,"NEXT reset interrupted window/episode");
end
task automatic np_plane(input int p,input bit req,ack,fault,
 input logic [31:0] addr,input bit instr,write,input logic [1:0] size,
 input logic [2:0] fc,input int policy,input bit bypassed,
 input int pc_bucket,cpu_bucket,fst_bucket);
 longint unsigned latency;
 int bin,mask;
 if(req && !np_e[p].active)begin
  if(instr && write)$fatal(1,"NEXT instruction write");
  np_e[p]='0;np_e[p].active=1;np_e[p].addr=addr;np_e[p].pc=dut.cpu.core.pc_i;
  np_e[p].instr=instr;np_e[p].write=write;np_e[p].size=size;np_e[p].fc=fc;
  np_e[p].pc_region=pc_bucket;np_e[p].addr_region=np_address_region(addr);
  np_e[p].kind=instr?0:(write?2:1);np_e[p].policy=policy;np_e[p].bypassed=bypassed;
  np_e[p].start_edge=np_tick;np_e[p].first_window=in_loop;np_starts[p]++;
  if(p==1)rr_begin();
 end
 if(np_e[p].active)begin
  if(req && {addr,instr,write,size,fc}!=={np_e[p].addr,np_e[p].instr,np_e[p].write,np_e[p].size,np_e[p].fc})
   $fatal(1,"NEXT request fields changed plane=%0d",p);
  if(!req && !ack && !fault)$fatal(1,"NEXT dropped request without completion plane=%0d",p);
  if(in_loop)begin
   if(!np_e[p].touched)begin np_e[p].touched=1;np_touched[p]++;end
   np_e[p].window_edges++;np_occ[p]++;np_wait[p][pc_bucket][cpu_bucket][fst_bucket]++;
   np_e[p].busy_seen|=(fst_bucket!=0);np_e[p].dec_seen|=(cpu_bucket==1);
  end
  if(p==1)rr_sample();
  if(ack || fault)begin
   if(ack && fault)$fatal(1,"NEXT ack and wrapper fault coincide plane=%0d",p);
   np_ends[p]++;latency=np_tick-np_e[p].start_edge+1;
   if(p==1 && !fault)rr_end(latency);
   if(np_e[p].touched)begin
    if(fault)begin np_faults[p]++;$fatal(1,"NEXT wrapper fault during measured episode plane=%0d",p);end
    if(np_e[p].first_window && np_e[p].window_edges==latency)begin
     bin=(latency>=65)?64:int'(latency-1);
     np_hist[p][np_e[p].pc_region][np_e[p].addr_region][np_e[p].kind][np_e[p].policy][bin]++;
     np_whole_n[p]++;np_whole_sum[p]+=latency;if(latency>np_max[p])np_max[p]=latency;
     np_group_n[p][np_e[p].pc_region][np_e[p].addr_region][np_e[p].kind][np_e[p].policy]++;
     np_group_sum[p][np_e[p].pc_region][np_e[p].addr_region][np_e[p].kind][np_e[p].policy]+=latency;
     if(latency>np_group_max[p][np_e[p].pc_region][np_e[p].addr_region][np_e[p].kind][np_e[p].policy])np_group_max[p][np_e[p].pc_region][np_e[p].addr_region][np_e[p].kind][np_e[p].policy]=latency;
     mask={np_e[p].busy_seen,np_e[p].dec_seen};np_ever[p][mask]++;
     np_bypass[p][np_e[p].bypassed]++;
    end else begin np_partial_n[p]++;np_partial_sum[p]+=np_e[p].window_edges;end
    if(np_diag[p]<64)begin
     $display("NEXT_EP plane=%0d pc=%08h addr=%08h instr=%0d write=%0d size=%0d fc=%0d policy=%0d bypass=%0d latency=%0d window=%0d first_window=%0d",p,np_e[p].pc,np_e[p].addr,np_e[p].instr,np_e[p].write,np_e[p].size,np_e[p].fc,np_e[p].policy,np_e[p].bypassed,latency,np_e[p].window_edges,np_e[p].first_window);
     np_diag[p]++;
    end else np_dropped[p]++;
   end
   np_e[p].active=0;
  end
 end
endtask
task automatic np_sample;
 int p,c,f,policy;
 np_tick++;p=np_pc_region(dut.cpu.core.pc_i);c=np_cpu_region();f=`FMON.fst;
 if(in_loop)begin
  if(dut.cpu.core.state>=256 || f>=32 || `FMON.r_op>=128)$fatal(1,"NEXT invalid index");
  np_edges++;np_joint[p][c][f]++;np_pc[p]++;np_cpu[c]++;np_fst[f]++;
  if(f!=0)np_op[p][c][`FMON.r_op]++;
  if(dut.cpu.core.fpu_bg)np_bg[p][c]++;
 end
 // Plane0 logical wrapper: policy0 is NOT a cacheability assertion.
 np_plane(0,dut.cpu.mem_req,dut.cpu.mem_ack,dut.cpu.mem_flt||dut.cpu.berr,
  dut.cpu.mem_addr,dut.cpu.mem_instr,dut.cpu.mem_write,dut.cpu.mem_size,dut.cpu.mem_fc,0,0,p,c,f);
 // Plane1 physical cache input; faults propagate from the exact wrapper only.
 policy={dut.cpu.g_cache.cache.c_nocache,!dut.cpu.g_cache.cache.ena};
 np_plane(1,dut.cpu.mm_req,dut.cpu.mm_ack,dut.cpu.mem_flt||dut.cpu.berr,
  dut.cpu.mm_addr,dut.cpu.mm_instr,dut.cpu.mm_write,dut.cpu.mm_size,dut.cpu.mm_fc,
  policy,dut.cpu.g_cache.cache.bypass,p,c,f);
endtask
task automatic np_finish;
 longint unsigned s,op_s,idle_s,wait_s,hist_s,active_occ,group_n,group_sum,group_max,ever_sum,bypass_sum,bg_sum;
 $display("NEXT_META format=native-whet-joint-v1 finish=BEFORE_ORIGINAL_DRAIN pc=ROM,BODY,REST_RESOURCE,OTHER cpu=MRD,DEC_BLOCKED,GO,OTHER plane=LOGICAL_WRAPPER,PHYSICAL_CACHE_INPUT fault=WRAPPER_mem_flt_OR_berr latency=FIRST_REQ_TO_COMPLETION_INCLUSIVE partials=WINDOW_INTERSECTIONS");
 s=0;op_s=0;idle_s=0;
 foreach(np_joint[a,b,c])begin
  s+=np_joint[a][b][c];if(c==0)idle_s+=np_joint[a][b][c];
  if(np_joint[a][b][c])$display("NEXT_JOINT pc=%0d cpu=%0d fst=%0d n=%0d",a,b,c,np_joint[a][b][c]);
 end
 foreach(np_op[a,b,c])begin op_s+=np_op[a][b][c];if(np_op[a][b][c])$display("NEXT_OP pc=%0d cpu=%0d op=%02h n=%0d",a,b,c,np_op[a][b][c]);end
 if(s!=np_edges || s!=loop_cycles || op_s!=s-idle_s)$fatal(1,"NEXT cycle reconciliation");
 for(int a=0;a<4;a++)begin
  longint unsigned ps,cs;ps=0;cs=0;
  for(int b=0;b<4;b++)for(int f=0;f<32;f++)begin ps+=np_joint[a][b][f];cs+=np_joint[b][a][f];end
  if(ps!=np_pc[a] || cs!=np_cpu[a])$fatal(1,"NEXT marginal reconciliation");
  $display("NEXT_MARGIN id=%0d pc=%0d cpu=%0d",a,np_pc[a],np_cpu[a]);
 end
 for(int f=0;f<32;f++)begin
  longint unsigned fs;fs=0;for(int a=0;a<4;a++)for(int b=0;b<4;b++)fs+=np_joint[a][b][f];
  if(fs!=np_fst[f] || fs!=fm_fst[f])$fatal(1,"NEXT FST reconciliation");
 end
 if(np_pc[0]!=native_rom || np_pc[1]!=native_body || np_pc[1]+np_pc[2]!=native_resource || np_cpu[1]!=native_blockdec || np_cpu[2]!=native_go || np_cpu[0]!=native_core[9])$fatal(1,"NEXT original marginal mismatch");
 bg_sum=0;foreach(np_bg[a,b])begin bg_sum+=np_bg[a][b];end
 if(bg_sum!=native_bg)$fatal(1,"NEXT background marginal mismatch");
 foreach(np_bg[a,b])if(np_bg[a][b])$display("NEXT_BG pc=%0d cpu=%0d n=%0d",a,b,np_bg[a][b]);
 for(int p=0;p<2;p++)begin
  wait_s=0;hist_s=0;active_occ=np_e[p].active?np_e[p].window_edges:0;
  for(int a=0;a<4;a++)for(int b=0;b<4;b++)for(int f=0;f<32;f++)begin
   wait_s+=np_wait[p][a][b][f];if(np_wait[p][a][b][f])$display("NEXT_WAIT plane=%0d pc=%0d cpu=%0d fst=%0d n=%0d",p,a,b,f,np_wait[p][a][b][f]);
  end
  for(int a=0;a<4;a++)for(int b=0;b<5;b++)for(int c=0;c<3;c++)for(int d=0;d<4;d++)for(int e=0;e<65;e++)begin
   hist_s+=np_hist[p][a][b][c][d][e];if(np_hist[p][a][b][c][d][e])$display("NEXT_LAT plane=%0d pc=%0d addr_region=%0d kind=%0d policy=%0d bin=%0d n=%0d",p,a,b,c,d,e,np_hist[p][a][b][c][d][e]);
  end
  group_n=0;group_sum=0;group_max=0;
  for(int a=0;a<4;a++)for(int b=0;b<5;b++)for(int c=0;c<3;c++)for(int d=0;d<4;d++)begin
   group_n+=np_group_n[p][a][b][c][d];group_sum+=np_group_sum[p][a][b][c][d];
   if(np_group_max[p][a][b][c][d]>group_max)group_max=np_group_max[p][a][b][c][d];
   if(np_group_n[p][a][b][c][d])$display("NEXT_GROUP plane=%0d pc=%0d addr_region=%0d kind=%0d policy=%0d n=%0d sum=%0d max=%0d",p,a,b,c,d,np_group_n[p][a][b][c][d],np_group_sum[p][a][b][c][d],np_group_max[p][a][b][c][d]);
  end
  ever_sum=0;bypass_sum=0;
  for(int a=0;a<4;a++)ever_sum+=np_ever[p][a];
  for(int a=0;a<2;a++)bypass_sum+=np_bypass[p][a];
  if(group_n!=np_whole_n[p] || group_sum!=np_whole_sum[p] || group_max!=np_max[p] || ever_sum!=np_whole_n[p] || bypass_sum!=np_whole_n[p] || np_diag[p]+np_dropped[p]!=np_whole_n[p]+np_partial_n[p])$fatal(1,"NEXT group/diagnostic reconciliation plane=%0d",p);
  if(np_starts[p]!=np_ends[p]+int'(np_e[p].active) || wait_s!=np_occ[p] || hist_s!=np_whole_n[p] || np_occ[p]!=np_whole_sum[p]+np_partial_sum[p]+active_occ || np_touched[p]!=np_whole_n[p]+np_partial_n[p]+int'(np_e[p].active&&np_e[p].touched))$fatal(1,"NEXT episode reconciliation plane=%0d",p);
  $display("NEXT_PLANE id=%0d starts=%0d ends=%0d active=%0d touched=%0d whole=%0d latency_sum=%0d max=%0d partial=%0d partial_edges=%0d active_edges=%0d occupancy=%0d faults=%0d diag=%0d dropped=%0d",p,np_starts[p],np_ends[p],np_e[p].active,np_touched[p],np_whole_n[p],np_whole_sum[p],np_max[p],np_partial_n[p],np_partial_sum[p],active_occ,np_occ[p],np_faults[p],np_diag[p],np_dropped[p]);
  for(int a=0;a<4;a++)$display("NEXT_EVER plane=%0d busy_dec_mask=%0d n=%0d",p,a,np_ever[p][a]);
  for(int a=0;a<2;a++)$display("NEXT_BYPASS plane=%0d bit=%0d n=%0d",p,a,np_bypass[p][a]);
 end
 $display("NEXT_TOTAL edges=%0d joint=%0d busy_op=%0d",np_edges,s,op_s);
 rr_finish();
endtask
