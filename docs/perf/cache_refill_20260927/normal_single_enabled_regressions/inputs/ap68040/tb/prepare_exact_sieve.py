#!/usr/bin/env python3
"""Verify provenance and extract ONLY the unchanged original 80-byte loop."""
import argparse
import hashlib
from pathlib import Path

RESOURCE_SHA = "af67113bceb4eb906e973a9b747a0b1925b9d64c62f0f9a84bc6f0578839ca80"
KERNEL_SHA = "345defabade69898e7c3300557944301ea7a1dc5cd2b6472326c524e5bf8882a"
START, END = 0x630C7, 0x63117


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("resource", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    data = args.resource.read_bytes()
    if hashlib.sha256(data).hexdigest() != RESOURCE_SHA:
        parser.error("resource SHA-256 mismatch; do not extract an unverified variant")
    kernel = data[START:END]
    if len(kernel) != 80 or hashlib.sha256(kernel).hexdigest() != KERNEL_SHA:
        parser.error("kernel byte identity mismatch")
    args.output.write_bytes(kernel)
    print(f"EXACT_SIEVE file=[0x{START:x},0x{END:x}) bytes=80 sha256={KERNEL_SHA}")


if __name__ == "__main__":
    main()
