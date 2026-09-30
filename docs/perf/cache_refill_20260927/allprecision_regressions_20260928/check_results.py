#!/usr/bin/env python3
"""Portable standard-library checker for archived paired regression outputs."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import sys

TARGETS = ("fpu", "fpu_frames", "fpu_resume", "mmu", "exceptions", "fpu_normalize")
PROGRAM_TARGETS = set(TARGETS) - {"fpu_normalize"}
FAIL = re.compile(r"FATAL|TEST FAILED|FAIL:|ERROR:")


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("results", type=Path, help="directory containing result.json and baseline/candidate logs")
    args = parser.parse_args()
    root = args.results.resolve()
    result = json.loads((root / "result.json").read_text())
    assert result["simulation_status"] == "PASS"
    assert result["immutable_inputs_revalidated"] == 100
    assert set(result["targets"]) == {"baseline", "candidate"}
    for variant in ("baseline", "candidate"):
        tests = result["targets"][variant]
        assert set(tests) == set(TARGETS), (variant, tests.keys())
        for target in TARGETS:
            entry = tests[target]
            assert entry["status"] == "PASS", (variant, target, entry)
            log = root / variant / (target + ".log")
            assert log.is_file(), log
            content = log.read_text(errors="replace")
            assert "ALL TESTS PASSED" in content, (variant, target, "missing terminal pass")
            assert not FAIL.search(content), (variant, target, "failure marker")
            assert sha256(log) == entry["log_sha256"], (variant, target, "log checksum")
            if target in PROGRAM_TARGETS:
                phases = re.findall(r"phase (\d) passed \((\d+) cycles\)", content)
                assert [int(p[0]) for p in phases] == [0, 1, 2], (variant, target, phases)
                assert {p: int(c) for p, c in phases} == entry["bus_phase_cycles"], (variant, target, "cycle summary")
            else:
                assert entry["bus_phase_cycles"] == {}, (variant, target, "unexpected bus phase counters")
            assert (root / variant / "compile.log").is_file()
            assert (root / variant / "normalize_compile.log").is_file()
    print("PASS: 12 terminal targets; logs, failure markers, bus phases, and result hashes verified")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        raise SystemExit(1)
