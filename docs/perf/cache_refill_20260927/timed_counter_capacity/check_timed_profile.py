#!/usr/bin/env python3
"""Fail-closed validator for fpu-timed-profile-v1/v2 TSV reports."""

import argparse
import csv
import re
import sys
import tempfile
from collections import Counter, defaultdict
from pathlib import Path


SITES = range(3)
SPANS = ("timer", "callback")
STATUSES = ("complete", "partial")
META = {
    "format": "fpu-timed-profile-v2",
    "clock": "post_eval_33MHz_rising_edges",
    "timer_bracket": "start_trap_return_inclusive_to_stop_trap_call_exclusive",
    "callback_bracket": "JSR_call_inclusive_to_return_exclusive",
    "raw_microseconds": "A0_D0_at_timer_trap_returns",
    "site_labels": "unknown_three_CODE3_sites",
    "raw_cap": "4096",
}
SCHEMAS = [
    ["SCHEMA", "TOTAL", "site", "span", "status", "clocks", "dispatches",
     "bg_samples", "blocking_decode", "go_samples", "mrd_fill_overlap",
     "mrd_fill_unacked_overlap"],
    ["SCHEMA", "HISTOGRAM", "kind", "site", "span", "status", "id", "clocks"],
    ["SCHEMA", "RAW", "site", "start_A0D0", "stop_A0D0", "delta_u64",
     "backwards", "start_return_cycle", "stop_return_cycle"],
    ["SCHEMA", "DIAG", "site", "cycle", "kind", "reason"],
]
HIST_KINDS = {"CORE", "CACHE", "FPU_FST", "FPU_OP_BUSY"}
HIST_LIMITS = {"CORE": 256, "CACHE": 16, "FPU_FST": 32, "FPU_OP_BUSY": 128}
V1_CACHE_LIMIT = 8
SUPPORTED_FORMATS = {"fpu-timed-profile-v1", "fpu-timed-profile-v2"}
TOTAL_FIELDS = ("cycles", "dispatches", "bg_samples", "blocking_decode",
                "go_samples", "mrd_fill_overlap", "mrd_fill_unacked_overlap")
INT = re.compile(r"(?:0|[1-9][0-9]*)\Z")


class ProfileError(ValueError):
    pass


def integer(value, where):
    if not INT.fullmatch(value):
        raise ProfileError(f"{where}: expected unsigned decimal integer, got {value!r}")
    return int(value)


def fields_kv(fields, expected, where):
    out = {}
    for item in fields:
        if "=" not in item:
            raise ProfileError(f"{where}: malformed key/value field {item!r}")
        key, value = item.split("=", 1)
        if key in out:
            raise ProfileError(f"{where}: duplicate field {key!r}")
        out[key] = value
    if set(out) != set(expected):
        raise ProfileError(f"{where}: expected fields {sorted(expected)}, got {sorted(out)}")
    return out


def require_site(text, where):
    site = integer(text, where)
    if site not in SITES:
        raise ProfileError(f"{where}: site {site} is outside 0..2")
    return site


