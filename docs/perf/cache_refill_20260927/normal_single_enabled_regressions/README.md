# Enabled-exception FPU/fullcore regressions

The paired regression run completed with **all 12 target runs passing**: six baseline targets against production FPU `2d53db3a…` and the same six against candidate `6c157b3b…`. Targets were `fpu`, `fpu_frames`, `fpu_resume`, `mmu`, `exceptions`, and `fpu_normalize`. The five program tests each passed all three existing bus phases. This checks the listed CPU-bus-model regressions only; it is not a full-machine/OS run, benchmark, performance-gain result, FPGA result, or hardware result.

The archive preserves the 102-entry immutable source/input manifest, copied test inputs, candidate and baseline FPU sources, source comparisons, runner, preflight/result identities, raw target and compile/assembly logs, and a portable checker. Generated `.vvp`, `.bin`, and `.hex` files are deliberately omitted; their hashes are recorded in `result.json`. Every raw target log contains the terminal pass marker and is checked against the corresponding recorded hash.

The launch ran in exec session `19222` and completed in 231.429 seconds. Root's live host process audit observed baseline MMU `vvp` PID `2441423` running `outputs/baseline/prog.vvp +prog=mmu.hex`. The runner did not persist individual child PIDs, so this archive records that one independently observed PID and the runner session without implying PIDs for the other children.

The immutable input manifest SHA-256 is `b769a8d916b316f39b7a210564e0efb73473e3eb3a5df9b0dbdcebc91be91e2b`; all 102 inputs revalidated after the run. The exact 13 simulation flags and compiler/assembler executable hashes are stored in the preflight and result identities. The source change compared to the reviewed all-precision regression recipe is candidate FPU RTL only.

Verify from the repository root:

    python3 docs/perf/cache_refill_20260927/normal_single_enabled_regressions/check_archive.py docs/perf/cache_refill_20260927/normal_single_enabled_regressions
