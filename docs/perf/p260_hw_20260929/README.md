# P260 ping-pong sector buffer on hardware: 2b30d64 at seed 27 (2026-09-29)

`583a98c` + `2b30d64` (P260) give the 53C96 engine a two-half sector buffer
(`ncr_sbuf` 512 x 16, still one M10K): the platform (Main/SD) transfer of the
next 512-byte block overlaps the guest's drain or fill of the current one.
The build is `d2a9207`'s seed 27 (`docs/perf/p260_fpga_20260929`).

**Result: the overlap is real on hardware and nothing regressed.**

- **PR Disk 2.462 median** (five runs, 2.447-2.532), against **1.699** on
  `dc281d64` (+45 %) and 1.741 on `b7e88b81` (+41 %). PR 1.266 (was 1.211).
- **Photoshop 3.0.1 Finder duplicate 4.95 s median** over 30 copies (4.71-5.20),
  against **6.68 s** (-26 %, 800 kB/s against 592). The sim qualification
  predicted 18-34 % faster.
- **Read phase 2.06-2.35 MiB/s** (was 1.63-1.65), **write phase 1.37-1.51
  MiB/s** (was 0.94-1.01). The best 0.25 s read window is 4.1 MiB/s (was 2.72).
- **CPU side unchanged:** CPU 0.895-0.896, Graphics 1.163-1.168, Math
  21.44-21.48; FPU 0.951 cold / 0.976 warm; Benchmark Mix 1.807 (b7e88b81 1.803).
- **Hangs: 0 of 30 duplicates, 0 bombs, no reboot.** Five PRs, one FPU pair and
  one Mix also clean.
- **Idle check passed:** the menu-bar clock kept step with the MiSTer over 4 min,
  and type-select answered. Shut Down reached "It is now safe to switch off
  your Macintosh".

Nothing was committed; `rtl/` and the `.qsf` were not touched. The operator
did not load or deploy anything: the coordinator deployed the rbf.

## Build under test

| | |
|---|---|
| RTL | `2b30d64` (P260 `583a98c` + the non-DMA underflow-arm fix); `.qsf` `d2a9207` (seed 27, placement effort 2.0, router timing MAXIMUM, release recipe) |
| fit | 39,246 ALMs (94 %), 24,645 registers, 468 / 553 M10K, 36 DSP |
| setup slack | CPU `general[0]` **+0.299**, HDMI **+0.299**, SDRAM `general[1]` **+0.678**, h2f_user0 +3.589 |
| hold | worst +0.207 (HDMI); CPU +0.220, RAM +0.442; recovery / removal / min pulse all positive (worst +0.505, CPU VCO pulse width) |
| crossings sys→RAM / RAM→sys | +0.707 / +0.600, 0 violated |
| rbf | 4,490,424 B, md5 `f769b9e1ef496428be071d4ded9e90ae`, sha256 `28c40b4b3999ca2f64d783892c13da760d17fadebb6fff3cfae5f2b2d38bdfa9` |

`MacQuadra800.{fit,sta}.summary` in this directory are this fit's own (copied
from the checkout's `output_files/`, where the rbf md5 is `f769b9e1`).

## Box, guest, method

- **Box:** `10.3.164.251` (eth0). `.92` not touched.
- **Main:** `/proc/$(pidof MiSTer)/exe` md5 `75e00b65` (the tight-loop build),
  the same Main as the `dc281d64` baseline.
- **Core:** `_Unstable/MacQuadra800.rbf` md5 `f769b9e1` on the box. The
  coordinator deployed it at about 18:18 UTC.
- **Disk and config:**
  - Slot 0 is the disposable `QuadSquad8-pipeline-test-20260919.hda` (`.s0`),
    Main's only open image. The master `QuadSquad8.hda` was not touched.
  - CFG byte 0 is `0x40` (32 MB, Ethernet on); Speedometer showed Physical RAM
    32768K (`speedo_main` in scratch).
