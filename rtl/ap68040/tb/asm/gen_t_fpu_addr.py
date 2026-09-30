#!/usr/bin/env python3
# Generator for t_fpu_addr.s (the P256 FPU addressing test).  The .s is the
# checked-in source that run_tests.sh assembles; this script produced it.
# Regenerate after editing the check list below:
#     cd rtl/ap68040/tb/asm && python3 gen_t_fpu_addr.py
# It rewrites t_fpu_addr.s next to this script and prints the check count
# (67).  Originally docs/perf/p252_p256_fpu_qual/addrtest/gen.py.
#
# P256 addressing check: FP loads/stores/arith with d16(An), d8(An,Xn), d16(PC), d8(PC,Xn)
# and full-format fallbacks, including index/base registers written by the
# immediately preceding instruction. Every result is compared bit-exact.
S0=0x5000   # single table: 64 longs
D0=0x5400   # double table: 16 doubles
OUT=0x6000  # store area
def sv(a): n=(a-S0)//4; return 0x40000000+(n<<12)
def dv(a): n=(a-D0)//8; return (0x40000000+(n<<12), 0x12345678+n)
L=[]; t=[0]
def e(s): L.append('\t'+s)
def nt(): t[0]+=1; return t[0]
def fl(n): e(f'move.w\t#{n},d7'); e('jmp\tfailed'); L.append(f'ok{n}:')
def chk_fp0_s(exp):
    n=nt(); e('fmove.s\tfp0,(OUTC).l'); e(f'cmp.l\t#${exp:08x},(OUTC).l'); e(f'beq\tok{n}'); fl(n)
def chk_fp1_d(exp):
    hi,lo=exp; n=nt()
    e('fmove.d\tfp1,(OUTC).l'); e(f'cmp.l\t#${hi:08x},(OUTC).l'); e(f'bne\tbad{n}'); e(f'cmp.l\t#${lo:08x},(OUTC+4).l'); e(f'beq\tok{n}')
    L.append(f'bad{n}:'); fl(n)
def chk_mem(addr,exp):
    n=nt(); e(f'cmp.l\t#${exp:08x},(${addr:x}).l'); e(f'beq\tok{n}'); fl(n)
def fill_out():
    for i in range(0,64,4): e(f'move.l\t#$a5a5a5a5,(${OUT+0x100+i:x}).l')
