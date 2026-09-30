#!/usr/bin/env python3
"""Summarise fpu_window_monitor segment dumps into per-window breakdowns.

usage:
  analyze.py fwm.txt --timeline                 # list marker traps + FP activity
  analyze.py fwm.txt --window NAME:SEGA:SEGB ... [--json out.json] [--md out.md]

A window NAME:A:B covers segments A .. B-1, i.e. from the start of segment A
(a marker-trap cycle) to the start of segment B (the next marker-trap cycle).
"""
import argparse, collections, json, re, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
CORE = HERE / 'tree/rtl/ap68040/rtl/ap040_core.v'

OPM = {0x00:'FMOVE',0x01:'FINT',0x02:'FSINH',0x03:'FINTRZ',0x04:'FSQRT',0x06:'FLOGNP1',
 0x08:'FETOXM1',0x09:'FTANH',0x0A:'FATAN',0x0C:'FASIN',0x0D:'FATANH',0x0E:'FSIN',0x0F:'FTAN',
 0x10:'FETOX',0x11:'FTWOTOX',0x12:'FTENTOX',0x14:'FLOGN',0x15:'FLOG10',0x16:'FLOG2',0x18:'FABS',
 0x19:'FCOSH',0x1A:'FNEG',0x1C:'FACOS',0x1D:'FCOS',0x1E:'FGETEXP',0x1F:'FGETMAN',0x20:'FDIV',
 0x21:'FMOD',0x22:'FADD',0x23:'FMUL',0x24:'FSGLDIV',0x25:'FREM',0x26:'FSCALE',0x27:'FSGLMUL',
 0x28:'FSUB',0x38:'FCMP',0x3A:'FTST',0x40:'FSMOVE',0x41:'FSSQRT',0x44:'FDMOVE',0x45:'FDSQRT',
 0x58:'FSABS',0x5A:'FSNEG',0x5C:'FDABS',0x5E:'FDNEG',0x60:'FSDIV',0x62:'FSADD',0x63:'FSMUL',
 0x64:'FDDIV',0x66:'FDADD',0x67:'FDMUL',0x68:'FSSUB',0x6C:'FDSUB'}
for i in range(0x30, 0x38): OPM[i] = 'FSINCOS'
FMT = ['L','S','X','P','W','D','B','?']
FST = {0:'F_IDLE',1:'F_SRC',2:'F_NORM',3:'F_EXEC',4:'F_WB',5:'F_SHR',6:'F_PACKI',7:'F_BIN',
 9:'F_ADDX',10:'F_MULT',11:'F_DIVL',12:'F_SQRTL',13:'F_NORM2',14:'F_ROUND',15:'F_PACKS',
 16:'F_UNFL',17:'F_STDONE',18:'F_RESTORE_A',19:'F_RESTORE_B',20:'F_RESTORE_N'}
CST = {0:'C_IDLE',1:'C_LOOK',2:'C_FERR',3:'C_WINV',4:'C_FILL',5:'C_TAGW',6:'C_PASS',7:'C_SWEEP',
 8:'C_XSTORE_LOOK',9:'C_XSTORE_WRITE'}
VEC = {2:'bus error',3:'address error',4:'illegal',9:'trace',10:'A-line',11:'F-line / FP unimplemented instr.',
 24:'spurious',25:'autovector L1 (VIA1)',26:'autovector L2 (VIA2/slot)',27:'L3',28:'L4 (SCC)',
 29:'L5',30:'L6',31:'L7 NMI',48:'FP BSUN',49:'FP INEX',50:'FP DZ',51:'FP UNFL',52:'FP OPERR',
 53:'FP OVFL',54:'FP SNAN',55:'FP unsupported data type'}
ALINE = {0xA193:'Microseconds',0xA975:'TickCount',0xA058:'InsTime',0xA458:'InsXTime',
 0xA05A:'PrimeTime',0xA059:'RmvTime'}


def core_source():
    if CORE.exists():
        return CORE.read_text()
    import subprocess  # docs copy: read the measured commit's core from git
    return subprocess.check_output(['git', '-C', str(HERE), 'show',
                                    '0b2d265:rtl/ap68040/rtl/ap040_core.v'], text=True)


