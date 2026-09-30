# P261/P262 seed walk: integer scaling + 512x384 back (b40acdd, then 0063c59), 2026-09-29

`b40acdd` adds the framework's `video_freak` (integer scaling) and brings back the
`pll_cfg` block for the 512x384 monitor option (`VIDEO_512_OFF` dropped).  Midway through
the walk the branch moved to `0063c59` (SCC RR0 CTS follows `UART_CTS`, `rtl/scc.v` and
`MacQuadra800.sv`, a few gates), and every seed after 31 was built from that commit.

**Result: no clean seed.**  Eight seeds were run before the walk was stopped on request
(the Quartus slot goes to an area-recovery change).  Five routed, three failed on
routing congestion (and one of those, b40acdd seed 31, was stopped after 90 minutes silent
in placement preparation).  No routed seed met all three clocks, and none qualified as a
fallback (CPU and RAM met, HDMI missed by under 0.15 ns).  Nothing was copied to
`output_files/`; the staged rbf there is still md5 `f769b9e1` (2b30d64 seed 27).

The chip is fuller than at P260: the routed fits are 39,441 to 39,721 ALMs (94-95 %), against
39,246 for the last clean fit (2b30d64 seed 27).  That is about +200 to +470 ALMs, in line with
the ~360 ALM estimate for `pll_cfg` + `video_freak`.  Registers rose by about 550 (24,645 to 25,168-25,254).
Three of the six 0063c59 seeds failed routing on congestion (Error 170143 / 11802, after
warnings 16684 / 16618).

## Build

- **Trees:**
  - `scratch/p261_quartus_seed{27,31}_20260929/tree/` (`git archive b40acdd`).
  - `scratch/p262_quartus_seed{24,23,25,26,28,29}_20260929/tree/` (`git archive 0063c59`).
  - Only the `SEED` line was edited: none for 27, one line for the others (`qsf.diff`).
  - Each tree has 178 input files (`input_manifest.sha256`); `COMMIT.txt` gives the full hash.
- **Tooling:** `scratch/p261_fit_tools/`. It holds `setup.sh`, `launch_when_free.sh`,
  `sta.sh` and `extract.sh`, all taking a seed, a tree prefix and a commit.
  - `walk.sh` drove b40acdd; `walk2.sh` drove the 0063c59 continuation.
  - The log is `walk.log`.
  - Each flow ran as `systemd-run --user --unit=<p261|p262>-seed<N>-20260929 --collect bash scripts/build_only.sh`,
    after two checks 60 s apart found no `quartus_*` process.
  - The seeds ran one at a time.
- **Host:** idle, load average about 1.

| seed | commit | window (EDT) | flow | placement prep / routing | result |
|---:|---|---|---:|---|---|
| 27 | b40acdd | 17:24 to 17:46 | 20m21s | 1m17s / 7m05s | Routed. CPU and RAM met, **HDMI -0.210** |
| 31 | b40acdd | 17:47 to 19:24 | stopped | placement prep did not finish in 90 min | **Stopped:** no Fitter output after 17:53, 1h54m of CPU. The two P260 seeds with long placement prep both went on to fail congestion. |
| 24 | 0063c59 | 19:26 to 20:01 | 34m43s | 1m07s / 22m36s | **Fitter failed**, routing congestion |
| 23 | 0063c59 | 20:03 to 20:22 | 18m41s | 1m07s / 5m52s | Routed. CPU +0.081, RAM met, **HDMI -0.339** |
| 25 | 0063c59 | 20:24 to 20:41 | 16m52s | 1m29s / 4m19s | **Fitter failed**, routing congestion |
| 26 | 0063c59 | 20:44 to 21:01 | 16m41s | 1m10s / 4m16s | **Fitter failed**, routing congestion |
| 28 | 0063c59 | 21:03 to 21:35 | 32m16s | 1m14s / 19m12s | Routed. HDMI and RAM met, **CPU -0.264** |
| 29 | 0063c59 | 21:38 to 22:21 | 43m05s | 1m14s / 29m44s | Routed. HDMI and RAM met, **CPU -0.663** |

