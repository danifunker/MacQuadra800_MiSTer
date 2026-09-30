# Source and result copy map

| Archived item | Frozen source/result |
|---|---|
| `candidate_source_manifest.sha256` | 128 candidate inputs under `scratch/native_whet_cache_v2_comparison_20260928/candidate/` |
| `source/candidate_ap040_cache.v` | `candidate/tree/rtl/ap68040/rtl/ap040_cache.v`, SHA `9e8c0582…1481` |
| `source/candidate_cache.diff` | Reviewed cache-v2 delta from the paired regression preparation |
| `source/tb_platform_whet.sv`, `source/next_monitor.svh` | `candidate/tb_platform_whet.sv` and `candidate/next_monitor.svh`; unchanged from qualified joint-profile measurement |
| `source/run_platform_whet.py`, `source/supervise_candidate.py`, checkers | Candidate runner, bounded supervisor, original runtime and profile checkers |
| `reference/run.log`, `reference/run_identity.json`, `reference/measurement.json` | Qualified 6c baseline in `docs/perf/cache_refill_20260927/native_fpu_whetstone_joint_profile_6c/profile/` |
| `reference/captures/` | Baseline `native_abi.hex`, `native_code.hex`, `native_globals.hex`, `native_stack.hex` |
| `candidate_run.log`, `candidate_run_identity.json`, `candidate_measurement.json` | Candidate run output and source/tool identity |
| `candidate_captures/` | Candidate's corresponding four final memory captures |

The only candidate RTL-file difference is `ap040_cache.v`; `source_comparison.json` records the 113-file tree comparison and `baseline_reference.json` pins the baseline run/artifacts. Full build inputs and large/generated outputs remain in the isolated scratch project rather than being copied into this compact archive.
