"""Strict byte comparison for the 123 captured 164-byte Matrix rows."""
import struct
from pathlib import Path


def verify_matrix_payloads(directory, oracle):
    directory = Path(directory)
    compared = 0
    for i in range(123):
        payload = bytes(int(x, 16) for x in
                        (directory / f"matrix_payload_{i+1:03d}.hex").read_text().split())
        assert len(payload) == 164, f"matrix payload length index={i}"
        group, row = ('A', i) if i < 41 else (('B', i-41) if i < 82 else ('C', i-82))
        if row == 0:
            continue
        values = oracle[group]
        for col in range(1, 41):
            off = col * 4
            expected = struct.pack('>f', float(values[row][col]))
            assert payload[off:off+4] == expected, (
                f"{group}[{row}][{col}] expected {expected.hex()} "
                f"got {payload[off:off+4].hex()}")
            compared += 1
    assert compared == 4800, f"compared {compared} cells, expected 4800"
    return compared
