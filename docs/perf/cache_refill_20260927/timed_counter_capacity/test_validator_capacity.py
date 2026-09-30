#!/usr/bin/env python3
"""Exercise v1 compatibility and the v2 16-state cache histogram bound."""
import importlib.util
from pathlib import Path

HERE = Path(__file__).resolve().parent
OLD_CHECKER = HERE / "reference/check_timed_profile_v1.py"


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


new = load("capacity_checker", HERE / "check_timed_profile.py")
old = load("old_v1_checker", OLD_CHECKER)
tests = HERE / "tests"
tests.mkdir(exist_ok=True)

v2_path = tests / "v2-cache-8-9-valid.tsv"
rows = new.synthetic_rows()
cache_rows = [r for r in rows if r[0] == "CACHE" and r[1] == "0" and r[4] == "0"]
cache_rows[0][4] = "8"
cache_rows[1][4] = "9"
new.write_rows(v2_path, rows)
assert new.validate(v2_path) == "complete timed profile validated"

bad_path = tests / "v2-cache-16-invalid.tsv"
bad = [r[:] for r in rows]
next(r for r in bad if r[0] == "CACHE" and r[4] == "0")[4] = "16"
new.write_rows(bad_path, bad)
try:
    new.validate(bad_path)
    raise AssertionError("v2 cache histogram index 16 unexpectedly passed")
except new.ProfileError:
    pass

v1_path = tests / "v1-cache-legacy-compatible.tsv"
v1 = old.synthetic_rows()
new.write_rows(v1_path, v1)
assert new.validate(v1_path) == "complete timed profile validated"

for invalid_id in (8, 9):
    old_path = tests / f"old-v1-cache-{invalid_id}-rejected.tsv"
    old_rows = old.synthetic_rows()
    next(r for r in old_rows if r[0] == "CACHE" and r[4] == "0")[4] = str(invalid_id)
    old.write_rows(old_path, old_rows)
    try:
        old.validate(old_path)
        raise AssertionError(f"old v1 checker unexpectedly accepted cache state {invalid_id}")
    except old.ProfileError:
        pass

    # The widened checker keeps v1's original 0..7 limit by format version.
    new_v1_path = tests / f"new-v1-cache-{invalid_id}-rejected.tsv"
    new_v1_rows = old.synthetic_rows()
    next(r for r in new_v1_rows if r[0] == "CACHE" and r[4] == "0")[4] = str(invalid_id)
    old.write_rows(new_v1_path, new_v1_rows)
    try:
        new.validate(new_v1_path)
        raise AssertionError(f"new checker unexpectedly accepted v1 cache state {invalid_id}")
    except new.ProfileError:
        pass

print("PASS validator: old and new v1 reject cache 8/9; new v2 accepts 8/9 and rejects 16; v1 remains compatible")
