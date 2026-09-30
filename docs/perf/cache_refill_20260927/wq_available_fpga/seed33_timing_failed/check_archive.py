#!/usr/bin/env python3
from pathlib import Path
import hashlib, json, re, sys

R = Path(sys.argv[1] if len(sys.argv) > 1 else ".")

def need(ok, msg):
    if not ok:
        raise SystemExit("FAIL: " + msg)

def sha(path):
    return hashlib.sha256((R / path).read_bytes()).hexdigest()

def j(path):
    return json.loads((R / path).read_text())

inventory = {}
for line in (R / "SHA256SUMS").read_text().splitlines():
    h, name = line.split("  ", 1)
    need(re.fullmatch(r"[0-9a-f]{64}", h) is not None, "malformed archive checksum")
    need(name not in inventory, "duplicate archive path")
    inventory[name] = h
actual = {p.relative_to(R).as_posix() for p in R.rglob("*")
          if p.is_file() and p.name != "SHA256SUMS" and "__pycache__" not in p.parts}
need(actual == set(inventory), "archive inventory differs from SHA256SUMS")
for name, digest in inventory.items():
    need(sha(name) == digest, "archive hash mismatch: " + name)

def manifest(path):
    rows = {}
    for line in (R / path).read_text().splitlines():
        h, name = line.split("  ", 1)
        need(re.fullmatch(r"[0-9a-f]{64}", h) is not None, "invalid source digest")
        need(name not in rows, "duplicate source path")
        rows[name] = h
    return rows

base = manifest("run/base_manifest.sha256")
candidate = manifest("run/candidate_manifest.sha256")
need(len(base) == len(candidate) == 1892 and set(base) == set(candidate), "manifest inventory")
delta = [p for p in base if base[p] != candidate[p]]
need(delta == ["MacQuadra800.qsf"], "expected only QSF hash change")
need(base["MacQuadra800.qsf"] == sha("source/seed32_MacQuadra800.qsf"), "seed32 QSF identity")
need(candidate["MacQuadra800.qsf"] == sha("source/seed33_MacQuadra800.qsf"), "seed33 QSF identity")
need(candidate["rtl/sdram_beat32.sv"] == sha("source/candidate_sdram_beat32.sv"), "bridge source identity")
old = (R / "source/seed32_MacQuadra800.qsf").read_text()
new = (R / "source/seed33_MacQuadra800.qsf").read_text()
need(old.count("set_global_assignment -name SEED 32") == 1, "seed32 assignment")
need(new.count("set_global_assignment -name SEED 33") == 1, "seed33 assignment")
need(old.replace("set_global_assignment -name SEED 32", "set_global_assignment -name SEED 33", 1) == new,
     "QSF differs beyond seed setting")

prep = j("run/preparation_identity.json")
need(prep["result"] == "PASS" and prep["hash_deltas"] == delta, "preparation result")
need(prep["base_manifest_sha256"] == hashlib.sha256((R / "run/base_manifest.sha256").read_bytes()).hexdigest(),
     "base manifest identity")
need(prep["candidate_manifest_sha256"] == hashlib.sha256((R / "run/candidate_manifest.sha256").read_bytes()).hexdigest(),
     "candidate manifest identity")
post = j("run/source_postrun_check.json")
need(post["result"] == "PASS" and post["entries"] == post["verified"] == 1892 and not post["mismatches"],
     "postrun source verification")
fc = j("run/full_compile_identity.json")
need(fc["wrapper_exit"] == 1 and fc["quartus_flow_exit"] == 0 and fc["fitter"] == "successful", "compile terminal status")
need(fc["source_postrun"] == "source_postrun_check.json", "postrun pointer")
need(fc["setup"]["cpu_slack_ns"] == 0.099 and fc["setup"]["hdmi_slack_ns"] == -0.198 and
     fc["setup"]["ram_rising_to_falling_slack_ns"] == -0.292, "setup slacks")
need(fc["setup"]["hdmi_tns_ns"] == -0.378 and fc["setup"]["ram_rising_to_falling_tns_ns"] == -0.579, "setup TNS")
need(fc["cross_domain"]["all_12_positive"] is True and fc["cross_domain"]["sys_to_ram_worst_ns"] == 0.035 and
     fc["cross_domain"]["ram_to_sys_worst_ns"] == 0.099, "cross-domain metadata")
need(fc["ram_paths"]["summary_paths"] == 12 and fc["ram_paths"]["negative_paths"] == 2 and
     fc["ram_paths"]["worst_slack_ns"] == -0.292, "RAM path metadata")
need(fc["artifacts"]["MacQuadra800.rbf"] == {"bytes":4447936,"sha256":"bcd6a403d51fad66b2b4dba6f76f251ee762c36f7c4aa9c06bb68fd7bdaacf11"}, "RBF metadata")
need(fc["artifacts"]["MacQuadra800.sof"] == {"bytes":6690368,"sha256":"9f36df6183209b252d2e5662bdb9d88d50c18982d0b5539b06b665f064fa1b4d"}, "SOF metadata")
need((R / "run/full_exit_status.txt").read_text().strip() == "1", "wrapper exit record")

sta = (R / "reports/sta.summary").read_text()
for marker in ("Slack : 0.099", "TNS   : 0.000", "Slack : -0.198", "TNS   : -0.378",
               "Slack : -0.292", "TNS   : -0.579", "Slack : 0.201"):
    need(marker in sta, "STA summary lacks " + marker)
for name, slack in (("cross_sys2ram.txt", "0.035"), ("cross_ram2sys.txt", "0.099")):
    text = (R / "reports" / name).read_text()
    need(len(re.findall(r"^;\s*[+-]?\d+\.\d+\s*;", text, re.M)) == 6, "cross report path count: " + name)
    need(slack in text, "cross report worst slack: " + name)
ram = (R / "reports/ram_worst_paths.txt").read_text()
need("wq_rp[1]" in ram and "wq_available_handoff" in ram and "-0.292" in ram, "RAM read-pointer critical path")
need("d_ram[31]" in ram and "0.355" in ram, "RAM availability output path")
need("wq_wp[1]" in ram and "0.040" in ram, "RAM write-pointer input path")
need(not any(p.name in {"MacQuadra800.rbf", "MacQuadra800.sof", "local.env"}
             for p in R.rglob("*") if p.is_file()), "payload/private file included")
need(not any(part in {"db", "incremental_db", "__pycache__"} for p in R.rglob("*") for part in p.parts),
     "database or bytecode included")
print(f"PASS archive={len(inventory)} source_inputs=1892 sole_delta=MacQuadra800.qsf wrapper=1 CPU=+0.099 HDMI=-0.198 RAM=-0.292 cross=12_positive no_payload")
