# The timing-clean pipeline build against a real Quadra 800 (2026-09-26)

Core: `31b6e99`, seed 24 (RBF md5 `8481fce4`).  It has the pipeline back
(P243/P244), `SCSI_CACHE_OFF`, three release-lite trims and 8+8 KB CPU
caches.  Timing is met on every clock: CPU +1.141, HDMI +0.158, SDRAM
+0.791 ns.  Main: the write-buffer build (`3dd49cd2`).  The guest has 32 MB
(the real machine had 120 MB).  The real machine's numbers come from the
photos `real_quadra800.jpg` and `speedometerrealquadra.png` in this
directory.

## Benchmark Mix (median run of five: 1.768, 1.779, 1.778, 1.784, 1.777)

Subtests are ordered worst-to-best by the recorded relative-speed percentage;
the aggregate Mix row remains separate at the bottom.

| test | MiSTer | real Q800 | MiSTer / real (speed) |
|---|---|---|---|
| Dhrystones/sec | 19385.6 | 24922.1 | **78 %** |
| Queens (s) | 0.363 | 0.306 | **84 %** |
| Permutations (s) | 0.709 | 0.617 | **87 %** |
| Bubble Sort (s) | 0.632 | 0.565 | 89 % |
| KWhetstones/sec | 1793.4 | 1979.9 | 91 % |
| Sieve (s) | 1.051 | 0.972 | 92 % |
| Towers (s) | 0.476 | 0.468 | 98 % |
| Quick Sort (s) | 0.529 | 0.531 | 100 % |
| Puzzle (s) | 0.766 | 0.798 | 104 % |
| Int. Matrix (s) | 0.479 | 0.598 | 125 % |
| **Mix** | **1.778** | **1.899** | **94 %** |

## FPU Benchmarks (Quadra 650 = 1.0)

Subtests are ordered worst-to-best by the recorded relative-speed percentage;
the average row remains separate at the bottom.

| test | MiSTer | real Q800 | speed |
|---|---|---|---|
| Fast Fourier (s) | 0.454 | 0.288 | **63 %** |
| Matrix Mult. (s) | 1.025 | 0.713 | **70 %** |
| KWhetstones/sec (FPU) | 3854.99 | 5456.61 | **71 %** |
| **Average** | **0.687** | **1.011** | **68 %** |

## Color Benchmarks

| test | MiSTer | real Q800 | speed |
|---|---|---|---|
| Eight bit (s) | 13.967 | 8.211 | **59 %** |
| Monochrome, 2 and 4 bit | not run (the dialog needs mouse clicks) | 5.264 / 5.957 / 6.772 | |
| Sixteen bit | not available (the core has no 16 bpp mode) | 10.239 | |

## Performance Rating

| | MiSTer | real Q800 |
|---|---|---|
| CPU | 0.895 | 1.186 |
| Graphics | 1.031 | 1.347 |
| Disk | 1.595 | 3.443 |
| Math | 20.942 | 20.011 |
| **PR** | **1.152** | **1.605** |

## Where the distance is

The following explanations were hypotheses at the time of these measurements.
The later cache experiment does not establish either arithmetic latency or
OS-triggered refills as the cause of the timed FPU gap; the saved full-window
profile includes post-test activity. Timed-subtest attribution is in progress.

1. **Graphics (8-bit QuickDraw 59 %)** is the largest gap, and it is not
   CPU-bound: the CPU Mix is at 94 %.  The likely cause is the VRAM path:
   uncached VRAM reads through the platform, and how posted VRAM writes
   and reads interleave in the store buffer.  It needs a profile of a
   QuickDraw blit before any change.
2. **The FPU (68 %)** is the iterative FPU's per-instruction latency (FMUL,
   FDIV, FADD) against the 040's pipelined FPU.  Whetstone in the Mix (91 %)
   hides this because it is dominated by memory traffic.
3. **Dhrystone (78 %), Queens, Permutations, Bubble** are the integer
   paths P243 slowed (the lookahead now waits a cycle after a memory
   operand).
4. **Disk (46 %)**: Main's per-sector round trip and the ~4.9 MB/s link.

Evidence: `scratch/hw_s24/` (`run*_table.png`, `fpu_done.png`,
`color_done.png`, `pr_done.png`).

## Update 2026-09-27: build `faf9d98` (seed 21, md5 `7bcd182d`)

VRAM fast path, MOVE16 chaining and the ROM line fetch.  Measured on the
write-buffer Main, same 32 MB guest.

| test | `31b6e99` | `faf9d98` | real Q800 | `faf9d98` / real |
|---|---|---|---|---|
| Mix (median) | 1.778 | 1.781 | 1.899 | 94 % |
| Dhrystones/sec | 19385.6 | 19377.6 | 24922.1 | 78 % |
| KWhetstones/sec (Mix) | 1793.4 | 1799.3 | 1979.9 | 91 % |
| Color 8-bit (s) | 13.967 | **9.873** | 8.211 | **83 %** |
| FPU average | 0.687 | 0.690 | 1.011 | 68 % |
| PR | 1.152 | **1.203** | 1.605 | 75 % |
| PR Graphics | 1.031 | **1.170** | 1.347 | 87 % |
| PR Disk | 1.595 | 1.619 | 3.443 | 47 % |

Follow-up measurements and qualifications are in
`docs/FPU_PROFILE_20260927.md` and `docs/GRAPHICS_PROFILE_20260926.md`.
The calibrated bulk-refill simulation leaves the FPU average unchanged at
0.698; do not treat fixed-window HLock/flush counts as timed-test attribution.

## Update 2026-09-28: FPU candidate status

The percentage tables above remain historical results for the dated builds
identified in their headings; they are not scores for the revised 55ff FPU
candidate. The original 73bc candidate's matched full-OS FPU aggregate remained
0.698 and its ten-test Mix remained 1.798, unchanged from baseline. See the
[FPU comparison](cache_refill_20260927/normal_single_move_fullmachine_fpu/README.md)
and [Mix comparison](cache_refill_20260927/normal_single_move_fullmachine_mix/README.md).
Revised 55ff is timing-clean, but its completed guest FPU result also remains
0.698 (Whetstone 3850.048/s, Matrix 0.991 s, FFT 0.447 s). Its observer shows
extended precision with exception-enable byte 0x20: the retained enable guard
excludes 5,346,934 normal single-move branch events across the profiling window.
These counts are not individual subtest attribution. The next scratch candidate
6c permits exact normal moves with enables set; its qualification is pending.
No hardware test of these candidates has been performed. Current status is
tracked in the [handoff](../../RESUME-20260927.md). The later graphics result
of 83% in the 2026-09-27 update above remains a separate historical measurement.
