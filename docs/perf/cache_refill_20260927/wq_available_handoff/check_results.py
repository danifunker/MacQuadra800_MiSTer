#!/usr/bin/env python3
"""Check saved paired evidence without running any simulator."""
from pathlib import Path
import hashlib,json,re,subprocess
R=Path(__file__).resolve().parent
def load(variant,target):
    p=R/variant/target
    assert (p/'build.exit').read_text().strip()=='0'
    assert (p/'run.exit').read_text().strip()=='0'
    s=(p/'run.log').read_text()
    assert not re.search(r'(^CHIP\s|FAILED|FAIL\s|TIMEOUT|FATAL|%Error)',s,re.M)
    return s
def metric(s,pattern):
    m=re.search(pattern,s,re.M);assert m,pattern
    return tuple(int(x) for x in m.groups())
def main():
    subprocess.run(['sha256sum','-c','--quiet','input_manifest.sha256'],cwd=R,check=True)
    subprocess.run(['sha256sum','-c','--quiet',str(R/'supplement/inputs.sha256')],check=True)
    result={'scope':'related-clock digital baseline/candidate queue handoff tests; no STA or FPGA qualification','variants':{}}
    for v in ['baseline','candidate']:
        s=load(v,'tb_sdram');mem=load(v,'tb_memory_path');dma=load(v,'tb_line_dma');mon=load(v,'handoff')
        assert metric(s,r'tb_sdram: (\d+) checks, (\d+) failures, (\d+) chip protocol errors')==(174,0,0)
        assert metric(mem,r'tb_memory_path: (\d+) failures, (\d+) chip protocol errors')==(0,0)
        assert '2048 mixed posted-write/read operations retire in order' in mem
        dm=metric(dma,r'tb_line_dma: (\d+) reads, (\d+) stores, (\d+) line acks, (\d+) DMA beats, (\d+) errors')
        assert dm==(20512,5381,15374,11423,0)
        eq=metric(mon,r'HANDOFF_EQ edges=(\d+) true=(\d+) consume=(\d+) init=(\d+) full=(\d+)')
        own=metric(mon,r'WQ_GUARD pushes=(\d+) consume-starts=(\d+) pops=(\d+) wraps=(\d+) max-used=(\d+) age-ps=\[(\d+),(\d+)\]')
        assert eq==(22320,2707,373,11,150) and own==(373,373,373,46,8,10102,515102)
        metrics=[line for data in [s,mem,dma] for line in data.splitlines() if re.search(r'clk_sys|64 sequential|integrated 64 reads|average 16-byte|^tb_line_dma:',line)]
        result['variants'][v]={'bridge_sha256':hashlib.sha256((R/v/'rtl/sdram_beat32.sv').read_bytes()).hexdigest(),'handoff':eq,'ownership':own,'dma':dm,'metrics':metrics}
    assert result['variants']['baseline']['metrics']==result['variants']['candidate']['metrics']
    for n in ['altdpram_edge_tb','altdpram_wrap_tb','altdpram_wrap_negative_tb']:
        p=R/'supplement'/n;assert (p/'build.exit').read_text().strip()=='0'
        s=(p/'run.log').read_text();negative='negative' in n
        assert (p/'run.exit').read_text().strip()==('1' if negative else '0')
        assert ('captured write missing' if negative else 'PASS') in s
    print(json.dumps(result,indent=2));print('PASS saved paired runtime/ownership/equivalence/primitive evidence')
if __name__=='__main__':main()
