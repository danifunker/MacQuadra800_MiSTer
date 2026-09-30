# P250..P258 FPU work on hardware: ad7a0d4 seed 31 (2026-09-28)

Speedometer 4.02 on the MiSTer, Mac OS 8.1, 32 MB. FPU Benchmarks **0.978** median, against
0.684 on the last hardware build (`6f0f159`, the prefetch fix) and 1.011 on a real Quadra 800.
Benchmark Mix **1.793** median, Color 8-bit **9.876 / 9.829 s**. All 12 runs were valid. The
guest shut down cleanly to "It is now safe to switch off your Macintosh", although the CPU clock
misses timing by 0.226 ns.

**Second run, same evening: a timing-clean fit of the same RTL** (seed 31, placement effort 2.0,
maximum router timing effort, rbf md5 `b7e88b81`). See [Clean fit b7e88b81](#clean-fit-b7e88b81)
below. It gives FPU 0.973, Mix 1.803 and Color 9.900 / 9.851 s, with all 12 runs valid, a
responsive idle Finder and a clean shutdown.

Its Mix rows differ from the marginal build's by up to 20 % on the same RTL. Bubble Sort is 0.682 s
instead of 0.710 s, Sieve 0.842 s instead of 1.046 s, Int. Matrix 0.515 s instead of 0.463 s.
So the "Bubble Sort regression" below is **not** evidence against P250..P258.

## Build under test

| | |
|---|---|
| commit | `ad7a0d4` (P250..P258, FPU issue/latency work; P258 = FSAVE frame words back to back, FSAVE/FRESTORE hinted) |
| seed | 31 (scratch tree `scratch/fpu_p258_quartus_seed31_20260928/tree/`, only the `SEED` line changed) |
| rbf | 4,457,520 bytes, sha256 `72bc7ca45078045f4f1f87ca1778588b777b4f4f8996825e482a397d65e3acf6`, md5 `19beb5b211a5785c589b97144222ed49` (verified locally and on the box after the deploy) |
| fit | 39,191 ALMs (94 %), 468 M10K |
| timing | **CPU `general[0]` -0.226 ns (TNS -0.256)**, **HDMI -0.116 ns (TNS -0.166)**, SDRAM `general[1]` +1.121, h2f_user0 +2.715, worst hold +0.209 (HDMI); crossings sys->RAM +1.195 / RAM->sys +0.801 (`docs/perf/fpu_p254_seed_walk/README.md`) |
| status | marginal: not a release build. Deployed with `ALLOW_TIMING_VIOLATION=1` under CLAUDE.md's "try it on hardware" rule |

`MacQuadra800.sta.summary` and `MacQuadra800.fit.summary` in this directory are the fit's own.

## Box state and deploy

- The MiSTer is 10.3.89.233; the .92 box was not touched.
- First look (18:18 EDT, `before.png`): the CoCo3 core (`_Computer/CoCo3_cartfix_20260928.rbf`)
  was sitting in a BASIC `?FC ERROR IN 110` loop left by another session. The operator stopped
  there. The user then rebooted the box to the menu and confirmed it was free.
- **Main:** `/media/fat/MiSTer` md5 `ff404af92e4aa55116ee61a98941e73b`, identical to
  `MiSTer.mac_printer_fujinet_b4192cd` and installed 2026-09-28 13:40 by another session.
  - Both checks pass: `grep -a -c macquadra800` = 1, `grep -a -c "Mac write buffer"` = 1.
  - It is **not** the `45182b73` write-buffer Main of the earlier runs. The CPU-bound FPU and Mix
    numbers compare with those runs. Disk numbers would not compare (no PR/Disk test was run here).
- **Deploy:** the coordinator ran `ALLOW_TIMING_VIOLATION=1 bash scripts/deploy_screenshot.sh`
  at 18:27 EDT from the box's menu.
  - The rbf was staged as `output_files/MacQuadra800.rbf` in the main checkout. What was there
    before (md5 `8481fce4`, `31b6e99` seed 24) is kept in `scratch/hw_p258_20260928/prev_output_files/`.
  - The deploy pushed to `_Unstable/MacQuadra800.rbf` (md5 `19beb5b2` verified on the box). That
    replaced the `a0b3072` build, md5 `46b85dcc`.
  - It sent `load_core`, and the core reported `coreRunning='MacQuadra800'`.
- **Disk:** slot 0 (`config/MacQuadra800.s0`) points at the disposable
  `games/MacQuadra800/QuadSquad8-pipeline-test-20260919.hda`.
  - The deploy's seed step is create-only-if-missing, so `.s0` was left alone.
  - The master `QuadSquad8.hda` was never opened. After shutdown Main's only open image was the
    disposable copy.
  - No new copy was made: `/media/fat` is 99 % full, 3.0 GB free.
- **RAM:** the OSD config `config/MacQuadra800.CFG` byte 0 is `0x40`, so `status[4:3]` = 0 = 32 MB.
  Speedometer's Hardware Information shows Physical RAM **32768K**, Logical 32731K, integral FPU
  and MMU, ROM `$067C` (`speedo_hwinfo.png`).

## Boot

| EDT | screen |
|---|---|
| 18:27:56 | "Welcome to Mac OS" (`boot1.png`) |
| 18:28:20 | Starting Up bar, extensions loading (`boot2.png`) |
| 18:28:49 | Finder desktop with the Quad Squad and Control Panels windows open (`boot3.png`) |

The desktop came up in about 55 s after the load, with no bomb or error dialog.

Speedometer was started with the recipe of the earlier runs:
1. Two Cmd-W to close the Finder windows.
2. Type-select "speed" to pick `Speedometer 4.02 alias`, then Cmd-O (`select.png`, `speedo_open.png`).
3. Escape past the splash, Escape past the registration nag (`speedo_nag.png`, `speedo_hwinfo.png`).

## Method

- Keys went through `scripts/mister_ws.py`. Command is keycode 56: Cmd-F = `down:56 raw:33 up:56`,
  Cmd-B = 48, Cmd-G = 34, Return = 28, Cmd-Q = 16.
- **Each run:**
  1. Open the setup dialog.
  2. Screenshot it (`*_setup.png`). This is before the timed interval.
  3. Return to start.
  4. Wait without input or screenshots: 45 s for FPU and Color, 90 s for Mix.
  5. Screenshot the result with "The tests are done!" up (`*_done.png`).
- **Mix:** after the done screenshot, Return dismisses the dialog and a second screenshot shows the
  full table (`mix*_table.png`), because the dialog covers the middle of the Rat. column.
- The as-run scripts are `fpu_run.sh` and `mix_run.sh`. Their scratchpad paths are from this session.
- Every value below was read from pixel-enlarged crops of the screenshots, not OCR.
- **Setup check:** each setup screen was inspected.
  - FPU: Whetstone, Matrix Multiply and Fast Fourier checked, Iter. 1.
  - Mix: all ten tests checked, Iter. 1.
  - Color: only 8 bits/pixel checked, Iter. 1.

## FPU Benchmarks (Cmd-F, all three tests, one iteration)

| run | KWhetstones/s | rating | Matrix Mult. s | rating | Fast Fourier s | rating | **Average** |
|---|---:|---:|---:|---:|---:|---:|---:|
| 1 | 4608.740 | 0.885 | 0.723 | 0.977 | 0.289 | 0.993 | **0.951** |
| 2 | 4618.766 | 0.887 | 0.717 | 0.985 | 0.281 | 1.023 | **0.965** |
| 3 | 4570.613 | 0.877 | 0.688 | 1.026 | 0.279 | 1.030 | **0.978** |
| 4 | 4559.589 | 0.875 | 0.680 | 1.039 | 0.279 | 1.031 | **0.982** |
| 5 | 4559.464 | 0.875 | 0.681 | 1.038 | 0.278 | 1.033 | **0.982** |
| **median** | **4570.613** | 0.877 | **0.688** | 1.026 | **0.279** | 1.030 | **0.978** |

Ratings are against a Quadra 650 = 1.0. Screens: `fpu{1..5}_setup.png`, `fpu{1..5}_done.png`.

- **Warm-up:** runs 1-2 are slower on Matrix and FFT than runs 3-5, and runs 3-5 agree within 8 ms
  on Matrix and 1 ms on FFT. Whetstone moves the other way, 4609/4619 then 4560-4571.
- **Invalid runs:** none. No negative, zero or implausible times.

| | `31b6e99` hw | `6f0f159` hw (prefetch fix) | **`ad7a0d4` s31 hw** | `ad7a0d4` sim | real Quadra 800 |
|---|---:|---:|---:|---:|---:|
| FPU average | 0.687 | 0.684 | **0.978** | 0.985 | 1.011 |
| KWhetstones/s | 3855 | 3852 | **4571** | 4591 | 5457 |
| Matrix Multiply | 1.025 s | 1.017 s | **0.688 s** | 0.667 s | 0.713 s |
| Fast Fourier | 0.454 s | 0.465 s | **0.279 s** | 0.283 s | 0.288 s |

- FPU is up **43 %** on the last hardware build (0.684 -> 0.978) and reaches **96.7 %** of the
  real Quadra 800.
- Matrix Multiply and Fast Fourier now beat the real machine. Whetstone is at 84 %.
- Hardware agrees with the simulated guest (0.985) to within 0.7 %.

## Benchmark Mix (Cmd-B, all ten tests, one iteration)

| run | KWhet/s | Dhry/s | Towers | QSort | Bubble | Queens | Puzzle | Perm | Int. Matrix | Sieve | **Mix** |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | 1834.061 | 19344.619 | 0.477 | 0.531 | 0.710 | 0.361 | 0.768 | 0.703 | 0.469 | 1.046 | **1.783** |
| 2 | 1857.399 | 19366.093 | 0.477 | 0.531 | 0.710 | 0.361 | 0.768 | 0.703 | 0.463 | 1.049 | **1.793** |
| 3 | 1857.417 | 19360.169 | 0.476 | 0.532 | 0.709 | 0.362 | 0.767 | 0.709 | 0.463 | 1.046 | **1.793** |
| 4 | 1859.824 | 19337.063 | 0.477 | 0.531 | 0.710 | 0.361 | 0.768 | 0.703 | 0.462 | 1.046 | **1.794** |
| 5 | 1859.250 | 19337.123 | 0.476 | 0.532 | 0.709 | 0.362 | 0.769 | 0.703 | 0.462 | 1.046 | **1.794** |
| **median** | 1857.417 | 19344.619 | 0.477 | 0.531 | 0.710 | 0.361 | 0.768 | 0.703 | 0.463 | 1.046 | **1.793** |

Times are in seconds.

**Ratings, Quadra 605 = 1.0:**

| run | Whet | Dhry | Towers | QSort | Bubble | Queens | Puzzle | Perm | Matrix | Sieve |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | 6.236 | 1.120 | 1.340 | 1.341 | 1.071 | 1.116 | 1.422 | 1.157 | 1.718 | 1.311 |
| 2 | 6.315 | 1.121 | 1.340 | 1.341 | 1.071 | 1.116 | 1.422 | 1.157 | 1.741 | 1.308 |
| 3 | 6.315 | 1.120 | 1.343 | 1.340 | 1.072 | 1.116 | 1.424 | 1.148 | 1.737 | 1.312 |
| 4 | 6.324 | 1.119 | 1.341 | 1.341 | 1.071 | 1.116 | 1.422 | 1.157 | 1.742 | 1.312 |
| 5 | 6.322 | 1.119 | 1.341 | 1.339 | 1.071 | 1.115 | 1.421 | 1.158 | 1.741 | 1.312 |

Screens: `mix{1..5}_setup.png`, `mix{1..5}_done.png`, `mix{1..5}_table.png`.

- **Invalid runs:** none. Every run shows "The tests are done!", all ten rows at Itr. 1, and
  plausible non-zero Matrix and Sieve times.
- **One attempt did not start** and is not counted as a run (`mix_notstarted_{setup,done,table}.png`).
  The first Cmd-B was sent while FPU run 5's "tests are done" alert was still up, so the alert
  swallowed it and the following Return only dismissed the alert. No timing was taken.
- As on every earlier build, run 1 is the low one: Whetstone 1834, Int. Matrix 0.469, Mix 1.783.
  Runs 2-5 agree to 0.001 on the Mix.

**Comparison with `6f0f159`** (the last hardware build, prefetch fix; its two Mix tables are
`docs/perf/prefetchfix_20260927/run{1,2}_table.png`). `6f0f159` values are run 1 / run 2;
the `ad7a0d4` column is this run's median.

| test | `6f0f159` | `ad7a0d4` | change |
|---|---:|---:|---|
| KWhetstones/s | 1792.0 / 1789.7 | 1857.4 | +3.7 % |
| Dhrystones/s | 19416.9 / 19383.2 | 19344.6 | -0.3 % |
| Towers | 0.477 / 0.476 | 0.477 | = |
| Quick Sort | 0.516 / 0.515 | **0.531** | **2.9 % slower** |
| Bubble Sort | 0.633 / 0.632 | **0.710** | **12.2 % slower** |
| Queens | 0.362 / 0.363 | 0.361 | = |
| Puzzle | 0.775 / 0.771 | 0.768 | +0.6 % |
| Permutations | 0.703 / 0.704 | 0.703 | = |
| Int. Matrix | 0.479 / 0.477 | 0.463 | +3.2 % |
| Sieve | 1.044 / 1.050 | 1.046 | = |
| **Mix** | 1.781 / 1.781 | **1.793** | +0.7 % |

- The Mix gains 0.7 % over `faf9d98` / `6f0f159` (1.781) and reaches **94.4 %** of the real
  Quadra 800's 1.899.
- **Bubble Sort regressed 12 % and Quick Sort 3 %,** steadily in all five runs (0.709-0.710 and
  0.531-0.532).
  - *Update:* the clean fit of the same RTL gives Bubble 0.682 and Quick 0.544, with other rows
    moving as much, so these shifts are not an RTL change. See the second section. Whetstone (+3.7 %) and
  Int. Matrix (+3.2 %) more than make up for them in the average.
- The only RTL between the two builds is the CPU's P250..P258 (`git log 6f0f159..ad7a0d4 -- rtl/`).
  Candidates are integer code paths those commits touched, for example P256's decode-clock d16 /
  brief-index resolution or P257's exception-prefetch window.
- The Main change (`ff404af9`) should not affect these CPU-bound loops, but it has not been ruled
  out on hardware.

## Color Benchmarks (Cmd-G, 8 bits/pixel only, one iteration)

| run | Eight bit | rating |
|---|---:|---:|
| 1 | **9.876 s** | 1.073 |
| 2 | **9.829 s** | 1.078 |

Screens: `color{1,2}_setup.png`, `color{1,2}_done.png`.

- **Invalid runs:** none.
- **Comparison:** unchanged from `faf9d98` / `6f0f159` (9.87 / 9.944 s). The real Quadra 800 does 8.211 s.

## Wall-clock check

The guest menu-bar clock shows the UTC hour on a 12-hour dial. Its script font draws 0/8/9 as
C/E/S, which is not corruption.

| guest menu bar | MiSTer `date` (UTC) | screenshot |
|---|---|---|
| Mon 10:28 | 22:28:49 | `boot3.png` (Finder up) |
| Mon 10:30 | 22:30:23 | `speedo_hwinfo.png` |
| Mon 10:40 | ~22:40:57 | `mix1_done.png` |
| Mon 10:52 | 22:52:34 | `color2_done.png` |
| Mon 10:57 | 22:57:08 | `sd_menu_lit.png` (just before Shut Down) |

The guest clock kept step with the MiSTer's over the 29 minutes of the session.

## Shutdown

1. **Quit Speedometer:** Return, Cmd-Q, then "Save before quitting?" -> **No** (`quit.png`). The
   pointer was placed with vmouse `home m:162,129` and checked on the button before
   `down 0.3 up` (`quit_ptr.png`, `quit2.png`: Finder in front).
2. **`bash scripts/mac_shutdown.sh` failed, exit 3** (`shutdown.log`). It pinned and probed the
   Finder menu bar (Special at x=181), but the pointer never moved, which it reports as `NOCURSOR`.
   The walker drives the mouse through mrext `mouseMove`, and this box's mrext does not act on
   mouse commands (already noted in `RESUME-cpu-speed-20260923.md`). Nothing was pressed, and
   `after_walker.png` shows the Finder at rest.
3. **Shut down with the CLAUDE.md vmouse recipe**, verified in two steps:
   1. With the button up, `home m:111,-10` put the pointer on "Special" (`sd_ptr.png`).
   2. A dry run, `home m:111,-10 0.5 down 0.8 m:13,66 10 m:0,-90 0.5 up`, showed **Shut Down lit**
      during the hold (`sd_dry_after.png`). It then slid back to the title and released there, so
      nothing was selected (`sd_dry_end.png`: menu closed, vmouse exited).
   3. The real run, `home m:111,-10 0.5 down 0.8 m:13,66 8 up` (`sd_menu_lit.png`: Shut Down lit
      before the release), reached **"It is now safe to switch off your Macintosh."** at 18:57:37
      EDT (`halt.png`).
   - vmouse releases the button on exit, and no vmouse process was left.
- **After the halt:** Main (pid 19058, running `_Unstable/MacQuadra800.rbf`) had write_bytes steady
  at 4,710,400 across 5 s. Its only open image was the disposable `.hda`. The box was left at the
  halt screen, and no other core was loaded.

## Verdict

The marginal build ran cleanly on this session's workload:
- boot to the Finder
- 5 FPU runs, 5 Mix runs and 2 Color 8-bit runs, all valid, with no timer anomaly, bomb,
  or visible video fault
- Speedometer quit, and a normal Finder Shut Down to the safe-to-switch-off screen

The -0.226 ns CPU-clock miss did not show up as corruption in about 30 minutes of heavy FPU,
integer and QuickDraw load. That is evidence, not proof: a setup miss of this size can fail
rarely, or only with temperature. The results match the simulation (FPU 0.978 on hardware vs
0.985 simulated), so the P250..P258 speed-up is real.

Bubble Sort is 12 % slower, and Quick Sort 3 %, than on `6f0f159`, steadily within the session.
The clean fit of the same RTL shows row shifts of the same size in other directions, so this
is boot-to-boot or build-to-build variation, not a P250..P258 regression (second section).

Still not covered on this build: A/UX 3.1 at 32 MB, CD audio (Play/Pause/Resume/Stop, and
audible), and disk (PR) numbers on the `45182b73` Main. It is also not a release candidate until
a seed meets the CPU clock, or the release entry records the miss as CLAUDE.md requires.

The `.qsf` seed comment covering both fits is at the end of the second section.

---

## Clean fit b7e88b81

Same RTL (`ad7a0d4`), same seed 31, with two extra `.qsf` lines:
`PLACEMENT_EFFORT_MULTIPLIER 2.0` and `ROUTER_TIMING_OPTIMIZATION_LEVEL MAXIMUM`.
The scratch tree is `scratch/fpu_p258_fit_effort_seed31_20260928/`, and its `qsf.diff` shows
exactly those lines plus `SEED`.

| | |
|---|---|
| rbf | 4,463,260 bytes, sha256 `7f6c835be1ed5bc4944cd697b01237838dbf3b92803a6e2c0ba5ae37787fe79c`, md5 `b7e88b8163679a607680e2e80669f396` (on the box: `_Unstable/MacQuadra800.rbf`, md5 checked by the operator after the run started) |
| fit | 39,191 ALMs (94 %), 468 / 553 M10K |
| timing | **all met**: CPU `general[0]` +0.103, HDMI +0.006, SDRAM `general[1]` +0.612, h2f_user0 +3.086, worst hold +0.220 (HDMI); all crossings met (coordinator's check) |
| summaries | `clean_b7e88b81/MacQuadra800.{sta,fit}.summary` |

**Session:**
- **Deploy:** the coordinator ran plain `bash scripts/deploy_screenshot.sh` at 19:09 EDT from the
  halt screen of the first run. The md5 was verified on the box and `coreRunning` confirmed.
- **Main, disk, RAM:** same as the first run. Main is `ff404af9`. Slot 0 is the disposable
  `QuadSquad8-pipeline-test-20260919.hda` (`.s0` checked). `.CFG` is `0x40`, so 32 MB, and
  Speedometer shows 32768K (`clean_b7e88b81/speedo_hwinfo.png`).
- **Boot:** "Welcome to Mac OS" at 19:10:15 and the Finder desktop by 19:11:09, about 60 s after
  the load (`boot1..3.png`).
- **Method:** the same as the first run, but the order was **Mix first**, then FPU, then Color.
  Every setup screen was checked: all ten Mix tests / all three FPU tests / 8-bit only, Iter. 1.
  Values were read from enlarged crops.
- **Screenshots:** all in `clean_b7e88b81/`.

### Benchmark Mix (all ten tests, one iteration)

| run | KWhet/s | Dhry/s | Towers | QSort | Bubble | Queens | Puzzle | Perm | Int. Matrix | Sieve | **Mix** |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | 1848.712 | 19407.504 | 0.475 | 0.544 | 0.682 | 0.362 | 0.811 | 0.712 | 0.517 | 0.846 | **1.796** |
| 2 | 1864.078 | 19415.364 | 0.476 | 0.543 | 0.683 | 0.362 | 0.809 | 0.712 | 0.515 | 0.842 | **1.803** |
| 3 | 1861.206 | 19414.934 | 0.475 | 0.544 | 0.683 | 0.362 | 0.807 | 0.711 | 0.516 | 0.841 | **1.802** |
| 4 | 1860.755 | 19362.613 | 0.475 | 0.545 | 0.682 | 0.362 | 0.805 | 0.712 | 0.509 | 0.842 | **1.804** |
| 5 | 1865.219 | 19414.670 | 0.476 | 0.543 | 0.682 | 0.362 | 0.805 | 0.712 | 0.509 | 0.841 | **1.806** |
| **median** | 1861.206 | 19414.670 | 0.475 | 0.544 | 0.682 | 0.362 | 0.807 | 0.712 | 0.515 | 0.842 | **1.803** |

**Ratings, Quadra 605 = 1.0:**

| run | Whet | Dhry | Towers | QSort | Bubble | Queens | Puzzle | Perm | Matrix | Sieve |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | 6.286 | 1.123 | 1.345 | 1.309 | 1.114 | 1.115 | 1.347 | 1.143 | 1.559 | 1.623 |
| 2 | 6.338 | 1.124 | 1.343 | 1.312 | 1.113 | 1.115 | 1.351 | 1.143 | 1.563 | 1.629 |
| 3 | 6.328 | 1.124 | 1.345 | 1.310 | 1.113 | 1.115 | 1.354 | 1.144 | 1.559 | 1.632 |
| 4 | 6.327 | 1.121 | 1.345 | 1.307 | 1.114 | 1.113 | 1.357 | 1.142 | 1.583 | 1.630 |
| 5 | 6.342 | 1.124 | 1.342 | 1.312 | 1.114 | 1.115 | 1.357 | 1.143 | 1.583 | 1.631 |

Screens: `clean_b7e88b81/mix{1..5}_{setup,done,table}.png`.

**Invalid runs:** none. There was no attempt this time with a stray keystroke.

**Row medians against the marginal build and `6f0f159`** (percentages are for the clean fit; a
positive time change means slower):

| test | `6f0f159` (runs 1 / 2) | marginal `19beb5b2` | **clean `b7e88b81`** | clean vs marginal | clean vs `6f0f159` |
|---|---:|---:|---:|---:|---:|
| KWhetstones/s | 1792.0 / 1789.7 | 1857.4 | **1861.2** | +0.2 % | +3.9 % |
| Dhrystones/s | 19416.9 / 19383.2 | 19344.6 | **19414.7** | +0.4 % | = |
| Towers | 0.477 / 0.476 | 0.477 | **0.475** | -0.4 % | -0.3 % |
| Quick Sort | 0.516 / 0.515 | 0.531 | **0.544** | +2.4 % | +5.5 % |
| Bubble Sort | 0.633 / 0.632 | 0.710 | **0.682** | **-3.9 %** | +7.8 % |
| Queens | 0.362 / 0.363 | 0.361 | **0.362** | = | = |
| Puzzle | 0.775 / 0.771 | 0.768 | **0.807** | +5.1 % | +4.4 % |
| Permutations | 0.703 / 0.704 | 0.703 | **0.712** | +1.3 % | +1.2 % |
| Int. Matrix | 0.479 / 0.477 | 0.463 | **0.515** | **+11.2 %** | +7.7 % |
| Sieve | 1.044 / 1.050 | 1.046 | **0.842** | **-19.5 %** | -19.6 % |
| **Mix** | 1.781 / 1.781 | 1.793 | **1.803** | +0.6 % | +1.2 % |

**The Bubble Sort / Quick Sort question:**
- **Bubble Sort does not come back to 0.633:** it is 0.682, between the marginal 0.710 and
  `6f0f159`'s 0.633.
- **Quick Sort is slower still:** 0.544 against 0.531 on the marginal build and 0.516 on `6f0f159`.

The more important result is that **the same RTL moves individual Mix rows by up to 20 % between
the two builds**: Sieve 1.046 -> 0.842, Int. Matrix 0.463 -> 0.515, Puzzle 0.768 -> 0.807. Each is
steady to a few ms within its session. The Mix average moves only 0.6 %. Two explanations fit, and
one boot per build cannot separate them:

1. **Boot-to-boot layout.** Each boot places Speedometer's code, stack and arrays at different
   physical addresses, which changes which 8 KB-cache sets and which SDRAM open pages the inner
   loops share. The loops then stay steady until the next launch. This fits earlier history too:
   Puzzle 0.698 -> 0.878 at P212 -> P232, and Int. Matrix swings, were read at the time as
   regressions.
2. **Placement-dependent behaviour.** Only the marginal fit missed the CPU clock. A failing path
   that only feeds a performance decision (a hint, a prefetch, a way select) could pick the slow
   option without corrupting anything.

**Test that separates them:** reboot the *same* bitstream (Finder Restart, or a reload from the
halt screen) and run Mix again. If the rows move again, the answer is layout. In either case the
single-boot Bubble Sort "regression" in the first section cannot be pinned on P250..P258.
Per-row comparisons between builds need several boots per build.

### FPU Benchmarks (all three tests, one iteration)

| run | KWhetstones/s | rating | Matrix Mult. s | rating | Fast Fourier s | rating | **Average** |
|---|---:|---:|---:|---:|---:|---:|---:|
| 1 | 4543.905 | 0.872 | 0.693 | 1.020 | 0.280 | 1.027 | **0.973** |
| 2 | 4540.398 | 0.871 | 0.693 | 1.019 | 0.280 | 1.026 | **0.972** |
| 3 | 4576.135 | 0.878 | 0.696 | 1.015 | 0.280 | 1.025 | **0.973** |
| 4 | 4579.635 | 0.879 | 0.687 | 1.027 | 0.280 | 1.027 | **0.978** |
| 5 | 4562.522 | 0.876 | 0.693 | 1.019 | 0.280 | 1.027 | **0.974** |
| **median** | **4562.522** | 0.876 | **0.693** | 1.019 | **0.280** | 1.027 | **0.973** |

| | `6f0f159` hw | marginal `19beb5b2` (median) | **clean `b7e88b81` (median)** | clean vs marginal | real Quadra 800 |
|---|---:|---:|---:|---:|---:|
| FPU average | 0.684 | 0.978 | **0.973** | -0.5 % | 1.011 |
| KWhetstones/s | 3852 | 4570.6 | **4562.5** | -0.2 % | 5457 |
| Matrix Multiply | 1.017 s | 0.688 s | **0.693 s** | +0.7 % | 0.713 s |
| Fast Fourier | 0.465 s | 0.279 s | **0.280 s** | +0.4 % | 0.288 s |

- The FPU result reproduces on the clean fit to within 0.5 %: **0.973, 96 % of the real Quadra
  800 and +42 % on `6f0f159`**.
- The clean build has no warm-up in runs 1-2, unlike the marginal build's first two FPU runs.
  Here FPU ran after Mix, so the code was already warm.
- **Invalid runs:** none. Screens: `clean_b7e88b81/fpu{1..5}_{setup,done}.png`.

### Color Benchmarks (8 bits/pixel only, one iteration)

| run | Eight bit | rating |
|---|---:|---:|
| 1 | **9.900 s** | 1.070 |
| 2 | **9.851 s** | 1.075 |

These match the marginal build (9.876 / 9.829 s) and `6f0f159` (9.944 s). **Invalid runs:** none.
Screens: `clean_b7e88b81/color{1,2}_{setup,done}.png`.

### Idle check, wall clock, shutdown

- **Quit Speedometer:** Return, Cmd-Q, then No via vmouse, with the pointer checked on the button
  first (`quit_ptr.png`).
- **Idle:** the Finder then sat with no input for 4 min 14 s (`idle0..2.png`). Main's
  write_bytes rose only 3,416,064 -> 3,506,176 over those 2 minutes. After the idle, type-select
  "tra" highlighted the Trash (`idle_keyboard.png`), so the keyboard responded.

| guest menu bar | MiSTer `date` (UTC) | screenshot |
|---|---|---|
| Mon 11:11 | 23:11:09 | `boot3.png` (Finder up) |
| Mon 11:14 | ~23:14:13 | `mix1_done.png` |
| Mon 11:30 | 23:30:19 | `color2_done.png` |
| Mon 11:31 | 23:31:06 | `idle0.png` (idle start) |
| Mon 11:33 | 23:33:16 | `idle1.png` |
| Mon 11:35 | 23:35:20 | `idle2.png` |
| Mon 11:36 | 23:36:23 | `sd_menu_lit.png` |

The menu-bar clock ticked at idle and kept step with the MiSTer's clock for the whole
26-minute session.

**Shutdown** used the vmouse recipe verified in the first run:
1. `home m:111,-10` put the pointer on "Special" with the button up (`sd_ptr.png`).
2. `home m:111,-10 0.5 down 0.8 m:13,66 8 up` showed Shut Down lit before the release
   (`sd_menu_lit.png`).
3. It reached **"It is now safe to switch off your Macintosh."** at 19:36:51 EDT (`halt.png`).

- `mac_shutdown.sh` was not used, because the box's mrext ignores mouse commands (first section).
- After the halt no vmouse process remained, Main's write_bytes held at 3,854,336 across 5 s, and
  its only open image was the disposable `.hda`.
- The box is left at the halt screen.

### Verdict (clean fit)

The timing-clean build of `ad7a0d4` passes the Mac OS 8.1 half of the gate on this session:
- boot to the Finder
- 5 Mix, 5 FPU and 2 Color 8-bit runs, all valid
- the menu-bar clock ticking at idle in step with the wall clock
- keyboard and mouse responding
- a clean Finder Shut Down

Its speed matches the marginal build: FPU 0.973 vs 0.978, Mix 1.803 vs 1.793, Color 9.85-9.90 s.
So the marginal build's CPU-clock miss cost nothing visible, and the FPU gain is confirmed on a
timing-clean bitstream.

Still owed for a release:
- A/UX 3.1 at 32 MB (boot, CommandShell, `shutdown -h now`)
- the CD audio transport, and the user's ear
- ideally, a run on the `45182b73` Main or an explicit decision to qualify on `ff404af9`
- the `.qsf` recipe decision: the clean fit needs the two effort settings, not just `SEED 31`

## `.qsf` seed comment (both fits; ready to paste above `set_global_assignment -name SEED`, the `.qsf` was not edited)

```
# 2026-09-28: + P250..P258 (FPU issue/latency; ad7a0d4).  Seeds: 22 (P254, 2af6b30) CPU -8.424; 23, 24,
# 27 router failed (congestion, 39.2-39.3k ALMs placed); 31 CPU -0.226 / HDMI -0.116, SDRAM +1.121,
# 39,191 ALMs, RBF md5 19beb5b2 (hardware: FPU 0.978, Mix 1.793, Color 8-bit 9.876/9.829 s, clean).
# Seed 31 + PLACEMENT_EFFORT_MULTIPLIER 2.0 + ROUTER_TIMING_OPTIMIZATION_LEVEL MAXIMUM: MET on every
# clock (CPU +0.103, HDMI +0.006, SDRAM +0.612, h2f_user0 +3.086, hold +0.220; crossings met),
# 39,191 ALMs, 468 M10K, RBF md5 b7e88b81.  Hardware (Main ff404af9, 32 MB): FPU 0.973 median, Mix
# 1.803 median, Color 8-bit 9.900/9.851 s, all 12 runs valid, idle clock OK, clean Finder Shut Down.
# Mix rows moved up to 20 % between the two fits of the same RTL (Sieve 1.046 -> 0.842 s, Int.
# Matrix 0.463 -> 0.515 s): compare per-row times only across several boots.
# docs/perf/hw_p258_seed31_20260928/.
```
