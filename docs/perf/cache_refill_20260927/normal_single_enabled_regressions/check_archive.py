#!/usr/bin/env python3
"""Verify compact paired enabled-FPU regression evidence; launches no tools."""
from pathlib import Path
import hashlib
import json
import re
import sys

TARGETS = ['fpu', 'fpu_frames', 'fpu_resume', 'mmu', 'exceptions', 'fpu_normalize']
EXPECTED_MANIFEST_SHA = 'b769a8d916b316f39b7a210564e0efb73473e3eb3a5df9b0dbdcebc91be91e2b'
EXPECTED_CANDIDATE = '6c157b3bc045e74a90416f4764f35cf65024e77577019a100b8aa9b5bdd9ce9b'
EXPECTED_BASELINE = '2d53db3ae4a04310add04eeb7919f0219197a98827ed92e410e6d4a4a90f5465'
FORBIDDEN = {'.vvp', '.bin', '.hex', '.hda', '.rom', '.o', '.a', '.so', '.fst', '.vcd'}


def sha(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as f:
        for block in iter(lambda: f.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def j(path):
    return json.loads(path.read_text())


def main(root):
    root = root.resolve()
    sums = root / 'archive_manifest.sha256'
    entries = {}
    for n, line in enumerate(sums.read_text().splitlines(), 1):
        digest, rel = line.split('  ', 1)
        parts = Path(rel).parts
        assert rel not in entries and not Path(rel).is_absolute() and '..' not in parts, f'bad archive row {n}'
        entries[rel] = digest
    actual = {p.relative_to(root).as_posix() for p in root.rglob('*') if p.is_file() and p != sums}
    assert set(entries) == actual, ('archive fileset', sorted(actual ^ set(entries)))
    for rel, digest in entries.items():
        assert sha(root / rel) == digest, rel
    forbidden = [p.relative_to(root).as_posix() for p in root.rglob('*') if p.is_file() and p.suffix.lower() in FORBIDDEN]
    assert not forbidden, f'generated/binary payload included: {forbidden}'
    assert max(p.stat().st_size for p in root.rglob('*') if p.is_file()) < 3_000_000

    manifest = root / 'input_manifest.sha256'
    assert sha(manifest) == EXPECTED_MANIFEST_SHA
    rows = {}
    for n, line in enumerate(manifest.read_text().splitlines(), 1):
        digest, rel = line.split('  ', 1)
        assert rel not in rows and not Path(rel).is_absolute() and '..' not in Path(rel).parts, f'bad input row {n}'
        rows[rel] = digest
    assert len(rows) == 102
    for rel, digest in rows.items():
        archived_input = root / 'frozen_inputs/README.md' if rel == 'README.md' else root / rel
        assert sha(archived_input) == digest, f'immutable input changed: {rel}'

    ident = j(root / 'prepared_identity.json')
    comp = j(root / 'source_comparison.json')
    profile = j(root / 'profile.json')
    pre = j(root / 'run_meta/preflight_identity.json')
    result = j(root / 'result.json')
    progress = j(root / 'run_meta/progress.json')
    execution = j(root / 'run_meta/execution_review.json')
    assert ident['candidate_fpu_sha256'] == profile['candidate_fpu_sha256'] == EXPECTED_CANDIDATE
    assert ident['baseline_fpu_sha256'] == profile['baseline_fpu_sha256'] == EXPECTED_BASELINE
    assert sha(root / 'inputs/ap68040/rtl/ap040_fpu.v') == EXPECTED_CANDIDATE
    assert sha(root / 'inputs/baseline_ap040_fpu.v') == EXPECTED_BASELINE
    assert ident['immutable_input_manifest_sha256'] == pre['immutable_input_manifest_sha256'] == result['immutable_input_manifest_sha256'] == EXPECTED_MANIFEST_SHA
    assert pre['status'] == 'PREFLIGHT_PASS_ONLY' and pre['no_compile_or_simulation'] is True
    assert pre['immutable_input_count'] == result['immutable_input_count'] == 102
    assert comp['input_differences'] == ['ap68040/rtl/ap040_fpu.v'] and comp['non_fpu_input_differences'] == []
    assert comp['candidate_sha256'] == EXPECTED_CANDIDATE and comp['baseline_sha256'] == EXPECTED_BASELINE
    assert profile['targets'] == TARGETS
    assert result['simulation_status'] == progress['simulation_status'] == 'PASS'
    assert progress == result
    assert result['immutable_inputs_revalidated'] == 102
    assert result['global_wall_cap_seconds'] == 3600 and result['command_wall_cap_seconds'] == 240
    assert result['tools'] == pre['tools'] == ident['tools']

    target_log_count = 0
    for variant in ('baseline', 'candidate'):
        assert set(result['targets'][variant]) == set(TARGETS)
        for target in TARGETS:
            record = result['targets'][variant][target]
            assert record['status'] == 'PASS'
            log = root / variant / f'{target}.log'
            text = log.read_text(errors='replace')
            assert sha(log) == record['log_sha256']
            assert 'ALL TESTS PASSED' in text
            assert not re.search(r'FATAL|TEST FAILED|FAIL:|ERROR:', text)
            target_log_count += 1
            phases = record['bus_phase_cycles']
            if target == 'fpu_normalize':
                assert phases == {}
            else:
                assert set(phases) == {'0', '1', '2'}
                assert re.findall(r'phase (\d) passed', text) == ['0', '1', '2']
                assert all(int(v) > 0 for v in phases.values())
            artifacts = record['artifacts']
            assert len(artifacts['simulation_binary_sha256']) == 64
            if target != 'fpu_normalize':
                assert len(artifacts['program_binary_sha256']) == 64 and len(artifacts['program_hex_sha256']) == 64
    assert target_log_count == 12
    assert execution['status'] == 'TERMINAL_PAIRED_REGRESSION_PASS'
    assert execution['runner_exec_session_id'] == 19222
    assert execution['root_observed_live_child']['pid'] == 2441423
    assert execution['individual_child_pids_persisted_by_runner'] is False
    print('PASS: archive checksums, 102 source inputs, 12 terminal logs, all target phases and session/process evidence')


if __name__ == '__main__':
    try:
        if len(sys.argv) != 2:
            raise SystemExit('usage: check_archive.py ARCHIVE_DIR')
        main(Path(sys.argv[1]))
    except Exception as exc:
        print(f'FAIL: {exc}', file=sys.stderr)
        raise SystemExit(1)
