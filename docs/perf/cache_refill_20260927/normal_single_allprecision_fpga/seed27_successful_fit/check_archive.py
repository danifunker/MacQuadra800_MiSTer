#!/usr/bin/env python3
"""Verify the compact 55ff seed-27 FPGA evidence archive."""
import argparse
import hashlib
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parent
EXPECTED = {
    "source/ap040_fpu.v": "55ff9b3cd1d59069ec0b94ca17e4dc3a8c87ac031317902285444d92643724a2",
    "source/MacQuadra800.qsf": "9b6fa7c352dd7667339e6e6ec4f03a00d1894b7e7fce14908f8b57b99c059ec4",
    "source/MacQuadra800.sdc": "b2f5bd18b52d7897f711b7b1c465c6a5bd1fffa344275557761aba8f40929062",
}


def sha(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-tree", type=Path, help="verify all manifest paths under this project tree")
    args = parser.parse_args()
    errors = []

    sums = ROOT / "SHA256SUMS"
    if not sums.exists():
        errors.append("missing SHA256SUMS")
    else:
        for line in sums.read_text().splitlines():
            expected, rel = line.split("  ", 1)
            target = ROOT / rel
            if not target.is_file():
                errors.append(f"missing archive file: {rel}")
            elif sha(target) != expected:
                errors.append(f"archive checksum mismatch: {rel}")

    for rel, expected in EXPECTED.items():
        target = ROOT / rel
        if not target.is_file() or sha(target) != expected:
            errors.append(f"pinned source hash mismatch: {rel}")

    manifest = ROOT / "tracked_source_manifest.sha256"
    rows = manifest.read_text().splitlines() if manifest.exists() else []
    if len(rows) != 1892:
        errors.append(f"expected 1892 tracked inputs, found {len(rows)}")
    for rel in ("rtl/ap68040/rtl/ap040_fpu.v", "MacQuadra800.qsf", "MacQuadra800.sdc"):
        matches = [row.split("  ", 1)[0] for row in rows if row.endswith("  " + rel)]
        expected = {
            "rtl/ap68040/rtl/ap040_fpu.v": EXPECTED["source/ap040_fpu.v"],
            "MacQuadra800.qsf": EXPECTED["source/MacQuadra800.qsf"],
            "MacQuadra800.sdc": EXPECTED["source/MacQuadra800.sdc"],
        }[rel]
        if matches != [expected]:
            errors.append(f"manifest identity mismatch: {rel}")

    forbidden = []
    for path in ROOT.rglob("*"):
        if path.is_dir() and path.name in {"db", "incremental_db", "output_files"}:
            forbidden.append(str(path.relative_to(ROOT)))
        if path.is_file() and path.suffix.lower() in {".rbf", ".sof"}:
            forbidden.append(str(path.relative_to(ROOT)))
    if forbidden:
        errors.append("forbidden build artifact(s): " + ", ".join(forbidden))

    if args.source_tree:
        tree = args.source_tree.resolve()
        for row in rows:
            expected, rel = row.split("  ", 1)
            target = tree / rel
            if not target.is_file() or sha(target) != expected:
                errors.append(f"source-tree manifest mismatch: {rel}")

    if errors:
        print("FAIL")
        print("\n".join(f"- {error}" for error in errors))
        return 1
    print(f"PASS: archive checksums and pinned identities; {len(rows)} source manifest entries")
    if args.source_tree:
        print("PASS: all source-tree manifest entries")
    return 0


if __name__ == "__main__":
    sys.exit(main())
