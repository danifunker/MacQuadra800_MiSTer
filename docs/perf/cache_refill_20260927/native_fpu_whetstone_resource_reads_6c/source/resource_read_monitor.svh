// Passive resource attribution. np_e[1] owns the original episode metadata.
`define RRC dut.cpu.g_cache.cache
longint unsigned rr_n[1892][2][3],rr_sum[1892][2][3],rr_max[1892][2][3];
longint unsigned rr_event[1892][2][3][7],rr_fail[1892][2][3][16];
longint unsigned rr_second[1892][2][3][8][2],rr_inv[64][3];
longint unsigned rr_starts=0,rr_ends=0,rr_touched=0,rr_occupancy=0;
longint unsigned rr_whole=0,rr_latency=0,rr_maximum=0,rr_partial=0,rr_partial_edges=0;
longint unsigned rr_rest_n=0,rr_rest_sum=0,rr_rest_max=0,rr_path[7];
bit rr_seen,rr_fast,rr_shortcut,rr_first_hit,rr_first_pass;
bit rr_second_hit,rr_second_fill,rr_second_pass;
function automatic bit rr_target;
 return np_e[1].kind==1 && np_e[1].policy==0 &&
        np_e[1].addr>=32'h00600000 && np_e[1].addr<32'h00600ec8;
endfunction
function automatic bit rr_crossline;
 return np_e[1].addr[3:2]==3 &&
  ((np_e[1].size==2 && np_e[1].addr[1:0]!=0) ||
   (np_e[1].size==1 && np_e[1].addr[1:0]==3));
endfunction
initial begin
 foreach(rr_n[a,b,c])begin rr_n[a][b][c]=0;rr_sum[a][b][c]=0;rr_max[a][b][c]=0;end
 foreach(rr_event[a,b,c,d])rr_event[a][b][c][d]=0;
 foreach(rr_fail[a,b,c,d])rr_fail[a][b][c][d]=0;
 foreach(rr_second[a,b,c,d,e])rr_second[a][b][c][d][e]=0;
 foreach(rr_inv[a,b])rr_inv[a][b]=0;
 foreach(rr_path[a])rr_path[a]=0;
 rr_seen=0;rr_fast=0;rr_shortcut=0;rr_first_hit=0;rr_first_pass=0;
 rr_second_hit=0;rr_second_fill=0;rr_second_pass=0;
end
task automatic rr_begin;
 rr_seen=0;rr_fast=0;rr_shortcut=0;rr_first_hit=0;rr_first_pass=0;
 rr_second_hit=0;rr_second_fill=0;rr_second_pass=0;
 if(rr_target())rr_starts++;
endtask
task automatic rr_sample;
 int a,b,s,mask,imask,rel;
 logic [6:0] next_set;
 bit admit;
 if(rr_target() && in_loop)begin
  a=int'((np_e[1].addr-32'h00600000)>>1);b=int'(np_e[1].addr[0]);s=int'(np_e[1].size);
  if(a<0 || a>=1892 || s>=3)$fatal(1,"RREAD address/size index");
  if(!rr_seen)begin rr_seen=1;rr_touched++;end
  rr_occupancy++;
  if(nreset && `RRC.ce)begin
   if(`RRC.fast_xline_idle && `RRC.c_ack)begin
    if(!rr_crossline() || rr_fast)$fatal(1,"RREAD duplicate/noncross fast hit");
    rr_fast=1;rr_event[a][b][s][0]++;
   end
   // Only the real C_IDLE read->C_LOOK admission, after all earlier priorities.
   // This is not an idle hold/hit classifier and not raw rd_accept.
   admit=(`RRC.cst==0) && !(`RRC.cinv_req && !`RRC.cinv_done) &&
    !`RRC.fast_ihit && !`RRC.iline_hit && !`RRC.fast_pair_idle && !`RRC.fast_xline_idle &&
    !(`RRC.idle_hit || `RRC.fast_hit) && `RRC.c_req && !`RRC.ack_r && !`RRC.err_hold &&
    !`RRC.c_write && !`RRC.ci_inv_pend && !`RRC.store_inv_lost &&
    !(`RRC.c_instr && !`RRC.c_ihold) && !(`RRC.c_hint_away && !`RRC.c_instr) && !`RRC.bypass;
   if(admit && `RRC.idle_xline_hit)begin
    if(!rr_crossline() || rr_shortcut)$fatal(1,"RREAD duplicate/noncross idle shortcut");
    rr_shortcut=1;rr_event[a][b][s][1]++;
   end
   if(`RRC.cst==1 && !`RRC.look2 && `RRC.r_xline)begin
    // Both lookup decisions still carry the original request address. Only
    // the clean second-line miss rewrites it on the upcoming NBA edge.
    if(!rr_crossline() || `RRC.r_addr!==np_e[1].addr || `RRC.r_size!==np_e[1].size)
     $fatal(1,"RREAD lookup not owned by saved episode");
    if(!`RRC.xlook)begin
     if(rr_first_hit || rr_first_pass)$fatal(1,"RREAD duplicate first lookup");
     if(`RRC.xlook_read)begin rr_first_hit=1;rr_event[a][b][s][2]++;end
     else begin
      mask={`RRC.inv_wren,`RRC.snoop_look_row,`RRC.look_snooped,!`RRC.look_hit};
      if(mask==0)$fatal(1,"RREAD unexplained first failure");
      rr_first_pass=1;rr_event[a][b][s][3]++;rr_fail[a][b][s][mask]++;
      if(`RRC.inv_wren)begin
       imask={`RRC.sweep_b,`RRC.ci_inv,`RRC.fill_err_inv,`RRC.store_inv_lost,`RRC.store_inv,`RRC.snoop_wr};
       if(imask==0 || $bits(`RRC.inv_idx)!=8 || `RRC.SETW!=7)$fatal(1,"RREAD invalidation metadata");
       next_set=np_e[1].addr[10:4]+7'd1;
       rel=(`RRC.inv_idx=={1'b0,np_e[1].addr[10:4]})?0:
           (`RRC.inv_idx=={1'b0,next_set})?1:2;
       rr_inv[imask][rel]++;
      end
     end
    end else begin
     if(rr_second_hit || rr_second_fill || rr_second_pass)$fatal(1,"RREAD duplicate second lookup");
     mask={`RRC.snoop_xrow,`RRC.xline_snoop_pending,`RRC.xsnooped};
     rr_second[a][b][s][mask][int'(`RRC.look_hit)]++;
     if(mask!=0)begin rr_second_pass=1;rr_event[a][b][s][6]++;end
     else if(`RRC.look_hit)begin rr_second_hit=1;rr_event[a][b][s][4]++;end
     else begin rr_second_fill=1;rr_event[a][b][s][5]++;end
    end
   end
  end
 end
endtask
task automatic rr_end(input longint unsigned latency);
 int a,b,s,path;
 if(rr_target())begin
  rr_ends++;
  if(rr_seen)begin
   if(np_e[1].first_window && np_e[1].window_edges==latency)begin
    a=int'((np_e[1].addr-32'h00600000)>>1);b=int'(np_e[1].addr[0]);s=int'(np_e[1].size);
    if(a<0 || a>=1892 || s>=3)$fatal(1,"RREAD completion index");
    rr_n[a][b][s]++;rr_sum[a][b][s]+=latency;
    if(latency>rr_max[a][b][s])rr_max[a][b][s]=latency;
    rr_whole++;rr_latency+=latency;if(latency>rr_maximum)rr_maximum=latency;
    if(np_e[1].pc_region==2)begin
     rr_rest_n++;rr_rest_sum+=latency;if(latency>rr_rest_max)rr_rest_max=latency;
    end
    path=0;
    if(rr_crossline())begin
     path=6;
     if(rr_fast && !(rr_shortcut || rr_first_hit || rr_first_pass || rr_second_hit || rr_second_fill || rr_second_pass))path=1;
     else if(rr_first_pass && !(rr_fast || rr_shortcut || rr_first_hit || rr_second_hit || rr_second_fill || rr_second_pass))path=2;
     else if((rr_shortcut ^ rr_first_hit) && !rr_fast && !rr_first_pass &&
             (int'(rr_second_hit)+int'(rr_second_fill)+int'(rr_second_pass)==1))begin
      if(rr_second_hit)path=3;else if(rr_second_fill)path=4;else path=5;
     end
    end
    rr_path[path]++;
   end else begin rr_partial++;rr_partial_edges+=np_e[1].window_edges;end
  end
 end
endtask
task automatic rr_finish;
 longint unsigned n,s,m,paths,active_edges,firstfail,invfail,invtotal,seconds,evfirst,evsecond;
 bit active;
 active=np_e[1].active && rr_target();active_edges=(active && rr_seen)?np_e[1].window_edges:0;
 n=0;s=0;m=0;paths=0;firstfail=0;invfail=0;invtotal=0;seconds=0;evfirst=0;evsecond=0;
 $display("RREAD_META format=native-resource-reads-v1 finish=BEFORE_ORIGINAL_DRAIN address=PHYSICAL_ORIGINAL size=B0_W1_L2 event=FAST0_IDLE_SECOND1_FIRST_HIT2_FIRST_PASS3_SECOND_HIT4_SECOND_FILL5_SECOND_PASS6 failmask=INV3_CURRENT_SNOOP2_LATCHED_SNOOP1_MISS0 invmask=SWEEP5_CI4_FERR3_LOST2_STORE1_SNOOP0 relation=FIRST0_NEXT1_OTHER2 path=OTHER0_FAST1_FIRST_PASS2_SECOND_HIT3_SECOND_FILL4_SECOND_PASS5_UNCLASSIFIED6");
 foreach(rr_n[a,b,c])begin
  n+=rr_n[a][b][c];s+=rr_sum[a][b][c];if(rr_max[a][b][c]>m)m=rr_max[a][b][c];
  if(rr_n[a][b][c])$display("RREAD_ADDR addr=%08h size=%0d n=%0d sum=%0d max=%0d",32'h00600000+2*a+b,c,rr_n[a][b][c],rr_sum[a][b][c],rr_max[a][b][c]);
 end
 foreach(rr_event[a,b,c,d])begin
  if(d==3)evfirst+=rr_event[a][b][c][d];if(d>=4)evsecond+=rr_event[a][b][c][d];
  if(rr_event[a][b][c][d])$display("RREAD_EVENT addr=%08h size=%0d event=%0d n=%0d",32'h00600000+2*a+b,c,d,rr_event[a][b][c][d]);
 end
 foreach(rr_fail[a,b,c,d])begin
  firstfail+=rr_fail[a][b][c][d];if(d&8)invfail+=rr_fail[a][b][c][d];
  if(rr_fail[a][b][c][d])$display("RREAD_FAIL addr=%08h size=%0d mask=%0d n=%0d",32'h00600000+2*a+b,c,d,rr_fail[a][b][c][d]);
 end
 foreach(rr_second[a,b,c,d,e])begin
  seconds+=rr_second[a][b][c][d][e];
  if(rr_second[a][b][c][d][e])$display("RREAD_SECOND addr=%08h size=%0d mask=%0d hit=%0d n=%0d",32'h00600000+2*a+b,c,d,e,rr_second[a][b][c][d][e]);
 end
 foreach(rr_inv[a,b])begin
  invtotal+=rr_inv[a][b];if(rr_inv[a][b])$display("RREAD_INV mask=%0d relation=%0d n=%0d",a,b,rr_inv[a][b]);
 end
 foreach(rr_path[a])begin paths+=rr_path[a];$display("RREAD_PATH id=%0d n=%0d",a,rr_path[a]);end
 if(n!=rr_whole || s!=rr_latency || m!=rr_maximum || paths!=rr_whole ||
    firstfail!=evfirst || invfail!=invtotal || seconds!=evsecond ||
    rr_starts!=rr_ends+int'(active) ||
    rr_touched!=rr_whole+rr_partial+int'(active && rr_seen) ||
    rr_occupancy!=rr_latency+rr_partial_edges+active_edges)$fatal(1,"RREAD aggregate reconciliation");
 $display("RREAD_TOTAL starts=%0d ends=%0d active=%0d touched=%0d whole=%0d sum=%0d max=%0d partial=%0d partial_edges=%0d active_edges=%0d occupancy=%0d unclassified=%0d",rr_starts,rr_ends,active,rr_touched,rr_whole,rr_latency,rr_maximum,rr_partial,rr_partial_edges,active_edges,rr_occupancy,rr_path[6]);
 $display("RREAD_REST n=%0d sum=%0d max=%0d",rr_rest_n,rr_rest_sum,rr_rest_max);
endtask
`undef RRC
