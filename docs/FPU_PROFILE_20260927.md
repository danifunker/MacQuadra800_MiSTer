# FPU benchmark baseline and cache-refill investigation (2026-09-27)

**Historical profile, current pointer updated 2026-09-28.** Later work qualified
the 6c FPU and cache-v2 candidate in directed tests and FPGA timing; native
Whetstone improves 2.139%, with full-machine qualification pending. No new
hardware speed is established. See [current handoff](../HANDOFF-20260928.md)
and [measurements](PERFORMANCE_MEASUREMENTS.md). Earlier fixed-window profiles
and rejected bulk-refill experiments below retain their original scope.

## Follow-up audit (2026-09-27)

The following qualifications were found when checking these notes against HEAD
`6456c62` before the next optimization:

- `verilator/sim.v` connects the ROM retained line but leaves the RAM
  `mem_line_valid/tag/data/pending` ports unconnected. The FPGA supplies those
  ports from `sdram_beat32`, and `ap040_cache` consumes the retained RAM fill
  tail locally. Therefore the 41% occupancy and ~15-clock fill figures below
  describe the existing simulation, not a measured hardware refill schedule.
  Similar overall benchmark scores do not establish that the internal costs
  match. A production memory-path measurement is needed before ranking fixes.
- The earlier claim that walker U/M-bit writes are not snooped is incorrect
  for this tree. `rtl/wombat_cpu.sv` queues them through `wsnp_pend`, merges
  them with DMA snoops and drives the cache snoop port. This is an early
  invalidate at walker request, rather than write completion. The existing
  `t_mmu.s` includes a cached-descriptor U-bit refresh check. Simultaneous
  walker/DMA snoops, pending-slot assumptions, posted-write ordering and the
  architectural cache-push contract still need review before changing CPUSH.
- The saved profile uses a fixed interval after launching the benchmark,
  not a stop event tied to benchmark completion. It can include post-result
  idle work. Fill occupancy and OS flush counts describe that entire window;
  they do not by themselves establish the bottleneck during timed subtests.
  Use guest scores/times for performance, and treat the counters as supporting
  path evidence. A faster candidate may spend more of the same window idle.

The following original profile and experiment results remain useful evidence,
subject to that simulation limitation.

Hardware, build `faf9d98` (seed 21) on the write-buffer Main: FPU average
**0.690** (KWhetstones 3864.6, Matrix Mult 1.017 s, Fast Fourier 0.454 s);
the real Quadra 800 scores 1.011.  Color 8-bit 9.879 s, PR 1.203.

## Profile (full-machine sim, Speedometer FPU Benchmarks, Cmd-F)

The old sim scores 0.668 (hardware 0.690). This aggregate agreement does not
validate its internal refill timing or the attribution of the measured gap.
`docs/perf/fpu_profile_20260927/` has the profile and the control stream.

- The cache is in **C_FILL 41 %** of the profiled clocks.  There are 15.6 M
  data-line and 19.7 M instruction-line fills, ~15 clocks each.  S_MRD is
  34 % of all clocks, 236 M of them with the cache filling.
- The fills follow **cache flushes by Mac OS**:
  - **23,909 CPUSHA (both caches)** at ROM `$40885032`, reached through the
    `jCacheFlush` vector (`$6F4`) from the Memory Manager at `$40887800`.
    That code sets a block's lock bit and, when CPUFlag (`$12F`) is 4 (a
    68040), flushes both caches.  It is **HLock** (A029: 23,551 calls; HUnlock
    A02A 23,497).  A real Quadra runs the same flushes.
  - **48,937 CPUSHL (both caches)** at RAM `$0009AD6E` (a System patch).
- The original notes cited a single-cycle 64x64 FMUL datapath and
  three-bits-per-clock FDIV/FSQRT. Datapath throughput alone does not establish
  total instruction latency or exclude arithmetic/dispatch as a bottleneck.

## What was tried

| change | sim | hardware | verdict |
|---|---|---|---|
| CPU caches 16+16 KB (`SETW = 8`) | Color 10.264 -> 10.140 s | -- | not worth it: fits miss by 2 ns or fail to route |
| ROM line into the cache's line-fill port | Color -1 %, FPU unchanged | -- | reverted |
| **P246**: CINVL/CPUSHL invalidate only their line's set (the core cleared the whole selected caches for every scope) | FPU unchanged | FPU 0.688, Mix 1.786/1.786/1.777 | reverted; no gain (`p246_cpushl_line_REJECTED.diff`) |

Seed 21 of P246 met timing (CPU +0.461, HDMI +0.078, SDRAM +0.931).  One of
its four hardware Mix runs showed the project's known intermittent **timer
anomaly** (Permutations 0.480 s and Int. Matrix 0.006 s, aggregate 15.728:
`v9_run2_timer_anomaly.png`).  Earlier builds logged the same pattern
("Towers 0.140", "Int. Matrix 0.521 s and Sieve 0.024 s").  It is not specific
to P246.

## What the completed refill experiment establishes

The integrated SDRAM test measures tag installation at clock 12 with the
existing retained line and clock 10 with bulk installation; critical-word
acknowledge remains at clock 9. The old ~15-clock simulation figure must not
be used as the production retained-line latency.

Matched full-machine simulations with the calibrated retained-RAM-line model
completed with FPU average **0.698 baseline and 0.698 candidate**. Whetstone
is 3849.262 versus 3848.418 KWhetstones/sec; Matrix Multiply 0.991 versus
0.990 s; FFT 0.447 s in both. Color improves from 9.878 to 9.807 s in this
single pair. The two-clock refill-tail reduction produces no meaningful FPU
gain, so this candidate does not advance to FPGA synthesis/fit.

Next isolate the timed FPU subtests before attributing the gap to cache
flushes, arithmetic, or dispatch. The fixed-window flush totals include
activity outside those subtests. Preserving cache lines across CPUSH remains
a separate architectural/coherence and posted-write ordering question, not
an approved optimization. In fact, the architectural check below rules out
simply leaving the selected clean lines valid. See
`NEXT_PERFORMANCE_PLAN_20260927.md`.

## CPUSH architectural constraint

The Motorola MC68040 User's Manual, section 4.2 (printed pages 4-5 to 4-6),
requires CPUSH to invalidate every selected cache line after writing back
any selected dirty data. Clean write-through lines avoid dirty writeback;
they do not avoid invalidation. Cache enable bits and CDIS do not suppress
the instruction's operation. Therefore preserving selected lines across
CPUSHA is not a compatible shortcut, even with complete DMA/walker snooping.
Source: [NXP-hosted MC68040 User's Manual](https://www.nxp.com/docs/en/reference-manual/MC68040UM.pdf#page=89).

## Reference FPU timing interpretation

The MC68040 manual section 10.7.3, printed pages 10-35 to 10-36, separates
conversion, execution and normalization. For normal operands, its execution
stage is 3 clocks for FADD/FSUB, 5 for FMUL, 37.5 for FDIV and 103 for FSQRT.
These are not full instruction latencies or issue intervals. Parenthesized
figures denote stage occupancy; integer-unit support and operand accesses
are separate. Compare measured CPU-blocking and FPU-state counts before
concluding that an arithmetic datapath is fast enough or is the bottleneck.
Source: [MC68040 FPU timing tables](https://www.nxp.com/docs/en/reference-manual/MC68040UM.pdf#page=326).
