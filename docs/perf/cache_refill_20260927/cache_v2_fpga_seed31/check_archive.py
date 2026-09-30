#!/usr/bin/env python3
"""Validate compact cache-v2 seed-31 FPGA evidence and scratch provenance."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import re
import sys


ARCHIVE = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent
REPO = Path(__file__).resolve().parents[4]
SCRATCH = REPO / "scratch/cache_xline_first_fill_quartus_seed31_20260928"
BASE_SCRATCH = REPO / "scratch/fpu_normal_single_enabled_quartus_20260928_seed31"


def need(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("FAIL: " + message)


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load_json(rel: str) -> dict:
    return json.loads((ARCHIVE / rel).read_text())


ORIGINALS = {
    "manifests/base_seed31_manifest.sha256": SCRATCH / "base_seed31_manifest.sha256",
    "manifests/candidate_source_manifest.sha256": SCRATCH / "source_manifest.sha256",
    "provenance/candidate_cache.diff": SCRATCH / "candidate_cache.diff",
    "provenance/preparation_identity.json": SCRATCH / "preparation_identity.json",
    "provenance/full_terminal_identity.json": SCRATCH / "full_terminal_identity.json",
    "provenance/full_process_identity.json": SCRATCH / "full_process_identity.json",
    "provenance/source_postrun_identity.json": SCRATCH / "source_postrun_identity.json",
    "provenance/cross_domain_identity.json": SCRATCH / "cross_domain_identity.json",
    "provenance/ram_path_identity.json": SCRATCH / "ram_path_identity.json",
    "reports/map.summary": SCRATCH / "tree/output_files/MacQuadra800.map.summary",
    "reports/fit.summary": SCRATCH / "tree/output_files/MacQuadra800.fit.summary",
    "reports/sta.summary": SCRATCH / "tree/output_files/MacQuadra800.sta.summary",
    "reports/full_sta.rpt": SCRATCH / "tree/output_files/MacQuadra800.sta.rpt",
    "reports/cross_sys2ram.txt": SCRATCH / "tree/scratch/cross_sys2ram_cache_xline_v2_seed31_20260928.txt",
    "reports/cross_ram2sys.txt": SCRATCH / "tree/scratch/cross_ram2sys_cache_xline_v2_seed31_20260928.txt",
    "reports/ram_worst_paths.txt": SCRATCH / "tree/scratch/ram_timing_6c_seed31_20260928/worst_paths.txt",
    "reports/ram_worst_detail.txt": SCRATCH / "tree/scratch/ram_timing_6c_seed31_20260928/worst_detail.txt",
    "reports/baseline_6c_seed31_sta.rpt": BASE_SCRATCH / "tree/output_files/MacQuadra800.sta.rpt",
}


def parse_manifest(rel: str) -> dict[str, str]:
    result: dict[str, str] = {}
    for line in (ARCHIVE / rel).read_text().splitlines():
        digest, path = line.split("  ", 1)
        need(re.fullmatch(r"[0-9a-f]{64}", digest) is not None, "bad source digest")
        need(path not in result, "duplicate source manifest path")
        result[path] = digest
    return result


def port_list(report: Path, title: str, kind: str) -> list[str]:
    lines = report.read_text(errors="replace").splitlines()
    # The actual port table has the title, divider, column header, divider.
    # Summary rows share a title but do not have this sequence.
    title_index = None
    for i, line in enumerate(lines):
        if line.startswith("; " + title) and i + 2 < len(lines):
            if kind in lines[i + 2] and lines[i + 1].startswith("+"):
                title_index = i
                break
    need(title_index is not None, "missing STA port list " + title)
    values = []
    for line in lines[title_index + 1 :]:
        if values and line.startswith("+"):
            break
        m = re.match(r";\s*([^;]+?)\s*;\s*(?:No input delay|No output delay|Partially constrained)", line)
        if m:
            values.append(m.group(1).strip())
    return values


def sdc_warnings(report: Path) -> list[str]:
    values = []
    for line in report.read_text(errors="replace").splitlines():
        if "Warning (" not in line or not (".sdc(" in line):
            continue
        values.append(re.sub(r" File: .*", "", line))
    return values


# Check archive checksum inventory (everything except the checksum file itself).
checksums: dict[str, str] = {}
for line in (ARCHIVE / "SHA256SUMS").read_text().splitlines():
    digest, rel = line.split("  ", 1)
    need(re.fullmatch(r"[0-9a-f]{64}", digest) is not None, "bad archive checksum")
    need(rel not in checksums, "duplicate archive checksum entry")
    checksums[rel] = digest
actual = {
    p.relative_to(ARCHIVE).as_posix()
    for p in ARCHIVE.rglob("*")
    if p.is_file() and p.name != "SHA256SUMS"
}
need(actual == set(checksums), "archive checksum inventory mismatch")
for rel, digest in checksums.items():
    need(sha(ARCHIVE / rel) == digest, "archive checksum mismatch: " + rel)

# Prove every copied raw file still matches the scratch original byte-for-byte.
for rel, original in ORIGINALS.items():
    need(original.is_file(), "missing comparison original: " + str(original))
    need((ARCHIVE / rel).read_bytes() == original.read_bytes(), "original copy mismatch: " + rel)

# The copied manifests identify all inputs and establish a one-file cache delta.
base = parse_manifest("manifests/base_seed31_manifest.sha256")
candidate = parse_manifest("manifests/candidate_source_manifest.sha256")
need(len(base) == len(candidate) == 1892 and set(base) == set(candidate), "source manifest inventory")
delta = [path for path in base if base[path] != candidate[path]]
need(delta == ["rtl/ap68040/rtl/ap040_cache.v"], "candidate must change only ap040_cache.v")
src = load_json("provenance/source_identity.json")
need(src["source_entries"] == 1892 and src["changed_paths"] == delta, "source identity delta")
need(src["candidate_manifest_sha256"] == sha(ARCHIVE / "manifests/candidate_source_manifest.sha256"), "candidate manifest identity")
need(src["base_manifest_sha256"] == sha(ARCHIVE / "manifests/base_seed31_manifest.sha256"), "base manifest identity")
need(src["baseline_cache_sha256"] == base[delta[0]], "baseline cache identity")
need(src["candidate_cache_sha256"] == candidate[delta[0]] == "9e8c0582db1b0bb88428e56fec63e99029b61faffac62c6f3dda9326b5191481", "candidate cache identity")
need(src["candidate_fpu_sha256"] == candidate["rtl/ap68040/rtl/ap040_fpu.v"], "preserved FPU identity")
need(src["qsf_sha256"] == candidate["MacQuadra800.qsf"] and src["sdc_sha256"] == candidate["MacQuadra800.sdc"], "QSF/SDC identity")
need(src["qsf_seed"] == 31, "QSF seed")

prep = load_json("provenance/preparation_identity.json")
need(prep["source_entries"] == 1892 and prep["changed_source_paths"] == delta, "preparation identity")
terminal = load_json("provenance/full_terminal_identity.json")
need(terminal["wrapper_exit"] == terminal["quartus_flow_exit"] == 0 and terminal["quartus_full_compile"] == "successful", "terminal fit state")
need(terminal["postrun_manifest_entries"] == 1892 and terminal["postrun_source_mismatches"] == 0, "terminal source check")
artifacts = {item["artifact"]: item for item in terminal["key_files_and_artifacts"] if "artifact" in item}
need(artifacts["MacQuadra800.rbf"] == {"artifact":"MacQuadra800.rbf","size_bytes":4440380,"sha256":"85db1130b61fa21eb4129c41b032d23c26ec3407f94dc283b3c3eb14eebcabe7"}, "RBF metadata")
need(artifacts["MacQuadra800.sof"] == {"artifact":"MacQuadra800.sof","size_bytes":6690368,"sha256":"cfcd19b624b5b043ae306cc6e42beebc33ca948eeb05342630808639093a7c6a"}, "SOF metadata")
post = load_json("provenance/source_postrun_identity.json")
need(post["entries"] == 1892 and post["mismatch_count"] == 0, "postrun source check")

# Resource and slack checks are derived from the preserved original reports.
fit = (ARCHIVE / "reports/fit.summary").read_text()
for value in ("38,760 / 41,910", "Total registers : 24659", "3,389,411 / 5,662,720", "468 / 553", "Total DSP Blocks : 36", "Total PLLs : 4 / 6"):
    need(value in fit, "fit resource summary: " + value)
sta = (ARCHIVE / "reports/sta.summary").read_text()
for value in ("Slack : 0.623", "Slack : 0.693", "Slack : 0.206", "Slack : 0.226"):
    need(value in sta, "STA summary slack: " + value)

cross_a = (ARCHIVE / "reports/cross_sys2ram.txt").read_text()
cross_b = (ARCHIVE / "reports/cross_ram2sys.txt").read_text()
need(len(re.findall(r"^;\s*[+-]?\d+\.\d+\s*;", cross_a, re.M)) == 6, "system-to-RAM six paths")
need(len(re.findall(r"^;\s*[+-]?\d+\.\d+\s*;", cross_b, re.M)) == 6, "RAM-to-system six paths")
need("; 0.712 ;" in cross_a and "; 0.759 ;" in cross_b, "cross-domain worst slack")
ram = (ARCHIVE / "reports/ram_worst_paths.txt").read_text()
need(len(re.findall(r"^;\s*[+-]?\d+\.\d+\s*;", ram, re.M)) == 12, "RAM 12-path summary")
need("; 0.693 ;" in ram and "Found 3 setup paths (0 violated)" in (ARCHIVE / "reports/ram_worst_detail.txt").read_text(), "RAM detailed-path report")

# Compare complete full-chip STA unconstrained-port lists and SDC warnings to
# the matched seed-31 baseline, including the unconstrained SDRAM DQ interface.
candidate_sta = ARCHIVE / "reports/full_sta.rpt"
baseline_sta = ARCHIVE / "reports/baseline_6c_seed31_sta.rpt"
for title, kind, expected in (("Unconstrained Input Ports", "Input Port", 26), ("Unconstrained Output Ports", "Output Port", 90)):
    c_list = port_list(candidate_sta, title, kind)
    b_list = port_list(baseline_sta, title, kind)
    need(len(c_list) == len(b_list) == expected and c_list == b_list, "baseline/candidate " + title + " mismatch")
    need(any(p.startswith("SDRAM_DQ[") for p in c_list), "SDRAM_DQ absent from unconstrained port list")
need("; Unconstrained Clocks            ; 0     ; 0    ;" in candidate_sta.read_text(), "unconstrained clocks count")
need(sdc_warnings(candidate_sta) == sdc_warnings(baseline_sta) and len(sdc_warnings(candidate_sta)) == 8, "normalized SDC warning comparison")

# Binary and Quartus working artifacts must be excluded from the archive.
for path in ARCHIVE.rglob("*"):
    if not path.is_file():
        continue
    lower = path.name.lower()
    need(lower not in {"macquadra800.rbf", "macquadra800.sof", "local.env"}, "binary/private file included")
    need(path.suffix.lower() not in {".qdb", ".cdb", ".hdb", ".pyc"}, "generated/cache file included")
    need("/db/" not in ("/" + path.relative_to(ARCHIVE).as_posix().lower()), "database included")

print(f"PASS archive_files={len(checksums)} source_inputs=1892 sole_delta=ap040_cache.v fit=0 cross=6+6 RAM=12 unconstrained_ports=26+90 binary/database_omitted")
