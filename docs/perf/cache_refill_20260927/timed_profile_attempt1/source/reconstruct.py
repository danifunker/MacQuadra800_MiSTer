#!/usr/bin/env python3
"""Freeze the files used by the already-running Vemu without touching live inputs."""
from pathlib import Path
import difflib
import hashlib
import shutil

here = Path(__file__).resolve().parent
parent = here.parent
manifest = parent / "source_manifest.sha256"
golden = Path("/home/alans/mister/MacQuadra800_fixtures/MacQuadra800-Speedometer402-profile.hda")
running_binary = parent / "build/Vemu_running_54569322"
old_conditional = "if(fpu_prefix_ && !fpu_identified_)++fpu_prefix_aborts_;"
new_conditional = "if(fpu_prefix_)++fpu_prefix_aborts_;"
rows = []
for line in manifest.read_text().splitlines():
    _, relative = line.split("  ", 1)
    src = (parent / relative)
    if relative == "baseline_sim/verilator/run.hda":
        src = golden
    elif relative == "baseline_sim/verilator/obj_dir/Vemu":
        src = running_binary
    dest = here / relative
    dest.parent.mkdir(parents=True, exist_ok=True)
    if relative in (
        "speedometer_observer.h",
        "baseline_sim/scripts/fixtures/speedometer_timing_observer/speedometer_observer.h",
    ):
        data = src.read_text()
        assert data.count(new_conditional) == 1
        dest.write_text(data.replace(new_conditional, old_conditional))
    else:
        shutil.copy2(src, dest)
    digest = hashlib.sha256(dest.read_bytes()).hexdigest()
    rows.append(f"{digest}  {relative}\n")

old_manifest = "".join(rows)
(here / "source_manifest.sha256").write_text(old_manifest)
old_manifest_digest = hashlib.sha256(old_manifest.encode()).hexdigest()
expected = "7fa63eec2603a26bf99b7378643a2a8c72302228baa6d96150efec1440f07233"
print("reconstructed manifest SHA-256", old_manifest_digest)
print("matches prelaunch manifest:", old_manifest_digest == expected)

old = (here / "speedometer_observer.h").read_text().splitlines(keepends=True)
new = (parent / "speedometer_observer.h").read_text().splitlines(keepends=True)
(here / "late_diagnostic.diff").write_text("".join(difflib.unified_diff(
    old, new, fromfile="running_source/speedometer_observer.h",
    tofile="later/speedometer_observer.h")))
(here / "manifest_late_diff.txt").write_text("".join(difflib.unified_diff(
    old_manifest.splitlines(keepends=True), manifest.read_text().splitlines(keepends=True),
    fromfile="running_source/source_manifest.sha256", tofile="later/source_manifest.sha256")))
if old_manifest_digest != expected:
    raise SystemExit("prelaunch manifest did not reproduce; inspect source differences")
