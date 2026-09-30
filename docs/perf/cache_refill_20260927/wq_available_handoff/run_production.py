#!/usr/bin/env python3
"""Frozen paired production benches; serial builds, two build workers."""
from pathlib import Path
import subprocess, json, hashlib, time, os
ROOT=Path(__file__).resolve().parent
os.environ['CCACHE_DIR']=str(ROOT/'ccache')
VERILATOR='/home/alans/verilator5/bin/verilator'
FLAGS=['--binary','--timing','-j','2','-Wno-fatal','-Wno-WIDTH','-Wno-WIDTHEXPAND','-Wno-WIDTHTRUNC','-Wno-UNSIGNED','-Wno-CMPCONST','-Wno-DECLFILENAME','+define+SIMULATION=1']
PARAMS=['-GFAST_BYPASS=1','-GDIRECT_FIRST_MISS=1','-GREGISTERED_FIRST_MISS=1','-GADAPTER_LINE_HIT=1','-GDIRECT_MEM_ACK=0','-GREGISTERED_LINE_HIT=1']
def run(argv, cwd, log, timeout):
    start=time.time()
    with log.open('x') as f:
        proc=subprocess.Popen(argv,cwd=cwd,stdout=f,stderr=subprocess.STDOUT)
        (log.with_suffix('.launch.json')).write_text(json.dumps({'argv':argv,'cwd':str(cwd),'pid':proc.pid,'start':start},indent=2)+'\n')
        try: rc=proc.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            proc.kill();proc.wait();raise
    log.with_suffix('.exit').write_text(str(rc)+'\n')
    if rc: raise RuntimeError(f'{log} exit {rc}')
    return log.read_text()
def main():
    subprocess.run(['sha256sum','-c','--quiet','input_manifest.sha256'],cwd=ROOT,check=True)
    (ROOT/'tools.txt').write_text(subprocess.check_output([VERILATOR,'--version'],text=True))
    for variant in ['baseline','candidate']:
        for top in ['tb_sdram','tb_memory_path','tb_line_dma']:
            out=ROOT/variant/top;out.mkdir(exist_ok=False)
            shared=ROOT/'shared'
            sources=[shared/(top+'.sv')]
            if top!='tb_sdram': sources.extend([shared/'tb_sdram.sv',shared/'wombat_bus32.sv'])
            sources.extend([ROOT/variant/'rtl/sdram_beat32.sv',shared/'sdram.sv',shared/'altddio_out_stub.v'])
            cmd=[VERILATOR,*FLAGS,'--top-module',top,'--Mdir',str(out/'obj'),'-o',top]
            if top=='tb_memory_path': cmd.extend(PARAMS)
            cmd.extend(map(str,sources))
            print(f'BUILD {variant}/{top}',flush=True)
            run(cmd,out,out/'build.log',600)
            print(f'RUN {variant}/{top}',flush=True)
            data=run([str(out/'obj'/top)],out,out/'run.log',300)
            if top=='tb_sdram': assert '0 failures, 0 chip protocol errors' in data and 'tb_sdram: OK' in data
            elif top=='tb_memory_path': assert '0 failures, 0 chip protocol errors' in data and 'tb_memory_path: OK' in data
            else: assert '0 errors' in data and 'tb_line_dma: PASS' in data and 'TIMEOUT' not in data
            print(data[-1500:],flush=True)
    subprocess.run(['sha256sum','-c','--quiet','input_manifest.sha256'],cwd=ROOT,check=True)
    print('PASS paired production targets; frozen input hashes unchanged',flush=True)
if __name__=='__main__': main()
