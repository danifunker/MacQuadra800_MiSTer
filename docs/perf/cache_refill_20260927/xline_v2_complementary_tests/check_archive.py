#!/usr/bin/env python3
"""Portable integrity and terminal-result checks for the archived v2 cache tests."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import sys


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def need(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"FAIL: {message}")


def main() -> None:
    root = Path(sys.argv[1] if len(sys.argv) == 2 else ".").resolve()
    sums = root / "SHA256SUMS"
    expected: dict[str, str] = {}
    for line in sums.read_text().splitlines():
        digest, rel = line.split("  ", 1)
        need(rel not in expected, f"duplicate checksum path: {rel}")
        expected[rel] = digest
    actual = {p.relative_to(root).as_posix() for p in root.rglob("*")
              if p.is_file() and p != sums}
    need(actual == set(expected),
         f"archive file set differs (unlisted={sorted(actual-set(expected))}, "
         f"missing={sorted(set(expected)-actual)})")
    for rel, digest in expected.items():
        need(sha(root / rel) == digest, f"checksum mismatch: {rel}")

    # Every scratch-origin artifact copied into the package must have an
    # independently checkable destination hash.
    maprows = [line.split("\t", 2) for line in
               (root / "COPY_MAP.tsv").read_text().splitlines()]
    need(maprows and all(len(row) == 3 for row in maprows), "malformed COPY_MAP.tsv")
    mapped = set()
    for origin, dest, digest in maprows:
        need(dest not in mapped, f"duplicate copy-map destination: {dest}")
        mapped.add(dest)
        need(dest in expected and expected[dest] == digest,
             f"copy map does not match manifest: {dest}")
        need((root / dest).is_file(), f"copy missing: {dest}")
        need(sha(root / dest) == digest, f"copy hash mismatch: {origin}")

    identity = json.loads((root / "provenance/source_identity.json").read_text())
    need(identity["baseline_cache_sha256"] ==
         "7cba7f73f6f7f16fa7a45d439af6a786bd55c3ef2a3f8c876b400e10d4fb7747",
         "unexpected baseline cache identity")
    need(identity["candidate_cache_sha256"] ==
         "9e8c0582db1b0bb88428e56fec63e99029b61faffac62c6f3dda9326b5191481",
         "unexpected candidate cache identity")
    need(identity["sole_RTL_delta"] == ["ap68040/rtl/ap040_cache.v"] and
         identity["all_other_RTL_equal"] is True and
         identity["cache_SETW"] == 7, "paired RTL identity changed")
    need(sha(root / "sources/tb_ap040_cache_xstore.sv") ==
         "d928fab7e4706454a7c2ae20c1d8f8b2528b9e5ea3990dcfce6e7e22a6042cc8",
         "XSTORE bench source changed")
    need(sha(root / "sources/dpram.v") ==
         "0b5fd0869d29374cb01f084ad545b4250efe303a366bd7b274e163a145363ba6",
         "RAM primitive source changed")
    need(sha(root / "posted_corrected/tb_cache_posted_read_matrix.sv") ==
         "504809e99acfa796150c63bb153e8903db697a460889e15f4ea02d8e0839493f",
         "corrected posted test source changed")
    need(sha(root / "posted_failed_attempt/original_tb_cache_posted_read_matrix.sv") ==
         "5f2271a5451978a64a6ceb0bf04dee292c79eec2116004d2fe174786d9c5c5c9",
         "original failed posted test source changed")

    original_manifest = root / "provenance/original_input_manifest.sha256"
    need(sha(original_manifest) ==
         "23937433536945689927de234649d8e1e8e5d556e05ad9d97d953b7ca7dbc25f",
         "original input manifest copy changed")
    need(sha(root / "posted_corrected/adapter.diff") ==
         "2f96f9c446f87dfa72124bb949ea2246b3ebcf2b53873c0059b34184385643ad",
         "reviewed adapter diff changed")

    # Verify the original failed attempt accurately and keep it disjoint from
    # the corrected pair's successful outcomes.
    first = json.loads((root / "xstore/initial_attempt_metadata.json").read_text())
    need(first["status"] == "FAILED", "initial combined-run status changed")
    need(first["input_manifest_sha256"] == sha(original_manifest),
         "initial run input manifest identity mismatch")
    steps = {s["name"]: s for s in first["steps"]}
    need(steps["baseline_xstore_run"]["exit_status"] == 0 and
         steps["baseline_xstore_run"]["terminal"] is True,
         "baseline XSTORE terminal record changed")
    need(steps["baseline_posted_run"]["exit_status"] == 1 and
         steps["baseline_posted_run"]["terminal"] is True and
         "candidate_posted_run" not in steps,
         "initial posted failure provenance changed")
    failed_log = (root / "posted_failed_attempt/baseline_posted_run.log").read_text()
    need("read acknowledged before posted store left PASS" in failed_log,
         "initial posted failure signature missing")
    xstore_old_log = (root / "xstore/baseline_xstore_run.log").read_text()
    need("XSTORE PASS cases=100" in xstore_old_log and
         "ALL TESTS PASSED" in xstore_old_log,
         "baseline XSTORE result missing")

    cand_x = json.loads((root / "xstore/candidate_metadata.json").read_text())
    need(cand_x["status"] == "PASS_XSTORE_COMPLEMENTARY" and
         cand_x["candidate_cache_sha256"] == identity["candidate_cache_sha256"] and
         cand_x["postrun_source"] == "PASS" and
         cand_x["existing_manifest_sha256"] == sha(original_manifest) and
         cand_x["recipe_sha256"] == sha(root / "xstore/run_candidate_xstore.py"),
         "candidate XSTORE metadata invalid")
    cand_x_steps = {s["name"]: s for s in cand_x["steps"]}
    need(all(cand_x_steps[name]["exit_status"] == 0 and
             cand_x_steps[name]["terminal"] is True for name in ("build", "run")),
         "candidate XSTORE child status invalid")
    xstore_new_log = (root / "xstore/run.log").read_text()
    need("XSTORE PASS cases=100" in xstore_new_log and
         "ALL TESTS PASSED" in xstore_new_log,
         "candidate XSTORE result missing")

    posted = json.loads((root / "posted_corrected/metadata.json").read_text())
    need(posted["status"] == "PASS_POSTED_CONTRACT_PAIR" and
         posted["postrun_sources"] == "PASS" and
         posted["existing_RTL_manifest_sha256"] == sha(original_manifest) and
         posted["recipe_sha256"] == sha(root / "posted_corrected/run.py"),
         "corrected posted pair status invalid")
    need(posted["baseline"]["cases"] == 216 and
         posted["candidate"]["cases"] == 216, "posted case totals changed")
    for variant in ("baseline", "candidate"):
        result = posted[variant]
        need((result["pending"], result["prepared"], result["early_disjoint_acks"]) ==
             (816, 816, 30), f"posted {variant} counters changed")
        runlog = (root / f"posted_corrected/{variant}_run.log").read_text()
        need("POSTED_MATRIX PASS cases=216 pending=816 prepared=816 early_disjoint_acks=30"
             in runlog and "FATAL:" not in runlog and "FAIL" not in runlog,
             f"posted {variant} result missing")
    for step in posted["steps"]:
        need(step["terminal"] is True and step["exit_status"] == 0,
             f"posted child not successful: {step['name']}")

    # Preserve, and verify, the original 3-file manifest for the corrected
    # source package using its original relative names.
    for line in (root / "posted_corrected/manifest.sha256").read_text().splitlines():
        digest, name = line.split("  ", 1)
        need(sha(root / "posted_corrected" / name) == digest,
             f"original posted manifest check failed: {name}")

    print("PASS xline v2 complementary archive checks")
    print("PASS XSTORE: baseline/candidate 100 cases each")
    print("PASS corrected posted matrix: 216 cases each, 816 pending/prepared each")
    print("PASS earlier blanket posted assertion retained as separate baseline failure")


if __name__ == "__main__":
    need(len(sys.argv) == 2, "usage: check_archive.py ARCHIVE_DIR")
    main()