The walk was stopped after seed 29.  Seeds 30 and 32 to 36 were not run.

## Results (routed seeds)

| | 2b30d64 s27 (last clean) | b40acdd s27 | 0063c59 s23 | 0063c59 s28 | 0063c59 s29 |
|---|---:|---:|---:|---:|---:|
| ALMs | 39,246 (94 %) | 39,601 (94 %) | 39,587 (94 %) | 39,441 (94 %) | 39,465 (94 %) |
| registers | 24,645 | 25,254 | 25,197 | 25,231 | 25,168 |
| M10K | 468 / 553 | 468 / 553 | 468 / 553 | 468 / 553 | 468 / 553 |
| block memory bits | 3,393,507 | 3,393,507 | 3,393,507 | 3,393,507 | 3,393,507 |
| DSP | 36 | 36 | 36 | 36 | 36 |
| CPU `general[0]` setup | +0.299 | +0.502 | +0.081 | **-0.264** (TNS -0.514) | **-0.663** (TNS -9.732) |
| RAM `general[1]` setup | +0.678 | +0.854 | +0.347 | +0.534 | +0.606 |
| HDMI setup | +0.299 | **-0.210** (TNS -2.366) | **-0.339** (TNS -0.668) | +0.098 | +0.064 |
| h2f_user0 setup | +3.589 | +3.851 | +2.286 | +3.801 | +2.809 |
| worst hold | +0.207 | +0.244 (HDMI), CPU +0.255 | +0.203 (HDMI), CPU +0.253 | +0.245, CPU +0.257, HDMI +0.262 | +0.210 (HDMI), CPU +0.253 |
| recovery / removal / min pulse | all positive | all positive (worst +0.505, CPU VCO pulse width) | same | same | same |
| crossings sys→RAM / RAM→sys | +0.707 / +0.600 | +0.863 / +0.826 | +0.347 / +0.672 | +0.534 / +0.636 | +0.925 / +0.594 |
| rbf size | 4,490,424 | 4,474,532 | 4,497,612 | 4,448,224 | 4,481,952 |
| rbf md5 | `f769b9e1` | `032e4b24` | `48a23a78` | `5bf0ee87` | `77afdff8` |

All four new rbfs are timing-failed and must not be flashed.  The crossing reports show no
violated paths.

The failed fits' figures come from the failed placement:

| Seed (0063c59) | ALMs | Registers |
|---|---:|---:|
| 24 | 39,721 (95 %) | 24,770 |
| 25 | 39,674 (95 %) | 24,769 |
| 26 | 39,799 (95 %) | 24,769 |

**Full hashes:**

| Build | rbf sha256 | SOF sha256 |
|---|---|---|
| b40acdd s27 | `4964aa47a2d00783c8748d9e0fd9dd0d8bf97d6456f74c6f1b4c4bc6414f8459` | `d0cc6964…70ffc1` |
| 0063c59 s23 | `e9cd494c29324d601b3df5fa6f4e06defee9ca44053c95d5886c33958d6e2629` | `34052edb…7c2e` |
| 0063c59 s28 | `b15cd0e0f359e12e609f068c14d1d74361ca5b759845816dc2f2792ca5b9c32a` | `9465ef0c…8025` |
| 0063c59 s29 | `8c300673e2009e251a7b022c9212fc03581663cef9ce0fa7f8266e163610c60f` | `0621abda…f1d` |

**Worst paths:**

- **HDMI:**
  - b40acdd s27: `ascal|o_vcpt_pre3[3]` → `o_vcpt_pre3[*]` (the framework scaler counter, as at 2b30d64 s31/s24).
  - 0063c59 s23: `ascal|o_r[2]` / `o_g[1]` → the `mask_bypass_rtl_0` shift-tap M10K, two endpoints.