def state_names():
    names = {}
    for m in re.finditer(r'localparam\s+(S_[A-Z0-9_]+)\s*=\s*8\'d(\d+)', core_source()):
        names[int(m.group(2))] = m.group(1)
    return names

SN = state_names()


def ea_str(ir):
    mode, reg = (ir >> 3) & 7, ir & 7
    if mode == 0: return 'Dn'
    if mode == 1: return 'An'
    if mode == 2: return '(An)'
    if mode == 3: return '(An)+'
    if mode == 4: return '-(An)'
    if mode == 5: return 'd16(An)'
    if mode == 6: return 'd8(An,Xn)'
    return {0:'abs.W',1:'abs.L',2:'d16(PC)',3:'d8(PC,Xn)',4:'#imm'}.get(reg, 'mode7?')


def fp_form(key):
    ir, cmd = key >> 16, key & 0xFFFF
    cls, fmt, opm = cmd >> 13, (cmd >> 10) & 7, cmd & 0x7F
    ea = ea_str(ir)
    if cls == 0: return f'{OPM.get(opm, "op%02X" % opm)} FPm,FPn'
    if cls == 2:
        if fmt == 7: return 'FMOVECR #rom,FPn'
        return f'{OPM.get(opm, "op%02X" % opm)}.{FMT[fmt]} {ea},FPn'
    if cls == 3: return f'FMOVE.{FMT[fmt]} FPn,{ea}'
    if cls == 4: return f'FMOVE(M) {ea},FPcr'
    if cls == 5: return f'FMOVE(M) FPcr,{ea}'
    if cls == 6: return f'FMOVEM {ea},FPlist'
    if cls == 7: return f'FMOVEM FPlist,{ea}'
    return f'class{cls}?'


def fp_class(key):
    cmd = key & 0xFFFF
    cls, fmt, opm = cmd >> 13, (cmd >> 10) & 7, cmd & 0x7F
    if cls == 0: return ('reg', OPM.get(opm, 'op%02X' % opm))
    if cls == 2: return (('#cr' if fmt == 7 else FMT[fmt]), ('FMOVECR' if fmt == 7 else OPM.get(opm, 'op%02X' % opm)))
    if cls == 3: return ('store.' + FMT[fmt], 'FMOVE out')
    return ('ctl/multi', {4:'FMOVE ea->cr',5:'FMOVE cr->ea',6:'FMOVEM ea->FP',7:'FMOVEM FP->ea'}[cls])


def parse(path):
    segs = []
    cur = None
    with open(path) as f:
        for line in f:
            if line.startswith('SEG\t'):
                p = line.rstrip('\n').split('\t')
                cur = dict(idx=int(p[1]), start=int(p[2]), end=int(p[3]), reason=p[4],
                           op=int(p[5], 16), pc=int(p[6], 16), a7=int(p[7], 16), c={})
            elif line.startswith('END'):
                segs.append(cur); cur = None
            elif cur is not None:
                k, v = line.rstrip('\n').split('\t')
                cur['c'][k] = int(v)
    return segs


def total(segs):
    t = collections.Counter()
    for s in segs: t.update(s['c'])
    return t


def pick(t, prefix):
    out = {}
    for k, v in t.items():
        if k.startswith(prefix + ':'):
            out[k[len(prefix) + 1:]] = v
    return out


def timeline(segs):
    print('seg\tstart\tlen\treason\ttrap\tpc\tfp_entries\tfst_busy\tdispatches')
    for s in segs:
        c = s['c']
        busy = c.get('cycles', 0) - c.get('fst:0', 0)
        if s['reason'] in 'TBE' or c.get('fp_entries', 0):
            print(f"{s['idx']}\t{s['start']}\t{s['end']-s['start']}\t{s['reason']}\t"
                  f"{ALINE.get(s['op'], '%04X' % s['op'])}\t{s['pc']:08X}\t{c.get('fp_entries',0)}\t{busy}\t{c.get('dispatches',0)}")


def pct(a, b):
    return f'{100.0*a/b:.2f}%' if b else '-'


