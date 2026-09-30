#!/usr/bin/env python3
"""Strict passive-observer v2 verification; no guest timing attribution."""
from pathlib import Path
import argparse
import re

META = {
    'format': 'fpu-guard-profile-v2-enabled',
    'post_round_predicate': 'candidate6c_guard_independent_of_FPCR_enables',
    'sample': 'pre_eval_inputs_committed_start_inclusive_stop_exclusive',
    'counts': 'new_fp_command_branch_events_not_retirements_or_unique_requests',
    'side_bits': 'cr_we,fm_we,bsun_req,fp_reset,frestore_idle,frestore_unimp,fsave_ack,pend_capture',
}
HEADERS = {
    'FPU_GUARD_SUMMARY': 'edges raw restore pending unexpected_single_class enable_rejected_55ff_normal context_dropped eligible_post_round eligible_post_mismatch reconciles'.split(),
    'FPU_GUARD_BUCKET': 'precision enables raw single exp_zero exp_normal exp_allones old_guard_73bc guard_55ff guard_6c'.split(),
    'FPU_GUARD_CONTEXT': 'profile_edge pc fpcr opclass side_bits old_guard_73bc guard_55ff guard_6c'.split(),
}

def uint(text):
    assert re.fullmatch(r'[0-9]+', text), ('unsigned decimal required', text)
    return int(text)

def check(path, allow_empty=False):
    rows = [line.split('\t') for line in path.read_text().splitlines()]
    meta = [r for r in rows if r[0] == 'FPU_GUARD_META']
    assert len(meta) == len(META) and all(len(r) == 3 for r in meta)
    assert len({r[1] for r in meta}) == len(meta)
    assert {r[1]: r[2] for r in meta} == META
    kinds = set(HEADERS) | {'FPU_GUARD_META', 'FPU_GUARD_REJECT_SIDE'}
    assert all(r[0] in kinds for r in rows if r[0].startswith('FPU_GUARD_'))
    data = {}
    for kind, fields in HEADERS.items():
        selected = [r for r in rows if r[0] == kind]
        assert sum(r[1:] == fields for r in selected) == 1, (kind, 'exact header required')
        data[kind] = [r[1:] for r in selected if r[1:] != fields]
        assert all(len(r) == len(fields) for r in data[kind]), kind
    ordinary = [r for r in rows if r[0] == 'SUMMARY' and len(r) > 1 and r[1].isdigit()]
    assert len(ordinary) == 1
    summaries = data['FPU_GUARD_SUMMARY']; assert len(summaries) == 1
    edge, raw, restore, pending, unexpected, enable_reject, dropped, rounds, mismatch, reconciles = map(uint, summaries[0])
    assert edge == uint(ordinary[0][1])
    assert raw + restore + pending <= edge and unexpected == mismatch == 0 and reconciles == 1
    buckets = [list(map(uint, r)) for r in data['FPU_GUARD_BUCKET']]
    assert len({(r[0], r[1]) for r in buckets}) == len(buckets)
    for precision, enables, br, bs, zero, normal, allones, old, guard55, guard6c in buckets:
        assert precision < 4 and enables < 256 and br > 0
        assert br >= bs == zero + normal + allones
        assert old <= guard55 <= guard6c <= normal
        assert guard55 == (guard6c if enables == 0 else 0)
        assert old == (guard55 if precision == 0 else 0)
    assert sum(r[2] for r in buckets) == raw
    assert sum(r[9] for r in buckets) == rounds
    assert sum(r[5] for r in buckets if r[1]) == enable_reject
    normal = sum(r[5] for r in buckets)
    sides = [r for r in rows if r[0] == 'FPU_GUARD_REJECT_SIDE']
    assert len(sides) == 8 and all(len(r) == 3 for r in sides)
    sidepairs = [(uint(r[1]), uint(r[2])) for r in sides]
    assert sorted(i for i, n in sidepairs) == list(range(8))
    assert all(n <= normal for i, n in sidepairs)
    rejected_ports = normal - rounds
    assert max(n for i, n in sidepairs) <= rejected_ports <= sum(n for i, n in sidepairs)
    contexts = data['FPU_GUARD_CONTEXT']
    assert len(contexts) == min(normal, 64) and len(contexts) + dropped == normal
    last = 0
    context_buckets = {}
    bucket_index = {(r[0], r[1]): r for r in buckets}
    for row in contexts:
        position = uint(row[0]); assert last < position <= edge; last = position
        assert re.fullmatch(r'[0-9A-F]{8}', row[1]) and re.fullmatch(r'[0-9A-F]{8}', row[2])
        fpcr = int(row[2], 16); opclass, ports, old, guard55, guard6c = map(uint, row[3:])
        assert opclass == 2 and ports < 256
        assert guard6c == (ports == 0)
        assert guard55 == (guard6c and ((fpcr >> 8) & 255) == 0)
        assert old == (guard55 and ((fpcr >> 6) & 3) == 0)
        key = ((fpcr >> 6) & 3, (fpcr >> 8) & 255)
        assert key in bucket_index
        context_buckets[key] = context_buckets.get(key, 0) + 1
        assert context_buckets[key] <= bucket_index[key][5]
    if not allow_empty:
        assert rounds > 0, 'no eligible normal-single branch observed'
    return {'edges': edge, 'raw': raw, 'normal': normal, 'guard73bc': sum(r[7] for r in buckets),
            'guard55ff': sum(r[8] for r in buckets), 'guard6c': rounds, 'post_mismatch': mismatch}

if __name__ == '__main__':
    parser = argparse.ArgumentParser(); parser.add_argument('report', type=Path)
    parser.add_argument('--allow-empty', action='store_true'); args = parser.parse_args()
    print('PASS v2 enabled observer report', check(args.report, args.allow_empty))
