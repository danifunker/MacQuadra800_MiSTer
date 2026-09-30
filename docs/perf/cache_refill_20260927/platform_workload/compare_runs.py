from pathlib import Path
import argparse
import hashlib
import json
import re

parser = argparse.ArgumentParser()
repo = next(x for x in Path(__file__).resolve().parents
            if (x / "MacQuadra800.qsf").is_file())
parser.add_argument("--work", type=Path,
                    default=repo / "scratch/fpu_refill_platform_workload_20260927")
work = parser.parse_args().work.resolve()
base_dir = work / "baseline_run"
cand_dir = work / "candidate_run"
reference = repo / "scratch/p198_ret/wl_p205_1"

def read_run(directory):
    identity = json.loads((directory / "identity.json").read_text())
    tree = Path(identity["tree"])
    source_hashes = {
        str(Path(name).relative_to(tree)) if Path(name).is_relative_to(tree)
        else Path(name).name: value
        for name, value in identity["sources"].items()
    }
    log = (directory / "run.log").read_text()
    loop = int(re.search(r"WHETSTONE_LOOP cycles=(\d+)", log).group(1))
    returned = re.search(r"WHETSTONE RETURNED cycles=(\d+) loop=(\d+)", log)
    assert returned and int(returned.group(2)) == loop
    assert re.search(r"SDRAM_PROTOCOL_ERRORS 0(?:\n|$)", log)
    assert "guest failure marker" not in log
    oracle = {}
    captures = {}
    for name in ("whet_globals.hex", "whet_code.hex", "whet_stack.hex"):
        data = [x.strip().lower() for x in (directory / name).read_text().split()]
        ref = [x.strip().lower() for x in (reference / name).read_text().split()
               if not x.startswith("//")]
        oracle[name] = data == ref
        captures[name] = hashlib.sha256((directory / name).read_bytes()).hexdigest()
    assert all(oracle.values()), f"oracle mismatch in {directory}: {oracle}"
    return identity, source_hashes, loop, oracle, captures

baseline = read_run(base_dir)
candidate = read_run(cand_dir)
b_id, b_src, b_cycles, b_oracle, b_captures = baseline
c_id, c_src, c_cycles, c_oracle, c_captures = candidate
assert b_id["flags"] == c_id["flags"]
assert b_id["image_sha256"] == c_id["image_sha256"]
assert b_id["rom_sha256"] == c_id["rom_sha256"]
assert b_id["romlat"] == c_id["romlat"]
assert b_src.keys() == c_src.keys()
differences = [key for key in b_src if b_src[key] != c_src[key]]
assert differences == ["rtl/ap68040/rtl/ap040_cache.v"], differences
assert b_captures == c_captures
result = {
    "baseline_loop_cycles": b_cycles,
    "candidate_loop_cycles": c_cycles,
    "candidate_minus_baseline_cycles": c_cycles - b_cycles,
    "candidate_speed_ratio": b_cycles / c_cycles,
    "source_differences": differences,
    "release_flags": b_id["flags"],
    "image_sha256": b_id["image_sha256"],
    "rom_sha256": b_id["rom_sha256"],
    "romlat": b_id["romlat"],
    "oracle_matches": b_oracle,
    "capture_sha256": b_captures,
}
(work / "comparison.json").write_text(json.dumps(result, indent=2) + "\n")
print(json.dumps(result, indent=2))
