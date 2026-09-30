#!/usr/bin/env python3
from pathlib import Path
import json,re,hashlib
D=Path(__file__).resolve().parent;r=D/'run';text=(r/'run.log').read_text()
loop=int(re.search(r'WHETSTONE_LOOP cycles=(\d+)',text)[1]);assert loop>0
assert 'SDRAM_PROTOCOL_ERRORS 0' in text and re.search(r'BERR 0\s+IPL_ASSERTED_CYCLES 0',text)
assert 'WHETSTONE RETURNED' in text
identity=json.loads((D/'image_identity.json').read_text());
if (D/'ram.bin').exists():assert hashlib.sha256((D/'ram.bin').read_bytes()).hexdigest()==identity['output_sha256']
abi=bytes(int(x,16) for x in (r/'native_abi.hex').read_text().split())
expected=[0x11110003,0x11110004,0x11110005,0x11110006,0x11110007,0x22222222,0x33333333,0x600000,0x620000,0x66666666]
assert abi[:40]==b''.join(x.to_bytes(4,'big') for x in expected)
assert abi[:40]==abi[0x40:0x68]
assert abi[0x100:0x130]==abi[0x140:0x170]
assert {abi[0x100+i*12:0x10c+i*12] for i in range(4)}=={bytes.fromhex('40020000'+m+'00000000000000') for m in ['b0','c0','d0','e0']}
assert int.from_bytes(abi[0x80:0x84],'big')==0x608ea0
assert int.from_bytes(abi[0x84:0x88],'big')==0x640000 and abi[0x84:0x88]==abi[0x88:0x8c]
code=bytes(int(x,16) for x in (r/'native_code.hex').read_text().split());assert hashlib.sha256(code).hexdigest()==json.loads((D/'qualification_identity.json').read_text())['initial_native_code_sha256']
core={int(a):int(b) for a,b in re.findall(r'NATIVE_CORE state=(\d+) samples=(\d+)',text)}
cache={int(a):int(b) for a,b in re.findall(r'NATIVE_CACHE state=(\d+) samples=(\d+)',text)}
fst={int(a):int(b) for a,b in re.findall(r'FPU_ELIG_FST id=(\d+) samples=(\d+)',text)}
assert max(core)<256 and max(cache)<16 and max(fst)<32
assert sum(core.values())==sum(cache.values())==sum(fst.values())==loop
ops={int(a,16):int(b) for a,b in re.findall(r'FPU_ELIG_BUSY_OP op=([0-9a-f]+) samples=(\d+)',text)}
assert sum(ops.values())==loop-fst.get(0,0)
roundrow=re.search(r'FPU_ELIG_ROUND samples=(\d+) eligible=(\d+) bg=(\d+) decode_wait=(\d+) cpu_go=(\d+)',text)
roundvalues=dict(zip(['samples','eligible','bg','decode_wait','cpu_go'],map(int,roundrow.groups())))
roundops=[tuple(map(int,(b,c))) for _,b,c in re.findall(r'FPU_ELIG_ROUND_OP op=([0-9a-f]+) samples=(\d+) eligible=(\d+)',text)]
assert sum(a for a,b in roundops)==roundvalues['samples'] and sum(b for a,b in roundops)==roundvalues['eligible']
coverage=dict((k,int(v)) for k,v in re.findall(r'(\w+)=(\d+)',re.search(r'NATIVE_COVERAGE (.*)',text)[1]))
assert coverage['body']>0
result={'scope':'native tEsT12000 selector3 FPMm baseline, copied OS RAM runtime and actual SDRAM path; no independent numerical oracle','loop_cycles':loop,'returned_cycles':int(re.search(r'WHETSTONE RETURNED cycles=(\d+)',text)[1]),'starting_fpcr':re.search(r'NATIVE_START fpcr=([0-9a-f]+)',text)[1],'ABI':'PASS callee-save integer/FP sentinel capture, returned A4/SP/D0, code unchanged','chip_bus_irq_errors':0,'coverage':coverage,'core':core,'cache':cache,'fst':fst,'round':roundvalues,'stdone_samples':int(re.search(r'FPU_ELIG_STDONE samples=(\d+)',text)[1]),'nonidle_fpu_samples':loop-fst[0]}
alloc=[(int(n),int(pc,16),int(ptr,16),int(err,16),int(sec)) for n,pc,ptr,err,sec in re.findall(r'MATRIX_RETURN alloc=(\d+) pc=([0-9a-f]+) ptr=([0-9a-f]+) error=([0-9a-f]+) secondary=(\d+)',text)]
freed=[(int(n),int(pc,16),int(ptr,16),int(err,16),int(sec)) for n,pc,ptr,err,sec in re.findall(r'MATRIX_RETURN free=(\d+) pc=([0-9a-f]+) ptr=([0-9a-f]+) error=([0-9a-f]+) secondary=(\d+)',text)]
assert len(alloc)==len(freed)==123
assert [x[0] for x in alloc]==[x[0] for x in freed]==list(range(1,124))
ptrs=[x[2] for x in alloc];assert len(set(ptrs))==123 and set(ptrs)=={x[2] for x in freed}
assert all(x[3]==0 for x in alloc+freed)
assert all(0x3f1890<x and x+0xa4<=0x492078 for x in ptrs)
assert all(a+0xa4<=b for a,b in zip(sorted(ptrs),sorted(ptrs)[1:]))
stack=bytes(int(x,16) for x in (r/'native_stack.hex').read_text().split())
for i,ptr in enumerate(ptrs):
 addr=0x63ffea-0xa4*(1+i//41)+(i%41)*4
 assert int.from_bytes(stack[addr-0x63f000:addr-0x63f000+4],'big')==ptr,'pointer table'
zone_before=bytes(int(x,16) for x in (r/'matrix_zone_before.hex').read_text().split())
zone_after=bytes(int(x,16) for x in (r/'matrix_zone_after.hex').read_text().split())
assert zone_before[:4]==zone_after[:4]==(0x492078).to_bytes(4,'big')
assert zone_before[12:16]==zone_after[12:16]==(0x3ff10).to_bytes(4,'big')
assert 'MATRIX_TRAPS alloc_calls=123 alloc_returns=123 free_calls=123 free_returns=123' in text
assert 'MATRIX_HEAP_END zone=003f1890 bkLim=00492078 free=0003ff10 memtop=00517754 ptr_tables=match' in text
result['allocations']={'successful':123,'frees':123,'payload_bytes':164,'pointer_tables':'match','heap_scalars':'restored','numerical_oracle':'none'}
if (D/'measurement.json').exists():
 assert json.loads((D/'measurement.json').read_text())==json.loads(json.dumps(result)), 'archived result differs from recomputed checks'
else:(D/'measurement.json').write_text(json.dumps(result,indent=2)+'\n')
print('PASS native baseline: return, ABI, code, native/allocator coverage, histogram totals, zero chip/bus/IRQ errors; numerical oracle NONE')
print('loop',loop,'ROUNDguard',roundvalues['eligible'],'STDONEedge',result['stdone_samples'],'FPU_nonidle',result['nonidle_fpu_samples'])
