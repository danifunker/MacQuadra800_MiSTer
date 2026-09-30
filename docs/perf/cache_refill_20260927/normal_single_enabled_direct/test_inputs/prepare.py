from pathlib import Path
D=Path(__file__).resolve().parent;R=D.parents[1]
s=(R/'rtl/ap68040/tb/tb_ap040_fpu_normalize.v').read_text();s=s[:s.index('localparam [4:0]')]
s=s.replace('tb_ap040_fpu_normalize','tb_normal_single_move')
s=s.replace('// White-box unit regression for the three mutually exclusive normalization\n// states. The reference shifts one bit at a time, including GRS, and checks\n// untouched operands, exponent wrap, next state and clock-enable holding.', '// Real-port all-precision FMOVE.S qualification with independent normal-single\n// conversion oracle, physical-bank/dependency checks, and excluded-path\n// signature comparison. Reuses the normalization bench port scaffold.')
s=s.replace('reg nreset = 0, ce = 0;', '''reg nreset=0,ce=1,req=0;
reg[2:0]op_class=2,src_fmt=1,src_r=0,dst_r=0,fm_sel=0;
reg[6:0]opmode=0;reg[95:0]din=0,fm_wdata=0;
reg[1:0]cr_sel=0;reg[31:0]cr_wdata=0,ia_wdata=0;
reg cr_we=0,fm_we=0,bsun_req=0,ia_we=0,fp_reset=0,fsave_ack=0;
reg frestore_idle=0,frestore_unimp=0,pend_capture=0;
reg[7:0]frestore_cusavepc=0;reg frestore_busy=0;
reg[15:0]frestore_cmd1=0;reg[2:0]frestore_flags=0;
reg[95:0]frestore_fpt=0,frestore_et=0;
wire done,accepted,unimp,unsupp,exc_req,frestore_e1_pend;wire[7:0]exc_vec;
wire[95:0]dout;integer checks=0,fast_cases=0,slow_cases=0;''')
for name in ['req','op_class','opmode','src_fmt','src_r','dst_r','din','cr_sel','cr_we','cr_wdata','bsun_req','ia_we','ia_wdata','fm_sel','fm_we','fm_wdata','fsave_ack','frestore_idle','frestore_unimp','pend_capture','frestore_cusavepc','frestore_busy','frestore_cmd1','frestore_flags','frestore_fpt','frestore_et','fp_reset']:
 import re
 s=re.sub(r'\.'+name+r'\([^)]*\)', '.'+name+'('+name+')',s)
s=s.replace('.op_class(op_class)', '.done(done),.accepted(accepted),.unimp(unimp),.unsupp(unsupp),.exc_req(exc_req),.exc_vec(exc_vec),.dout(dout),\n    .frestore_e1_pend(frestore_e1_pend),.op_class(op_class)')
(D/'tb_normal_single_move.sv').write_text(s+(D/'tests.inc').read_text())
