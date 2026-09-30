# Why 8-bit QuickDraw runs at 59 % of a real Quadra 800 (2026-09-26)

Speedometer's Color Benchmark, 8 bit: **13.967 s on hardware** (build
`31b6e99`), **8.211 s on the real machine**.  The CPU Benchmark Mix is at
94 %, so the missing time is not general CPU speed.

## How it was measured

The full-machine Verilator sim of `31b6e99` (pipeline and `SCSI_CACHE_OFF`
macros) booted the `MacQuadra800-Speedometer402-profile.hda` fixture (Mac OS
7.5.5) with the fast-boot ROM.  Navigation went through the control stream
(`simkeys.py`, PS/2 scancodes; `color8_control.txt` is the exact stream):
MacAtrium -> Esc -> Tab Tab -> Return -> the Finder -> Mac7-5-5 ->
Applications -> Speedometer 4.02 Folder -> Speedometer 4.02 -> Cmd-G ->
`profile start` -> Return.

The sim ran the test in **12.442 s** (`sim_color8_result.png`).  That is
close enough to the hardware's 13.967 s (Mac OS 8.1 there) to use as a
model.  Two instruments were used:

- the CPU profiler (`--cpu-profile`, `color8_profile.tsv`), for state
  cycles and the memory-path counters;
- simulation-only counters in `quadra800.sv` (`gfx_counters.diff`).  They
  count, per 2^24 clocks, the cycles a CPU beat is presented to VRAM or RAM
  and the beats completed (`color8_vram_counters.log`;
  `boot81_vram_counters.log` is the Mac OS 8.1 boot for comparison).

## Findings

- **Every VRAM access costs 4 clocks at the platform**, reads and writes
  alike.  The sequence is: decode in S_IDLE, S_MEM, the VRAM port's
  capture/deliver phases, the registered `b_ack`, then the adapter's guard
  cycle.
- **Seen from the CPU, a VRAM read costs ~7.4 clocks.**  S_MRD spends 76 M
  clocks with the cache in C_PASS (uncached) over 10.3 M VRAM reads.
- **Posted writes block other accesses.**  S_MRD waits 21.5 M clocks and
  S_MWR 34.6 M clocks for the store buffer to drain (VRAM writes queued
  ahead).  The store buffer holds two entries.
- **MOVE16 is a large share of the test.**  2.5 M MOVE16 instructions, each
  moved as 4 separate longword reads and 4 separate writes, with a state per
  longword step (S_M16_RD/RD2/WR/WR2: 40 M clocks, 7.4 %).  MOVE16 makes 29 %
  of all S_MRD entries and 38 % of all S_MWR entries.  A real 68040 moves the
  line with one burst read and one burst write.
- Whole-test shares: S_MRD 36.9 %, S_MWR 15.0 %, S_FETCH 8.7 %, S_DECODE
  7.9 %; 6.58 clocks per dispatched instruction; VRAM bus time 17 % of all
  clocks (reads 7 %, writes 10 %).

## What to change, in order of expected gain

1. **A shorter VRAM path in the platform:**
   - a VRAM write acknowledged in S_IDLE and written straight into the
     BRAM, so the store buffer drains at 2 clocks per beat instead of 4;
   - a VRAM read without the capture/deliver phase.
   Both sit outside the CPU core's critical paths.
2. **MOVE16 as a line move:** chain the four reads at the acknowledge (as
   the MOVEM load chain does) and the four writes likewise, dropping the
   per-longword RD2/WR2 states.  Longer term, one 16-byte transfer each way.
3. **A deeper store buffer for VRAM** (or route VRAM writes through the
   SDRAM bridge's 8-entry posted FIFO).

## Results (2026-09-26, later)

| build | change | sim Color 8-bit | hardware Color 8-bit | Mix (hw) |
|---|---|---|---|---|
| `31b6e99` | baseline | 12.442 s | 13.967 s | 1.778 |
| V1 (not committed alone) | direct VRAM writes | 12.507 s | -- | -- |
| `31ff820` | + direct VRAM reads, combinational read ack | 12.010 s | 12.61 s | 1.776 |
| `0679ca8` | + P245 MOVE16 chaining | 10.834 s | **11.42 s** | 1.777 |

The sim's old VRAM model acknowledged in 2 clocks, one fewer than the emu's
port did, so the sim gains less from the read change than the hardware.
V1's direct writes cut the store-buffer waits in the profile
(`mrd/mwr_cycles_sb_pending` 21.5 M + 34.6 M -> 9.9 M + 11.9 M), yet the sim
time did not move.  That is not explained yet.  The writes that remain behind
a VRAM store are the serialized C_PASS ones, whose cost did not change.

Timing-clean build: `0679ca8` at seed 21 (CPU +0.461, HDMI +0.441, SDRAM
+0.155 ns), `test-builds/MacQuadra800_vram_move16_timingclean_20260926_0679ca8.rbf`.
Evidence: `docs/perf/vram_move16_20260926/`.

### Next: the ROM

Split sim counters (`[GFX2]`, the V3 sim) show the test's CPU bus time is
dominated by **ROM beats**: 0.5-1.0 M ROM beats per 2^24 clocks while the
test runs, against 0.1-0.3 M VRAM writes.  In the sim a ROM beat costs 4
clocks.  On hardware ROM comes from DDR3 (`MacQuadra800.sv`, `DDR_ROM_BASE`),
several times slower, which is likely most of the sim/hardware gap
(10.83 s against 11.42 s).  ROM is cacheable in the core's physical decode
(`wombat_cpu.sv` `cache_allow`).  Whether these beats are cache fills
(capacity misses) or reads the MMU marks non-cacheable decides the fix: a
larger cache, or a ROM line cache/copy in faster memory.  An instrumented sim
is splitting them.

### The ROM, measured and fixed

The split counters (`[GFX3]`, instrumented V4 sim) show that the test's ROM
beats are instruction-cache **fills**: e.g. 262k I-fill beats, 5k D-fill beats
and no uncached ROM reads per 2^24 clocks.  The MMU marks nothing
non-cacheable.  `faf9d98` fetches each ROM line from DDR3 in one burst and
serves the other fill beats from the retained line.  Hardware Color 8-bit went
from 11.42 to **9.87 s** (see `PERFORMANCE_MEASUREMENTS.md`).  The fills
themselves remain: the 8 KB I-cache cannot hold QuickDraw's working set
(hot pages $4080D000, $40809000, $4080E000, $40811000).  A larger I-cache is
the next lever.
