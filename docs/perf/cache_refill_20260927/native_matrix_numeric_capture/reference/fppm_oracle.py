#!/usr/bin/env python3
"""Integer-exact oracle for native tEsT12000 FPMm, reconstructed from pinned disassembly."""
import hashlib
import json
import struct

N = 40
MASK = 0xffff
seed = 0x2403
random_calls = 0

def s16(v):
    v &= MASK
    return v - 0x10000 if v & 0x8000 else v

def next_value():
    global seed, random_calls
    random_calls += 1
    # LocalRand's MULS.W / ADDI.W leave the low-word recurrence modulo 2^16.
    seed = (seed * 0x051d + 0x3619) & MASK
    r = s16(seed)
    # DIVS.W truncates toward zero; the preceding MULS/SUB produce signed remainder.
    q120 = (abs(r) // 120) * (-1 if r < 0 else 1)
    rem = r - q120 * 120
    centered = rem - 60
    return (abs(centered) // 3) * (-1 if centered < 0 else 1)

def init_matrix():
    # rInitmatrix iterates row D5=1..40, then column D3=1..40.
    matrix = [[0] * (N + 1)]
    matrix.extend([[0] + [next_value() for _ in range(N)] for _row in range(N)])
    return matrix

C = [[0] * (N + 1) for _ in range(N + 1)]
for _pass in range(4):
    # FPMm reseeds and reinitializes both input matrices on every pass.
    seed = 0x2403
    random_calls = 0
    A = init_matrix()
    B = init_matrix()
    assert random_calls == 3200
    # Independently cross-check the low-word recurrence after exactly 3200 calls.
    check_seed = 0x2403
    for _ in range(3200):
        check_seed = (check_seed * 0x051d + 0x3619) & MASK
    assert seed == check_seed
    # Caller writes result[row D5][column D4]. rInnerproduct reads
    # A[row][k] and B[k][column], sums k=1..40.
    for row in range(1, N + 1):
        for col in range(1, N + 1):
            C[row][col] = sum(A[row][k] * B[k][col] for k in range(1, N + 1))
    seed_after_pass = seed

cells = {(r, c): C[r][c] for r, c in [(1, 1), (1, 2), (2, 1), (20, 20), (40, 40)]}
# Row-major 40x40, signed int32 big-endian: all expected cells are integral.
packed = b''.join(struct.pack('>i', C[r][c]) for r in range(1, N + 1) for c in range(1, N + 1))
values = [C[r][c] for r in range(1, N + 1) for c in range(1, N + 1)]
result = {
    'seed_initial_each_pass': '0x2403', 'seed_after_3200_values_each_pass': f'0x{seed_after_pass:04x}',
    'A_hash_row_major_binary32_be': hashlib.sha256(b''.join(struct.pack('>f', float(A[r][c])) for r in range(1,N+1) for c in range(1,N+1))).hexdigest(),
    'B_hash_row_major_binary32_be': hashlib.sha256(b''.join(struct.pack('>f', float(B[r][c])) for r in range(1,N+1) for c in range(1,N+1))).hexdigest(),
    'C_hash_row_major_signed32_be': hashlib.sha256(packed).hexdigest(),
    'C_hash_row_major_binary32_be': hashlib.sha256(b''.join(struct.pack('>f', float(C[r][c])) for r in range(1,N+1) for c in range(1,N+1))).hexdigest(),
    'C_known_cells_1based': {f'{r},{c}': v for (r,c),v in cells.items()},
    'C_range': [min(values), max(values)],
    'A_range': [min(A[r][c] for r in range(1,N+1) for c in range(1,N+1)), max(A[r][c] for r in range(1,N+1) for c in range(1,N+1))],
    'B_range': [min(B[r][c] for r in range(1,N+1) for c in range(1,N+1)), max(B[r][c] for r in range(1,N+1) for c in range(1,N+1))],
    'random_calls_per_pass': 3200, 'passes': 4, 'inputs_reinitialized_each_pass': True, 'identical_inputs_and_result_each_pass': True,
    'single_precision_exactness_bound': 'input abs<=59; product abs<=3481; 40-term partial-sum abs<=139240 < 2^24, so each integer product/sum is exactly representable in IEEE binary32',
}
print(json.dumps(result, indent=2))
