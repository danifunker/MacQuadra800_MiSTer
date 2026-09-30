#!/usr/bin/env python3
"""Run the six existing paired FPU/fullcore regressions after review approval."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import shutil
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parent
INPUTS = ROOT / "inputs"
OUT = ROOT / "outputs"
PROFILE = ROOT / "profile.json"
MANIFEST = ROOT / "input_manifest.sha256"
TARGETS = ["fpu", "fpu_frames", "fpu_resume", "mmu", "exceptions", "fpu_normalize"]
UNITS = [
    "ap040_tg68k_compat", "ap040_core", "ap040_bus16_adapter", "ap040_bus_timeout",
    "ap040_regfile", "ap040_alu", "ap040_muldiv", "ap040_mmu", "ap040_cache",
    "ap040_walker_cdc", "primitives/dpram",
]
BASELINE_FPU = INPUTS / "baseline_ap040_fpu.v"
CANDIDATE_FPU = INPUTS / "ap68040/rtl/ap040_fpu.v"
ASSEMBLER = Path("/home/alans/mister/MacQuadra800_fixtures/wombat-vasm/vasmm68k_mot")


def sha256(path):
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def parse_manifest():
    rows = {}
    for n, line in enumerate(MANIFEST.read_text().splitlines(), 1):
        parts = line.split("  ", 1)
        if len(parts) != 2 or len(parts[0]) != 64 or parts[1] in rows:
            raise RuntimeError(f"malformed immutable input manifest row {n}")
        rel = Path(parts[1])
        if rel.is_absolute() or ".." in rel.parts:
            raise RuntimeError(f"unsafe manifest path on row {n}")
        rows[parts[1]] = parts[0]
    if not rows:
        raise RuntimeError("empty immutable input manifest")
    return rows


def validate_immutable_inputs():
    rows = parse_manifest()
    expected = {p.relative_to(ROOT).as_posix() for p in INPUTS.rglob("*") if p.is_file()}
    expected |= {"profile.json", "source_comparison.json", "README.md", "candidate_vs_baseline_fpu.diff", "candidate_vs_previous_fpu.diff", "run.py"}
    if set(rows) != expected:
        raise RuntimeError(f"input set differs from reviewed manifest: missing={sorted(expected-set(rows))[:8]} extra={sorted(set(rows)-expected)[:8]}")
    for rel, digest in rows.items():
        path = ROOT / rel
        if not path.is_file() or sha256(path) != digest:
            raise RuntimeError(f"immutable input hash mismatch: {rel}")
    profile = json.loads(PROFILE.read_text())
    if sha256(BASELINE_FPU) != profile["baseline_fpu_sha256"]:
        raise RuntimeError("baseline FPU identity mismatch")
    if sha256(CANDIDATE_FPU) != profile["candidate_fpu_sha256"]:
        raise RuntimeError("candidate FPU identity mismatch")
    if profile["targets"] != TARGETS or not profile["sim_flags"]:
        raise RuntimeError("unexpected test target or flag profile")
    return rows, profile


def check_output_freshness():
    if not OUT.exists():
        return
    allowed = {"run_meta"}
    unexpected = {p.name for p in OUT.iterdir()} - allowed
    if unexpected:
        raise RuntimeError(f"output directory already contains run data: {sorted(unexpected)}")
    meta = OUT / "run_meta"
    if meta.exists():
        unexpected_meta = {p.name for p in meta.iterdir()} - {"preflight_identity.json"}
        if unexpected_meta:
            raise RuntimeError(f"run metadata directory is not fresh: {sorted(unexpected_meta)}")
    for label in ("baseline", "candidate"):
        d = OUT / label
        if d.exists() and any(d.iterdir()):
            raise RuntimeError(f"{label} output directory is not fresh")


def preflight(rows, profile):
    check_output_freshness()
    for tool in ("iverilog", "vvp"):
        if not shutil.which(tool):
            raise RuntimeError(f"required tool not found on PATH: {tool}")
    if not ASSEMBLER.is_file() or not (ASSEMBLER.stat().st_mode & 0o111):
        raise RuntimeError(f"required assembler missing or not executable: {ASSEMBLER}")
    if not (INPUTS / "reference/MacQuadra800.qsf").is_file():
        raise RuntimeError("pinned full-feature QSF reference missing")
    meta = OUT / "run_meta"
    meta.mkdir(parents=True, exist_ok=True)
    record = {
        "status": "PREFLIGHT_PASS_ONLY",
        "created_epoch": time.time(),
        "immutable_input_count": len(rows),
        "immutable_input_manifest_sha256": sha256(MANIFEST),
        "baseline_fpu_sha256": profile["baseline_fpu_sha256"],
        "candidate_fpu_sha256": profile["candidate_fpu_sha256"],
        "qsf_reference_sha256": profile["qsf_reference_sha256"],
        "flags": profile["flags"],
        "targets": TARGETS,
        "outputs_hashed_as_inputs": False,
    }
    (meta / "preflight_identity.json").write_text(json.dumps(record, indent=2) + "\n")
    return record


def run(cmd, log_path, timeout=180):
    with log_path.open("w") as log:
        p = subprocess.run([str(x) for x in cmd], stdout=log, stderr=subprocess.STDOUT, timeout=timeout)
    text = log_path.read_text(errors="replace")
    if p.returncode != 0:
        raise RuntimeError(f"command failed ({p.returncode}): {' '.join(map(str, cmd))}\n{text[-2500:]}")
    return text


def run_suite(label, fpu, flags):
    out = OUT / label
    out.mkdir(parents=True, exist_ok=False)
    rtl = INPUTS / "ap68040/rtl"
    units = [rtl / (u + ".v") for u in UNITS]
    sources = [INPUTS / "tb/tb_ap040_program.v", *units, fpu, INPUTS / "ap68040/experimental/ap040_pipeline_integer.sv"]
    run(["iverilog", *flags, "-I", rtl, "-s", "tb_ap040_program", "-o", out / "prog.vvp", *sources], out / "compile.log")
    run(["iverilog", *flags, "-I", rtl, "-s", "tb_ap040_fpu_normalize", "-o", out / "normalize.vvp",
         INPUTS / "tb/tb_ap040_fpu_normalize.v", fpu, rtl / "ap040_regfile.v", rtl / "primitives/dpram.v"], out / "normalize_compile.log")
    results = {}
    for target in TARGETS:
        started = time.monotonic()
        if target == "fpu_normalize":
            cmd = ["vvp", out / "normalize.vvp"]
        else:
            binary, hexfile = out / (target + ".bin"), out / (target + ".hex")
            run([ASSEMBLER, "-Fbin", "-m68040", "-no-opt", "-o", binary, INPUTS / "tb/asm" / ("t_" + target + ".s")], out / (target + "_asm.log"))
            run(["python3", INPUTS / "tb/bin2hex.py", binary, hexfile], out / (target + "_hex.log"))
            cmd = ["vvp", out / "prog.vvp", "+prog=" + str(hexfile)]
        text = run(cmd, out / (target + ".log"))
        if "ALL TESTS PASSED" not in text or re.search(r"FATAL|TEST FAILED|FAIL:", text):
            raise RuntimeError(f"terminal regression failure in {label}/{target}:\n{text[-2500:]}")
        phases = re.findall(r"phase (\d) passed \((\d+) cycles\)", text)
        if target != "fpu_normalize" and [int(x[0]) for x in phases] != [0, 1, 2]:
            raise RuntimeError(f"missing bus phases in {label}/{target}: {phases}")
        results[target] = {
            "status": "PASS",
            "bus_phase_cycles": {a: int(b) for a, b in phases},
            "log_sha256": sha256(out / (target + ".log")),
            "wall_seconds": round(time.monotonic() - started, 3),
        }
        print(f"{label} {target} PASS", flush=True)
    return results


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--preflight-only", action="store_true", help="validate immutable source identity and tools; do not build or simulate")
    args = ap.parse_args()
    rows, profile = validate_immutable_inputs()
    preflight(rows, profile)
    if args.preflight_only:
        print("PREFLIGHT PASS ONLY; no compile or simulation launched", flush=True)
        return 0
    result = {
        "scope": profile["scope"],
        "immutable_input_manifest_sha256": sha256(MANIFEST),
        "simulation_status": "RUNNING",
        "targets": {},
    }
    result["targets"]["baseline"] = run_suite("baseline", BASELINE_FPU, profile["flags"])
    result["targets"]["candidate"] = run_suite("candidate", CANDIDATE_FPU, profile["flags"])
    # Rehash exactly the immutable manifest rows; never enumerate or hash outputs/logs here.
    after = parse_manifest()
    if after != rows:
        raise RuntimeError("immutable input manifest changed during regression run")
    for rel, digest in rows.items():
        if sha256(ROOT / rel) != digest:
            raise RuntimeError(f"immutable input changed during run: {rel}")
    result["simulation_status"] = "PASS"
    result["immutable_inputs_revalidated"] = len(rows)
    (OUT / "result.json").write_text(json.dumps(result, indent=2) + "\n")
    print("PASS paired six-target baseline/candidate regressions; immutable inputs revalidated", flush=True)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"FAIL CLOSED: {exc}", file=sys.stderr, flush=True)
        raise SystemExit(1)
