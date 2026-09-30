# P263 seed walk: one FPU state frame (6ce38c8), 2026-09-30

`6ce38c8` (P263) removes the core's FRESTORE staging and the FPU's duplicate copies of the
state frame.  It sits on top of the P261/P262 features (`video_freak` integer scaling,
`pll_cfg` 512x384, SCC RR0 CTS).  This walk looks for a seed that meets every clock with
that design.

**Result: seed 24 is clean.**  It meets every clock: CPU +0.507, RAM +0.834, HDMI +0.310,
worst hold +0.219.  Its rbf (md5 `49951492`) and its `.fit` / `.sta` / `.map` summaries are
staged in `output_files/`.  They replace the seed 23 fallback staged earlier (md5 `920ffa2a`),
which had replaced the P262 seed 23 rbf (md5 `48a23a78`).

The walk ran in two parts:

1. **Seeds 23, 27, 28, 31** (the first walk, with a stop three seeds after a fallback):
   - Seed 23 was a fallback: CPU +0.073 and RAM +0.943 met, HDMI -0.157 (TNS -0.180, two
     endpoints, the framework's `ascal` to `mask_bypass` shift-tap M10K).
   - 27 and 28 failed on routing congestion.
   - 31 routed but missed the CPU clock by -0.117.
   - The walk stopped there, with seed 23 staged.
2. **The continuation** (requested order 24, 25, 26, 29, 30, 32 to 36, no fallback stop):
   - Seed 24, the first seed run, met every clock.
   - The walk stopped there.  Seeds 25, 26, 29, 30 and 32 to 36 were not run.

## Build

- **Trees:** `scratch/p263_quartus_seed{23,27,28,31,24}_20260930/tree/`, from `git archive 6ce38c8`.
  - Only the `SEED` line was edited: none for 27, one line for the others (`qsf.diff`).
  - Each tree has 178 input files (`input_manifest.sha256`); `COMMIT.txt` gives the full hash.
- **Tooling:** `scratch/p263_fit_tools/`.
  - `setup.sh`, `sta.sh` and `extract.sh` are the p261 tools with the new prefix and date.
  - `walk.sh` is the first driver.  `walk2.sh` is the continuation, the same driver with no fallback budget.  It checks twice, 60 s apart, that no `quartus_*` process is running.
    It then runs each flow as `systemd-run --user --unit=p263-seed<N>-20260930 --collect bash scripts/build_only.sh`.
  - Both drivers have a 60-minute silent-log watchdog.  It never fired.
  - The log is `walk.log`.
- **Host:** idle (load average about 1).  The seeds ran one at a time.

| seed | window (EDT) | Fitter elapsed | placement prep / placement / routing | result |
|---:|---|---:|---|---|
| 23 | 09-29 23:43 to 00:03 | 13m42s | 1m08s / 1m29s / 6m45s | Routed. CPU +0.073, RAM +0.943, **HDMI -0.157**. **FALLBACK** |
| 27 | 00:05 to 00:25 | 14m37s | 1m09s / 1m34s / 7m46s | **Fitter failed**, routing congestion (Warning 16684 / 16618, Error 170143 / 11802) |
| 28 | 00:26 to 00:50 | 18m10s | 1m04s / 1m29s / 11m40s | **Fitter failed**, routing congestion (Error 170143 / 11802) |
| 31 | 00:52 to 01:12 | 14m33s | 1m04s / 1m29s / 7m49s | Routed. HDMI +0.429 and RAM +0.567 met, **CPU -0.117** (TNS -0.117, 1 endpoint) |
| **24** | 01:17 to 01:35 | 12m15s | 1m04s / 1m31s / 5m25s | Routed. **CLEAN**: CPU +0.507, RAM +0.834, HDMI +0.310 |

## Results

| | **6ce38c8 s24 (clean)** | 6ce38c8 s23 (fallback) | 6ce38c8 s31 | 6ce38c8 s27 (failed) | 6ce38c8 s28 (failed) |
|---|---:|---:|---:|---:|---:|
| ALMs | 39,300 (94 %) | 39,335 (94 %) | 39,413 (94 %) | 39,467 (94 %) | 39,231 (94 %) |
| registers | 24,668 | 24,704 | 24,626 | 24,175 | 24,175 |
| M10K | 468 / 553 | 468 / 553 | 468 / 553 | 468 / 553 | 468 / 553 |
| block memory bits | 3,393,507 | 3,393,507 | 3,393,507 | 3,393,507 | 3,393,507 |
| DSP | 36 | 36 | 36 | 36 | 36 |
| CPU `general[0]` setup | +0.507 | +0.073 | **-0.117** | n/a | n/a |
| RAM `general[1]` setup | +0.834 | +0.943 | +0.567 | | |
| HDMI setup | +0.310 | **-0.157** (TNS -0.180) | +0.429 | | |
| h2f_user0 setup | +3.465 | +3.885 | +3.461 | | |
| worst hold | +0.219 (HDMI), CPU +0.257 | +0.227 (HDMI), CPU +0.253 | +0.235 (HDMI), CPU +0.269 | | |
| recovery / removal / min pulse | all positive (worst +0.505) | all positive (worst +0.505, CPU VCO pulse width) | same | | |
| crossings sys→RAM / RAM→sys | +1.201 / +0.507 | +0.943 / +0.815 | +0.567 / +0.950 | | |
| rbf size | 4,479,436 | 4,478,776 | 4,460,644 | | |
| rbf md5 | `49951492d3576add9470bc1d1ef28e5d` | `920ffa2aaac3f936a58244e020c9bac7` | `8797e8098c76bfe0c4a23c9f38ea370b` | | |
| rbf sha256 | `2627bf94d547200cfc5d2151b9487b21e379f145e3e0bb2945246f188cf7ccf0` | `f5981e131e7f943e9e3cf5bd2fb687d2fd308bfc8ab3dbe2522ca4d22416b677` | `d2488e12d22082a38d93d82bbf3d57d22ed2bb3ac6ddc4ebe4ebee8230a1f776` | | |
| SOF sha256 | `e453b882…2d917f3e` | `1ec8abea…080da2` | `0cd79ba0…1a8972` | | |

The failed fits' figures come from the failed placement.  The crossing reports show no violated paths.

**Worst paths:**

- **Seed 24 (clean):**
  - The CPU clock's worst path is the RAM→sys crossing `sdram_beat32|line_done_handoff` → `line_data[1][14]` at +0.507.
  - The worst CPU-core paths are `pres_v` → `rr_b[2]` at +0.510 and → `epf_data[0][0]` at +0.542.
  - HDMI's worst paths are `osd|osd_mux` and `mask_bypass` into the `vga_scaler_out` shift-tap, at +0.310.
  - The worst hold is +0.219, `mask_bypass_rtl_1` → `ascal|o_v_poly_phase`.

- **HDMI, s23:**
  - `ascal|o_g[3]` → `mask_bypass_rtl_0` shift-tap M10K `porta_datain_reg11` at -0.157.
  - `ascal|o_r[5]` → the same RAM's `datain_reg21` at -0.023.
  - This is the same framework scaler family as P262 s23 (-0.339), at about half the size.
- **CPU:**
  - s23: `ifr_addr[12]` → `epf_data[*]`, from +0.073.
  - s31: `wombat_cpu|pres_instr` → `epf_data[0][15]` at -0.117, then +0.119 and up.
  - Both are the fetch/`epf_data` family behind every earlier CPU miss.
- **RAM:** `sdram_beat32` `req_tgl` → `req_handoff`, then `wq_wp_handoff` / `a_ram` → `sdram|command`; every path is +0.57 or better.

The reports are in each tree's `p254_sta/` and `scratch/cross_*`, with a summary in each seed directory's `extract.txt`.

## Against the P261/P262 walk (without P263)

- **Routed fits:**
  - P262 (0063c59): 39,441 to 39,587 ALMs, 25,168 to 25,231 registers.
  - P263: 39,300 to 39,413 ALMs, 24,626 to 24,704 registers.
  - Seed 23 against seed 23: **-252 ALMs, -493 registers**.
  - The clean seed 24 is 39,300 ALMs and 24,668 registers.  Against the last clean fit (2b30d64 s27, 39,246 / 24,645), which predates `pll_cfg` and `video_freak`, that is +54 ALMs and +23 registers.
- **Failed placements:**
  - P262: 39,674 to 39,799 ALMs, 24,769 to 24,770 registers.
  - P263: 39,231 to 39,467 ALMs, 24,175 registers.
  - Change: about -200 to -570 ALMs, **-595 registers**.
- **Net:** about -100 to -250 ALMs and -500 to -600 registers.  The expected change was about -160 ALMs and -600 registers.
- **Routability:** congestion still fails fits.  Two of the five seeds failed here, against three of six on 0063c59.

## RAM Summary check

The same result holds in all three routed seeds (24, 23, 31).

- **Analysis & Synthesis RAM Summary:** 99 normalised rows.
  - It differs from the P253 seed 21 reference only in the `ncr_sbuf` row (512 x 16 where the reference has 256), as at P260 to P262.
  - The same 6 instances stay uninferred.
  - No array spilled to registers.
- **`ncr_sbuf`:** the Fitter row is 8192 bits, **1 M10K**.
- **Other blocks:** both are present, and both are logic only:
  - `pll_cfg_hdmi:pll_video_cfg`: 199 LUTs, 95 registers.
  - `video_freak:video_freak`: 220 LUTs, 372 registers.
- **M10K total:** 468 / 553, unchanged.

## .qsf comment block (ready to paste above the `SEED` line, then set `SEED 24`)

```
# 2026-09-30: P263 one FPU state frame (6ce38c8; ~39,230-39,470 ALMs 94 %, ~24,600-24,700 regs routed, -250 ALMs / -500 regs
#   against 0063c59 at the same seed; 468 M10K, 36 DSP; ncr_sbuf 1 M10K, pll_video_cfg + video_freak logic only): seed 23
#   CPU +0.073 / SDRAM +0.943 / HDMI -0.157 (fallback); seed 27, 28 FITTER FAILED (routing congestion); seed 31 CPU -0.117 /
#   SDRAM +0.567 / HDMI +0.429; seed 24 CLEAN: CPU +0.507 / SDRAM +0.834 / HDMI +0.310, hold +0.219, crossings met,
#   39,300 ALMs, 24,668 regs, rbf md5 49951492d3576add9470bc1d1ef28e5d (docs/perf/p263_fpga_20260930).  SEED 24.
set_global_assignment -name SEED 24
```

## Summaries

The summaries are in this directory, named `MacQuadra800_6ce38c8_seed<N>.{fit,sta}.summary`.
They are gitignored `*.summary` files.  Seeds 27 and 28 have a `.fit.summary` only.
`output_files/` holds seed 24's rbf and its `.fit`, `.sta` and `.map` summaries.
