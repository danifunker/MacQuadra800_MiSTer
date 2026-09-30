#!/usr/bin/env python3
"""Actual full-machine ROM fixture; opcodes emitted directly, no fabricated observer events."""
from pathlib import Path
import struct,json,hashlib
root=Path(__file__).parent
rom=bytearray(b'\x4e\x71'*(1024*1024//2))
base=0x40800000
writes={}
def put(off,data,label):
 if isinstance(data,str):data=bytes.fromhex(data)
 rom[off:off+len(data)]=data;writes[label]={'offset':hex(off),'bytes':data.hex()}
def addr(x):return struct.pack('>I',base+x)
put(0,struct.pack('>II',0x00200000,base+0x1000),'reset vectors')
put(0x1000,bytes.fromhex('46fc27004bf90010000049f9')+addr(0x4d40)+bytes.fromhex('4ef9')+addr(0x50bc),'entry: mask IRQ, A5 globals, A4 callback, jump prefix')
put(0x4d36,'4e75','helper RTS')
put(0x4d40,'52804e75','callback ADDQ.L #1,D0; RTS')
put(0x50bc,bytes.fromhex('3b7c0004beaa3b7c0042beac4eb9')+addr(0x4d36)+bytes.fromhex('78004ef9')+addr(0x5106),'pinned site1 prefix, relocated helper, returnword, jump timer')
put(0x5106,'3f3c00004e944a2dbeaa4ef9'+addr(0x5132).hex(),'fallback start, callback, return TST.B, jump stop')
put(0x5132,bytes.fromhex('4eb9')+addr(0x4d36)+bytes.fromhex('548f23fc600d0042001001004e72270060fe'),'fallback stop, stack balance, RAM signature, STOP')
(root/'fixture.rom.hex').write_text('\n'.join(f'{int.from_bytes(rom[i:i+4],"big"):08x}' for i in range(0,len(rom),4))+'\n')
(root/'fixture.json').write_text(json.dumps({'scope':'actual quadra800 CPU/MMU/cache/model bus, one site1 fallback span; no OS/DoBall/traps/flush', 'rom_base':hex(base),'expected_memory':{'0x000fbeaa':'0004','0x000fbeac':'0042','0x00100100':'600d0042'},'expected_D0':1,'expected_sp':'0x00200000','rom_bytes_sha256':hashlib.sha256(rom).hexdigest(),'segments':writes},indent=2)+'\n')
print('fixture ROM generated')

# Prime the timer's fetched bytes before identity, then branch to that known
# marker directly from MOVEQ retirement. The core's early branch arm rewrites
# post-edge pc_i to target while IR still names BRA; that is not a timer event.
put(0x1000,bytes.fromhex('46fc27004bf90010000049f9')+addr(0x4d40)+bytes.fromhex('72004ef9')+addr(0x5106),'earlybranch entry primes timer before identity')
put(0x50d0,'584a6032','ADDQ.W #4,A2; BRA.B to known timer marker')
put(0x5138,bytes.fromhex('548f4a01660872014ef9')+addr(0x50bc)+bytes.fromhex('23fc600d0042001001004e72270060fe'),'prime pass returns to prefix, second pass terminates')
(root/'fixture_earlybranch.rom.hex').write_text('\n'.join(f'{int.from_bytes(rom[i:i+4],"big"):08x}' for i in range(0,len(rom),4))+'\n')
(root/'fixture_earlybranch.json').write_text(json.dumps({'scope':'real CPU early branch into already captured timer marker; only second pass is identified','expected_D0':2,'expected_memory':{'0x000fbeaa':'0004','0x000fbeac':'0042','0x00100100':'600d0042'},'expected_sp':'0x00200000','rom_bytes_sha256':hashlib.sha256(rom).hexdigest(),'segments':writes},indent=2)+'\n')
