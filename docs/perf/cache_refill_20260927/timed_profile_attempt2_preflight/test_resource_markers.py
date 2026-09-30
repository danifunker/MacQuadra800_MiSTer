#!/usr/bin/env python3
"""Pin the original Speedometer resource and FPU CODE3 markers, read-only."""
from pathlib import Path
import hashlib
import sys
import tempfile

repo = next(p for p in Path(__file__).resolve().parents if (p / 'MacQuadra800.qsf').is_file())
sys.path.insert(0, str(repo))
from scripts.mac_rsrc import Rsrc

path = Path(sys.argv[1] if len(sys.argv) > 1 else
            '/home/alans/mister/MacQuadra800_fixtures/Speedometer 4.02.rsrc')
raw = path.read_bytes()
assert hashlib.sha256(raw).hexdigest() == 'af67113bceb4eb906e973a9b747a0b1925b9d64c62f0f9a84bc6f0578839ca80'
# Fixture is an AppleDouble file; the raw resource fork starts at byte 82.
with tempfile.TemporaryDirectory() as tmp:
    pure = Path(tmp) / 'fork'
    pure.write_bytes(raw[82:])
    r = Rsrc(pure)
    code, info = r.get('CODE', 3)
    assert info['len'] == 39228
    assert hashlib.sha256(code).hexdigest() == '02123c6cb020961c79cbb66cbadef9247a1add4c480b421645d2a4a4c3fefc31'
    assert raw[0x62561:0x62561+len(code)] == code
    assert code[0x4eb5:0x4eb5+len(b'DoFPUBenchMarks')] == b'DoFPUBenchMarks'
    sites = (
        (0x4f4a,0x4f68,0x4f7c,0x4f80,0x4f82,0x4f8e,0x4f90,0x4fa8,0x24),
        (0x50bc,0x50f2,0x5106,0x510a,0x510c,0x5118,0x511a,0x5132,0x42),
        (0x527a,0x52b0,0x52c4,0x52c8,0x52ca,0x52d6,0x52d8,0x52f0,0x56),
    )
    all_code = [r.get('CODE', it['id'])[0] for typ, items in r.types if typ == 'CODE' for it in items]
    for prefix, mstart, fstart, call, ret, mstop, rawstop, fstop, selector in sites:
        assert code[prefix:prefix+12] == bytes.fromhex('3b7c0004beaa3b7c') + selector.to_bytes(2,'big') + bytes.fromhex('beac')
        assert code[prefix+12:prefix+14] == bytes.fromhex('4eb9')
        assert code[call:call+2] == bytes.fromhex('4e94')
        assert code[ret:ret+2] == bytes.fromhex('4a2d')
        assert code[mstart:mstart+2] == code[rawstop:rawstop+2] == bytes.fromhex('225f')
        assert code[mstop:mstop+2] == bytes.fromhex('a193')
        assert code[fstart:fstart+2] == bytes.fromhex('3f3c')
        assert code[fstop:fstop+2] == bytes.fromhex('4eb9')
        sig = code[prefix:prefix+20]
        # The loader relocates the 32-bit absolute JSR operand at bytes 14..17.
        hits = [(seg, i) for seg, b in enumerate(all_code) for i in range(len(b)-19)
                if all(b[i+j] == sig[j] for j in (*range(14),18,19))]
        assert len(hits) == 1 and all_code[hits[0][0]] == code and hits[0][1] == prefix, hits
    # An 18-byte prefix alone confuses site 2 with an unrelated CODE3 wrapper.
    third18 = code[0x527a:0x527a+18]
    assert [i for i in range(len(code)-17) if code[i:i+18] == third18] == [0x2e54,0x527a]
print('PASS pinned resource/CODE3 hashes, DoFPUBenchMarks, three unique relocation-masked 20-byte signatures and timer/callback opcodes')
