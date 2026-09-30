#!/usr/bin/env python3
"""FPU latency / issue-interval measurement for the AP68040 in wombat_cpu.

gen    writes fpu_latency.s (the measured program) next to this script
run    assembles it, builds tb_fpu_latency.sv with Verilator 5 and the
       production AP040_* macros, runs it at each --latency, prints the table
       (and writes results_latN.txt into the output directory)

Every test is run as a straight-line block of 16, 32 and 64 copies,
each bracketed by FNOP + cycle-stamp store, and each block is executed twice
(the first pass warms the I- and D-caches, only the second is reported).
  per16 = (clocks(16 copies) - clocks(empty block)) / 16
  32-16 = (clocks(32 copies) - clocks(16 copies)) / 16
  64-32 = (clocks(64 copies) - clocks(32 copies)) / 32   (stamp to stamp)
  body  = the same slope from the bench's BODY decode-PC timing  <- reported
"""
import argparse, math, os, re, struct, subprocess, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
VASM = os.environ.get('VASM', '/home/alans/mister/MacQuadra800_fixtures/wombat-vasm/vasmm68k_mot')
VERILATOR = os.environ.get('VERILATOR', '/home/alans/verilator5/bin/verilator')
FLAGS = ['-DAP040_EXPERIMENTAL_' + x for x in
         ('XSTORE', 'LEA', 'PIPELINE', 'PIPELINE_LOADS', 'PIPELINE_STORES', 'PIPELINE_PEA', 'PIPELINE_P6')] + \
        ['-DAP040_PIPELINE_MEMORY_ENTRY', '-DAP040_PIPELINE_COMPARE', '-DAP040_PIPELINE_EARLY_DRAIN']

# ---------------------------------------------------------------- constants
def xbits(v):
    """IEEE double -> 68881 extended (3 longwords)."""
    if v == 0: return (0, 0, 0)
    s = 0x80000000 if v < 0 else 0
    m, e = math.frexp(abs(v))          # v = m * 2^e, 0.5 <= m < 1
    mant = int(m * (1 << 64))          # exact for doubles
    return (s | ((e - 1 + 16383) << 16), mant >> 32, mant & 0xffffffff)

CONSTS = {  # name -> list of longwords
    'c1p2345':  xbits(1.2345),
    'cmul':     xbits(1.0000123),
    'c1p1':     xbits(1.1),
    'c40p5':    xbits(40.5),
    'c2p40':    xbits(1.3 * 2.0**40),
    'cone':     xbits(1.0),
    'conep60':  (16383 << 16, 0x80000000, 0x00000008),   # 1 + 2^-60
    'c1000':    xbits(1000.5),
    'c1234':    xbits(1234.5),
    'c1p01':    xbits(1.01),
    'c2p5':     xbits(2.5),
    'cbig':     xbits(1.2345e300),
    'ctwo':     xbits(2.0),
    'c0p7071':  xbits(0.70710678),
}
DOUBLE = struct.unpack('>2L', struct.pack('>d', 1.0000123))
SINGLE = struct.unpack('>L', struct.pack('>f', 1.0000123))[0]

def load(regs_vals):
    """setup: list of (fpreg, constname)"""
    return ['\tfmove.x\t(%s).l,fp%d' % (c, r) for r, c in regs_vals]

def all_regs(c, c7=None):
    return load([(r, c) for r in range(7)] + [(7, c7 or c)])

A0_X = ['\tlea\t(mx).l,a0']
A0_D = ['\tlea\t(md).l,a0']
A0_S = ['\tlea\t(ms).l,a0']
A0_TAB = ['\tlea\t(dtab).l,a0']
A0_BUF = ['\tlea\t(sbuf).l,a0']
A0_SDAT = ['\tlea\t(sdat).l,a0']
A0_FDAT = ['\tlea\t(fdat).l,a0']

