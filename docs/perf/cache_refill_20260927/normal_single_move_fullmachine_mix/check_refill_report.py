#!/usr/bin/env python3
"""Require a valid refill sample report and reconcile it with cache-state clocks."""

import argparse
import csv
from collections import defaultdict


def check(path, allow_empty=False):
    cache = defaultdict(int)
    samples = defaultdict(int)
    regions = {}
    durations = defaultdict(int)
    metadata = set()
    headers = set()
    sample_rows = set()
    with open(path, newline="", encoding="utf-8") as report:
        for row in csv.reader(report, delimiter="\t"):
            if not row:
                continue
            kind = row[0]
            if kind == "REFILL_META":
                assert len(row) == 3, (kind, row)
                metadata.add(tuple(row[1:]))
            elif kind == "CACHE_STATE" and row[1] != "id":
                assert len(row) == 4, (kind, row)
                cache[int(row[1])] += int(row[2])
            elif kind == "REFILL_SAMPLE":
                assert len(row) == 7, (kind, row)
                if row[1] == "bank":
                    headers.add(kind)
                    continue
                key = (row[1], row[2])
                assert key[0] in ("data", "instruction") and key[1] in ("ram", "rom", "other"), row
                sample_key = tuple(row[1:6])
                assert sample_key not in sample_rows, ("duplicate sample", sample_key)
                sample_rows.add(sample_key)
                assert int(row[3]) in range(4) and row[4] in ("0", "1") and row[5] in ("0", "1"), row
                value = int(row[6])
                assert value > 0, ("nonpositive sample", row)
                samples[key] += value
            elif kind == "REFILL_REGION":
                assert len(row) == 11, (kind, row)
                if row[1] == "bank":
                    headers.add(kind)
                    continue
                key = (row[1], row[2])
                assert key[0] in ("data", "instruction") and key[1] in ("ram", "rom", "other"), row
                assert key not in regions, ("duplicate region", key)
                values = tuple(map(int, row[3:]))
                assert all(value >= 0 for value in values), row
                regions[key] = values
            elif kind == "REFILL_DURATION":
                assert len(row) == 5, (kind, row)
                if row[1] == "bank":
                    headers.add(kind)
                    continue
                key = (row[1], row[2])
                assert key[0] in ("data", "instruction") and key[1] in ("ram", "rom", "other"), row
                assert int(row[3]) > 0 and int(row[4]) > 0, row
                durations[key] += int(row[4])

    assert ("clock_sample", "post_eval_rising_edge") in metadata, "missing refill schema marker"
    assert ("duration", "C_FILL_through_C_TAGW_complete_bracket_spans_only") in metadata, "missing duration convention"
    assert headers == {"REFILL_SAMPLE", "REFILL_REGION", "REFILL_DURATION"}, ("missing headers", headers)
    assert set(samples) == {key for key, r in regions.items() if r[1] > 0}, "sample/region keys disagree"
    assert set(durations) == {key for key, r in regions.items() if r[7] > 0}, "duration/region keys disagree"

    fill = sum(samples.values())
    tagwrite = sum(r[2] for r in regions.values())
    complete = sum(r[7] for r in regions.values())
    hist_complete = sum(durations.values())
    if not allow_empty:
        assert fill > 0 and complete > 0, ("unqualified empty refill profile", fill, complete)
    assert fill == cache[4], ("C_FILL", fill, cache[4])
    assert tagwrite == cache[5], ("C_TAGW", tagwrite, cache[5])
    assert complete == hist_complete, ("duration histogram", complete, hist_complete)
    for key, r in regions.items():
        assert samples[key] == r[1], (key, "fill region", samples[key], r[1])
        assert r[3] + r[4] + r[5] == r[1], (key, "state partition", r)
        assert durations[key] == r[7], (key, "completed", durations[key], r[7])
    return f"refill report reconciles: fill={fill} tagwrite={tagwrite} completed={complete}"


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("profile", help="CPU profile TSV file")
    parser.add_argument("--allow-empty", action="store_true", help="allow a schema-correct profile with no complete refill")
    args = parser.parse_args()
    print(check(args.profile, args.allow_empty))
