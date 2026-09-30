#!/usr/bin/env python3
"""Check the directed bench's explicit coverage, not equivalent bus traces."""
from pathlib import Path
import argparse, json, re

EXPECTED = [32, 4, 4, 15, 1, 1, 1, 7, 1, 1, 1, 1, 1, 1, 1, 1]
FIELDS = ['candidate', 'cases', 'phase_entries', 'critical_issued', 'local_words',
          'publications', 'local_fallbacks', 'poisoned_publications', 'phase_errors',
          'operand_acks', 'external_tail_requests', 'held_faults',
          'error_ack_overlaps', 'cinv_completions']

def check(text, candidate):
    assert not re.search(r'FATAL|ERROR|global bounded timeout', text), 'HDL failure'
    summary = re.findall(r'^XFIRST_PHASE PASS (.*)$', text, re.M)
    assert len(summary) == 1, 'exactly one terminal PASS required'
    pairs = [part.split('=') for part in summary[0].split()]
    assert [key for key, value in pairs] == FIELDS, 'summary schema'
    result = {key: int(value) for key, value in pairs}
    assert result['candidate'] == candidate and result['cases'] == sum(EXPECTED)
    coverage = re.findall(r'^PHASE_COVERAGE id=(\d+) count=(\d+)$', text, re.M)
    assert [(int(i), int(n)) for i, n in coverage] == list(enumerate(EXPECTED)), 'scenario coverage'
    cases = re.findall(r'^PHASE_CASE id=(\d+) count=(\d+) entries=(\d+) local_words=(\d+) publications=(\d+) fallbacks=(\d+) poison=(\d+) errors=(\d+)$', text, re.M)
    assert len(cases) == sum(EXPECTED)
    seen = [0] * len(EXPECTED)
    for row in cases:
        values = [int(v) for v in row]
        ident, count = values[:2]
        assert 0 <= ident < len(seen)
        seen[ident] += 1
        assert count == seen[ident]
    assert seen == EXPECTED
    for col, key in enumerate(['phase_entries', 'local_words', 'publications',
                               'local_fallbacks', 'poisoned_publications', 'phase_errors'], 2):
        assert sum(int(row[col]) for row in cases) == result[key], key
    assert result['external_tail_requests'] == 0
    assert result['held_faults'] == 4 and result['error_ack_overlaps'] == 1
    assert result['cinv_completions'] >= 1 and result['operand_acks'] > 0
    if candidate:
        for key in ['phase_entries', 'critical_issued', 'local_words', 'publications',
                    'poisoned_publications', 'phase_errors']:
            assert result[key] > 0, key
        assert result['local_fallbacks'] >= 5
        # Coverage must occur in the relevant scenarios, not only warm checks.
        by_id = {ident: [row for row in cases if int(row[0]) == ident]
                 for ident in range(len(EXPECTED))}
        assert all(int(row[2]) > 0 for row in by_id[1]), 'all-way phase entries'
        assert all(int(row[5]) > 0 for row in by_id[2]), 'each sideband-loss fallback'
        assert int(by_id[14][0][5]) > 0, 'wrong-tag fallback'
        assert int(by_id[15][0][7]) > 0, 'ACK+error first-phase priority'
    else:
        for key in ['phase_entries', 'critical_issued', 'local_words', 'publications',
                    'local_fallbacks', 'poisoned_publications', 'phase_errors']:
            assert result[key] == 0, key
    return result

def main():
    p = argparse.ArgumentParser()
    p.add_argument('output_directory', type=Path)
    a = p.parse_args()
    result = {name: check((a.output_directory / (name + '_run.log')).read_text(), cand)
              for name, cand in [('baseline', 0), ('candidate', 1)]}
    print(json.dumps({'status': 'PASS_XFIRST_PHASE_PAIR', 'results': result}, indent=2))

if __name__ == '__main__':
    main()
