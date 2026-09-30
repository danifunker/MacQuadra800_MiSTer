#!/usr/bin/env python3
"""Extract cache FSM names, including comma-declared XSTORE states."""
import re
from pathlib import Path

HERE = Path(__file__).resolve().parent
RTL = HERE / "reference/rtl/ap040_cache.v"
PINNED_SHA256 = "7cba7f73f6f7f16fa7a45d439af6a786bd55c3ef2a3f8c876b400e10d4fb7747"


def labels(path=RTL):
    import hashlib
    if hashlib.sha256(path.read_bytes()).hexdigest() != PINNED_SHA256:
        raise RuntimeError(f"cache RTL does not match pinned source: {path}")
    out = {}
    for declaration in re.findall(r"\blocalparam\s+([^;]+);", path.read_text()):
        for name, _width, value in re.findall(r"\b(C_[A-Z0-9_]+)\s*=\s*(\d+)'d(\d+)", declaration):
            out[int(value)] = name
    return out


if __name__ == "__main__":
    for ident, name in sorted(labels().items()):
        print(f"{ident}\t{name}")
