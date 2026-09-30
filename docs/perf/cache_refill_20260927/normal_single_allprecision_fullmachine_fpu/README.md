# Revised 55ff full-OS FPU result

The revised55ff candidate completed the full Speedometer FPU suite: all three tests selected at one iteration, terminal “The tests are done!” screen, and displayed average rating **0.698**. Results were Whetstones 3850.048/s (rating .739), Matrix .991 s (rating .713), and FFT .447 s (rating .642). These displayed values show no gain over the original73bc candidate at the UI's displayed precision. The full-OS guest result is measured with the calibrated simulation RAM model; it is not a hardware score.

The candidate change removed the FPCR precision-00 restriction from the fast normal-single FMOVE admission condition while retaining the exception-enable requirement. The full-window observer profile shows why that relaxation did not help this guest run: its counters are raw `new_fp_command` branch events, not deduplicated instructions. The precision-0 / enables-32 normal-single bucket contains 5,346,934 normal-exponent events rejected by the retained exception-enable guard. The 930 eligible precision-0 / enables-0 events pass both the old and new predicates (`old_guard_accepted = new_guard_accepted = 930`); post-mismatch and side rejects are zero. Thus this run falsifies the precision-mode explanation for the absent gain and points to the exception-enable gate blocking the dominant observed bucket. The observer spans the whole control window, not individual timed tests, so it does **not** attribute those events to Whetstone, Matrix, or FFT separately.

Evidence includes setup and terminal screenshots, the raw reconciled `refill.tsv`, run metadata and checker logs, build/source identities, the consumed control, exact candidate and baseline FPU source files, and small source diffs. The copied source manifest is byte-exact and records the frozen source paths; its hash is `cd794af982858ddbb3f116345bf9dd301111897c73c575a343f6283ccc58ab0f`. The binary, ROM, golden disk, and 125 MB simulator log are intentionally omitted. `check_archive.py` verifies archive hashes, identities, terminal status, report/checker results, and observer totals without launching a simulator.

The runner metadata retains its pre-review `PENDING_SCREENSHOT_REVIEW` state; `result/review.json` records the later primary visual review. The archive checker validates stored result metadata and images are present; it does not OCR or independently interpret screenshot pixels.

This is a fullguest simulation result only. It makes no hardware speed claim. The separate original73bc FPU and Mix comparisons are archived in sibling `normal_single_move_fullmachine_fpu/` and `normal_single_move_fullmachine_mix/` directories. Current task status is in the [handoff](../../../../RESUME-20260927.md).

From the repository root:

    python3 docs/perf/cache_refill_20260927/normal_single_allprecision_fullmachine_fpu/check_archive.py docs/perf/cache_refill_20260927/normal_single_allprecision_fullmachine_fpu