def validate(path, allow_empty=False):
    meta = {}
    schemas = []
    lifecycle = {}
    spans = {}
    totals = {}
    hist = defaultdict(dict)
    raws = []
    diagnostics = []

    try:
        with open(path, newline="", encoding="utf-8") as f:
            rows = csv.reader(f, delimiter="\t", strict=True)
            for line_no, row in enumerate(rows, 1):
                where = f"line {line_no}"
                if not row or (any(field == "" for field in row) and
                               not (row[0] == "DIAG" and len(row) == 5 and row[4] == "")):
                    raise ProfileError(f"{where}: blank row or empty field")
                kind = row[0]
                if kind == "META":
                    if len(row) != 3:
                        raise ProfileError(f"{where}: META needs 3 columns")
                    key, value = row[1:]
                    if key not in (*META, "invalid_samples", "raw_dropped", "diagnostic_dropped"):
                        raise ProfileError(f"{where}: unknown META key {key!r}")
                    if key in meta:
                        raise ProfileError(f"{where}: duplicate META key {key!r}")
                    meta[key] = value
                elif kind == "SCHEMA":
                    schemas.append(row)
                elif kind == "LIFECYCLE":
                    if len(row) != 6:
                        raise ProfileError(f"{where}: LIFECYCLE needs 6 columns")
                    site = require_site(row[1], where)
                    if site in lifecycle:
                        raise ProfileError(f"{where}: duplicate LIFECYCLE for site {site}")
                    kv = fields_kv(row[2:], {"identifies", "unmatched", "raw_pairs", "raw_missing"}, where)
                    lifecycle[site] = {k: integer(v, f"{where} {k}") for k, v in kv.items()}
                elif kind == "SPAN":
                    if len(row) != 7:
                        raise ProfileError(f"{where}: SPAN needs 7 columns")
                    site = require_site(row[1], where)
                    span = row[2]
                    if span not in SPANS:
                        raise ProfileError(f"{where}: unknown span {span!r}")
                    key = (site, span)
                    if key in spans:
                        raise ProfileError(f"{where}: duplicate SPAN {key}")
                    kv = fields_kv(row[3:], {"starts", "complete", "aborted", "open"}, where)
                    values = {k: integer(v, f"{where} {k}") for k, v in kv.items()}
                    if values["open"] not in (0, 1):
                        raise ProfileError(f"{where}: open must be 0 or 1")
                    spans[key] = values
                elif kind == "TOTAL":
                    if len(row) != 11:
                        raise ProfileError(f"{where}: TOTAL needs 11 columns")
                    site = require_site(row[1], where)
                    span, status = row[2:4]
                    if span not in SPANS or status not in STATUSES:
                        raise ProfileError(f"{where}: invalid span/status {span!r}/{status!r}")
                    key = (site, span, status)
                    if key in totals:
                        raise ProfileError(f"{where}: duplicate TOTAL {key}")
                    totals[key] = {name: integer(value, f"{where} {name}")
                                   for name, value in zip(TOTAL_FIELDS, row[4:])}
                elif kind in HIST_KINDS:
                    if len(row) != 6:
                        raise ProfileError(f"{where}: {kind} needs 6 columns")
                    site = require_site(row[1], where)
                    span, status = row[2:4]
                    if span not in SPANS or status not in STATUSES:
                        raise ProfileError(f"{where}: invalid span/status {span!r}/{status!r}")
                    index = integer(row[4], f"{where} histogram index")
                    if index >= HIST_LIMITS[kind]:
                        raise ProfileError(f"{where}: {kind} index {index} out of range")
                    count = integer(row[5], f"{where} histogram count")
                    key = (kind, site, span, status)
                    if index in hist[key]:
                        raise ProfileError(f"{where}: duplicate {kind} histogram index {index}")
                    hist[key][index] = count
                elif kind == "RAW":
                    if len(row) != 8:
                        raise ProfileError(f"{where}: RAW needs 8 columns")
                    site = require_site(row[1], where)
                    start, stop, delta = (integer(row[i], f"{where} RAW value") for i in (2, 3, 4))
                    backwards = integer(row[5], f"{where} backwards flag")
                    start_cycle = integer(row[6], f"{where} start cycle")
                    stop_cycle = integer(row[7], f"{where} stop cycle")
                    if backwards not in (0, 1):
                        raise ProfileError(f"{where}: backwards flag must be 0 or 1")
                    raws.append((site, start, stop, delta, backwards, start_cycle, stop_cycle))
                elif kind == "DIAG":
                    if len(row) != 5:
                        raise ProfileError(f"{where}: DIAG needs 5 columns")
                    site = require_site(row[1], where)
                    cycle = integer(row[2], f"{where} DIAG cycle")
                    if row[3] not in ("identify", "abort", "unmatched"):
                        raise ProfileError(f"{where}: unknown DIAG kind {row[3]!r}")
                    diagnostics.append((site, cycle, row[3], row[4]))
                else:
                    raise ProfileError(f"{where}: unknown record type {kind!r}")
    except (OSError, UnicodeError, csv.Error) as exc:
        raise ProfileError(f"cannot read report: {exc}") from exc

    expected_meta = set(META) | {"invalid_samples", "raw_dropped", "diagnostic_dropped"}
    if set(meta) != expected_meta:
        raise ProfileError(f"META keys missing/extra: expected {sorted(expected_meta)}, got {sorted(meta)}")
    if meta["format"] not in SUPPORTED_FORMATS:
        raise ProfileError(f"META format: unsupported {meta['format']!r}")
    for key, value in META.items():
        if key != "format" and meta[key] != value:
            raise ProfileError(f"META {key}: expected {value!r}, got {meta[key]!r}")
    cache_limit = V1_CACHE_LIMIT if meta["format"] == "fpu-timed-profile-v1" else HIST_LIMITS["CACHE"]
    for (kind, site, span, status), bins in hist.items():
        limit = cache_limit if kind == "CACHE" else HIST_LIMITS[kind]
        if any(index >= limit for index in bins):
            raise ProfileError(f"{kind} histogram index out of range for {meta['format']}")
    if schemas != SCHEMAS:
        raise ProfileError("SCHEMA records are missing, reordered, duplicated, or do not match v1")
    for key in ("invalid_samples", "raw_dropped", "diagnostic_dropped"):
        if integer(meta[key], f"META {key}") != 0:
            raise ProfileError(f"META {key} must be zero for a clean report")

    expected_sites = set(SITES)
    if set(lifecycle) != expected_sites:
        raise ProfileError(f"LIFECYCLE sites: expected 0,1,2; got {sorted(lifecycle)}")
    expected_spans = {(site, span) for site in SITES for span in SPANS}
    if set(spans) != expected_spans:
        raise ProfileError("SPAN records must contain timer and callback for all three sites")
    expected_totals = {(site, span, status) for site in SITES for span in SPANS for status in STATUSES}
    if set(totals) != expected_totals:
        raise ProfileError("TOTAL records must cover complete and partial for every site/span")
    for key in hist:
        if (key[1], key[2], key[3]) not in expected_totals:
            raise ProfileError(f"histogram without matching TOTAL: {key}")

    for site in SITES:
        life = lifecycle[site]
        for k, v in life.items():
            if v < 0:
                raise ProfileError(f"site {site}: negative lifecycle value {k}")
        for span in SPANS:
            skey = (site, span)
            state = spans[skey]
            if state["starts"] != state["complete"] + state["aborted"] + state["open"]:
                raise ProfileError(f"site {site} {span}: starts != complete + aborted + open")
            for status in STATUSES:
                key = (site, span, status)
                total = totals[key]
                if total["dispatches"] > total["cycles"]:
                    raise ProfileError(f"{key}: dispatches exceed samples")
                h = {kind: hist.get((kind, site, span, status), {}) for kind in HIST_KINDS}
                sums = {kind: sum(bins.values()) for kind, bins in h.items()}
                for kind in ("CORE", "CACHE", "FPU_FST"):
                    if sums[kind] != total["cycles"]:
                        raise ProfileError(f"{key}: {kind} histogram sums to {sums[kind]}, expected {total['cycles']}")
                fpu_zero = h["FPU_FST"].get(0, 0)
                if sums["FPU_OP_BUSY"] != total["cycles"] - fpu_zero:
                    raise ProfileError(f"{key}: FPU_OP_BUSY sum does not equal samples outside FST=0")
                if total["bg_samples"] > total["cycles"]:
                    raise ProfileError(f"{key}: bg_samples exceeds total")
                if total["blocking_decode"] > min(h["CORE"].get(153, 0), total["bg_samples"]):
                    raise ProfileError(f"{key}: blocking_decode exceeds CORE=153 or background samples")
                if total["go_samples"] > h["CORE"].get(160, 0):
                    raise ProfileError(f"{key}: GO samples exceed CORE=160")
                overlap_limit = min(h["CORE"].get(9, 0), h["CACHE"].get(4, 0))
                if total["mrd_fill_overlap"] > overlap_limit:
                    raise ProfileError(f"{key}: MRD/fill overlap exceeds CORE=9 and CACHE=4")
                if total["mrd_fill_unacked_overlap"] > total["mrd_fill_overlap"]:
                    raise ProfileError(f"{key}: unacked overlap exceeds MRD/fill overlap")

    diagnostic_counts = Counter((site, kind) for site, _cycle, kind, _reason in diagnostics)
    for site in SITES:
        if diagnostic_counts[(site, "identify")] != lifecycle[site]["identifies"]:
            raise ProfileError(f"site {site}: identify diagnostics do not reconcile with lifecycle")
        if diagnostic_counts[(site, "unmatched")] != lifecycle[site]["unmatched"]:
            raise ProfileError(f"site {site}: unmatched diagnostics do not reconcile with lifecycle")

    for site, start, stop, delta, backwards, start_cycle, stop_cycle in raws:
        if backwards:
            raise ProfileError(f"site {site}: RAW marks A0/D0 value as backwards")
        if stop < start or delta != stop - start:
            raise ProfileError(f"site {site}: RAW delta does not reconcile")
        if stop_cycle < start_cycle:
            raise ProfileError(f"site {site}: RAW cycles go backwards")
    raw_counts = Counter(row[0] for row in raws)
    if sum(lifecycle[s]["raw_pairs"] for s in SITES) != len(raws):
        raise ProfileError("LIFECYCLE raw_pairs do not reconcile with RAW rows")

    is_empty = True
    for site in SITES:
        life = lifecycle[site]
        if life["unmatched"] or life["raw_missing"]:
            raise ProfileError(f"site {site}: unmatched event or missing raw pair")
        for span in SPANS:
            state = spans[(site, span)]
            if state["aborted"] or state["open"]:
                raise ProfileError(f"site {site} {span}: aborted/open span present")
            if state["complete"]:
                is_empty = False
            for status in STATUSES:
                if totals[(site, span, status)]["cycles"]:
                    is_empty = False
        timer_complete = spans[(site, "timer")]["complete"]
        if life["raw_pairs"] != raw_counts[site]:
            raise ProfileError(f"site {site}: raw_pairs do not match its RAW rows")
        if life["raw_pairs"] != timer_complete:
            raise ProfileError(f"site {site}: raw_pairs do not match completed timer spans")

    if raws:
        is_empty = False
    if allow_empty and is_empty:
        return "empty schema validated; this is not workload proof"
    for site in SITES:
        for span in SPANS:
            state = spans[(site, span)]
            if state["complete"] < 1:
                raise ProfileError(f"site {site} {span}: require at least one complete span")
    return "complete timed profile validated"


