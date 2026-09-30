#!/usr/bin/env python3
"""Small synthetic path/index smoke plus active-cell corruption rejection."""
import contextlib
import importlib.util
import io
import runpy
import struct
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('check_payloads', HERE/'check_payloads.py')
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)
with contextlib.redirect_stdout(io.StringIO()):
    oracle = runpy.run_path(str(HERE/'fppm_oracle.py'))

with tempfile.TemporaryDirectory() as td:
    d = Path(td)
    for i in range(123):
        group, row = ('A', i) if i < 41 else (('B', i-41) if i < 82 else ('C', i-82))
        values = oracle[group]
        payload = b''.join(struct.pack('>f', float(values[row][col])) for col in range(41))
        (d/f'matrix_payload_{i+1:03d}.hex').write_text(''.join(f'{b:02x}\n' for b in payload))
    assert checker.verify_matrix_payloads(d, oracle) == 4800
    path = d/'matrix_payload_002.hex'  # A row 1, active column 1 at byte offset 4.
    raw = bytearray(bytes(int(x, 16) for x in path.read_text().split()))
    raw[4] ^= 1
    path.write_text(''.join(f'{b:02x}\n' for b in raw))
    try:
        checker.verify_matrix_payloads(d, oracle)
    except AssertionError as error:
        assert 'A[1][1]' in str(error)
    else:
        raise AssertionError('corrupted active Matrix cell was accepted')
print('PASS payload checker synthetic 4800-cell fixture; active-cell corruption rejected')