def summarize(name, segs):
    t = total(segs)
    cyc = t['cycles']
    r = collections.OrderedDict()
    r['name'] = name
    r['segments'] = [segs[0]['idx'], segs[-1]['idx'] + 1]
    r['start_cycle'] = segs[0]['start']; r['end_cycle'] = segs[-1]['end']
    r['start_trap'] = ALINE.get(segs[0]['op'], '%04X' % segs[0]['op']); r['start_pc'] = '%08X' % segs[0]['pc']
    r['cycles'] = cyc
    assert cyc == r['end_cycle'] - r['start_cycle'], (cyc, r['end_cycle'] - r['start_cycle'])
    r['seconds_at_32.90112MHz'] = cyc / 32901120.0
    r['dispatches'] = t['dispatches']
    st = {int(k): v for k, v in pick(t, 'st').items()}
    fst = {int(k): v for k, v in pick(t, 'fst').items()}
    r['fpu_not_idle'] = cyc - fst.get(0, 0)
    r['fst'] = {FST.get(k, str(k)): v for k, v in sorted(fst.items()) if k}
    r['fpdec_cycles'] = st.get(153, 0)
    r['fpdec_wait_bg'] = t['fpdec_wait_bg']
    r['fp_waited_instrs'] = t['fp_waited']
    r['fpu_bg_cycles'] = t['fpu_bg_cycles']
    r['fpu_busy_while_bg'] = t['fpu_busy_bg']
    r['fpcc_wait_bg'] = t['fpcc_wait_bg']; r['fsave_wait_bg'] = t['fsave_wait_bg']; r['exc0_wait_bg'] = t['exc0_wait_bg']
    mrd = {int(k): v for k, v in pick(t, 'mrd_ret').items()}
    mwr = {int(k): v for k, v in pick(t, 'mwr_ret').items()}
    r['fp_read_states'] = {'S_FPU_RD': st.get(158, 0), 'S_FPU_RD2': st.get(159, 0), 'S_FPU_IMM': st.get(157, 0),
                           'S_FPU_EA': st.get(155, 0), 'S_FPU_AN': st.get(154, 0), 'S_FPU_DREG': st.get(156, 0),
                           'S_MRD->S_FPU_RD': mrd.get(158, 0), 'S_MRD->S_FPU_RD2': mrd.get(159, 0)}
    r['fp_store_states'] = {'S_FPU_WR': st.get(161, 0), 'S_MWR->S_FPU_WR': mwr.get(161, 0)}
    r['fp_go'] = st.get(160, 0)
    r['fp_other_states'] = {SN.get(k, str(k)): st.get(k, 0) for k in list(range(162, 174)) + [177] if st.get(k, 0)}
    # FP instructions
    forms = {int(k, 16): v for k, v in pick(t, 'fpf').items()}
    fcyc = {int(k, 16): v for k, v in pick(t, 'fpc').items()}
    r['fp_instructions'] = t['fp_entries']
    r['cpgen_dispatch'] = t['cpgen_dispatch']
    r['fbcc_dispatch'] = t['fbcc_dispatch']; r['fscc_dispatch'] = t['fscc_dispatch']
    r['fsave_dispatch'] = t['fsave_dispatch']; r['frestore_dispatch'] = t['frestore_dispatch']
    by_op = collections.Counter(); by_fmt = collections.Counter(); by_opfmt = collections.Counter()
    for k, v in forms.items():
        fmt, op = fp_class(k)
        by_op[op] += v; by_fmt[fmt] += v; by_opfmt[(op, fmt)] += v
    r['fp_by_opmode'] = dict(by_op.most_common())
    r['fp_by_source'] = dict(by_fmt.most_common())
    r['fp_by_opmode_source'] = {f'{a} / {b}': v for (a, b), v in by_opfmt.most_common()}
    agg = collections.Counter(); aggc = collections.Counter()
    for k, v in forms.items():
        agg[fp_form(k)] += v; aggc[fp_form(k)] += fcyc.get(k, 0)
    r['fp_top_forms'] = [(f, n, aggc[f]) for f, n in agg.most_common(15)]
    r['fp_form_cpu_cycles_total'] = sum(fcyc.values())
    # exceptions
    exc = {int(k): v for k, v in pick(t, 'exc').items()}
    exm = {int(k): v for k, v in pick(t, 'exc_matched').items()}
    exd = {int(k): v for k, v in pick(t, 'exc_dur').items()}
    exa = {int(k): v for k, v in pick(t, 'exc_abandoned').items()}
    r['exceptions'] = {f'{k} {VEC.get(k, "")}'.strip(): dict(count=v, rte_matched=exm.get(k, 0),
                        entry_to_rte_cycles=exd.get(k, 0), abandoned=exa.get(k, 0))
                       for k, v in sorted(exc.items())}
    exk = {int(k, 16): v for k, v in pick(t, 'exk').items()}
    exkd = {int(k, 16): v for k, v in pick(t, 'exkd').items()}
    exkm = {int(k, 16): v for k, v in pick(t, 'exkm').items()}
    det = []
    for k, v in sorted(exk.items(), key=lambda kv: -kv[1]):
        vec, w = k >> 16, k & 0xFFFF
        if vec in (11, 55):
            cls, fmt, opm = w >> 13, (w >> 10) & 7, w & 0x7F
            lab = f'vec{vec} {OPM.get(opm, "op%02X" % opm)}' + (f'.{FMT[fmt]}' if cls == 2 else (' FPm,FPn' if cls == 0 else f' cls{cls}'))
        elif vec == 10:
            lab = f'A-line {w:04X}'
        else:
            lab = f'vec{vec}'
        det.append((lab, v, exkm.get(k, 0), exkd.get(k, 0)))
    agg_det = collections.OrderedDict()
    for lab, v, m, d in det:
        a = agg_det.setdefault(lab, [0, 0, 0]); a[0] += v; a[1] += m; a[2] += d
    r['exception_detail'] = [(k, *v) for k, v in sorted(agg_det.items(), key=lambda kv: -kv[1][0])][:25]
    r['exc_stack_drops'] = t['exc_stack_drops']
    r['rte_count'] = t['rte_count']; r['rte_unmatched'] = t['rte_unmatched']
    r['aline'] = {f'{int(k,16):04X} {ALINE.get(int(k,16), "")}'.strip(): v
                  for k, v in sorted(pick(t, 'al').items(), key=lambda kv: -kv[1])[:20]}
    # cache
    cst = collections.Counter()
    for k, v in pick(t, 'cst').items():
        c, b = map(int, k.split(':')); cst[(c, b)] += v
    r['cache_state'] = {f'{CST.get(c, c)}/{"I" if b else "D"}': v for (c, b), v in sorted(cst.items())}
    r['dcache_fill_cycles'] = cst[(4, 0)]; r['icache_fill_cycles'] = cst[(4, 1)]
    r['dcache_fills'] = t['fill_start:0']; r['icache_fills'] = t['fill_start:1']
    stc = collections.Counter()
    for k, v in pick(t, 'stc').items():
        a, c = map(int, k.split(':')); stc[(a, c)] += v
    r['fill_by_core_state'] = {SN.get(a, str(a)): v for (a, c), v in stc.most_common() if c == 4}
    # store buffer
    r['store_buffer'] = dict(nonempty=t['sb_nonempty'], full_or_blocked=t['sb_full'],
                             read_behind_store=t['read_behind_store'], pushes=t['sb_pushes'])
    # exclusive partition of every window clock by core state (memory-access
    # states S_MRD/S_MWR/_B are charged to the group of their return state)
    def grp(x):
        if x == 153: return 'FP dispatch (S_FPU_DEC)'
        if 154 <= x <= 159: return 'FP operand EA/read'
        if x == 160: return 'FP issue/wait (S_FPU_GO)'
        if x == 161: return 'FP store (S_FPU_WR)'
        if 162 <= x <= 166 or x in (172, 173, 177): return 'FP control/FMOVEM'
        if 167 <= x <= 171 or x in (151, 152) or 182 <= x <= 189: return 'FP branch/FSAVE/FRESTORE'
        if 34 <= x <= 47 or 108 <= x <= 111 or x in (174, 181) or 191 <= x <= 199: return 'exception entry/RTE'
        if x in (3, 4, 5, 8, 178, 179, 180): return 'fetch/decode/ext words'
        return 'integer execute'
    part = collections.Counter()
    for x, v in st.items():
        if x in (9, 10, 175, 176): continue
        part[grp(x)] += v
    INT = ('integer execute', 'fetch/decode/ext words')
    for x, v in mrd.items(): part[grp(x) + ' [mem read]' if grp(x) not in INT else 'integer memory read'] += v
    for x, v in mwr.items(): part[grp(x) + ' [mem write]' if grp(x) not in INT else 'integer memory write'] += v
    assert sum(part.values()) == cyc, (sum(part.values()), cyc)
    r['partition'] = dict(part.most_common())
    r['fpu_foreground_busy'] = r['fpu_not_idle'] - r['fpu_busy_while_bg']
    r['rom_pc_cycles'] = t['rom_pc_cycles']
    r['core_states_top'] = [(SN.get(k, str(k)), v) for k, v in sorted(st.items(), key=lambda kv: -kv[1])[:20]]
    r['mrd_by_return_top'] = [(SN.get(k, str(k)), v) for k, v in sorted(mrd.items(), key=lambda kv: -kv[1])[:12]]
    pcs = {int(k, 16): v for k, v in pick(t, 'pc').items()}
    r['pc_top_256B'] = [('%08X' % (k << 8), v) for k, v in sorted(pcs.items(), key=lambda kv: -kv[1])[:15]]
    ops = {int(k, 16): v for k, v in pick(t, 'op').items()}
    r['opcode_top'] = [('%04X' % k, v) for k, v in sorted(ops.items(), key=lambda kv: -kv[1])[:20]]
    return r


