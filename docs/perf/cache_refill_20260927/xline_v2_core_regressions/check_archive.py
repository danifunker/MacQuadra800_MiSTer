#!/usr/bin/env python3
"""Offline integrity and scope checker for this compact evidence archive."""
from __future__ import annotations
import hashlib
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parent

def sha(path: Path) -> str:
    h = hashlib.sha256()
    with path.open('rb') as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()

def need(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit('FAIL: ' + message)

# Reject generated products and bulky build caches; this is a source/evidence archive.
for path in ROOT.rglob('*'):
    if not path.is_file():
        continue
    need(path.suffix.lower() not in {'.bin', '.hex', '.vvp', '.o', '.pyc'},
         f'generated file is present: {path.relative_to(ROOT)}')
    need(path.name not in {'Vemu'} and path.name != 'ccache',
         f'generated executable/cache is present: {path.relative_to(ROOT)}')
    need('__pycache__' not in path.parts, 'Python cache is present')

sums = ROOT / 'SHA256SUMS.txt'
need(sums.is_file(), 'SHA256SUMS.txt missing')
recorded = {}
for line in sums.read_text().splitlines():
    if not line.strip():
        continue
    digest, rel = line.split('  ', 1)
    need(rel not in recorded, f'duplicate checksum path: {rel}')
    recorded[rel] = digest
actual = {p.relative_to(ROOT).as_posix() for p in ROOT.rglob('*')
          if p.is_file() and p != sums}
need(set(recorded) == actual,
     f'checksum inventory mismatch: missing={sorted(actual-set(recorded))}, extra={sorted(set(recorded)-actual)}')
for rel, digest in recorded.items():
    need(sha(ROOT / rel) == digest, f'checksum mismatch: {rel}')

result = json.loads((ROOT / 'program_result.json').read_text())
meta = json.loads((ROOT / 'program_execution_metadata.json').read_text())
prep = json.loads((ROOT / 'prepared_identity.json').read_text())
need(result['simulation_status'] == 'PASS' and meta['terminal_exit_status'] == 0,
     'five-program pair is not recorded as successful')
need(meta['immutable_inputs_revalidated'] == 101 and result['input_count'] == 101,
     'five-program input count mismatch')
need(result['input_manifest_sha256'] == prep['input_manifest_sha256'] ==
     '9462419b0f13e9cdf173caef70f12abd5b24865af0bfcbe08aecfbc6563a9d81',
     'five-program manifest identity mismatch')
need(result['fpu_sha256'] == '6c157b3bc045e74a90416f4764f35cf65024e77577019a100b8aa9b5bdd9ce9b',
     'FPU source identity mismatch')
need(result['cache_sha256']['baseline'] == '7cba7f73f6f7f16fa7a45d439af6a786bd55c3ef2a3f8c876b400e10d4fb7747',
     'baseline cache identity mismatch')
need(result['cache_sha256']['candidate'] == '9e8c0582db1b0bb88428e56fec63e99029b61faffac62c6f3dda9326b5191481',
     'candidate cache identity mismatch')
need(result['flags'][0] == '-g2012' and result['flags'][1:] == result['sim_flags'],
     'compile/simulation defines differ beyond the language-standard flag')
# Verify the archived source subset against the original frozen 101-input manifest.
original = {}
for line in (ROOT / 'input_manifest.sha256').read_text().splitlines():
    digest, rel = line.split('  ', 1)
    original[rel] = digest
source_map = {
    'inputs/tb/asm/t_fpu.s': 'source/programs/t_fpu.s',
    'inputs/tb/asm/t_fpu_frames.s': 'source/programs/t_fpu_frames.s',
    'inputs/tb/asm/t_fpu_resume.s': 'source/programs/t_fpu_resume.s',
    'inputs/tb/asm/t_mmu.s': 'source/programs/t_mmu.s',
    'inputs/tb/asm/t_exceptions.s': 'source/programs/t_exceptions.s',
    'inputs/tb/tb_ap040_program.v': 'source/harness/tb_ap040_program.v',
    'inputs/tb/bin2hex.py': 'source/harness/bin2hex.py',
}
for original_path, archived_path in source_map.items():
    need(original_path in original, f'original manifest lacks {original_path}')
    need(sha(ROOT / archived_path) == original[original_path],
         f'archived source differs from frozen input: {original_path}')
need('-DCACHE_SMALL=1' in result['flags'] and '-DSIMULATION=1' in result['flags'],
     'expected cache/simulation defines missing')
targets = ['fpu', 'fpu_frames', 'fpu_resume', 'mmu', 'exceptions']
for target in targets:
    base = result['targets']['baseline'][target]
    cand = result['targets']['candidate'][target]
    need(base['status'] == cand['status'] == 'PASS', f'{target} not PASS on both sides')
    need(base['bus_phase_cycles'] == cand['bus_phase_cycles'], f'{target} phase counts differ')
    need(set(base['bus_phase_cycles']) == {'0', '1', '2'}, f'{target} missing phase')
    for side, rec in [('baseline', base), ('candidate', cand)]:
        log = ROOT / 'program_runs' / side / f'{target}.log'
        need(log.is_file() and sha(log) == rec['log_sha256'], f'{side}/{target} log identity mismatch')
    need(base['log_sha256'] == cand['log_sha256'], f'{target} logs are not byte-identical by digest')
phase_observations = sum(len(result['targets'][side][target]['bus_phase_cycles'])
                         for side in ('baseline', 'candidate') for target in targets)
need(phase_observations == 30, 'expected 30 paired bus-phase observations')
need(meta['runner_wall_seconds'] == 117.95, 'runner wall-time record mismatch')

# Supplementary t_cache reused these exact paired simulation executables.
tc = json.loads((ROOT / 't_cache' / 'metadata.json').read_text())
need(tc['status'] == 'PASS', 't_cache is not PASS')
need(sha(ROOT / 'source' / 'programs' / 't_cache.s') == tc['source_sha256'],
     'archived t_cache source identity mismatch')
for side, expected_vvp in [('baseline', result['targets']['baseline']['fpu']['simulation_binary_sha256']),
                           ('candidate', result['targets']['candidate']['fpu']['simulation_binary_sha256'])]:
    variant = tc['variants'][side]
    need(variant['status'] == 'PASS' and variant['vvp_sha256'] == expected_vvp,
         f'{side} t_cache reused VVP identity mismatch')
    need(variant['bus_phase_cycles'] == {'0': 2294, '1': 3382, '2': 3382},
         f'{side} t_cache phase count mismatch')
    for log_name, command_index in [('assemble.log', 0), ('hex.log', 1), ('run.log', 2)]:
        log = ROOT / 't_cache' / side / log_name
        rec = variant['commands'][command_index]
        need(log.is_file() and sha(log) == rec['log_sha256'], f'{side} {log_name} hash mismatch')
        need(rec['exit_status'] == 0, f'{side} {log_name} command failed')

# Separate host build and short disk-free smoke: explicitly not workload evidence.
build = ROOT / 'build_smoke' / 'build.meta.json'
bm = json.loads(build.read_text())
sm = json.loads((ROOT / 'build_smoke' / 'smoke' / 'meta.json').read_text())
need(bm['status'] == 'PASS' and bm['before_manifest'] == bm['after_manifest'] == 'PASS',
     'generated-host build/source-postcheck status mismatch')
need(all(c['exit_status'] == 0 for c in bm['commands']), 'generated-host build command failed')
need(sm['status'] == 'PASS' and sm['exit_status'] == sm['check0'] == sm['check1'] == 0,
     'disk-free smoke/checker status mismatch')
need(sm['source_manifest_postrun'] == 'PASS' and sm['child_terminal'] is True,
     'disk-free smoke source/terminal status mismatch')
need('not benchmark or guard coverage' in sm['scope'], 'smoke scope caveat missing')
need('SUMMARY\t100002' in (ROOT / 'build_smoke' / 'smoke' / 'refill.tsv').read_text(),
     'smoke report cycle count does not match its recorded short run')
guard_check = (ROOT / 'build_smoke' / 'smoke' / 'check1.log').read_text()
need(all(f"'{key}': 0" in guard_check for key in ('raw', 'normal', 'guard73bc', 'guard55ff', 'guard6c')),
     'smoke was not explicitly empty for FPU guard coverage')
need(sm['source_manifest_sha256'] == bm['source_manifest_sha256'], 'smoke/build source manifest mismatch')
need(sm['binary_sha256'] == sm['running_exe_sha256'], 'smoke binary identity mismatch')
need((ROOT / 'build_smoke' / 'smoke' / 'refill.tsv').is_file(), 'smoke report missing')
print('PASS: archive hashes, paired test logs/results, t_cache records, and separate build/smoke provenance verified')
print('Scope reminder: the short disk-free smoke is not benchmark or guard-coverage evidence.')
