# Native FFT candidate runtime comparison

Matched baseline14,301,941 → candidate13,358,788 loop clocks:943,153 fewer (6.59458% fewer clocks;7.06017% more loop throughput). Both passed return600D, integer/FP/stack ABI, code/heap/chip/bus/IRQ/state-sum gates and actual20 FFft/1 FExptab/20 N-pointer/20 scalar checks. FPU73bc is the only RTL change. This is native callback runtime evidence, not full OS suite gain or numerical output qualification. No payload buffers were captured.

The exact baseline image/TB/entry/monitor/checker were reused byte-for-byte; preflight.json documents their identities and sole RTL delta. Runner changed only the FPU pin/guard wording. Thus the unchanged checker prints “baseline” and measurement.scope inherits “baseline”; those labels do not identify the executed variant. comparison.json, preflight.json and run/identity.json identify actual candidate73bc. The source manifest records frozen original scratch paths; it is not an archive-relative manifest.

Baseline archive ../native_fpu_fft contains the common image generator/entry/TB/monitor and pinned external dependency recipe. This candidate archive keeps only variant-specific runner, identities, terminal logs and small ABI/code/stack/heap captures. No RAM/ROM images, binary or generated model. Source input paths belong to scratch/native_fpu_fft_candidate_20260928; copied scratch state was frozen before the run and was never mutated during execution.

From the repository root:

    python3 docs/perf/cache_refill_20260927/native_fpu_fft_candidate/check_archive.py

The proposed first-free paired payload replay is a separate review/run gate; current timing evidence does not claim output equality. No FPGA or production qualification.
