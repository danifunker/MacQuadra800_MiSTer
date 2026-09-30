#!/usr/bin/env python3
from pathlib import Path
import subprocess, json
from run_production import ROOT, FLAGS, VERILATOR, run
D=ROOT/'supplement'
MODEL='/home/alans/intelFPGA_lite/quartus/eda/sim_lib/altera_mf.v'
def main():
    subprocess.run(['sha256sum','-c','--quiet',str(D/'inputs.sha256')],check=True)
    for variant in ['baseline','candidate']:
        out=ROOT/variant/'handoff';out.mkdir(exist_ok=False)
        cmd=[VERILATOR,*FLAGS,'--top-module','tb_sdram','--Mdir',str(out/'obj'),'-o','tb_sdram']
        if variant=='candidate': cmd.append('+define+CANDIDATE=1')
        cmd.extend(map(str,[D/'tb_sdram_handoff.sv',ROOT/variant/'rtl/sdram_beat32.sv',ROOT/'shared/sdram.sv',ROOT/'shared/altddio_out_stub.v']))
        print('BUILD handoff '+variant,flush=True);run(cmd,out,out/'build.log',600)
        data=run([str(out/'obj/tb_sdram')],out,out/'run.log',300)
        assert '0 failures, 0 chip protocol errors' in data and 'HANDOFF_EQ' in data and 'WQ_GUARD' in data
        print(data[-700:],flush=True)
    for name,negative in [('altdpram_edge_tb',False),('altdpram_wrap_tb',False),('altdpram_wrap_negative_tb',True)]:
        out=D/name;out.mkdir(exist_ok=False)
        # Negative source deliberately retains the same top module name.
        top='altdpram_wrap_tb' if negative else name
        run(['iverilog','-g2012','-s',top,'-o',str(out/'test.vvp'),MODEL,str(D/(name+'.sv'))],out,out/'build.log',300)
        if negative:
            try: run(['vvp',str(out/'test.vvp')],out,out/'run.log',60)
            except RuntimeError: pass
            else: raise AssertionError('negative primitive mutation unexpectedly passed')
            assert 'captured write missing' in (out/'run.log').read_text()
        else:
            data=run(['vvp',str(out/'test.vvp')],out,out/'run.log',60)
            assert 'PASS' in data
        print(name+': '+(out/'run.log').read_text().strip(),flush=True)
    subprocess.run(['sha256sum','-c','--quiet','input_manifest.sha256'],cwd=ROOT,check=True)
    print('PASS handoff decisions/ownership and actual Intel primitive checks',flush=True)
if __name__=='__main__':main()
