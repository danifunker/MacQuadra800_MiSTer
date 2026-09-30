#!/usr/bin/env python3
"""Small fail-closed checks for the refill TSV reconciler."""

import tempfile
from pathlib import Path

from check_refill_report import check


VALID = """REFILL_META\tclock_sample\tpost_eval_rising_edge
REFILL_META\tduration\tC_FILL_through_C_TAGW_complete_bracket_spans_only
REFILL_REGION\tbank\tregion\tfill_entries\tfill_samples\ttagwrite_samples\tissued_state_samples\tlocal_match_samples\tsetup_state_samples\tmrd_overlap_samples\tcompleted
REFILL_REGION\tdata\tram\t1\t1\t1\t1\t0\t0\t0\t1
REFILL_SAMPLE\tbank\tregion\tfill_cnt\tr_issued\tfill_acked\tclocks
REFILL_SAMPLE\tdata\tram\t0\t1\t0\t1
REFILL_DURATION\tbank\tregion\tclocks\tcomplete_fills
REFILL_DURATION\tdata\tram\t2\t1
CACHE_STATE\tid\tcycles\tpercent
CACHE_STATE\t4\t1\t1.0
CACHE_STATE\t5\t1\t1.0
"""


def attempt(report, expected_ok):
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory) / "profile.tsv"
        path.write_text(report, encoding="utf-8")
        try:
            check(path)
        except (AssertionError, ValueError, IndexError):
            assert not expected_ok, report
        else:
            assert expected_ok, report


attempt(VALID, True)
attempt("", False)
attempt("CACHE_STATE\t4\t1\t1.0\n", False)
attempt(VALID.split("REFILL_DURATION\tbank")[0], False)
attempt(VALID.replace("CACHE_STATE\t4\t1", "CACHE_STATE\t4\t2"), False)
attempt(VALID.replace("REFILL_SAMPLE\tbank", "REFILL_SAMPLE\tdata\trom\t0\t1\t0\t1\nREFILL_SAMPLE\tbank"), False)
attempt(VALID.replace("REFILL_SAMPLE\tbank", "REFILL_REGION\tdata\tram\t1\t1\t1\t1\t0\t0\t0\t1\nREFILL_SAMPLE\tbank"), False)