- **Boot:** the Finder desktop was already up at the first look, 18:20:17 UTC,
  with no bomb (`boot_finder.png`). The Photoshop folder showed 63 items,
  953.5 MB available: far above the 100 MB stop line, so the copies went ahead.
- **Scripts:** copies of `scratch/iosbfix_hw_20260929/scripts/` in
  `scratch/p260_hw_20260929/scripts/`, with only the output path changed:
  - `speedo_launch.sh` (the "Not Yet" nag), `p_pr.sh`, `speedo_quit.sh` (No
    to the Machine Record, pointer checked before the click);
  - `ps_open.sh`, `p_dup.sh`, `analyze.py`: Cmd-D (keycode 56 + D), timed to
    the sampler window that holds the copy's last `write()`; complete when
    Main's `wchar` delta is at least 3,958,000 B;
  - `shutdown.sh`: the vmouse Special-menu recipe with an explicit button-up.
- **Sampler:** `/tmp/armfine.sh` on the box, md5 identical to the scratch copy,
  samples Main's `/proc/PID/io` every ~0.25 s. Phase lengths are therefore
  quantised to about 0.25 s: 1.76 / 2.01 s reads and 2.49 / 2.74 s writes are
  neighbouring window counts.
- **Readings:** every Speedometer value was read by eye from pixel-enlarged
  crops.

## Speedometer 4.02 Performance Rating (all four tests)

| PR run | CPU | Graphics | Disk | Math | PR |
|---:|---:|---:|---:|---:|---:|
| 1 | 0.895 | 1.163 | 2.462 | 21.472 | 1.265 |
| 2 | 0.896 | 1.167 | 2.462 | 21.480 | 1.267 |
| 3 | 0.896 | 1.167 | 2.447 | 21.446 | 1.266 |
| 4 | 0.895 | 1.165 | 2.469 | 21.439 | 1.266 |
| 5 | 0.896 | 1.168 | 2.532 | 21.457 | 1.271 |
| **median** | **0.896** | **1.167** | **2.462** | **21.457** | **1.266** |
| `dc281d64` median (3 runs) | 0.896 | 1.166 | 1.699 | 21.448 | 1.211 |
| `b7e88b81` median (production, 3 runs) | 0.895 * | 1.166 | 1.741 | 21.441 | 1.210 / 1.214 * |

\* The production run 2 hit the intermittent Speedometer timer anomaly (CPU 2.972, PR 1.958); these two columns show runs 1 and 3 only.

- **PR Disk is up 45 % on `dc281d64`** (1.699 → 2.462) and 41 % on the
  production figure, steadily in all five runs. That is 72 % of the real
  Quadra 800's 3.44, up from 49 %.
- **CPU, Graphics and Math are unchanged.** The PR rises only through Disk.
- **Sampler during the PRs:** Main's read rate over the active windows had a
  median of 1.29-1.72 MiB/s and a best window of 2.2 MiB/s (4.25 in run 2).
  On `dc281d64` the same measure was 1.04-1.11 median and 1.53-1.78 best.
  Each PR read 7.1-9.0 MiB and wrote 4.4 MiB.
- Screens: `pr{1..5}_done_crop.png`, `pr5_done.png`.

## Photoshop 3.0.1 Finder duplicates

Ten timed copies (1-10), FPU and Mix, then twenty more (11-30) on the same
boot. Before copy 11, Speedometer was quit and the folder reopened by
`ps_open.sh`, so copy 11 is a second cold read of the source.