- **CPU:**
  - s28: `epf_data[3][5]` → `epf_data[0][12]` at -0.264, then `epf_data[4][13]` at -0.150 and
    `mem_addr_q[12]` → `rr_b[1]` at -0.098; four endpoints.
  - s29: `ret_kind[0]` → `epf_data[*]`, many endpoints down to -0.663.
  - This is the same fetch/`epf_data` family as every earlier CPU miss.
- **RAM:** `sdram_beat32` handoffs (`wq_wp*`, `req_tgl`) → `a_ram` / `*_handoff`, and s29
  `rd_burst` → `SDRAM_A[12]`; all +0.35 ns or better.

The reports are in each tree's `p254_sta/` and `scratch/cross_*`, with a summary in each seed directory's `extract.txt`.

## The best two (release commit 0063c59)

1. **Seed 28:**
   - HDMI +0.098, RAM +0.534.
   - Misses the **CPU clock by -0.264 ns** (TNS -0.514, 4 endpoints).
   - A CPU miss is the kind that can corrupt memory silently, so it is not a release candidate.
2. **Seed 23:**
   - CPU +0.081, RAM +0.347.
   - Misses **HDMI by -0.339 ns** (TNS -0.668, only 2 endpoints, `ascal` → `mask_bypass` shift-tap M10K).
   - This is a video-output miss. Per CLAUDE.md it is the kind worth trying on hardware with
     `ALLOW_TIMING_VIOLATION=1`, but it is outside the 0.15 ns fallback band.

On b40acdd, seed 27 (HDMI -0.210, CPU +0.502) was the best overall, but it is the superseded commit.

## RAM Summary check

The same result holds in all five routed seeds.

- **Analysis & Synthesis RAM Summary:** 99 normalised rows.
  - It differs from the P253 seed 21 reference only in the `ncr_sbuf` row (512 x 16 where the
    reference has 256), exactly as at P260.
  - The same 6 instances stay uninferred.
  - No array spilled to registers.
- **`ncr_sbuf`:** the Fitter row is 8192 bits, **1 M10K**.
- **New blocks:** both are present in the Resource Utilization by Entity table, and both are logic only (no RAM):
  - `emu|pll_cfg_hdmi:pll_video_cfg`: 196-197 LUTs, 95 registers.
  - `emu|video_freak:video_freak`: 220-231 LUTs, 372 registers, including `video_scale_int` with its `sys_udiv` / `sys_umul`.
- **M10K total:** 468 / 553, unchanged.

## .qsf comment block (ready to paste above the `SEED` line; `SEED 27` stays)

```
# 2026-09-29: P261/P262 integer scaling + 512x384 back (b40acdd, then 0063c59 SCC CTS; ~39,440-39,800 ALMs 94-95 %, ~25,200 regs,
#   468 M10K, 36 DSP; pll_video_cfg + video_freak logic only, ncr_sbuf still 1 M10K): b40acdd seed 27 CPU +0.502 / SDRAM +0.854 /
#   HDMI -0.210; b40acdd seed 31 stopped (90 min in placement prep); 0063c59 seed 24, 25, 26 FITTER FAILED (routing congestion);
#   seed 23 CPU +0.081 / SDRAM +0.347 / HDMI -0.339; seed 28 CPU -0.264 / SDRAM +0.534 / HDMI +0.098; seed 29 CPU -0.663 /
#   SDRAM +0.606 / HDMI +0.064 -- no clean seed, walk stopped after 29 (docs/perf/p261_fpga_20260929).  SEED 27 kept.
```

## Summaries

The summaries are in this directory, named `MacQuadra800_<commit>_seed<N>.{fit,sta}.summary`.
They are gitignored `*.summary` files, like the earlier ones.  Seeds 24, 25 and 26 have a
`.fit.summary` only.
