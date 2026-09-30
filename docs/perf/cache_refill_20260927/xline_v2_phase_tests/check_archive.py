#!/usr/bin/env python3
"""Portable verification of recorded cache phase evidence; no simulation."""
from pathlib import Path
import hashlib, json, runpy

P = Path(__file__).resolve().parent
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
for row in (P / 'archive_manifest.sha256').read_text().splitlines():
    h, name = row.split('  ', 1)
    assert sha(P / name) == h, name
mapping = json.loads((P / 'source_copy_map.json').read_text())
assert mapping['format'] == 'xline-v2-phase-source-copy-map-v1'
assert len({row['archive_path'] for row in mapping['files']}) == len(mapping['files'])
for row in mapping['files']:
    path = P / row['archive_path']
    assert sha(path) == row['sha256'] and path.stat().st_size == row['bytes'], row['archive_path']

old = (P / 'attempt1/tb_xfirst_sideband.sv').read_text()
new = (P / 'attempt2/tb_xfirst_sideband.sv').read_text()
final = (P / 'attempt3/tb_xfirst_sideband.sv').read_text()
needle = '   req=0;error_arm=0;error_with_ack=0;drain();'
replacement = ('   req=0;error_arm=0;error_with_ack=0;\n'
               '   @(negedge clk); // one enabled posedge observes withdrawal and clears err_hold\n'
               '   drain();')
assert old.count(needle) == 1 and old.replace(needle, replacement) == new
pattern_old = 'memory[i]=(i*13+7)&255;oracle[i]=memory[i];'
pattern_new = 'memory[i]=(i*13 + (i>>8)*37 + (i>>11)*53 + 7)&255;oracle[i]=memory[i];'
assert new.count(pattern_old) == 1 and new.replace(pattern_old, pattern_new) == final
for name in ['run.py', 'check_results.py']:
    assert (P / 'attempt1' / name).read_bytes() == (P / 'attempt2' / name).read_bytes()
    assert (P / 'attempt2' / name).read_bytes() == (P / 'attempt3' / name).read_bytes()
pattern = json.loads((P / 'pattern_distinction.json').read_text())
assert pattern['initial_pattern'] == '(i*13 + (i>>8)*37 + (i>>11)*53 + 7)&255'
value = lambda i: (i*13 + (i >> 8)*37 + (i >> 11)*53 + 7) & 255
assert len(pattern['victim_sets']) == 3
for row, (base, maximum) in zip(pattern['victim_sets'], [(0x1000, 7), (0x5000, 4), (0x8000, 4)]):
    assert row['base'] == hex(base) and row['tags_0_through'] == maximum
    assert row['offset0_bytes'] == [value(base + tag*0x800) for tag in range(maximum+1)]
    for offset in range(16):
        assert len({value(base + tag*0x800 + offset) for tag in range(maximum+1)}) == maximum+1
    assert row['all_16_same_offsets_distinct'] is True

summary = json.loads((P / 'result_summary.json').read_text())
expected = {'baseline': summary['cache_baseline_sha256'],
            'candidate': summary['cache_candidate_sha256']}
for name in ['attempt1', 'attempt2', 'attempt3']:
    manifest = P / name / 'source_manifest.sha256'
    meta = json.loads((P / name / 'outputs/metadata.json').read_text())
    assert sha(manifest) == meta['source_manifest_sha256'] == summary['attempts'][name]['source_manifest_sha256']
    assert meta['cache_sha256'] == expected
    assert all(s['terminal'] for s in meta['steps'])
    maps = {variant: {} for variant in expected}
    for row in manifest.read_text().splitlines():
        h, path = row.split('  ', 1)
        for variant in expected:
            prefix = 'inputs/' + variant + '/rtl/'
            if path.startswith(prefix):
                maps[variant][path[len(prefix):]] = h
    assert len(maps['baseline']) == len(maps['candidate']) == 113
    assert maps['baseline'].keys() == maps['candidate'].keys()
    delta = [key for key in maps['baseline'] if maps['baseline'][key] != maps['candidate'][key]]
    assert delta == ['ap68040/rtl/ap040_cache.v']
    for variant in expected:
        assert maps[variant][delta[0]] == expected[variant]

failed = json.loads((P / 'attempt1/outputs/metadata.json').read_text())
assert failed['status'] == 'FAILED'
assert [(s['name'], s['exit_status']) for s in failed['steps']] == [('baseline_build', 0), ('baseline_run', 1)]
assert 'fault phase/hold not released' in (P / 'attempt1/outputs/baseline_run.log').read_text()
assert summary['qualified_attempt'] == 'attempt3' and summary['attempt2_result_counters_identical'] is True
for name in ['attempt2', 'attempt3']:
    passed = json.loads((P / name / 'outputs/metadata.json').read_text())
    assert passed['status'] == 'PASS_XFIRST_PHASE_PAIR' and passed['postrun_source'] == 'PASS'
    assert [(s['name'], s['exit_status']) for s in passed['steps']] == [('baseline_build', 0), ('baseline_run', 0), ('candidate_build', 0), ('candidate_run', 0)]
    check = runpy.run_path(str(P / name / 'check_results.py'))['check']
    results = {variant: check((P / name / 'outputs' / (variant + '_run.log')).read_text(), cand)
               for variant, cand in [('baseline', 0), ('candidate', 1)]}
    assert results == summary['qualified_results']['results']
    assert json.loads((P / name / 'outputs/check_results.log').read_text()) == summary['qualified_results']
print('PASS xline-v2 phase archive: failure preserved, both corrected pairs 73 cases each, distinguishing victim pattern and source identities verified')