| copy | time (s) | kB/s | written (B) | read phase | write phase |
|---:|---:|---:|---:|---|---|
| 1 (cold) | 5.18 | 764 | 3,966,976 | 2.77 s, 1.68 MiB/s | 2.74 s, 1.38 MiB/s |
| 2 | 4.96 | 798 | 3,964,928 | 1.76 s, 2.35 | 2.75 s, 1.37 |
| 3 | 4.95 | 799 | 3,965,952 | 1.76 s, 2.35 | 2.75 s, 1.37 |
| 4 | 4.93 | 803 | 3,969,536 | 1.77 s, 2.34 | 2.75 s, 1.37 |
| 5 | 4.93 | 803 | 3,964,928 | 1.77 s, 2.32 | 2.74 s, 1.38 |
| 6 | 4.71 | 839 | 3,965,952 | 2.03 s, 2.04 | 2.49 s, 1.51 |
| 7 | 4.90 | 808 | 3,966,976 | 1.76 s, 2.35 | 2.72 s, 1.39 |
| 8 | 4.93 | 803 | 3,964,928 | 2.01 s, 2.06 | 2.47 s, 1.53 |
| 9 | 4.95 | 799 | 3,968,512 | 1.76 s, 2.36 | 2.75 s, 1.37 |
| 10 | 4.97 | 797 | 3,966,976 | 1.76 s, 2.34 | 2.75 s, 1.37 |
| 11 (cold) | 5.15 | 768 | 3,964,928 | 2.76 s, 1.63 | 2.73 s, 1.38 |
| 12 | 4.98 | 794 | 3,965,952 | 1.76 s, 2.34 | 2.76 s, 1.37 |
| 13 | 4.92 | 805 | 3,968,000 | 2.02 s, 2.07 | 2.50 s, 1.51 |
| 14 | 4.93 | 802 | 3,967,488 | 2.01 s, 2.06 | 2.49 s, 1.51 |
| 15 | 5.15 | 768 | 3,965,952 | 2.01 s, 2.06 | 2.74 s, 1.38 |
| 16 | 4.95 | 799 | 3,967,488 | 2.01 s, 2.08 | 2.50 s, 1.51 |
| 17 | 5.20 | 761 | 3,964,928 | 2.01 s, 2.07 | 2.76 s, 1.37 |
| 18 | 4.95 | 800 | 3,965,952 | 2.01 s, 2.06 | 2.51 s, 1.50 |
| 19 | 4.95 | 800 | 3,971,584 | 1.78 s, 2.33 | 2.76 s, 1.37 |
| 20 | 5.20 | 762 | 3,964,928 | 2.01 s, 2.07 | 2.75 s, 1.37 |
| 21 | 4.95 | 800 | 3,965,952 | 1.76 s, 2.35 | 2.75 s, 1.37 |
| 22 | 4.93 | 803 | 3,968,000 | 1.76 s, 2.36 | 2.75 s, 1.37 |
| 23 | 5.18 | 764 | 3,964,928 | 2.02 s, 2.05 | 2.74 s, 1.38 |
| 24 | 5.16 | 767 | 3,968,512 | 2.01 s, 2.10 | 2.74 s, 1.38 |
| 25 | 4.93 | 802 | 3,966,976 | 2.01 s, 2.06 | 2.50 s, 1.51 |
| 26 | 5.19 | 763 | 3,964,928 | 2.02 s, 2.06 | 2.75 s, 1.37 |
| 27 | 4.92 | 805 | 3,965,952 | 2.01 s, 2.06 | 2.49 s, 1.51 |
| 28 | 5.16 | 767 | 3,968,512 | 2.01 s, 2.06 | 2.73 s, 1.38 |
| 29 | 5.16 | 767 | 3,967,488 | 2.02 s, 2.06 | 2.74 s, 1.38 |
| 30 | 5.19 | 763 | 3,965,952 | 2.01 s, 2.06 | 2.74 s, 1.38 |

