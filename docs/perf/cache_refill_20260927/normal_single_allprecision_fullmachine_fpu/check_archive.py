#!/usr/bin/env python3
"""Verify compact terminal 55ff FPU evidence without launching a simulator."""
from pathlib import Path
import hashlib
import json
import subprocess
import sys


def sha(path):
    h = hashlib.sha256()
    with Path(path).open("rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def verify_observer(path):
    rows = [line.split("\t") for line in path.read_text().splitlines() if line]
    summary_rows = [r for r in rows if r[0] == "SUMMARY" and len(r) > 1 and r[1].isdigit()]
    enabled_rows = [r for r in rows if r[0] == "ENABLED_CYCLES" and len(r) > 1 and r[1].isdigit()]
    guard_rows = [r for r in rows if r[0] == "FPU_GUARD_SUMMARY" and len(r) > 1 and r[1].isdigit()]
    buckets = [list(map(int, r[1:])) for r in rows if r[0] == "FPU_GUARD_BUCKET" and len(r) > 1 and r[1].isdigit()]
    side = [list(map(int, r[1:])) for r in rows if r[0] == "FPU_GUARD_REJECT_SIDE" and len(r) > 1 and r[1].isdigit()]
    assert len(summary_rows) == len(enabled_rows) == len(guard_rows) == 1
    assert len(buckets) == 2 and len(side) == 8
    clocks = int(summary_rows[0][1])
    assert list(map(int, enabled_rows[0][1:4])) == [clocks, clocks, clocks]
    g = list(map(int, guard_rows[0][1:]))
    edges, raw, restore, pending, unexpected, enable_reject, dropped, rounds, mismatch, reconciles = g
    assert edges == clocks and reconciles == 1 and mismatch == 0
    assert restore == pending == unexpected == 0 and sum(r[1] for r in side) == 0
    # Bucket schema after removing the tag: precision,enables,raw,single,zero,normal,allones,old,new.
    assert sum(r[2] for r in buckets) == raw
    normal = sum(r[5] for r in buckets)
    old = sum(r[7] for r in buckets)
    new = sum(r[8] for r in buckets)
    assert rounds == old == new == 930
    assert normal == 5_347_864
    assert enable_reject == 5_346_934
    assert raw == 11_666_052
    assert sorted(buckets) == sorted([
        [0, 0, 140224, 930, 0, 930, 0, 930, 930],
        [0, 32, 11525828, 5584580, 237646, 5346934, 0, 0, 0],
    ])
    assert (edges, raw, normal, old, new, enable_reject) == (1_304_100_000, 11_666_052, 5_347_864, 930, 930, 5_346_934)


def main(root):
    root = root.resolve()
    sums = root / "archive_manifest.sha256"
    entries = {}
    for line in sums.read_text().splitlines():
        digest, rel = line.split("  ", 1)
        assert rel not in entries
        entries[rel] = digest
    actual = {p.relative_to(root).as_posix() for p in root.rglob("*") if p.is_file() and p != sums}
    assert set(entries) == actual, sorted(actual ^ set(entries))
    for rel, digest in entries.items():
        assert sha(root / rel) == digest, rel
    forbidden = {".hda", ".vvp", ".o", ".a", ".so", ".rom", ".hex", ".bin", ".fst", ".vcd"}
    assert not [p.name for p in root.rglob("*") if p.is_file() and p.suffix.lower() in forbidden]
    assert max(p.stat().st_size for p in root.rglob("*") if p.is_file()) < 2_000_000

    meta = json.loads((root / "result/run.meta.json").read_text())
    build = json.loads((root / "provenance/completed_build_identity.json").read_text())
    freeze = json.loads((root / "provenance/freeze_identity.json").read_text())
    prep = json.loads((root / "provenance/preparation_identity.json").read_text())
    result = json.loads((root / "result/comparison.json").read_text())
    source_manifest = root / "provenance/source_manifest.sha256"
    assert sha(source_manifest) == "cd794af982858ddbb3f116345bf9dd301111897c73c575a343f6283ccc58ab0f"
    assert sha(source_manifest) == freeze["manifest_sha256"] == build["source_manifest_sha256"] == meta["source_manifest_sha256"]
    assert build["candidate_sha256"] == freeze["candidate_fpu"] == "55ff9b3cd1d59069ec0b94ca17e4dc3a8c87ac031317902285444d92643724a2"
    assert sha(root / "source/candidate_fpu.v") == build["candidate_sha256"]
    assert sha(root / "source/sim_fpu_guard_profile.h") == build["observer_sha256"]
    assert sha(root / "source/baseline_fpu.v") == "2d53db3ae4a04310add04eeb7919f0219197a98827ed92e410e6d4a4a90f5465"
    assert "fpcr[7:6] == 2'b00" in (root / "source/55ff_vs_73bc.diff").read_text()
    assert build["status"] == "PASS" and meta["status"] == "EXIT0_REFILL_OBSERVER_PASS_PENDING_SCREENSHOT_REVIEW"
    assert meta["exit_status"] == meta["refill_check_exit_status"] == meta["observer_check_exit_status"] == 0
    assert meta["child_terminal"] and meta["postrun_source_manifest"] == "PASS"
    assert meta["binary_sha256"] == meta["running_exe_sha256"] == build["binary_sha256"]
    assert meta["build_identity_sha256"] == sha(root / "provenance/completed_build_identity.json")
    assert meta["supervisor_sha256"] == sha(root / "provenance/run_fpu.py")
    assert meta["observer_checker_sha256"] == sha(root / "provenance/check_guard_report.py")
    assert meta["control_sha256"] == sha(root / "result/control.txt")
    assert meta["golden_input_disk_sha256"] == "80d8479430a66edae161c2bac6a9563dbb4f6bd0f564ee7849a555c447df8888"
    assert prep["candidate_fpu"] == build["candidate_sha256"]
    assert prep["original_manifest"] == sha(root / "provenance/original73bc_source_manifest.sha256") == "c528f7e7e9030de959dd5c8adddb239c3727abb5895a2285f9b35c04de243810"

    # Re-run only the copied host report checkers against the archived TSV.
    subprocess.run([sys.executable, str(root / "provenance/check_refill_report.py"), str(root / "result/refill.tsv")], check=True, capture_output=True, text=True)
    subprocess.run([sys.executable, str(root / "provenance/check_guard_report.py"), str(root / "result/refill.tsv")], check=True, capture_output=True, text=True)
    verify_observer(root / "result/refill.tsv")
    assert (root / "result/refill_check.log").read_text().startswith("refill report reconciles: fill=359097836 tagwrite=35471601 completed=35471601")
    assert (root / "result/observer_check.log").read_text().startswith("PASS observer report edges 1304100000 raw 11666052 normal 5347864 old 930 new 930 post_mismatch 0")
    assert (root / "result/exit_status.txt").read_text().strip() == "0"

    terminal = result["terminal_result"]
    assert terminal["tests_done"] and terminal["iterations"] == [1, 1, 1]
    assert terminal["aggregate_rating"] == 0.698
    assert (root / "result/fpu_setup.png").is_file() and (root / "result/fpu_done.png").is_file()
    review = json.loads((root / "result/review.json").read_text())
    assert review["status"] == "PASS_VISUALLY_REVIEWED" and review["screenshot"] == "fpu_done.png"
    assert "does not OCR" in review["method"]
    assert result["observer_full_window"]["edges"] == 1_304_100_000
    assert "not subtest attribution" in result["scope"]
    print("PASS: archive hashes, terminal guest metadata, refill report, and full-window observer totals")


if __name__ == "__main__":
    try:
        if len(sys.argv) != 2:
            raise SystemExit("usage: check_archive.py ARCHIVE_DIR")
        main(Path(sys.argv[1]))
    except Exception as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        raise SystemExit(1)
