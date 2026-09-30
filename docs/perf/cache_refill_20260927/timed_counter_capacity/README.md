# Timed-profile cache-state capacity correction

This archive contains a host-only correction and its review evidence. The timed-profile counter and strict validator originally accepted only cache-state IDs 0–7. The pinned release build enables `AP040_EXPERIMENTAL_XSTORE`, whose cache-state field is four bits and includes legal IDs 8 and 9. The corrected counter uses 16 bins, accepts 8/9, and rejects index 16 atomically. No RTL, live simulator inputs, or prior reports were changed, and no simulation is part of this archive.

`window_counters.h` and `check_timed_profile.py` are corrected copies. The emitted format tag is `fpu-timed-profile-v2`; the TSV columns are unchanged, while the cache histogram's accepted ID range is widened to 0–15. The strict checker accepts v1 reports with IDs 0–7 and v2 reports with IDs 0–15. It retains the existing strict validation of schema, coverage, partial spans, raw counters, and histogram totals. `reference/window_counters_v1.h` and `reference/check_timed_profile_v1.py` are the complete old eight-bin controls used to show that 8/9 fail before the correction. `reference/rtl/ap040_cache.v` and `reference/MacQuadra800.qsf` are the pinned source evidence; no path outside this archive is needed to run the host checks.

The legacy `verilator/sim_main.cpp` observer has a separate eight-bin histogram and masks `cst` with `& 7`. Under XSTORE, its IDLE/LOOK bins can combine states 8/9 with states 0/1; existing legacy histograms therefore do not identify those bins purely. The parent review established that 8/9 are not in the C_FILL or C_TAGW span states, so this alias does not alter those fill-span measurements. This archive does not modify or relabel legacy outputs. It also does not change the live attempt2 profile; its `invalid_samples` and strict-checker result determine whether any rerun is needed.

Run the archive's host checks from any working directory with:

```sh
bash docs/perf/cache_refill_20260927/timed_counter_capacity/run_host_tests.sh
```

The script compiles small host test executables in `build/`; they are removed from this text-only archive after the recorded check. Test TSVs and human-readable logs are retained.
