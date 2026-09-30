#!/usr/bin/env python3
"""Compile and run the isolated production/candidate FPU qualification pair."""
from pathlib import Path
import hashlib
import json
import re
import subprocess
import time

D = Path(__file__).resolve().parent
R = D.parents[1]
base = R / "scratch/fpu_refill_platform_workload_20260927/baseline/rtl/ap68040/rtl/ap040_fpu.v"
cand = R / "scratch/fpu_normal_single_enabled_candidate_20260928/ap040_fpu.v"
expected_inputs = {
    base: "2d53db3ae4a04310add04eeb7919f0219197a98827ed92e410e6d4a4a90f5465",
    cand: "6c157b3bc045e74a90416f4764f35cf65024e77577019a100b8aa9b5bdd9ce9b",
}
for path, expected in expected_inputs.items():
    actual = hashlib.sha256(path.read_bytes()).hexdigest()
    assert actual == expected, f"unexpected source hash {path}: {actual}"

qsf = R / "MacQuadra800.qsf"
macros = sorted(set(re.findall(
    r'^set_global_assignment -name VERILOG_MACRO "((?:AP040_[A-Z0-9_]+|CACHE_CD_OFF|CACHE_SMALL)=1)"',
    qsf.read_text(), re.M)))
flags = ["-D" + macro for macro in macros] + ["-DSIMULATION=1"]
defs = base.parent / "ap040_defs.svh"
sources = [base, cand, qsf, D / "tb_normal_single_move.sv", D / "prepare.py",
           D / "tests.inc", D / "run.py", defs]
identity = {
    "sources": {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in sources},
    "flags": flags,
    "independent_oracle": "exact IEEE binary32-to-extended conversion with FPSR/FPIAR/shadow checks; excluded and restore signatures compared against production",
    "tool": "iverilog -g2012/vvp",
    "scope": "FPU real-port unit qualification only; no CPU/workload/timing qualification",
    "candidate_sha256": expected_inputs[cand],
    "production_sha256": expected_inputs[base],
}
(D / "identity.json").write_text(json.dumps(identity, indent=2) + "\n")

for label, source in (("baseline", base), ("candidate", cand)):
    for suffix in ("compile.log", "run.log", "vvp"):
        assert not (D / f"{label}.{suffix}").exists(), f"refusing to overwrite {label}.{suffix}"
    with (D / f"{label}.compile.log").open("w") as log:
        subprocess.run(["iverilog", "-g2012", *flags,
                        *( ["-DCAND=1"] if label == "candidate" else []),
                        "-I", str(base.parent), "-s", "tb_normal_single_move",
                        "-o", str(D / f"{label}.vvp"),
                        str(D / "tb_normal_single_move.sv"), str(source)],
                       stdout=log, stderr=subprocess.STDOUT, check=True, timeout=60)
    start = time.monotonic()
    with (D / f"{label}.run.log").open("w") as log:
        subprocess.run(["vvp", str(D / f"{label}.vvp")], stdout=log,
                       stderr=subprocess.STDOUT, check=True, timeout=600)
    text = (D / f"{label}.run.log").read_text()
    assert "$fatal" not in text and "ERROR:" not in text, f"failure marker in {label} log"
    summary = re.search(r"^PASS normal_single .*$", text, re.M)
    assert summary, f"{label} PASS marker missing"
    fields = dict(re.findall(r"(\w+)=(\d+)", summary.group(0)))
    assert int(fields["normal"]) == 97795, (label, summary.group(0))
    if label == "baseline":
        assert int(fields["fast"]) == 0, summary.group(0)
    else:
        assert int(fields["fast"]) == int(fields["normal"]), summary.group(0)
    print(label, summary.group(0), "wall", round(time.monotonic() - start, 2))

baseline_lines = [line for line in (D / "baseline.run.log").read_text().splitlines()
                  if line.startswith("SIG")]
candidate_lines = [line for line in (D / "candidate.run.log").read_text().splitlines()
                   if line.startswith("SIG")]
assert len(baseline_lines) == 36, f"expected 36 excluded/restore signatures, got {len(baseline_lines)}"
assert baseline_lines == candidate_lines, "excluded/restore production signatures differ"
print("PASS production_excluded_and_restore_signatures", len(baseline_lines))
for path, expected in identity["sources"].items():
    assert hashlib.sha256(Path(path).read_bytes()).hexdigest() == expected, f"source changed during run: {path}"
(D / "qualification.json").write_text(json.dumps({
    "status": "PASS",
    "excluded_and_restore_signatures": len(baseline_lines),
    "baseline": re.search(r"^PASS normal_single .*$", (D / "baseline.run.log").read_text(), re.M).group(0),
    "candidate": re.search(r"^PASS normal_single .*$", (D / "candidate.run.log").read_text(), re.M).group(0),
}, indent=2) + "\n")