def synthetic_rows():
    rows = [["META", k, v] for k, v in META.items()]
    rows.extend([["META", "invalid_samples", "0"], ["META", "raw_dropped", "0"],
                 ["META", "diagnostic_dropped", "0"]])
    rows.extend(SCHEMAS)
    for site in SITES:
        rows.append(["LIFECYCLE", str(site), "identifies=1", "unmatched=0", "raw_pairs=1", "raw_missing=0"])
        rows.extend([
            ["SPAN", str(site), "timer", "starts=1", "complete=1", "aborted=0", "open=0"],
            ["SPAN", str(site), "callback", "starts=1", "complete=1", "aborted=0", "open=0"],
        ])
        for span in SPANS:
            rows.append(["TOTAL", str(site), span, "complete", "3", "1", "1", "1", "1", "1", "1"])
            rows.extend([
                ["CORE", str(site), span, "complete", "9", "1"],
                ["CORE", str(site), span, "complete", "153", "1"],
                ["CORE", str(site), span, "complete", "160", "1"],
                ["CACHE", str(site), span, "complete", "4", "1"],
                ["CACHE", str(site), span, "complete", "0", "2"],
                ["FPU_FST", str(site), span, "complete", "0", "1"],
                ["FPU_FST", str(site), span, "complete", "1", "2"],
                ["FPU_OP_BUSY", str(site), span, "complete", "17", "2"],
                ["TOTAL", str(site), span, "partial", "0", "0", "0", "0", "0", "0", "0"],
            ])
        rows.append(["RAW", str(site), "100", "120", "20", "0", "50", "70"])
        rows.append(["DIAG", str(site), "1", "identify", ""])
    return rows


