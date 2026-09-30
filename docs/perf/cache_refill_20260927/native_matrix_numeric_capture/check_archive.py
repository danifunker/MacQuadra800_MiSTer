#!/usr/bin/env python3
"""Offline integrity and numerical checks for the archived baseline/candidate captures."""
import contextlib
import hashlib
import importlib.util
import io
import json
import re
import runpy
from pathlib import Path

D = Path(__file__).resolve().parent
REF = D/'reference'
spec = importlib.util.spec_from_file_location('matrix_payloads', REF/'check_payloads.py')
payloads = importlib.util.module_from_spec(spec)
spec.loader.exec_module(payloads)
with contextlib.redirect_stdout(io.StringIO()):
    oracle = runpy.run_path(str(REF/'fppm_oracle.py'))
summary = oracle['result']
oracle_hash = hashlib.sha256((REF/'fppm_oracle.py').read_bytes()).hexdigest()
checker_hash = hashlib.sha256((REF/'check_payloads.py').read_bytes()).hexdigest()
assert summary['C_hash_row_major_binary32_be'] == '95b611a1ef946a97c8940e5d5723666d3cf7fe3ab5180df6f2e3565ce752a45f'

for line in (D/'archive_artifact_manifest.sha256').read_text().splitlines():
    digest, rel = line.split('  ', 1)
    path = D/rel
    assert path.is_file() and hashlib.sha256(path.read_bytes()).hexdigest() == digest, rel

results = {}
source_maps = {}
fpu_hashes = {}
for name, expected_loop in [
    ('baseline', 31_634_431),
    ('candidate', 29_640_994),
]:
    root = D/name
    run = root/'run'
    identity = json.loads((run/'identity.json').read_text())
    measurement = json.loads((root/'measurement.json').read_text())
    log = (run/'run.log').read_text()
    assert identity['numeric_oracle_sha256'] == oracle_hash
    assert identity['payload_checker_sha256'] == checker_hash
    assert identity['image_sha256'] == 'a8d1b0b4786139e906481f1341ed2c35488ab2d900df6dd04eae029112e5f8d7'
    assert identity['romlat'] == 6
    assert identity['flags'] == json.loads((D/'baseline/run/identity.json').read_text())['flags']
    fpu = [v for k, v in identity['sources'].items() if k.endswith('/rtl/ap68040/rtl/ap040_fpu.v')]
    assert len(fpu) == 1 and len(fpu[0]) == 64 and all(c in '0123456789abcdef' for c in fpu[0])
    fpu_hashes[name] = fpu[0]
    normalized = {}
    for key, value in identity['sources'].items():
        if '/scratch/fpu_refill_platform_workload_20260927/baseline/' in key:
            rel = 'TREE/' + key.split('/scratch/fpu_refill_platform_workload_20260927/baseline/', 1)[1]
        elif '/scratch/native_fpu_matrix_candidate_20260928/tree/' in key:
            rel = 'TREE/' + key.split('/scratch/native_fpu_matrix_candidate_20260928/tree/', 1)[1]
        elif '/scratch/native_matrix_numeric_20260928/' in key:
            rel = 'FIXTURE/' + key.split('/scratch/native_matrix_numeric_20260928/', 1)[1]
        elif '/scratch/native_matrix_candidate_numeric_20260928/' in key:
            rel = 'FIXTURE/' + key.split('/scratch/native_matrix_candidate_numeric_20260928/', 1)[1]
        else:
            rel = key
        assert rel not in normalized, (name, rel)
        normalized[rel] = value
    source_maps[name] = normalized
    assert 'MATRIX_NUMERIC_CAPTURE_GUARDS_PASS' in log
    assert 'MATRIX_NUMERIC_CAPTURE files=123 bytes_each=164 first_free_pc=000600260' in log
    assert 'MATRIX_TRAPS alloc_calls=123 alloc_returns=123 free_calls=123 free_returns=123' in log
    assert 'MATRIX_HEAP_END zone=003f1890 bkLim=00492078 free=0003ff10 memtop=00517754 ptr_tables=match' in log
    assert 'SDRAM_PROTOCOL_ERRORS 0' in log
    assert re.search(r'BERR 0\s+IPL_ASSERTED_CYCLES 0', log)
    assert measurement['loop_cycles'] == expected_loop
    assert int(re.search(r'WHETSTONE_LOOP cycles=(\d+)', log)[1]) == expected_loop
    assert int(re.search(r'WHETSTONE RETURNED cycles=(\d+)', log)[1]) == measurement['returned_cycles']
    assert measurement['matrix_numeric']['status'] == 'PASS'
    assert measurement['matrix_numeric']['active_cells_compared'] == 4800
    assert measurement['matrix_numeric']['C_hash_row_major_binary32_be'] == summary['C_hash_row_major_binary32_be']
    assert payloads.verify_matrix_payloads(run, oracle) == 4800
    qual = json.loads((root/'qualification_identity.json').read_text())
    abi = bytes(int(x, 16) for x in (run/'native_abi.hex').read_text().split())
    expected_abi = [0x11110003,0x11110004,0x11110005,0x11110006,0x11110007,
                    0x22222222,0x33333333,0x600000,0x620000,0x66666666]
    assert abi[:40] == b''.join(x.to_bytes(4, 'big') for x in expected_abi)
    assert abi[:40] == abi[0x40:0x68]
    assert abi[0x100:0x130] == abi[0x140:0x170]
    assert int.from_bytes(abi[0x80:0x84], 'big') == 0x608ea0
    assert int.from_bytes(abi[0x84:0x88], 'big') == 0x640000
    code = bytes(int(x, 16) for x in (run/'native_code.hex').read_text().split())
    assert hashlib.sha256(code).hexdigest() == qual['initial_native_code_sha256']
    assert sum(measurement['core'].values()) == expected_loop
    assert sum(measurement['cache'].values()) == expected_loop
    assert sum(measurement['fst'].values()) == expected_loop
    assert measurement['chip_bus_irq_errors'] == 0
    assert measurement['allocations']['successful'] == measurement['allocations']['frees'] == 123
    assert measurement['allocations']['pointer_tables'] == 'match'
    assert measurement['allocations']['heap_scalars'] == 'restored'
    results[name] = measurement

base_map, candidate_map = source_maps['baseline'], source_maps['candidate']
assert set(base_map) == set(candidate_map), 'consumed source sets differ'
rtl_differences = [key for key in base_map if base_map[key] != candidate_map[key]]
assert rtl_differences == ['TREE/rtl/ap68040/rtl/ap040_fpu.v'], rtl_differences
assert fpu_hashes['baseline'] != fpu_hashes['candidate']
assert results['baseline']['matrix_numeric']['C_hash_row_major_binary32_be'] == results['candidate']['matrix_numeric']['C_hash_row_major_binary32_be']
print('PASS archive integrity: manifests, normalized consumed sources, 123 payloads each, 9,600 exact cells, ABI/code/histogram/heap/error gates')
print('loop clocks baseline=%d candidate=%d; C hash=%s' % (
    results['baseline']['loop_cycles'], results['candidate']['loop_cycles'], summary['C_hash_row_major_binary32_be']))