body=[]
def section(title): L.append(f'; ---- {title}')
section('d16(An) source')
e(f'lea\t${S0:x},a0'); e('fmove.s\t8(a0),fp0'); chk_fp0_s(sv(S0+8))
e(f'lea\t${S0+0x40:x},a0'); e('fmove.s\t-12(a0),fp0'); chk_fp0_s(sv(S0+0x34))
e(f'lea\t(${(S0-0x7000+0x10)&0xffffffff:x}).l,a1'); e('fmove.s\t$7000(a1),fp0'); chk_fp0_s(sv(S0+0x10))  # large positive d16
e(f'lea\t(${S0+0x7ff0:x}).l,a1'); e('fmove.s\t-$7fe0(a1),fp0'); chk_fp0_s(sv(S0+0x10))
section('base written by the previous instruction')
e(f'lea\t${S0+0x20:x},a3'); e('fmove.s\t4(a3),fp0'); chk_fp0_s(sv(S0+0x24))
e(f'move.l\t#${S0:x},a3'); e('addq.l\t#8,a3'); e('fmove.s\t4(a3),fp0'); chk_fp0_s(sv(S0+0xc))
section('brief indexed source, data index')
e(f'lea\t${S0:x},a0'); e('moveq\t#8,d1'); e('fmove.s\t4(a0,d1.l),fp0'); chk_fp0_s(sv(S0+12))
e('move.l\t#$ffff0005,d1'); e('fmove.s\t-8(a0,d1.w*4),fp0'); chk_fp0_s(sv(S0+12))
e('move.l\t#$0001fffe,d1'); e(f'lea\t${S0+0x40:x},a2'); e('fmove.s\t8(a2,d1.w*2),fp0'); chk_fp0_s(sv(S0+0x44))
e('moveq\t#3,d2'); e('fmove.s\t0(a0,d2.l*8),fp0'); chk_fp0_s(sv(S0+24))
e('moveq\t#1,d2'); e('fmove.s\t$7f(a0,d2.l*1),fp0'); chk_fp0_s(sv(S0+0x80))
e('moveq\t#$20,d2'); e('fmove.s\t-$80(a0,d2.l*4),fp0'); chk_fp0_s(sv(S0+0))
section('index written by the previous instruction')
e('moveq\t#12,d2'); e('fmove.s\t0(a0,d2.l),fp0'); chk_fp0_s(sv(S0+12))
e('moveq\t#12,d2'); e('addq.l\t#4,d2'); e('fmove.s\t0(a0,d2.l),fp0'); chk_fp0_s(sv(S0+16))
e('move.l\t#20,d3'); e('move.l\t d3,d4'); e('fmove.s\t0(a0,d4.l),fp0'); chk_fp0_s(sv(S0+20))
e('moveq\t#6,d4'); e('lsl.l\t#2,d4'); e('fmove.s\t0(a0,d4.l),fp0'); chk_fp0_s(sv(S0+24))
section('address-register index')
e('move.l\t#$28,a1'); e('fmove.s\t0(a0,a1.l),fp0'); chk_fp0_s(sv(S0+0x28))
e('lea\t$2c,a1'); e('fmove.s\t0(a0,a1.l),fp0'); chk_fp0_s(sv(S0+0x2c))
e('lea\t4(a1),a1'); e('fmove.s\t0(a0,a1.w),fp0'); chk_fp0_s(sv(S0+0x30))
e('move.l\t#$fffffffc,a1'); e(f'lea\t${S0+0x38:x},a2'); e('fmove.s\t0(a2,a1.l),fp0'); chk_fp0_s(sv(S0+0x34))
section('index/base = same register')
e(f'move.l\t#${S0//2+8:x},a4'); e('fmove.s\t-16(a4,a4.l),fp0'); chk_fp0_s(sv(S0+0))
section('index and base updated by a preceding FP (An)+ / -(An)')
e(f'lea\t${S0+0x40:x},a5'); e('fmove.s\t(a5)+,fp3'); e('fmove.s\t0(a5),fp0'); chk_fp0_s(sv(S0+0x44))
e(f'lea\t${S0+0x40:x},a5'); e('sub.l\ta6,a6'); e('fmove.s\t(a5)+,fp3'); e('fmove.s\t4(a6,a5.l),fp0'); chk_fp0_s(sv(S0+0x48))
e(f'lea\t${S0+0x50:x},a5'); e('fmove.s\t-(a5),fp3'); e('fmove.s\t-4(a5),fp0'); chk_fp0_s(sv(S0+0x48))
e(f'lea\t${S0+0x50:x},a5'); e('fmove.s\t-(a5),fp3'); e('fmove.s\t0(a6,a5.w),fp0'); chk_fp0_s(sv(S0+0x4c))
section('A7 base / index')
e('move.l\ta7,d6'); e(f'lea\t${S0+0x60:x},a7'); e('fmove.s\t4(a7),fp0'); e('move.l\td6,a7'); chk_fp0_s(sv(S0+0x64))
e('move.l\ta7,d6'); e('move.l\t#$68,a7'); e('fmove.s\t0(a0,a7.l),fp0'); e('move.l\td6,a7'); chk_fp0_s(sv(S0+0x68))
section('PC-relative sources')
e('bra.s\tpcskip'); e('cnop\t0,4'); L.append('pctab:'); e('dc.l\t$3f800000,$3fa00000,$3fc00000,$3fe00000'); L.append('pcskip:')
e('fmove.s\tpctab+8(pc),fp0'); chk_fp0_s(0x3fc00000)
e('moveq\t#4,d1'); e('fmove.s\tpctab(pc,d1.l),fp0'); chk_fp0_s(0x3fa00000)
e('move.l\t#$ffff0003,d1'); e('fmove.s\tpctab(pc,d1.w*4),fp0'); chk_fp0_s(0x3fe00000)
e('moveq\t#12,d1'); e('fmove.s\tpctab-4(pc,d1.l),fp0'); chk_fp0_s(0x3fc00000)
section('full-format extension (fallback path)')
e('moveq\t#8,d1'); e('fmove.s\t(4.l,a0,d1.l),fp0'); chk_fp0_s(sv(S0+12))
e(f'move.l\t#${S0+0x70:x},(ptr).l'); e('fmove.s\t([ptr.l],4),fp0'); chk_fp0_s(sv(S0+0x74))
e('fmove.s\t(-4.w,a0,d1.l*2),fp0'); chk_fp0_s(sv(S0+12))
section('double sources')
e(f'lea\t${D0:x},a0'); e('fmove.d\t16(a0),fp1'); chk_fp1_d(dv(D0+16))
e('moveq\t#3,d1'); e('fmove.d\t8(a0,d1.l*8),fp1'); chk_fp1_d(dv(D0+32))
e('moveq\t#40,d1'); e('fmove.d\t0(a0,d1.w),fp1'); chk_fp1_d(dv(D0+40))
e('fmove.d\tpcd(pc),fp1'); chk_fp1_d((0x40091eb8,0x51eb851f))
section('arithmetic with displacement / indexed sources')
e(f'lea\t${S0:x},a0'); e('fmove.s\t#2.0,fp0'); e('fmul.s\t8(a0),fp0'); chk_fp0_s(sv(S0+8)+0x00800000)  # *2 => exponent+1
e('fmove.s\t#1.0,fp0'); e('moveq\t#4,d1'); e('fmul.s\t0(a0,d1.l*4),fp0'); chk_fp0_s(sv(S0+16))
e('fmove.s\t#0.0,fp0'); e('fadd.s\t-4(a0,d1.l*8),fp0'); chk_fp0_s(sv(S0+28))
e('fmove.s\t#2.0,fp0'); e('lea\tpctab,a2'); e('fdiv.s\t8(a2),fp0'); chk_fp0_s(0x3faaaaab)  # 2/1.5
e(f'lea\t${D0:x},a0'); e('fmove.s\t#1.0,fp1'); e('fmul.d\t16(a0),fp1'); chk_fp1_d(dv(D0+16))
e('fmove.s\t#0.0,fp1'); e('moveq\t#1,d1'); e('fadd.d\t0(a0,d1.l*8),fp1'); chk_fp1_d(dv(D0+8))
section('single stores')
fill_out()
e(f'lea\t${OUT+0x100:x},a4'); e(f'fmove.s\t(${S0+4:x}).l,fp0'); e('fmove.s\tfp0,8(a4)'); chk_mem(OUT+0x108,sv(S0+4)); chk_mem(OUT+0x104,0xa5a5a5a5); chk_mem(OUT+0x10c,0xa5a5a5a5)
e('moveq\t#4,d1'); e(f'fmove.s\t(${S0+8:x}).l,fp0'); e('fmove.s\tfp0,4(a4,d1.l*4)'); chk_mem(OUT+0x114,sv(S0+8)); chk_mem(OUT+0x110,0xa5a5a5a5); chk_mem(OUT+0x118,0xa5a5a5a5)
e('move.l\t#$fffe0007,d1'); e(f'fmove.s\t(${S0+12:x}).l,fp0'); e('fmove.s\tfp0,-4(a4,d1.w*4)'); chk_mem(OUT+0x118,sv(S0+12))
e(f'fmove.s\t(${S0+16:x}).l,fp0'); e('moveq\t#$20,d3'); e('fmove.s\tfp0,0(a4,d3.l)'); chk_mem(OUT+0x120,sv(S0+16))
e(f'fmove.s\t(${S0+20:x}).l,fp0'); e(f'lea\t${OUT+0x100:x},a3'); e('fmove.s\tfp0,$24(a3)'); chk_mem(OUT+0x124,sv(S0+20))
e(f'fmove.s\t(${S0+24:x}).l,fp0'); e('move.l\t#$28,a1'); e('fmove.s\tfp0,0(a4,a1.l)'); chk_mem(OUT+0x128,sv(S0+24))
e(f'fmove.s\t(${S0+28:x}).l,fp0'); e('fmove.s\tfp0,(-4.l,a4,a1.l)'); chk_mem(OUT+0x124,sv(S0+28))
section('arith result stored to displacement / indexed (P255 + P256)')
e('fmove.s\t#1.5,fp0'); e('fadd.s\t#1.5,fp0'); e('fmove.s\tfp0,$2c(a4)'); chk_mem(OUT+0x12c,0x40400000)
e('fmove.s\t#3.0,fp2'); e('fmul.s\t#0.5,fp2'); e('moveq\t#$30,d1'); e('fmove.s\tfp2,0(a4,d1.l)'); chk_mem(OUT+0x130,0x3fc00000)
section('double stores')
e(f'fmove.d\t(${D0+8:x}).l,fp1'); e('fmove.d\tfp1,$38(a4)'); chk_mem(OUT+0x138,dv(D0+8)[0]); chk_mem(OUT+0x13c,dv(D0+8)[1]); chk_mem(OUT+0x134,0xa5a5a5a5)
e(f'fmove.d\t(${D0+16:x}).l,fp1'); e('moveq\t#8,d1'); e('fmove.d\tfp1,$38(a4,d1.l*2)'); chk_mem(OUT+0x148,dv(D0+16)[0]); chk_mem(OUT+0x14c,dv(D0+16)[1])
e('fmove.s\t#2.5,fp1'); e('fsub.s\t#0.5,fp1'); e('fmove.d\tfp1,-8(a4,d1.l*8)'); chk_mem(OUT+0x138,0x40000000); chk_mem(OUT+0x13c,0)
section('extended loads/stores with d16 (non-shortcut format)')
e(f'fmove.s\t(${S0+32:x}).l,fp0'); e('fmove.x\tfp0,$50(a4)'); e('fmove.x\t$50(a4),fp2'); e('moveq\t#$60,d1'); e('fmove.s\tfp2,0(a4,d1.l)'); chk_mem(OUT+0x160,sv(S0+32))
e('fmove.l\t#12345,fp0'); e('fmove.l\tfp0,$64(a4)'); chk_mem(OUT+0x164,12345)
e('moveq\t#$68,d1'); e('fmove.w\t#-7,fp0'); e('fmove.l\tfp0,0(a4,d1.l)'); chk_mem(OUT+0x168,0xfffffff9)
asm=f'''; generated by gen_t_fpu_addr.py -- P256 d16 / brief-indexed FPU operand check
FAILREG equ $F100
OUTC    equ ${OUT:x}
    org 0
    dc.l $7000,start
    rept 254
    dc.l failed
    endr
    org $400
start:
    move.l #$80008000,d0
    movec d0,cacr
    fmove.l #0,fpcr
    moveq #0,d7
'''+'\n'.join(L)+f'''
    move.w #$600d,($f102).l
    stop #$2700
    cnop 0,4
pcd:
    dc.l $40091eb8,$51eb851f
ptr:
    dc.l 0
failed:
    move.w d7,($f100).l
    move.w #$bad0,($f102).l
    stop #$2700
    org ${S0:x}
'''+'\n'.join(f'    dc.l ${sv(S0+4*i):08x}' for i in range(64))+f'''
    org ${D0:x}
'''+'\n'.join('    dc.l ${:08x},${:08x}'.format(*dv(D0+8*i)) for i in range(16))+'\n'
# a4+a4 case: a4 = S0/2+8 => 2*a4 = S0+16, -16 => S0. fine, no extra data needed
import os
open(os.path.join(os.path.dirname(os.path.abspath(__file__)),'t_fpu_addr.s'),'w').write(asm)
print(t[0],'checks')