def write_rows(path, rows):
    with open(path, "w", newline="", encoding="utf-8") as f:
        csv.writer(f, delimiter="\t", lineterminator="\n").writerows(rows)


def self_test():
    with tempfile.TemporaryDirectory(prefix="timed-profile-test-") as tmp:
        p = Path(tmp) / "profile.tsv"
        valid = synthetic_rows()
        write_rows(p, valid)
        assert validate(p) == "complete timed profile validated"

        missing = [r for r in valid if len(r) < 2 or not (r[0] in {"LIFECYCLE", "SPAN", "TOTAL", "CORE", "CACHE", "FPU_FST", "FPU_OP_BUSY", "RAW", "DIAG"} and r[1] == "2")]
        write_rows(p, missing)
        try:
            validate(p)
            raise AssertionError("missing-site report unexpectedly passed")
        except ProfileError:
            pass

        bad_sum = [row[:] for row in valid]
        core_row = next(r for r in bad_sum if r[0] == "CORE" and r[1] == "0")
        core_row[-1] = "2"
        write_rows(p, bad_sum)
        try:
            validate(p)
            raise AssertionError("histogram sum mismatch unexpectedly passed")
        except ProfileError:
            pass

        partial = [row[:] for row in valid]
        span_row = next(r for r in partial if r[:3] == ["SPAN", "0", "timer"])
        span_row[4], span_row[5] = "0", "1"
        write_rows(p, partial)
        try:
            validate(p)
            raise AssertionError("aborted partial report unexpectedly passed")
        except ProfileError:
            pass

        empty = [["META", k, v] for k, v in META.items()]
        empty.extend([["META", "invalid_samples", "0"], ["META", "raw_dropped", "0"],
                      ["META", "diagnostic_dropped", "0"]])
        empty.extend(SCHEMAS)
        for site in SITES:
            empty.append(["LIFECYCLE", str(site), "identifies=0", "unmatched=0", "raw_pairs=0", "raw_missing=0"])
            for span in SPANS:
                empty.append(["SPAN", str(site), span, "starts=0", "complete=0", "aborted=0", "open=0"])
                for status in STATUSES:
                    empty.append(["TOTAL", str(site), span, status, "0", "0", "0", "0", "0", "0", "0"])
        write_rows(p, empty)
        try:
            validate(p)
            raise AssertionError("empty report unexpectedly passed without smoke flag")
        except ProfileError:
            pass
        assert validate(p, allow_empty=True) == "empty schema validated; this is not workload proof"
    print("self-test passed: valid, missing site, sum mismatch, partial, and empty smoke modes")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("report", nargs="?", help="timed-profile TSV")
    parser.add_argument("--allow-empty", action="store_true",
                        help="allow only a completely empty schema smoke report; does not prove workload coverage")
    parser.add_argument("--self-test", action="store_true", help="run synthetic parser tests")
    args = parser.parse_args()
    if args.self_test:
        if args.report:
            parser.error("--self-test does not take a report path")
        self_test()
        return 0
    if not args.report:
        parser.error("a report path is required unless --self-test is used")
    try:
        print(validate(args.report, allow_empty=args.allow_empty))
        return 0
    except ProfileError as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
