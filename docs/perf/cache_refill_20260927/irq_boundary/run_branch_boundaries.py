#!/usr/bin/env python3
"""Check pipeline CMP handoff across odd targets, trace and interrupt boundaries."""
import argparse
from pathlib import Path
import subprocess
r = next(p for p in Path(__file__).resolve().parents if (p/'MacQuadra800.qsf').is_file())
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--core', type=Path, required=True, help='candidate ap040_core.v')
parser.add_argument('--cache', type=Path, required=True)
parser.add_argument('--candidate', action='store_true')
parser.add_argument('--out', type=Path, required=True)
parser.add_argument('--pipeline-module', type=Path, default=r/'rtl/ap68040/experimental/ap040_pipeline_integer.sv')
parser.add_argument('--vasm', default='/home/alans/mister/MacQuadra800_fixtures/wombat-vasm/vasmm68k_mot')
args = parser.parse_args()
d = args.out.resolve()
d.mkdir(parents=True, exist_ok=True)
rtl = r/'rtl/ap68040/rtl'
exp = r/'rtl/ap68040/experimental'

def run(cmd,name):
 with (d/name).open('w') as f:subprocess.run(list(map(str,cmd)),stdout=f,stderr=subprocess.STDOUT,check=True)
monitor='''`timescale 1ns/1ps
`define C tb_ap040_program.dut.core
module boundary_monitor;
integer commits=0,injections=0; reg injected=0; integer irq_test=0;
initial if($value$plusargs("irq_test=%d",irq_test)) begin end
always @(negedge tb_ap040_program.clk)
 if(!tb_ap040_program.nreset) injected=0;
 else if(irq_test && !injected && `C.pipe_load_req && `C.pipe_load_pc=='h600) begin
  tb_ap040_program.ipl_lvl=2; injected=1; injections++;
 end
always @(posedge tb_ap040_program.clk) if(tb_ap040_program.nreset && `C.ce && `C.pipe_retire && `C.pipe_pc=='h600) commits++;
final begin
 $display("BOUNDARY commits=%0d injections=%0d",commits,injections);
 if(commits!=3 || (irq_test && injections!=3)) $fatal(1,"boundary pipeline coverage missing");
end
endmodule
'''
(d/'monitor.sv').write_text(monitor)
units=('ap040_bus16_adapter','ap040_bus_timeout','ap040_alu','ap040_muldiv','ap040_mmu','ap040_fpu','ap040_walker_cdc','primitives/dpram')
sources=[Path(__file__).resolve().parent/'tb_ap040_program_retained.v',d/'monitor.sv',exp/'handoff_monitor.sv',args.core.resolve(),rtl/'ap040_regfile.v',args.pipeline_module.resolve(),Path(__file__).resolve().parent/'ap040_tg68k_retained.v',args.cache.resolve(),*[rtl/(u+'.v') for u in units]]
flags=['-DAP040_EXPERIMENTAL_'+x for x in ('XSTORE','LEA','PIPELINE','PIPELINE_LOADS','PIPELINE_STORES','PIPELINE_PEA','PIPELINE_P6')]+['-DAP040_PIPELINE_COMPARE','-DAP040_PIPELINE_MEMORY_ENTRY','-DAP040_PIPELINE_EARLY_DRAIN','-DCACHE_CD_OFF=1','-DCACHE_SMALL=1']
if args.candidate: flags.append('-DBULK_CANDIDATE')
run(['iverilog','-g2012','-I',rtl,'-s','tb_ap040_program','-s','handoff_monitor','-s','boundary_monitor',*flags,'-o',d/'test.vvp',*sources],'compile.log')
# 68040 checks an odd Bcc target even when the condition is false; see t_exceptions.s.
for name,sr,vec,pc,fa,fmt,branch in [('irq',0x2010,26,0x604,None,0x68,0x6604)]:
 vectors=['$7000','start']+['handler' if i==vec else 'failed' for i in range(2,256)]
 asm=' org 0\n'+''.join(' dc.l '+v+'\n' for v in vectors)+f''' org $400
start:
 move.w #$2700,sr
 move.l #$80008000,d0
 movec d0,cacr
 movea.l #$c000,a0
 moveq #0,d1
 moveq #1,d3
 moveq #0,d7
 clr.l ($c000).l
 clr.w ($c100).l
 clr.w -(a7)
 move.l #$600,-(a7)
 move.w #${sr:04x},-(a7)
 rte
 org $600
 dc.w $b6b0,$1800
 dc.w ${branch:04x}
'''
 asm+=' bra.w failed\n nop\n moveq #1,d7\n'
 if name=='irq':asm+=' cmpi.w #1,($c100).l\n bne failed\n bra success\n'
 else:asm+=' bra failed\n'
 asm+=f'''handler:
 cmpi.w #${sr:04x},(a7)
 bne failed
 cmpi.l #${pc:x},2(a7)
 bne failed
 cmpi.w #${fmt:04x},6(a7)
 bne failed
'''
 if fa is not None:asm+=f' cmpi.l #${fa:x},8(a7)\n bne failed\n'
 asm+=' cmpi.l #1,d3\n bne failed\n tst.l d7\n bne failed\n'
 if name=='irq':asm+=' move.w #0,($f110).l\n addq.w #1,($c100).l\n rte\n'
 asm+='''success:
 move.w #$600d,($f102).l
 stop #$2700
failed:
 move.w #$bad0,($f102).l
 stop #$2700
'''
 (d/(name+'.s')).write_text(asm)
 run([args.vasm,'-Fbin','-m68040','-no-opt','-o',d/(name+'.bin'),d/(name+'.s')],name+'_asm.log')
 run(['python3',r/'rtl/ap68040/tb/bin2hex.py',d/(name+'.bin'),d/(name+'.hex')],name+'_hex.log')
 run(['vvp',d/'test.vvp','+prog='+str(d/(name+'.hex')),'+irq_test='+str(int(name=='irq'))],name+'.log')
 s=(d/(name+'.log')).read_text();assert 'ALL TESTS PASSED' in s and 'FAIL:' not in s,s[-2000:]
 print(name,'PASS',next(l for l in s.splitlines() if l.startswith('BOUNDARY')),flush=True)
