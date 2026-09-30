#!/usr/bin/env python3
from pathlib import Path
import json,re,hashlib
D=Path(__file__).resolve().parent;r=D/'run';text=(r/'run.log').read_text()
loop=int(re.search(r'WHETSTONE_LOOP cycles=(\d+)',text)[1]);assert loop>0
source_identity=json.loads((r/'identity.json').read_text())
fpu=[v for k,v in source_identity['sources'].items() if k.endswith('/ap040_fpu.v')];assert len(fpu)==1
expected={'2d53db3ae4a04310add04eeb7919f0219197a98827ed92e410e6d4a4a90f5465':14301941,'73bc156d147e4f8b1c7ee08f0bb03c7f1cd720d4e78293d8252f63bf992f0b1f':13358788}
assert loop==expected[fpu[0]],'capture changed timing'
assert text.count('FFT_CAPTURE_DONE pc=00600e00 blocks=3 bytes=5152')==1 and 'FFT_CAPTURE_GUARDS bad=0 ' in text
for x,n in enumerate([2056,2056,1040]):
 payload=bytes(int(v,16) for v in (r/f'fft_payload_{x}.hex').read_text().split());assert len(payload)==n
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
assert coverage['body']>0 and coverage['vector11_pc']>0 and coverage['unimp_pulse_samples']>0
result={'scope':'native tEsT12000 selector2 FPUFFT baseline, copied OS RAM runtime and actual SDRAM path; no independent numerical oracle','loop_cycles':loop,'returned_cycles':int(re.search(r'WHETSTONE RETURNED cycles=(\d+)',text)[1]),'starting_fpcr':re.search(r'NATIVE_START fpcr=([0-9a-f]+)',text)[1],'ABI':'PASS callee-save integer/FP sentinel capture, returned A4/SP/D0, code unchanged','chip_bus_irq_errors':0,'coverage':coverage,'core':core,'cache':cache,'fst':fst,'round':roundvalues,'stdone_samples':int(re.search(r'FPU_ELIG_STDONE samples=(\d+)',text)[1]),'nonidle_fpu_samples':loop-fst[0]}
alloc=[(int(n),int(pc,16),int(ptr,16),int(size,16),int(err,16),int(sec)) for n,pc,ptr,size,err,sec in re.findall(r'FFT_RETURN alloc=(\d+) pc=([0-9a-f]+) ptr=([0-9a-f]+) size=([0-9a-f]+) error=([0-9a-f]+) secondary=(\d+)',text)]
free=[(int(n),int(pc,16),int(ptr,16),int(err,16),int(sec)) for n,pc,ptr,err,sec in re.findall(r'FFT_RETURN free=(\d+) pc=([0-9a-f]+) ptr=([0-9a-f]+) error=([0-9a-f]+) secondary=(\d+)',text)]
assert len(alloc)==len(free)==3 and [a[0] for a in alloc]==[a[0] for a in free]==[1,2,3]
assert [a[1] for a in alloc]==[0x600c98,0x600cce,0x600d04] and [a[1] for a in free]==[0x600e02,0x600e06,0x600e0a]
assert [a[3] for a in alloc]==[0x808,0x808,0x410]
assert all(a[4]==0 for a in alloc) and all(a[3]==0 for a in free)
ptrs=[a[2] for a in alloc];assert len(set(ptrs))==3 and ptrs==[a[2] for a in free]
assert all(0x3f1890<a[2] and a[2]+a[3]<=0x492078 for a in alloc)
for i,a in enumerate(alloc):
 for b in alloc[i+1:]:assert a[2]+a[3]<=b[2] or b[2]+b[3]<=a[2]
args=re.findall(r'FFT_ABI call=(\d+) N=256 input=([0-9a-f]+) scratch=([0-9a-f]+) twiddle=([0-9a-f]+) scalar=3ffb8000000000000000',text)
assert [int(a[0]) for a in args]==list(range(1,21)) and all([int(x,16) for x in a[1:]]==ptrs for a in args)
assert 'FFT_TRAPS alloc_calls=3 alloc_returns=3 free_calls=3 free_returns=3' in text
assert 'FFft_calls=20 FExptab_calls=1 N_checks=20 scalar_checks=20' in text
assert 'FFT_HEAP_END zone=003f1890 bkLim=00492078 free=0003ff10 memtop=00517754' in text
hexbytes=lambda n:bytes(int(x,16) for x in (r/n).read_text().split())
zone_before=hexbytes('fft_zone_before.hex');zone_after=hexbytes('fft_zone_after.hex')
assert zone_before[:4]==zone_after[:4]==(0x492078).to_bytes(4,'big')
assert zone_before[12:16]==zone_after[12:16]==(0x3ff10).to_bytes(4,'big')
assert hexbytes('fft_limit_before.hex')==hexbytes('fft_limit_after.hex')
result['allocations']={'successful':3,'frees':3,'payload_sizes':[2056,2056,1040],'heap_scalars':'restored','pointers':ptrs}
result['native_calls']={'FFft':20,'FExptab':1,'N_pointer_checks':20,'scalar_FP4_bothbanks_checks':20}
result['numerical_oracle']='NONE; no input/output payloadcapture'
if (D/'measurement.json').exists():assert json.loads((D/'measurement.json').read_text())==json.loads(json.dumps(result))
else:(D/'measurement.json').write_text(json.dumps(result,indent=2)+'\n')
print('PASS nativeFFT baseline runtime/ABI/heap/code/FPSP/20FFftcalls/state sums;no numericaloracle')
print('loop',loop,'ROUNDguard',roundvalues['eligible'],'STDONEedge',result['stdone_samples'],'FPU_nonidle',result['nonidle_fpu_samples'])