def md(r):
    c = r['cycles']
    L = []
    L.append(f"### {r['name']}\n")
    L.append(f"Window: segments {r['segments'][0]}..{r['segments'][1]-1}, monitor cycles "
             f"[{r['start_cycle']:,}, {r['end_cycle']:,}), opened by `{r['start_trap']}` at PC {r['start_pc']}. "
             f"**{c:,} clocks** = {r['seconds_at_32.90112MHz']:.4f} s of guest VIA time.\n")
    L.append('| quantity | clocks / count | % of window |\n|---|---:|---:|')
    row = lambda a, b: L.append(f'| {a} | {b:,} | {pct(b, c)} |')
    row('total clocks', c)
    row('FPU FSM not idle (fst != F_IDLE)', r['fpu_not_idle'])
    for k, v in r['fst'].items(): row(f'&nbsp;&nbsp;{k}', v)
    row('S_FPU_DEC total', r['fpdec_cycles'])
    row('&nbsp;&nbsp;S_FPU_DEC waiting on fpu_bg (previous FP op not retired)', r['fpdec_wait_bg'])
    row('FBcc/FScc waiting on fpu_bg', r['fpcc_wait_bg'])
    row('exception entry waiting on fpu_bg', r['exc0_wait_bg'])
    row('fpu_bg set (FP op running in background)', r['fpu_bg_cycles'])
    row('FPU busy with CPU not released (foreground: fst!=IDLE and !fpu_bg)', r['fpu_foreground_busy'])
    rd = r['fp_read_states']; wr = r['fp_store_states']
    row('FP operand read: S_FPU_RD + S_FPU_RD2', rd['S_FPU_RD'] + rd['S_FPU_RD2'])
    row('FP operand read: S_MRD with return S_FPU_RD/RD2', rd['S_MRD->S_FPU_RD'] + rd['S_MRD->S_FPU_RD2'])
    row('FP operand EA/imm states (S_FPU_AN/EA/DREG/IMM)', rd['S_FPU_AN'] + rd['S_FPU_EA'] + rd['S_FPU_DREG'] + rd['S_FPU_IMM'])
    row('S_FPU_GO (issue/wait for FPU accept or done)', r['fp_go'])
    row('FP store: S_FPU_WR', wr['S_FPU_WR'])
    row('FP store: S_MWR with return S_FPU_WR', wr['S_MWR->S_FPU_WR'])
    for k, v in r['fp_other_states'].items(): row(f'other FP core state {k}', v)
    row('D-cache C_FILL clocks', r['dcache_fill_cycles'])
    row('I-cache C_FILL clocks', r['icache_fill_cycles'])
    row('store buffer non-empty', r['store_buffer']['nonempty'])
    row('store buffer push blocked (req && !push && !ack)', r['store_buffer']['full_or_blocked'])
    row('bus read issued behind a queued store', r['store_buffer']['read_behind_store'])
    row('PC in ROM ($4xxxxxxx)', r['rom_pc_cycles'])
    L.append('')
    L.append('Exclusive partition of the window by CPU core state (S_MRD/S_MWR charged to the state that issued them):\n')
    L.append('| core activity | clocks | % |\n|---|---:|---:|')
    for k, v in r['partition'].items(): L.append(f'| {k} | {v:,} | {pct(v, c)} |')
    L.append('')
    L.append(f"Dispatches {r['dispatches']:,}; FP instructions (S_FPU_DEC entries) {r['fp_instructions']:,} "
             f"(cpGEN opcode dispatches {r['cpgen_dispatch']:,}); FBcc {r['fbcc_dispatch']:,}, FScc/FDBcc {r['fscc_dispatch']:,}, "
             f"FSAVE {r['fsave_dispatch']:,}, FRESTORE {r['frestore_dispatch']:,}. FP instructions that found the previous "
             f"op still running: {r['fp_waited_instrs']:,}. D-cache fills {r['dcache_fills']:,}, I-cache fills {r['icache_fills']:,}.\n")
    L.append('Exceptions (entry = first exception-processing state; duration to the RTE that pops the same frame, nested time included):\n')
    L.append('| vector | count | RTE-matched | entry→RTE clocks | % of window | mean |\n|---|---:|---:|---:|---:|---:|')
    for k, e in r['exceptions'].items():
        mean = e['entry_to_rte_cycles'] / e['rte_matched'] if e['rte_matched'] else 0
        L.append(f"| {k} | {e['count']:,} | {e['rte_matched']:,} | {e['entry_to_rte_cycles']:,} | {pct(e['entry_to_rte_cycles'], c)} | {mean:,.0f} |")
    L.append('')
    L.append('Exception detail (vector 11 by emulated opmode; A-line by trap word):\n')
    L.append('| kind | count | RTE-matched | entry→RTE clocks | mean |\n|---|---:|---:|---:|---:|')
    for lab, n, m, d in r['exception_detail'][:12]:
        L.append(f'| {lab} | {n:,} | {m:,} | {d:,} | {(d/m if m else 0):,.0f} |')
    L.append('')
    L.append('Top FP instruction forms (count; clocks from S_FPU_DEC entry to the next dispatch or exception):\n')
    L.append('| # | form | count | CPU clocks | clocks/instr |\n|---:|---|---:|---:|---:|')
    for i, (f, n, cc) in enumerate(r['fp_top_forms'][:10], 1):
        L.append(f'| {i} | `{f}` | {n:,} | {cc:,} | {cc/n:.1f} |')
    L.append('')
    return '\n'.join(L)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('fwm')
    ap.add_argument('--timeline', action='store_true')
    ap.add_argument('--window', action='append', default=[])
    ap.add_argument('--json'); ap.add_argument('--md')
    a = ap.parse_args()
    segs = parse(a.fwm)
    # integrity: contiguous segments
    for x, y in zip(segs, segs[1:]):
        assert x['end'] == y['start'] and y['idx'] == x['idx'] + 1, (x['idx'], y['idx'])
        assert x['c'].get('cycles', 0) == x['end'] - x['start'], x['idx']
    if a.timeline:
        timeline(segs); return
    res = []
    for w in a.window:
        name, sa, sb = w.rsplit(':', 2)
        sel = [s for s in segs if int(sa) <= s['idx'] < int(sb)]
        res.append(summarize(name, sel))
    if a.json: Path(a.json).write_text(json.dumps(res, indent=1) + '\n')
    text = '\n'.join(md(r) for r in res)
    if a.md: Path(a.md).write_text(text + '\n')
    print(text)


if __name__ == '__main__':
    main()