| | **P260 `f769b9e1`** | `dc281d64` (30 copies, two boots) | change |
|---|---:|---:|---:|
| median time, all 30 | **4.95 s** (min 4.71, max 5.20) | 6.68 s (min 6.44, max 6.95) | **-25.9 %** |
| median, copies 1-10 / 11-30 | 4.94 / 5.07 s | 6.68 / 6.68 s | |
| median throughput | **799 kB/s** | 592-593 kB/s | +35 % |
| warm read phase | **1.76-2.02 s, 2.06-2.36 MiB/s** (median 2.07) | 2.25-2.53 s, 1.63-1.82 MiB/s (typ. 2.51 s, 1.65) | **+25-43 %** |
| cold read phase (copies 1, 11) | 2.77 / 2.76 s, 1.68 / 1.63 MiB/s | 3.51-3.56 s, 1.28-1.30 MiB/s | +27 % |
| best 0.25 s read window | **4.06-4.14 MiB/s** | 2.71-2.72 MiB/s | +52 % |
| write phase | **2.47-2.76 s, 1.37-1.53 MiB/s** (median 1.38) | 3.73-4.01 s, 0.94-1.01 MiB/s | **+37-50 %** |
| best 0.25 s write window | 1.75-2.02 MiB/s | 1.25-1.28 MiB/s | +45 % |

- **All 30 completed**, each with a `wchar` delta of 3,964,928-3,971,584 B.
  The folder went from 63 to 93 items and from 953.5 MB to 840.1 MB free
  (`dup10_after.png`, `dup30_after.png`).
- **Hangs: 0 of 30. Bombs: 0.** No reboot was needed.
- **The read phase is where the overlap shows.** The guest's drain is no longer
  serialised behind the SPI transfer: the best read windows doubled toward the
  SD path's own rate (4.1 MiB/s against 2.7), and the warm read phase shrank
  from 2.51 s to 1.76-2.01 s.
- **The write phase gained as much.** The guest's fill of one half now overlaps
  the platform's flush of the other, which the sim also showed (7,717 of 7,738
  write chunks completed with the previous flush in flight).
- **Two-mode spread.** Copy times split into 4.90-4.98 s and 5.15-5.20 s, with
  one fast outlier at 4.71 s. The step is one sampler window (a 0.25 s longer
  read or write phase), the same pattern as the baseline's 6.68 / 6.92 s pair.
  Copies 11-30 fell more often into the slower mode (median 5.07 against 4.94).
  One boot cannot separate filling the disk from chance.

## FPU Benchmarks and Benchmark Mix (one iteration)

Setup screens checked: FPU with all three tests at Iter. 1, Mix with all ten
at Iter. 1 (`mix1_setup.png`).

| FPU run | KWhet/s | Matrix s | FFT s | **Average** |
|---:|---:|---:|---:|---:|
| 1 (first after launch) | 4610.462 (0.885) | 0.724 (0.975) | 0.289 (0.993) | **0.951** |
| 2 (after Mix, warm) | 4573.749 (0.878) | 0.690 (1.023) | 0.280 (1.027) | **0.976** |

- **The brief asked for one run.** Run 1 came out at the known cold value, so
  one warm run followed, as in the baseline session.
- **The pattern repeats the earlier builds:**
  - `dc281d64`: 0.955 cold, then 0.960 / 0.981;
  - `b7e88b81`: 0.972-0.978;
  - marginal P258: 0.951 / 0.965 cold.
- Screens: `fpu1_done_crop.png`, `fpu2_done_crop.png`.

| Mix | KWhet/s | Dhry/s | Towers | QSort | Bubble | Queens | Puzzle | Perm | Int. Matrix | Sieve | **Mix** |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| **P260 run 1** | 1847.493 | 19356.302 | 0.477 | 0.511 | 0.632 | 0.362 | 0.775 | 0.704 | 0.463 | 1.049 | **1.807** |
| `b7e88b81` median | 1861.206 | 19414.670 | 0.475 | 0.544 | 0.682 | 0.362 | 0.807 | 0.712 | 0.515 | 0.842 | 1.803 |
| marginal P258 median | 1857.417 | 19344.619 | 0.477 | 0.531 | 0.710 | 0.361 | 0.768 | 0.703 | 0.463 | 1.046 | 1.793 |

- **The Mix average is unchanged:** 1.807 against 1.803 / 1.793.
- **The rows land in yet another layout:** Bubble 0.632 and QSort 0.511 match
  `6f0f159`, and Sieve 1.049 matches the marginal build. That is the
  boot-to-boot layout effect documented in `hw_p258_seed31_20260928`, not an
  RTL change: P260 touches only the 53C96.
