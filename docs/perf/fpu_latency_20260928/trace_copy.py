#!/usr/bin/env python3
"""Clock-by-clock trace of ONE steady-state copy of a harness row.

Needs a build kept with  run.sh --rev <c> --out <dir> --keep-obj.  Picks copy
number --copy (default 8) of the row's 64-copy block in the second (warm)
pass, finds the clocks where the decode PC reaches that copy and the next
one, re-runs the bench with +tracec0/+tracec1 over exactly that span and
prints run-length groups of (decode PC, core state): the instruction at that
PC from the listing, core and FPU states, and the core-side memory requests
issued in the group (I = instruction fetch, R/W = data read/write, with the
data for writes, and the address as an offset from the stack pointer at the copy's start, $3F000, when
it is within 256 bytes of it).

  trace_copy.py <out dir> <rev> <row key> [--latency 3] [--copy 8]
"""
import argparse, re, subprocess, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SP = 0x3F000

def states(rev):
    core = subprocess.run(['git', '-C', str(ROOT), 'show', rev + ':rtl/ap68040/rtl/ap040_core.v'], capture_output=True, text=True, check=True).stdout
    fpu = subprocess.run(['git', '-C', str(ROOT), 'show', rev + ':rtl/ap68040/rtl/ap040_fpu.v'], capture_output=True, text=True, check=True).stdout
    S = {int(n): k for k, n in re.findall(r"localparam\s+(S_\w+)\s*=\s*8'd(\d+)", core)}
    F = {int(n): k for k, n in re.findall(r"localparam\s+(F_\w+)\s*=\s*\d+'d(\d+)", fpu)}
    return S, F

def listing(out):
    """pc -> source text, and per block key the body instruction addresses"""
    text, blocks, cur, inbody = {}, {}, None, False
    for line in (out / 'fpu_latency.lst').read_text(errors='replace').splitlines():
        m = re.match(r'\s*\d+:([0-9A-F]{8}) [0-9A-F]+\s+\d+: \t?(.*)$', line)
        h = re.search(r'; ---- (\w+)\s+n=(\d+)', line)
        if h:
            cur = (h.group(1), int(h.group(2))); blocks[cur] = []; inbody = False; continue
        if not m: continue
        pc, src = int(m.group(1), 16), ' '.join(m.group(2).split())
        text.setdefault(pc, src)
        if cur is None: continue
        if src.startswith('move.w #1,(STAMP)'): inbody = True; continue
        if inbody and src.startswith('fnop'): inbody = False; cur = None; continue
        if inbody: blocks[cur].append(pc)
    return text, blocks

def sim(out, latency, *args):
    r = subprocess.run([str(out / 'obj/Vtb_fpu_latency'), '+prog=' + str(out / 'fpu_latency.hex'), '+latency=%d' % latency] + list(args),
                       capture_output=True, text=True)
    return [l for l in r.stdout.splitlines() if l.startswith('TRACE')]

def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('out', type=Path); ap.add_argument('rev'); ap.add_argument('key')
    ap.add_argument('--latency', type=int, default=3); ap.add_argument('--copy', type=int, default=8)
    ap.add_argument('--per', type=int, default=1, help='instructions per copy (2 for pair rows)')
    a = ap.parse_args()
    S, F = states(a.rev)
    text, blocks = listing(a.out)
    body = blocks[(a.key, 64)]
    k0, k1 = body[a.copy * a.per], body[(a.copy + 1) * a.per]
    lo, hi = min(k0, k1), max(k0, k1) + 1
    pcs = [(int(re.search(r'cyc=(\d+)', l).group(1)), int(re.search(r'pc=(\w+)', l).group(1), 16))
           for l in sim(a.out, a.latency, '+tracelo=%x' % lo, '+tracehi=%x' % hi)]
    starts = [c for c, p in pcs if p == k0]
    c0 = starts[-1]
    c1 = min(c for c, p in pcs if p == k1 and c > c0)
    groups = []
    for l in sim(a.out, a.latency, '+tracec0=%d' % c0, '+tracec1=%d' % (c1 - 1)):
        d = dict(re.findall(r'(\w+)=(\w+)', l))
        pc, st, fs = int(d['pc'], 16), S.get(int(d['state']), d['state']), F.get(int(d['fpu_st']), d['fpu_st'])
        mem = ''
        if d['req'] == '1':
            addr = int(d['addr'], 16)
            kind = 'I' if d['instr'] == '1' else ('W' if d['wr'] == '1' else 'R')
            where = ('SP%+d' % (addr - SP)) if kind != 'I' and abs(addr - SP) < 256 else '%x' % addr
            mem = kind + ' ' + where + ((' =%s' % d['wdata']) if kind == 'W' else '') + ('*' if d['ack'] == '1' else '')
        key = (pc, st)
        if groups and groups[-1][0] == key:
            g = groups[-1]; g[1] += 1; g[2].add(fs)
            if mem and (not g[3] or g[3][-1] != mem.rstrip('*')): g[3].append(mem.rstrip('*'))
        else:
            groups.append([key, 1, {fs}, [mem.rstrip('*')] if mem else []])
    print('row %s rev %s latency %d: copy %d, clocks %d..%d = %d clocks' % (a.key, a.rev, a.latency, a.copy, c0, c1 - 1, c1 - c0))
    print('| clocks | decode PC: instruction | core state | FPU | memory requests |')
    print('|---:|---|---|---|---|')
    for (pc, st), n, fs, mem in groups:
        kind = 'data' if st in ('S_MRD', 'S_MWR') else ('ifetch' if st in ('S_EPF_FILL', 'S_FETCH') and mem else '')
        print('| %d | %x: %s | %s%s | %s | %s |' % (n, pc, text.get(pc, '?'), st, ' (%s wait)' % kind if kind else '',
                                                   ','.join(sorted(fs)), '; '.join(mem)))
    # phase summary: data-memory states (S_MRD/S_MWR), instruction-fetch
    # waits (S_EPF_FILL, or S_FETCH with a fetch outstanding) and the rest
    phases, entered = [], False
    for (pc, st), n, fs, mem in groups:
        if pc in (k0,) + tuple(body[a.copy * a.per:(a.copy + 1) * a.per]):
            if st.startswith('S_EXC') or entered and st in ('S_MRD', 'S_MWR'):
                entered = True; ph = 'exception entry'
            elif st == 'S_FETCH' and mem: ph = 'refetch after previous copy'
            else: ph = 'instruction: ' + text.get(pc, '?')
        elif st.startswith('S_EPF'): ph = 'handler prefetch fill'
        else: ph = 'handler: ' + text.get(pc, '?').split(':')[-1].strip()
        kind = 'data' if st in ('S_MRD', 'S_MWR') else ('ifetch' if st in ('S_EPF_FILL', 'S_FETCH') and mem else 'internal')
        if not phases or phases[-1][0] != ph: phases.append([ph, {'data': 0, 'ifetch': 0, 'internal': 0}])
        phases[-1][1][kind] += n
    print()
    print('| phase | clocks | data-memory wait (S_MRD/S_MWR) | instruction-fetch wait | internal sequencing |')
    print('|---|---:|---:|---:|---:|')
    tot = {'data': 0, 'ifetch': 0, 'internal': 0}
    for ph, k in phases:
        for x in tot: tot[x] += k[x]
        print('| %s | %d | %d | %d | %d |' % (ph, sum(k.values()), k['data'], k['ifetch'], k['internal']))
    print('| **total** | **%d** | %d | %d | %d |' % (sum(tot.values()), tot['data'], tot['ifetch'], tot['internal']))

if __name__ == '__main__':
    main()
