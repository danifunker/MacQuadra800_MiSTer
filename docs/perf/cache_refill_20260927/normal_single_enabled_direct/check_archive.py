#!/usr/bin/env python3
"""Portable integrity and result check for the enabled normal FMOVE.S archive."""
from difflib import unified_diff
import hashlib
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parent
BASE_SHA = "2d53db3ae4a04310add04eeb7919f0219197a98827ed92e410e6d4a4a90f5465"
CAND_SHA = "6c157b3bc045e74a90416f4764f35cf65024e77577019a100b8aa9b5bdd9ce9b"


def sha(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def fail(message):
    print(f"FAIL: {message}")
    return 1


def main():
    sums = ROOT / "SHA256SUMS"
    if not sums.is_file():
        return fail("missing SHA256SUMS")
    entries = {}
    for line in sums.read_text().splitlines():
        expected, rel = line.split("  ", 1)
        path = (ROOT / rel).resolve()
        if ROOT not in path.parents or rel in entries:
            return fail(f"unsafe or duplicate manifest path: {rel}")
        if not path.is_file() or sha(path) != expected:
            return fail(f"archive checksum mismatch: {rel}")
        entries[rel] = expected

    actual_files = {str(path.relative_to(ROOT)) for path in ROOT.rglob("*")
                    if path.is_file() and path.name != "SHA256SUMS"}
    if set(entries) != actual_files:
        return fail("SHA256SUMS does not cover the complete archive file set")

    for path in ROOT.rglob("*"):
        if path.is_file() and path.suffix.lower() in {".vvp", ".rbf", ".sof"}:
            return fail(f"unexpected compiled/programming binary: {path.relative_to(ROOT)}")

    expected_sources = {
        "source/production_2d53_ap040_fpu.v": BASE_SHA,
        "source/candidate_6c157b3_ap040_fpu.v": CAND_SHA,
        "test_inputs/MacQuadra800.qsf": "75c69f933515f05c729076108b26515f3f6aff84a36692fdd58d2f95077fe1fd",
        "test_inputs/ap040_defs.svh": "195c37afb9961a1baf8c6ebbdba8df53da97d93c5cb4924cf673a3e9dc065a81",
    }
    for rel, expected in expected_sources.items():
        if entries.get(rel) != expected:
            return fail(f"pinned input hash mismatch: {rel}")

    baseline = (ROOT / "source/production_2d53_ap040_fpu.v").read_text().splitlines(keepends=True)
    candidate = (ROOT / "source/candidate_6c157b3_ap040_fpu.v").read_text().splitlines(keepends=True)
    expected_delta = list(unified_diff(baseline, candidate, n=3))[2:]
    saved_delta = (ROOT / "source/production_to_candidate.diff").read_text().splitlines(keepends=True)[2:]
    if expected_delta != saved_delta:
        return fail("stored source delta does not match archived RTL pair")

    qualification = json.loads((ROOT / "qualification.json").read_text())
    if qualification != {
        "status": "PASS",
        "excluded_and_restore_signatures": 36,
        "baseline": "PASS normal_single checks=97834 normal=97795 fast=0 slow=97830",
        "candidate": "PASS normal_single checks=97834 normal=97795 fast=97795 slow=35",
    }:
        return fail("qualification result metadata differs from expected run")

    baseline_log = (ROOT / "logs/baseline.run.log").read_text()
    candidate_log = (ROOT / "logs/candidate.run.log").read_text()
    for label, content in (("baseline", baseline_log), ("candidate", candidate_log)):
        if "$fatal" in content or "ERROR:" in content:
            return fail(f"failure marker in {label} run log")
        if not re.search(r"^" + re.escape(qualification[label]) + r"$", content, re.M):
            return fail(f"PASS summary missing from {label} log")
    baseline_sigs = [line for line in baseline_log.splitlines() if line.startswith("SIG")]
    candidate_sigs = [line for line in candidate_log.splitlines() if line.startswith("SIG")]
    if len(baseline_sigs) != 36 or baseline_sigs != candidate_sigs:
        return fail("excluded/restore signatures do not match exactly (36 expected)")

    print(f"PASS: {len(entries)} archive files verified; RTL pair/delta and 36 matching signatures validated")
    return 0


if __name__ == "__main__":
    sys.exit(main())