- `mix1_table_crop.png`. All ten rows are at Itr. 1, and the run is valid.

## Idle check and Shut Down

- **Speedometer quit:** Return, Cmd-Q, then No to the Machine Record, with the
  pointer checked on the button, and an explicit button-up.
- **Idle:** the Finder then sat with no input from 19:07:31 to 19:11:31 UTC by
  the MiSTer's clock. The menu-bar clock read Tue 7:07, 7:09, 7:11
  (`idle_clocks.png`), in step with the MiSTer.
  - The UTC hour is shown on a 12-hour dial.
  - The scaled screenshot drops a pixel column, so 7:09 reads "7:05".
  - Main's `write_bytes` rose 162,656,256 → 162,934,784 over the 4 min:
    housekeeping only.
- **Keyboard:** after the idle, Cmd-W did not close the front window. The
  chord probably arrived while the window was not active; the cause is not
  known.
  - Type-select "tra" then went to that window and selected "Tutorial", the
    first name after "tra" (`idle_keyboard.png`). So the keyboard responded.
  - The Trash was not the target, as it was in the baseline session.
- **Shut Down:** vmouse `home m:111,-10 0.5 down 0.8 m:13,66 8 up`, then an
  explicit `up`.
  - Shut Down was lit before the release (`sd_lit.png`).
  - The guest reached **"It is now safe to switch off your Macintosh"**
    (`halt.png`).
  - After that, `write_bytes` was flat at 163,213,312 across 5 s, and no vmouse
    process remained.

## Verdict

**P260 passes on hardware and is the fastest disk this core has had.**

- PR Disk is up 45 % (1.699 → 2.462), and 4 MB Finder copies are 26 % faster
  (6.68 → 4.95 s). Both the read phase (+25-43 %) and the write phase
  (+37-50 %) gained, consistent with the sim's 18-34 %.
- The CPU, FPU, Mix and Graphics figures are unchanged.
- There were no hangs in 30 duplicates, which matches the `dc281d64` bound on
  the same Main. The idle clock, keyboard and mouse responded, and Shut Down
  was clean.
- The fit meets every clock (CPU +0.299 ns).

**Not covered here:** A/UX 3.1 at 32 MB and the CD audio transport (neither
image is on the box). Both remain owed for a release.

## Box state at the end

- **Guest:** halted at "It is now safe to switch off your Macintosh" (19:13 UTC).
- **Core:** `MacQuadra800` running `_Unstable/MacQuadra800.rbf`, md5 `f769b9e1`.
- **Main:** `75e00b65`. No reboot was needed.
- **Disk:** `.s0` is still the disposable disk. It now holds thirty more
  Photoshop copies: 93 items, 840.1 MB free. Nothing was deleted.
- **Config:** CFG byte 0 is `0x40`.

## `.qsf` seed-history line (ready to paste after the P260 block, above `set_global_assignment -name SEED 27`)

```
# 2026-09-29: hardware, f769b9e1 (Main 75e00b65, 32 MB): PR Disk 2.462 median (dc281d64 1.699, +45 %); Photoshop 3.0.1 Finder
# duplicate 4.95 s median over 30 (6.68 s, -26 %), read phase 2.06-2.36 MiB/s (1.65), write 1.37-1.53 (1.01); CPU 0.896, FPU
# 0.951 cold / 0.976 warm, Mix 1.807 unchanged; 30/30 duplicates, 0 hangs; idle clock and Shut Down clean
# (docs/perf/p260_hw_20260929).  SEED 27 kept.
```

## Files

- `scratch/p260_hw_20260929/`:
  - `scripts/`;
  - `run/`: PRs 1-5 and copies 1-10, with their screenshots, `*_arm.txt`
    samplers and `log.txt`;
  - `run2/`: the FPU and Mix runs;
  - `run3/`: copies 11-30;
  - `idle/`, `final/`: the idle check and Shut Down.
- This directory: the screenshots named above, plus the fit and sta summaries.
