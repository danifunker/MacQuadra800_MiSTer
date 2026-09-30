#!/usr/bin/env python3
from pathlib import Path
import hashlib, json, re, sys

R = Path(sys.argv[1] if len(sys.argv) > 1 else ".")

def need(ok, msg):
    if not ok:
        raise SystemExit("FAIL: " + msg)

def digest(path):
    return hashlib.sha256((R / path).read_bytes()).hexdigest()

def load_json(path):
    return json.loads((R / path).read_text())

inventory = {}
for line in (R / "SHA256SUMS").read_text().splitlines():
    h, name = line.split("  ", 1)
    need(re.fullmatch(r"[0-9a-f]{64}", h) is not None, "malformed archive digest")
    need(name not in inventory, "duplicate archive path")
    inventory[name] = h
actual = {p.relative_to(R).as_posix() for p in R.rglob("*")
          if p.is_file() and p.name != "SHA256SUMS" and "__pycache__" not in p.parts}
need(actual == set(inventory), "archive inventory differs from SHA256SUMS")
for name, expected in inventory.items():
    need(digest(name) == expected, "archive file hash: " + name)

def read_manifest(path):
    rows = {}
    for line in (R / path).read_text().splitlines():
        h, name = line.split("  ", 1)
        need(re.fullmatch(r"[0-9a-f]{64}", h) is not None, "invalid source digest")
        need(name not in rows, "duplicate source path")
        rows[name] = h
    return rows

base = read_manifest("run/base_manifest.sha256")
candidate = read_manifest("run/candidate_manifest.sha256")
need(len(base) == len(candidate) == 1892 and set(base) == set(candidate), "source manifest inventory")
delta = [p for p in base if base[p] != candidate[p]]
need(delta == ["MacQuadra800.qsf"], "source manifest delta is not QSF-only")
need(candidate["MacQuadra800.qsf"] == digest("source/seed32_MacQuadra800.qsf"), "seed-32 QSF hash")
need(base["MacQuadra800.qsf"] == digest("source/seed31_MacQuadra800.qsf"), "seed-31 QSF hash")
need(candidate["rtl/sdram_beat32.sv"] == digest("source/candidate_sdram_beat32.sv"), "candidate bridge source hash")
old = (R / "source/seed31_MacQuadra800.qsf").read_text()
new = (R / "source/seed32_MacQuadra800.qsf").read_text()
need(old.count("set_global_assignment -name SEED 31") == 1, "seed31 QSF assignment")
need(new.count("set_global_assignment -name SEED 32") == 1, "seed32 QSF assignment")
need(old.replace("set_global_assignment -name SEED 31", "set_global_assignment -name SEED 32", 1) == new,
     "QSF changed beyond the seed assignment")

prep = load_json("run/preparation_identity.json")
need(prep["manifest_sha256"] == hashlib.sha256((R / "run/candidate_manifest.sha256").read_bytes()).hexdigest(),
     "preparation manifest identity")
need(prep["hash_deltas"] == ["MacQuadra800.qsf"] and prep["result"] == "PASS", "preparation identity")
post = load_json("run/source_postrun_check.json")
need(post["result"] == "PASS" and post["entries"] == post["verified"] == 1892 and not post["mismatches"],
     "postrun source check")
fc = load_json("run/full_compile_identity.json")
need(fc["wrapper_exit"] == 3 and fc["analysis_synthesis"] == "successful", "terminal build identity")
need("Error11802" in fc["fitter"] and "failed" in fc["fitter"].lower(), "fitter failure identity")
need(fc["timing_analysis"] == "not generated" and fc["cross_domain_sta"].startswith("NOT_AVAILABLE") and
     fc["same_ram_clock_sta"].startswith("NOT_AVAILABLE"), "STA availability identity")
need(not fc["artifacts"]["MacQuadra800.rbf"]["exists"] and
     not fc["artifacts"]["MacQuadra800.sof"]["exists"] and
     not fc["artifacts"]["MacQuadra800.sta.summary"]["exists"], "absent final outputs")
need((R / "run/full_exit_status.txt").read_text().strip() == "3", "recorded wrapper exit")

log = (R / "reports/build.log").read_text()
for marker in ("Info (170137): Fitter placement was successful",
               "Router estimated average interconnect usage is 46%",
               "Router estimated peak interconnect usage is 75%",
               "Warning (16618): Fitter routing phase terminated due to routing congestion",
               "Critical Warning (188026): The Fitter failed to successfully route the design",
               "Error (170143): Final fitting attempt was unsuccessful",
               "Error (11802): Can't fit design in device"):
    need(marker in log, "expected fitter diagnostic missing: " + marker)
need(not any(p.name in {"MacQuadra800.rbf", "MacQuadra800.sof", "local.env"}
             for p in R.rglob("*") if p.is_file()), "bitstream/private file included")
need(not any(part in {"db", "incremental_db", "__pycache__"}
             for p in R.rglob("*") for part in p.parts), "database/cache included")
print(f"PASS archive={len(inventory)} source_inputs=1892 sole_delta=MacQuadra800.qsf fitter=route_congestion wrapper=3 no_RBF no_STA")
