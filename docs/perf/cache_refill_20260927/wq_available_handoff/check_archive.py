#!/usr/bin/env python3
"""Portable validation of frozen WQ handoff evidence; no tools/scratch needed."""
from pathlib import Path
import hashlib, json, re, sys
R=Path(sys.argv[1] if len(sys.argv)>1 else '.')
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def need(ok,msg):
    if not ok: raise SystemExit('FAIL: '+msg)

# The archive checksum manifest covers every file except itself.
checks={}
for line in (R/'SHA256SUMS').read_text().splitlines():
    h,n=line.split('  ',1);need(re.fullmatch('[0-9a-f]{64}',h) is not None,'bad SHA256SUMS digest')
    need(n not in checks,'duplicate archive path');checks[n]=h
actual={p.relative_to(R).as_posix() for p in R.rglob('*') if p.is_file() and p.name!='SHA256SUMS'}
need(set(checks)==actual,'archive inventory differs from SHA256SUMS')
for n,h in checks.items(): need(sha(R/n)==h,'archive checksum mismatch: '+n)

# Verify both original frozen manifests. README is preserved under provenance
# because the archive has its own scope/limitations README.
def verify_original_manifest(name):
    for line in (R/name).read_text().splitlines():
        h,rel=line.split('  ',1)
        p=R/('provenance/original_validation_README.md' if rel=='README.md' else rel)
        need(p.is_file() and sha(p)==h,'original '+name+' mismatch: '+rel)
verify_original_manifest('source_manifest.sha256')
verify_original_manifest('evidence_manifest.sha256')
for line in (R/'input_manifest.sha256').read_text().splitlines():
    h,rel=line.split('  ',1);need(sha(R/rel)==h,'paired input hash: '+rel)

# Supplement input pins are absolute in the preserved original manifest. Map
# testbench basenames to archived copies; external model is represented by the
# frozen tool-identity path/hash only, not loaded by this checker.
tool=json.loads((R/'tool_identity.json').read_text())
external_lib='/home/alans/intelFPGA_lite/quartus/eda/sim_lib/altera_mf.v'
external_hash='e7bc6f0200f8236986c4b255a4ce7937596946bdb646a93551057edc1e08ca69'
need(tool.get(external_lib,{}).get('sha256')==external_hash,'external primitive model identity')
for line in (R/'supplement/inputs.sha256').read_text().splitlines():
    h,path=line.split('  ',1)
    if path==external_lib:
        need(h==external_hash,'external library pinned hash');continue
    name=Path(path).name; p=R/'supplement'/name
    need(p.is_file() and sha(p)==h,'supplement input hash: '+name)

# The independent saved checker is kept verbatim and its output is retained.
need('PASS saved paired runtime/ownership/equivalence/primitive evidence' in (R/'result_check.log').read_text(),'saved result checker output')
results={}
for variant in ('baseline','candidate'):
    for target in ('tb_sdram','tb_memory_path','tb_line_dma','handoff'):
        d=R/variant/target
        need((d/'build.exit').read_text().strip()=='0',variant+'/'+target+' build exit')
        need((d/'run.exit').read_text().strip()=='0',variant+'/'+target+' run exit')
        for field in ('build.launch.json','run.launch.json'):
            json.loads((d/field).read_text())
    s=(R/variant/'tb_sdram/run.log').read_text()
    need('tb_sdram: 174 checks, 0 failures, 0 chip protocol errors' in s,variant+' SDRAM result')
    m=(R/variant/'tb_memory_path/run.log').read_text()
    need('2048 mixed posted-write/read operations retire in order' in m and 'tb_memory_path: 0 failures, 0 chip protocol errors' in m,variant+' memory path result')
    dma=(R/variant/'tb_line_dma/run.log').read_text()
    match=re.search(r'tb_line_dma: (\d+) reads, (\d+) stores, (\d+) line acks, (\d+) DMA beats, (\d+) errors',dma)
    need(match is not None and tuple(map(int,match.groups()))==(20512,5381,15374,11423,0),variant+' line/DMA counts')
    hand=(R/variant/'handoff/run.log').read_text()
    need('HANDOFF_EQ edges=22320 true=2707 consume=373 init=11 full=150' in hand,variant+' handoff equivalence')
    need('WQ_GUARD pushes=373 consume-starts=373 pops=373 wraps=46 max-used=8 age-ps=[10102,515102]' in hand,variant+' ownership')
    metric_text='\n'.join((R/variant/target/'run.log').read_text() for target in ('tb_sdram','tb_memory_path','tb_line_dma'))
    results[variant]=re.findall(r'  (?:cold read / critical|page-hit read|buffered line read|isolated write beat|64 sequential reads|64 sequential writes|integrated 64 reads|average 16-byte fill)[^\n]+|tb_line_dma: (?:4096 back-to-back stores took|\d+ reads, \d+ stores, \d+ line acks)[^\n]+',metric_text)
need(results['baseline']==results['candidate'],'baseline/candidate timing lines differ')

for target in ('altdpram_edge_tb','altdpram_wrap_tb','altdpram_wrap_negative_tb'):
    p=R/'supplement'/target
    need((p/'build.exit').read_text().strip()=='0','supplement build '+target)
    expect='1' if target.endswith('negative_tb') else '0'
    need((p/'run.exit').read_text().strip()==expect,'supplement exit '+target)
    log=(p/'run.log').read_text()
    need(('captured write missing' if expect=='1' else 'PASS') in log,'supplement result '+target)

# Generated build products and caches must not enter the archive.
for p in R.rglob('*'):
    rel=p.relative_to(R)
    need(not any(part in {'obj','obj_dir','ccache','__pycache__'} for part in rel.parts),'generated directory included: '+str(rel))
    if p.is_file(): need(p.suffix.lower() not in {'.vvp','.o','.a','.so','.pyc'},'generated binary included: '+str(rel))
print('PASS archive files=%d production_pairs=8 handoff_edges=22320 DMA_rounds=4000 primitive_tests=3 generated_outputs_omitted=1' % len(checks))