# ---------------------------------------------------------------- tests
# (key, row label, setup lines, body(n) -> lines, ops per copy)
T = []
def t(key, label, setup, body, per=1):
    T.append((key, label, setup, body, per))

r7 = lambda i: i % 7
t('fmove_i', 'FMOVE.X FPm,FPn  indep', all_regs('c1p2345'), lambda n: ['\tfmove.x\tfp7,fp%d' % r7(i) for i in range(n)])
t('fmove_d', 'FMOVE.X FPm,FPn  dep',   all_regs('c1p2345'), lambda n: ['\tfmove.x\tfp%d,fp%d' % (i % 8, (i + 1) % 8) for i in range(n)])
t('faddeq_i', 'FADD.X equal exp  indep', all_regs('c1p2345'), lambda n: ['\tfadd.x\tfp%d,fp%d' % (i % 8, i % 8) for i in range(n)])
t('faddeq_d', 'FADD.X equal exp  dep',   all_regs('c1p2345'), lambda n: ['\tfadd.x\tfp0,fp0'] * n)
t('fadd5_i', 'FADD.X exp diff 5  indep', all_regs('c40p5', 'c1p1'), lambda n: ['\tfadd.x\tfp7,fp%d' % r7(i) for i in range(n)])
t('fadd5_d', 'FADD.X exp diff 5  dep',   all_regs('c40p5', 'c1p1'), lambda n: ['\tfadd.x\tfp7,fp0'] * n)
t('fadd40_i', 'FADD.X exp diff 40  indep', all_regs('c2p40', 'c1p1'), lambda n: ['\tfadd.x\tfp7,fp%d' % r7(i) for i in range(n)])
t('fadd40_d', 'FADD.X exp diff 40  dep',   all_regs('c2p40', 'c1p1'), lambda n: ['\tfadd.x\tfp7,fp0'] * n)
# heavy cancellation: (1+2^-60) - 1 = 2^-60 (normalize by 60), then + 1 restores it
t('fsubc_i', 'FSUB.X cancel/FADD d60 pairs  indep', all_regs('conep60', 'cone'),
  lambda n: sum([['\tfsub.x\tfp7,fp0', '\tfsub.x\tfp7,fp1', '\tfadd.x\tfp7,fp0', '\tfadd.x\tfp7,fp1'] for _ in range(n // 4)], []))
t('fsubc_d', 'FSUB.X cancel/FADD d60 pairs  dep', all_regs('conep60', 'cone'),
  lambda n: sum([['\tfsub.x\tfp7,fp0', '\tfadd.x\tfp7,fp0'] for _ in range(n // 2)], []))
t('fsubn_i', 'FSUB.X no cancel  indep', all_regs('c1000', 'c1p1'), lambda n: ['\tfsub.x\tfp7,fp%d' % r7(i) for i in range(n)])
t('fsubn_d', 'FSUB.X no cancel  dep',   all_regs('c1000', 'c1p1'), lambda n: ['\tfsub.x\tfp7,fp0'] * n)
t('fmul_i', 'FMUL.X FPm,FPn  indep', all_regs('c1p2345', 'cmul'), lambda n: ['\tfmul.x\tfp7,fp%d' % r7(i) for i in range(n)])
t('fmul_d', 'FMUL.X FPm,FPn  dep',   all_regs('c1p2345', 'cmul'), lambda n: ['\tfmul.x\tfp7,fp0'] * n)
t('fmul2_i', 'FMUL.X by 2.0 (fast path)  indep', all_regs('c1p2345', 'ctwo'), lambda n: ['\tfmul.x\tfp7,fp%d' % r7(i) for i in range(n)])
t('fdiv_i', 'FDIV.X FPm,FPn  indep', all_regs('c1234', 'c1p01'), lambda n: ['\tfdiv.x\tfp7,fp%d' % r7(i) for i in range(n)])
t('fdiv_d', 'FDIV.X FPm,FPn  dep',   all_regs('c1234', 'c1p01'), lambda n: ['\tfdiv.x\tfp7,fp0'] * n)
t('fsqrt_i', 'FSQRT.X FPm,FPn  indep', all_regs('c1234', 'c2p5'), lambda n: ['\tfsqrt.x\tfp7,fp%d' % r7(i) for i in range(n)])
t('fsqrt_d', 'FSQRT.X FPn  dep',       all_regs('cbig'), lambda n: ['\tfsqrt.x\tfp0'] * n)
for fmt, a0 in (('x', A0_X), ('d', A0_D), ('s', A0_S)):
    t('fmulm%s_i' % fmt, 'FMUL.%s (A0),FPn  indep' % fmt.upper(), all_regs('c1p2345') + a0,
      lambda n, f=fmt: ['\tfmul.%s\t(a0),fp%d' % (f, r7(i)) for i in range(n)])
    t('fmulm%s_d' % fmt, 'FMUL.%s (A0),FPn  dep' % fmt.upper(), all_regs('c1p2345') + a0,
      lambda n, f=fmt: ['\tfmul.%s\t(a0),fp0' % f] * n)
t('faddpi_i', 'FADD.D (A0)+,FPn  indep', all_regs('c40p5') + A0_TAB, lambda n: ['\tfadd.d\t(a0)+,fp%d' % r7(i) for i in range(n)])
t('faddpi_d', 'FADD.D (A0)+,FPn  dep',   all_regs('c40p5') + A0_TAB, lambda n: ['\tfadd.d\t(a0)+,fp0'] * n)
for fmt in 'xdsl':
    t('fst%s_i' % fmt, 'FMOVE.%s FPn,(A0)  indep' % fmt.upper(), all_regs('c1000', 'c1p1') + A0_BUF,
      lambda n, f=fmt: ['\tfmove.%s\tfp%d,(a0)' % (f, i % 8) for i in range(n)])
    # "dep": the store's source is the FADD result produced just before it
    t('fst%s_d' % fmt, 'FADD.X + FMOVE.%s of its result (pair)' % fmt.upper(), all_regs('c1000', 'c1p1') + A0_BUF,
      lambda n, f=fmt: sum([['\tfadd.x\tfp7,fp0', '\tfmove.%s\tfp0,(a0)' % f] for _ in range(n)], []), 2)
t('fld_i', 'FMOVE.D (A0),FPn  different dest', A0_D, lambda n: ['\tfmove.d\t(a0),fp%d' % (i % 8) for i in range(n)])
t('fld_d', 'FMOVE.D (A0),FP0  same dest',      A0_D, lambda n: ['\tfmove.d\t(a0),fp0'] * n)
t('fcmp_i', 'FCMP.X FPm,FPn', all_regs('c1p2345', 'c1p1'), lambda n: ['\tfcmp.x\tfp7,fp%d' % r7(i) for i in range(n)])
t('fcmpb_d', 'FCMP.X + FBEQ.W not taken (pair)', all_regs('c1p2345', 'c1p1'),
  lambda n: sum([['\tfcmp.x\tfp7,fp0', '\tfbeq.w\t.b%d' % i, '.b%d:' % i] for i in range(n)], []), 2)
t('fbnt', 'FBEQ.W not taken', all_regs('c1p2345', 'c1p1') + ['\tfcmp.x\tfp7,fp0'],
  lambda n: sum([['\tfbeq.w\t.b%d' % i, '.b%d:' % i] for i in range(n)], []))
t('fbt', 'FBNE.W taken (to next insn)', all_regs('c1p2345', 'c1p1') + ['\tfcmp.x\tfp7,fp0'],
  lambda n: sum([['\tfbne.w\t.b%d' % i, '.b%d:' % i] for i in range(n)], []))
t('add_i', 'ADD.L D0,Dn  (integer only)', ['\tmoveq\t#3,d0'], lambda n: ['\tadd.l\td0,d%d' % (1 + i % 5) for i in range(n)])
t('mulint1', 'FMUL.X FP7,FPn + 1 ADD.L (pair)', all_regs('c1p2345', 'cmul') + ['\tmoveq\t#3,d0'],
  lambda n: sum([['\tfmul.x\tfp7,fp%d' % r7(i), '\tadd.l\td0,d1'] for i in range(n)], []), 2)
t('mulint1d', 'FMUL.X FP7,FP0 dep + 1 ADD.L (pair)', all_regs('c1p2345', 'cmul') + ['\tmoveq\t#3,d0'],
  lambda n: sum([['\tfmul.x\tfp7,fp0', '\tadd.l\td0,d1'] for i in range(n)], []), 2)
t('mulint4', 'FMUL.X FP7,FPn + 4 ADD.L (group)', all_regs('c1p2345', 'cmul') + ['\tmoveq\t#3,d0'],
  lambda n: sum([['\tfmul.x\tfp7,fp%d' % r7(i), '\tadd.l\td0,d1', '\tadd.l\td0,d2', '\tadd.l\td0,d3', '\tadd.l\td0,d4'] for i in range(n)], []), 5)
t('mulint8', 'FMUL.X FP7,FPn + 8 ADD.L (group)', all_regs('c1p2345', 'cmul') + ['\tmoveq\t#3,d0'],
  lambda n: sum([['\tfmul.x\tfp7,fp%d' % r7(i)] + ['\tadd.l\td0,d%d' % (1 + k % 5) for k in range(8)] for i in range(n)], []), 9)
t('divint8', 'FDIV.X FP7,FPn + 8 ADD.L (group)', all_regs('c1234', 'c1p01') + ['\tmoveq\t#3,d0'],
  lambda n: sum([['\tfdiv.x\tfp7,fp%d' % r7(i)] + ['\tadd.l\td0,d%d' % (1 + k % 5) for k in range(8)] for i in range(n)], []), 9)
t('divint24', 'FDIV.X FP7,FPn + 24 ADD.L (group)', all_regs('c1234', 'c1p01') + ['\tmoveq\t#3,d0'],
  lambda n: sum([['\tfdiv.x\tfp7,fp%d' % r7(i)] + ['\tadd.l\td0,d%d' % (1 + k % 5) for k in range(24)] for i in range(n)], []), 25)
# ---- Speedometer Matrix / FFT shapes (added 2026-09-28 afternoon)
r8 = lambda i: i % 8
t('flds16_i', 'FMOVE.S d16(A0),FPn', A0_SDAT, lambda n: ['\tfmove.s\t8(a0),fp%d' % r8(i) for i in range(n)])
t('fldsx_i', 'FMOVE.S d8(A0,D0.L),FPn', A0_SDAT + ['\tmoveq\t#4,d0'], lambda n: ['\tfmove.s\t8(a0,d0.l),fp%d' % r8(i) for i in range(n)])
t('flds0_i', 'FMOVE.S (A0),FPn', A0_SDAT, lambda n: ['\tfmove.s\t(a0),fp%d' % r8(i) for i in range(n)])
t('fsts16_i', 'FMOVE.S FPn,d16(A0)', all_regs('c1000', 'c1p1') + A0_BUF, lambda n: ['\tfmove.s\tfp%d,8(a0)' % r8(i) for i in range(n)])
t('ldmul', 'FMOVE.S d16(A0),FP0 ; FMUL.X FP0,FP1 (pair)', all_regs('c1p2345') + A0_SDAT,
  lambda n: ['\tfmove.s\t8(a0),fp0', '\tfmul.x\tfp0,fp1'] * n, 2)
t('mulst', 'FMUL.X FP1,FP2 ; FMOVE.S FP2,d16(A0) (pair)', all_regs('c1p2345', 'cmul') + ['\tfmove.x\t(cmul).l,fp1'] + A0_BUF,
  lambda n: ['\tfmul.x\tfp1,fp2', '\tfmove.s\tfp2,8(a0)'] * n, 2)
t('matrix', 'Matrix: FMOVE.S 0(A0,D0.L),FP0; FMUL.X FP1,FP0; FADD.X FP0,FP2; ADDQ.L #4,D0 (group)',
  all_regs('c1p2345') + A0_SDAT + ['\tmoveq\t#0,d0'],
  lambda n: ['\tfmove.s\t0(a0,d0.l),fp0', '\tfmul.x\tfp1,fp0', '\tfadd.x\tfp0,fp2', '\taddq.l\t#4,d0'] * n, 4)
t('fft', 'FFT: 2x FMOVE.S d16(A0),FPn; FSUB.X; FMUL.X; FADD.X; 2x FMOVE.S FPn,d16(A0) (group)',
  all_regs('c1p2345', 'c0p7071') + ['\tfmove.x\t(c0p7071).l,fp3'] + A0_FDAT,
  lambda n: ['\tfmove.s\t16(a0),fp0', '\tfmove.s\t20(a0),fp1', '\tfsub.x\tfp1,fp0', '\tfmul.x\tfp3,fp0',
             '\tfadd.x\tfp0,fp1', '\tfmove.s\tfp0,24(a0)', '\tfmove.s\tfp1,28(a0)'] * n, 7)
t('fldd16_i', 'FMOVE.D d16(A0),FPn', A0_TAB, lambda n: ['\tfmove.d\t8(a0),fp%d' % r8(i) for i in range(n)])
t('fstd16_i', 'FMOVE.D FPn,d16(A0)', all_regs('c1000', 'c1p1') + A0_BUF, lambda n: ['\tfmove.d\tfp%d,8(a0)' % r8(i) for i in range(n)])
# ---- FSAVE / FRESTORE pairs (added for the trap traces)
t('fsnull', 'FSAVE -(A7) ; FRESTORE (A7)+, NULL frame (pair)', ['\tclr.l\t-(a7)', '\tfrestore\t(a7)+'],
  lambda n: ['\tfsave\t-(a7)', '\tfrestore\t(a7)+'] * n, 2)
t('fsidle', 'FSAVE -(A7) ; FRESTORE (A7)+, IDLE frame after FMOVE (pair)', all_regs('c1p2345') + ['\tfmove.x\tfp0,fp1'],
  lambda n: ['\tfsave\t-(a7)', '\tfrestore\t(a7)+'] * n, 2)
# traps: one exception per copy, checked from the bench's S_EXC0 count
SETV = lambda vec, h: ['\tmove.l\t#%s,(%d).w' % (h, vec * 4)]
t('fintrz_rte', 'FINTRZ.X FP1,FP0 -> vec 11, handler RTE', all_regs('c1p2345') + SETV(11, 'h_rte'),
  lambda n: ['\tfintrz.x\tfp1,fp0'] * n)
t('fintrz_fs', 'FINTRZ.X FP1,FP0 -> vec 11, handler FSAVE/FRESTORE/RTE', all_regs('c1p2345') + SETV(11, 'h_fsave'),
  lambda n: ['\tfintrz.x\tfp1,fp0'] * n)
t('fmovecr_rte', 'FMOVECR #0,FP0 -> vec 11, handler RTE', all_regs('c1p2345') + SETV(11, 'h_rte'),
  lambda n: ['\tfmovecr.x\t#0,fp0'] * n)
t('fmovecr_fs', 'FMOVECR #0,FP0 -> vec 11, handler FSAVE/FRESTORE/RTE', all_regs('c1p2345') + SETV(11, 'h_fsave'),
  lambda n: ['\tfmovecr.x\t#0,fp0'] * n)
t('trap', 'TRAP #0 -> handler RTE', SETV(32, 'h_rte'), lambda n: ['\ttrap\t#0'] * n)
t('aline', 'A-line $A000 -> handler ADDQ.L #2,2(SP); RTE', SETV(10, 'h_aline'), lambda n: ['\tdc.w\t$a000'] * n)
t('nop_rte', 'handler-only reference: BSR to RTS (not a trap)', ['\tbra.w\t.skip', '.rts:\trts', '.skip:'], lambda n: ['\tbsr.w\t.rts'] * n)

EXPECT_EXC = {'fintrz_rte': 11, 'fintrz_fs': 11, 'fmovecr_rte': 11, 'fmovecr_fs': 11, 'trap': 32, 'aline': 10}

# ---------------------------------------------------------------- program
def gen(path):
    L = []
    a = L.append
    a('; generated by fpu_latency.py -- do not edit; see README.md')
    a('STAMP\tequ\t$F108')
    a('DONE\tequ\t$F102')
    a('\torg\t0')
    a('\tdc.l\t$3F000,start')
    a('\trept\t254')
    a('\tdc.l\tfailh')
    a('\tendr')
    a('\torg\t$10000\t; code; $F100-$F10F are the bench registers')
    a('start:')
    a('\tmove.w\t#$2700,sr')
    a('\tmove.l\t#$80008000,d0\t; I and D caches on')
    a('\tmovec\td0,cacr')
    a('\tcinva\tbc')
    a('\tfmove.l\t#0,fpcr')
    tags = {}
    tag = 16
    blocks = [('base', 'empty block', [], lambda n: [], 1)] + T
    for key, label, setup, body, per in blocks:
        for n in ((0,) if key == 'base' else (16, 32, 64)):
            tags[tag] = (key, n)
            lbl = 'T%d' % tag
            a('; ---- %s  n=%d  (%s)' % (key, n, label))
            a('\tmoveq\t#1,d7\t; two passes, second is reported')
            a(lbl + ':')
            L.extend(setup)
            a('\tfnop')
            a('\tnop')
            a('\tmove.w\t#1,(STAMP).l')
            for line in body(n):
                a(line)   # local .labels are scoped by the block's T label
            a('\tfnop')
            a('\tmove.w\t#%d,(STAMP).l' % tag)
            a('\tdbra\td7,%s' % lbl)
            tag += 1
    a('\tmove.w\t#$600d,(DONE).l')
    a('\tbra.s\t*')
    a('h_rte:\trte')
    a('h_fsave:')
    a('\tfsave\t-(sp)')
    a('\tfrestore\t(sp)+')
    a('\trte')
    a('h_aline:')
    a('\taddq.l\t#2,2(sp)')
    a('\trte')
    a('failh:\tmove.w\t#$bad0,(DONE).l')
    a('\tbra.s\t*')
    a('\torg\t$38000\t; data')
    for name, lw in CONSTS.items():
        a('%s:\tdc.l\t$%08x,$%08x,$%08x' % ((name,) + tuple(lw)))
    a('mx:\tdc.l\t$%08x,$%08x,$%08x' % xbits(1.0000123))
    a('md:\tdc.l\t$%08x,$%08x' % DOUBLE)
    a('ms:\tdc.l\t$%08x' % SINGLE)
    a('\tcnop\t0,16')
    a('dtab:')
    for i in range(64):
        a('\tdc.l\t$%08x,$%08x' % struct.unpack('>2L', struct.pack('>d', 1.1)))
    a('\tcnop\t0,16')
    a('sbuf:\tds.b\t64')
    a('\tcnop\t0,16')
    a('sdat:')
    for i in range(80):
        a('\tdc.l\t$%08x' % struct.unpack('>L', struct.pack('>f', 1.1 + 0.01 * i))[0])
    a('\tcnop\t0,16')
    a('fdat:')
    for v in (1.0, 1.0, 1.0, 1.0, 1.5, 1.25, 0.0, 0.0):
        a('\tdc.l\t$%08x' % struct.unpack('>L', struct.pack('>f', v))[0])
    path.write_text('\n'.join(L) + '\n')
    return tags

def assemble(src, out):
    binf = out / 'fpu_latency.bin'
    r = subprocess.run([VASM, '-Fbin', '-m68040', '-no-opt', '-L', str(out / 'fpu_latency.lst'), '-o', str(binf), str(src)],
                       capture_output=True, text=True)
    if r.returncode: sys.exit(r.stdout + r.stderr)
    data = binf.read_bytes()
    # program text runs from $10000 and must stay below the data at $38000
    m = re.search(r'org\d+:10000\(\S+\):\s+(\d+) bytes', r.stdout)
    if not m or 0x10000 + int(m.group(1)) > 0x38000: sys.exit('program text overlaps the data:\n' + r.stdout)
    with open(out / 'fpu_latency.hex', 'w') as f:
        d = data + (b'\0' if len(data) % 2 else b'')
        for i in range(0, len(d), 2):
            f.write('%02x%02x\n' % (d[i], d[i + 1]))
    return data

def build(out, rev):
    """Build from git revision `rev` (exported with git show into out/src, so
    edits other sessions make to the working tree cannot leak into the
    measurement), or from the working tree when rev is None."""
    rels = ['rtl/wombat_cpu.sv', 'rtl/wombat_store_buffer.sv', 'rtl/ap68040/experimental/ap040_pipeline_integer.sv'] + \
           ['rtl/ap68040/rtl/%s.v' % u for u in ('ap040_core', 'ap040_bus_timeout', 'ap040_regfile', 'ap040_alu', 'ap040_muldiv',
                                                   'ap040_mmu', 'ap040_cache', 'ap040_fpu', 'primitives/dpram')]
    incs = ['rtl/ap68040/rtl/ap040_defs.svh']
    if rev is None:
        base = ROOT
    else:
        base = out / 'src'
        subprocess.run(['rm', '-rf', str(base)])
        for rel in rels + incs:
            dst = base / rel
            dst.parent.mkdir(parents=True, exist_ok=True)
            dst.write_bytes(subprocess.run(['git', '-C', str(ROOT), 'show', '%s:%s' % (rev, rel)],
                                           capture_output=True, check=True).stdout)
    rtl = base / 'rtl/ap68040/rtl'
    srcs = [HERE / 'tb_fpu_latency.sv'] + [base / r for r in rels]
    cmd = [VERILATOR, '--binary', '--timing', '-Wno-fatal', '-Wno-BLKLOOPINIT', '-j', '8', '--top-module', 'tb_fpu_latency',
           '--Mdir', str(out / 'obj'), '-I' + str(rtl)] + FLAGS + [str(s) for s in srcs]
    with open(out / 'compile.log', 'w') as f:
        r = subprocess.run(cmd, stdout=f, stderr=subprocess.STDOUT)
    if r.returncode: sys.exit('verilator failed, see %s' % (out / 'compile.log'))

def run(out, latency):
    r = subprocess.run([str(out / 'obj/Vtb_fpu_latency'), '+prog=' + str(out / 'fpu_latency.hex'), '+latency=%d' % latency],
                       capture_output=True, text=True)
    (out / ('run_lat%d.log' % latency)).write_text(r.stdout + r.stderr)
    if 'DONE' not in r.stdout: sys.exit('run failed:\n' + (r.stdout + r.stderr)[-3000:])
    return r.stdout

def analyse(tags, log, latency):
    # A stamp line reports the clocks and exceptions since the previous
    # stamp's bus acknowledge.  The start stamp (tag 1) is a posted store, so
    # the first exception of a block can land before its acknowledge: the
    # block's exception count is the start line's plus the end line's.
    seen = {}
    bodyc = {}
    pend = 0
    for m in re.finditer(r'STAMP tag=(\d+) clocks=(\d+) exc=(\d+) vec=(\d+)|BODY tag=(\d+) clocks=(\d+)', log):
        if m.group(5):
            bodyc.setdefault(tags[int(m.group(5))], []).append(int(m.group(6))); continue
        tg, clk, exc, vec = map(int, m.groups()[:4])
        if tg == 1: pend = exc; continue
        seen.setdefault(tags[tg], []).append((clk, exc + pend, vec))
    by = {k: v[-1] for k, v in seen.items()}         # the second (warm) pass
    base = by[('base', 0)][0]
    rows, errs = [], []
    for key, label, setup, body, per in T:
        cnt = {n: len([l for l in body(n) if not l.startswith('.')]) // per for n in (16, 32, 64)}
        c = {n: by[(key, n)][0] for n in (16, 32, 64)}
        want = EXPECT_EXC.get(key)
        for n in (16, 32, 64):
            clk, e, v = by[(key, n)]
            if want is None and e: errs.append('%s n=%d: %d unexpected exceptions (vec %d)' % (key, n, e, v))
            if want is not None and (e != cnt[n] or v != want):
                errs.append('%s n=%d: %d exceptions, last vec %d; expected %d x vec %d' % (key, n, e, v, cnt[n], want))
            cold = seen[(key, n)][0][0]
            if cold != clk and n == 64: pass
        b = {n: bodyc[(key, n)][-1] for n in (16, 32, 64)}
        rows.append((key, label, c[16], c[32], c[64], seen[(key, 64)][0][0],
                     (c[32] - c[16]) / (cnt[32] - cnt[16]), (c[64] - c[32]) / (cnt[64] - cnt[32]),
                     (c[16] - base) / cnt[16], b[16], b[32], b[64], (b[64] - b[32]) / (cnt[64] - cnt[32])))
    lines = ['latency=%d  empty block=%d clocks' % (latency, base),
             '%-12s %-56s %6s %6s %6s %7s %7s %7s %7s | %6s %6s %6s %7s' % ('key', 'test', 'c16', 'c32', 'c64', 'c64cold', '32-16', '64-32', 'per16', 'b16', 'b32', 'b64', 'body')]
    for r in rows:
        lines.append('%-12s %-56s %6d %6d %6d %7d %7.2f %7.2f %7.2f | %6d %6d %6d %7.2f' % r)
    lines += ['ERROR ' + e for e in errs]
    return '\n'.join(lines)

def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('cmd', choices=['gen', 'run'])
    ap.add_argument('--out', type=Path, default=ROOT / 'scratch/fpu_latency_20260928')
    ap.add_argument('--latency', type=int, nargs='+', default=[3, 1])
    ap.add_argument('--keep-obj', action='store_true')
    ap.add_argument('--rev', default='HEAD', help='git revision whose RTL is measured (default HEAD)')
    ap.add_argument('--worktree', action='store_true', help='measure the working-tree RTL instead of --rev')
    a = ap.parse_args()
    src = HERE / 'fpu_latency.s'
    tags = gen(src)
    if a.cmd == 'gen': return
    out = a.out.resolve(); out.mkdir(parents=True, exist_ok=True)
    assemble(src, out)
    rev = None
    if not a.worktree:
        rev = subprocess.run(['git', '-C', str(ROOT), 'rev-parse', '--short', a.rev], capture_output=True, text=True, check=True).stdout.strip()
    build(out, rev)
    what = 'rtl=%s' % (rev if rev else 'working tree')
    for lat in a.latency:
        res = what + '  ' + analyse(tags, run(out, lat), lat)
        (out / ('results_lat%d.txt' % lat)).write_text(res + '\n')
        print(res)
    if not a.keep_obj:
        subprocess.run(['rm', '-rf', str(out / 'obj'), str(out / 'src')])

if __name__ == '__main__':
    main()
