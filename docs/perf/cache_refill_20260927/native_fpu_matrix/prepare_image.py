#!/usr/bin/env python3
from pathlib import Path
import hashlib,json,struct,subprocess,sys
R=Path(__file__).resolve().parents[2];D=Path(__file__).resolve().parent
sys.path.insert(0,str(R/'scripts'));from mac_rsrc import Rsrc
source=R/'scratch/whetstone_full_fixture_20260920/ram.bin'
original=source.read_bytes();assert hashlib.sha256(original).hexdigest()=='6822b7289bc21c7472c3e1f6d1661140a68aaf7338cfddf693f4a22df330ad00'
fork=R/'scratch/speedo_kernel_profile_20260919/raw.rsrc';rsrc=Rsrc(fork);code,meta=rsrc.get('tEsT',12000)
assert len(code)==3784 and hashlib.sha256(code).hexdigest()=='34ee511807b66d2360c505b352d0946c01730d764843ed815cfd49bab2fa8aa0'
ram=bytearray(original);ram[0x600000:0x600000+len(code)]=code
ram[0x625000:0x625200]=bytes(0x200)
asm=''' org $630000
start:
 move.w #$2700,sr
 move.l #$40810000,($0).l
 move.l #$40810000,($4).l
 move.l #$1ff6c00,d0
 movec d0,srp
 moveq #0,d0
 movec d0,urp
 move.l #$c000,d0
 movec d0,tc
 move.l #$80008000,d0
 movec d0,cacr
 lea ($620000).l,a5
 lea ($600000).l,a4
 move.l #$11110003,d3
 move.l #$11110004,d4
 move.l #$11110005,d5
 move.l #$11110006,d6
 move.l #$11110007,d7
 movea.l #$22222222,a2
 movea.l #$33333333,a3
 movea.l #$66666666,a6
 moveq #11,d0
 fmove.l d0,fp4
 moveq #12,d0
 fmove.l d0,fp5
 moveq #13,d0
 fmove.l d0,fp6
 moveq #14,d0
 fmove.l d0,fp7
 movem.l d3-d7/a2-a6,($625000).l
 fmovem.x fp4-fp7,($625100).l
 move.l a7,($625088).l
 move.w #1,($f108).l
 move.w #3,-(a7)
 jsr (a4)
 addq.w #2,a7
 move.w #2,($f108).l
 movem.l d3-d7/a2-a6,($625040).l
 move.l d0,($625080).l
 move.l a7,($625084).l
 fmovem.x fp4-fp7,($625140).l
 move.w #$600d,($f102).l
 stop #$2700
'''
(D/'entry.s').write_text(asm)
with (D/'assemble.log').open('w') as log:subprocess.run(['/home/alans/mister/MacQuadra800_fixtures/wombat-vasm/vasmm68k_mot','-Fbin','-m68040','-no-opt','-o',str(D/'entry.bin'),str(D/'entry.s')],stdout=log,stderr=subprocess.STDOUT,check=True)
entry=(D/'entry.bin').read_bytes();assert len(entry)<4096
ram[0x630000:0x630000+len(entry)]=entry
assert ram[0x600ea0:0x600ec8]==code[0xea0:0xec8]
for lo,hi in [(0,0x600000),(0x600ec8,0x625000),(0x625200,0x630000),(0x630000+len(entry),len(ram))]:assert ram[lo:hi]==original[lo:hi]
(D/'ram.bin').write_bytes(ram)
identity={'scope':'native tEsT12000 selector3 baseline fixture; no numerical oracle','input_image':str(source),'input_sha256':hashlib.sha256(original).hexdigest(),'output_sha256':hashlib.sha256(ram).hexdigest(),'resource':meta,'resource_sha256':hashlib.sha256(code).hexdigest(),'fork_sha256':hashlib.sha256(fork.read_bytes()).hexdigest(),'entry_sha256':hashlib.sha256(entry).hexdigest(),'entry_bytes':len(entry),'resource_base':'0x600000','a4_anchor':'0x608ea0','globals':'0x600ea0..0x600ec7','entry':'0x630000','stack':'0x640000','abi_area':'0x625000..0x6251ff','selector':3,'fpcr':'unchanged; monitor reports starting value','preserved_ranges_checked':True,'vector11':hex(int.from_bytes(ram[44:48],'big'))}
(D/'image_identity.json').write_text(json.dumps(identity,indent=2)+'\n');print(json.dumps(identity,indent=2))
