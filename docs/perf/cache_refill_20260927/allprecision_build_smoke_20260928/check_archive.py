#!/usr/bin/env python3
"""Portable checker for the compact 55ff build/smoke archive."""
from pathlib import Path
import hashlib
import json
import sys

FORBIDDEN_SUFFIXES = {".hda", ".vvp", ".o", ".a", ".so", ".rom", ".hex", ".bin", ".fst", ".vcd"}


def sha(path):
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def readj(root, rel):
    return json.loads((root / rel).read_text())


def main(root):
    root = root.resolve()
    sums = root / "SHA256SUMS"
    entries = {}
    for n, line in enumerate(sums.read_text().splitlines(), 1):
        digest, rel = line.split("  ", 1)
        if rel in entries or Path(rel).is_absolute() or ".." in Path(rel).parts:
            raise ValueError(f"bad checksum manifest row {n}")
        entries[rel] = digest
    actual = {p.relative_to(root).as_posix() for p in root.rglob("*") if p.is_file() and p != sums}
    assert set(entries) == actual, ("archive file set", sorted(actual ^ set(entries)))
    for rel, digest in entries.items():
        assert sha(root / rel) == digest, rel
    forbidden = [str(p.relative_to(root)) for p in root.rglob("*") if p.is_file() and p.suffix.lower() in FORBIDDEN_SUFFIXES]
    assert not forbidden, f"forbidden build payloads copied: {forbidden}"
    assert not any(p.name in {"ccache", "obj_dir", "fpu_run"} for p in root.rglob("*")), "generated/live run directory copied"

    freeze = readj(root, "source/freeze_identity.json")
    build_meta = readj(root, "build/build.meta.json")
    build_id = readj(root, "build/completed_build_identity.json")
    ready = readj(root, "build/launch_ready_identity.json")
    source_manifest = root / "source/source_manifest.sha256"
    assert sha(source_manifest) == freeze["manifest_sha256"] == build_meta["source_manifest_sha256"] == build_id["source_manifest_sha256"] == ready["source_manifest_sha256"]
    assert freeze["candidate_fpu"] == build_id["candidate_sha256"] == "55ff9b3cd1d59069ec0b94ca17e4dc3a8c87ac031317902285444d92643724a2"
    assert sha(root / "source/rtl/ap68040/rtl/ap040_fpu.v") == freeze["candidate_fpu"]
    assert build_meta["status"] == "PASS" and build_meta["before_manifest"] == build_meta["after_manifest"] == "PASS"
    assert [c["exit_status"] for c in build_meta["commands"]] == [0, 0]
    assert build_id["status"] == "PASS" and build_id["binary_sha256"] == "fc196b28762c249c6af8820326a1c4689f9ac99e30350160a70091eac8464a4d"
    assert sha(root / "build/build.log") == build_id["build_log_sha256"]
    assert ready["status"] == "READY_FOR_ROOT_LAUNCH_REVIEW_NO_FULLGUEST_STARTED"
    assert ready["completed_build_identity_sha256"] == sha(root / "build/completed_build_identity.json")

    host = readj(root, "host_tests/host_checks.json")
    assert host["status"] == "PASS" and host["output"].startswith("PASS guard observer")
    assert host["mapping_scope"] == "prior generated header only, not55ff full-model build"
    assert sha(root / "source/verilator/sim_fpu_guard_profile.h") == build_id["observer_sha256"]
    assert sha(root / "host_tests/sim_fpu_guard_profile_test.cpp").startswith("a6b59600")

    smoke = readj(root, "smoke2/meta.json")
    assert smoke["status"] == "PASS" and smoke["child_terminal"] and smoke["exit_status"] == 0
    assert smoke["check0"] == smoke["check1"] == 0 and smoke["source_manifest_postrun"] == "PASS"
    assert smoke["scope"] == "new generated model short disk-free smoke, not benchmark or guest guard coverage"
    assert smoke["binary_sha256"] == build_id["binary_sha256"]
    assert "+rom=rom.hex" in smoke["argv"]
    assert sha(root / "smoke2/meta.json") == ready["smoke2_meta_sha256"]
    c0 = (root / "smoke2/check0.log").read_text()
    c1 = (root / "smoke2/check1.log").read_text()
    assert "edges 100002 raw 0" in c1 and "PASS observer report" in c1
    assert "fill=620 tagwrite=62 completed=62" in c0
    assert "readmem file not found" not in (root / "smoke2/run.log").read_text()

    invalid = readj(root, "invalid_smoke1/meta.json")
    assert invalid["status"] == "INVALID_ROM_PATH_TRUNCATION" and invalid["exit_status"] == 0 and invalid["check0"] == 1
    bad_run = (root / "invalid_smoke1/run.log").read_text()
    bad_check = (root / "invalid_smoke1/check0.log").read_text()
    assert "file not found" in bad_run and "unqualified empty refill profile" in bad_check
    print("PASS: archive hashes, build, host observer tests, corrected integration smoke, and invalid prior smoke verified")


if __name__ == "__main__":
    try:
        if len(sys.argv) != 2:
            raise SystemExit("usage: check_archive.py ARCHIVE_DIR")
        main(Path(sys.argv[1]))
    except Exception as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        raise SystemExit(1)
