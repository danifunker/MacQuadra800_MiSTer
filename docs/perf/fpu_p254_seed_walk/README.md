# FPU P254..P258 seed walk (2026-09-28)

The walk started on commit `2af6b30` (P254: P250..P254, dead second multiplier
removed). Seed 22 was already running when the target moved, so seed 22 is
P254. The coordinator then moved it twice. The second move came before seed 24
launched, so every later seed was built from `ad7a0d4` ("cpu: P258, FSAVE frame
words issued back to back, FRESTORE reads hinted"; P255..P258 on top of P254).
No tree was built from P256 (`b2ed1b0`). A tree for it was exported, then
removed before launch.

Recipe for each seed: `git archive <commit>` into
`scratch/fpu_<tag>_quartus_seed<N>_20260928/tree/`, with `scripts/local.env`
copied in at mode 0600. Only the `.qsf` `SEED` line was changed (the
`qsf_seed.diff` in each seed dir shows that one line). Each seed ran as a
`systemd-run --user --unit=fpu-<tag>-seed<N>-20260928 --collect bash
scripts/build_only.sh` flow. They ran one after another. Before each launch the
host had no `quartus_*` process: two CoCo3 flows from another session ran
between seeds 24 and 27, and the walk waited for them to finish.
Rehashing each tree's input manifest (176 files) after its run gave the same
hashes as before. Nothing was deployed. **No seed met the CPU clock, so no rbf
from this walk is a release candidate.**

## Results

| seed | commit | fit | ALMs | regs | M10K | DSP | CPU `general[0]` | RAM `general[1]` | HDMI | worst hold | sys→RAM / RAM→sys | RAM Summary | rbf |
|---:|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|---|
| 22 | `2af6b30` P254 | OK (59m53s) | 39,059 (93 %) | 24,656 | 468 | 36 | **−8.424** (TNS −6808.6) | +0.535 | **−1.338** (TNS −16.7) | +0.218 (HDMI) | +1.551 / +1.005 | same as P253 s21, 6 uninferred | 4,497,328 B, sha256 `3174eb5e…fd56487`, md5 `a0eedc93` |
| 24 | `ad7a0d4` P258 | **router failed** (congestion, 16618) | 39,280 (94 %) placed | 24,231 | 468 | 36 | – | – | – | – | – | same, 6 uninferred | none |
| 27 | `ad7a0d4` P258 | **router failed** (congestion + hold-routing demand) | 39,217 (94 %) placed | 24,231 | 468 | 36 | – | – | – | – | – | same, 6 uninferred | none |
| 31 | `ad7a0d4` P258 | OK (16m33s) | 39,191 (94 %) | 24,615 | 468 | 36 | **−0.226** (TNS −0.256) | +1.121 | **−0.116** (TNS −0.166) | +0.209 (HDMI) | +1.195 / +0.801 | same, 6 uninferred | 4,457,520 B, sha256 `72bc7ca45078045f4f1f87ca1778588b777b4f4f8996825e482a397d65e3acf6`, md5 `19beb5b2` |
| 23 | `ad7a0d4` P258 | **router failed** (congestion, 65m44s) | 39,304 (94 %) placed | 24,231 | 468 | 36 | – | – | – | – | – | same, 6 uninferred | none |

Full rbf sha256 for seed 22:
`3174eb5e46db0fb195cada409475ce34a5132fde581da7e276c0afff7fd56487`
(SOF `0106dd36…4078415`). Seed 31 SOF:
`89e4e26b1cc894263142fc331f602e72ea82041686074e4b25358f9838985689`.

For router failures the fit summary gives placement-stage figures, so their
register count (24,231) is lower than for the routed builds. "RAM Summary" means
the normalised `.map.rpt` RAM Summary: 99 rows, identical to the P253 seed-21
build once auto-generated instance suffixes are masked. Each build also has the
same 6 "uninferred RAM" notes (open_row, hparam, vparam, kbdFifo, m16buf, ras).
No array fell out to registers in any seed.

**Best seed: 31 on `ad7a0d4` (P258).** It misses the CPU clock by 0.226 ns and
HDMI by 0.116 ns. RAM clock and both crossings pass. It is a marginal
hardware-trial build only (`ALLOW_TIMING_VIOLATION=1`), not a release.

### Area

P254 removed the 9 DSPs P250..P253 had added, bringing DSPs from 45 back to 36.
It also took `ap040_fpu` from 4,949.5 to 4,670.3 ALMs. P255..P258 then added
back about 200 to 230 ALMs, so `ap040_fpu` is 4,871–4,899 and the design needs
39,19x–39,30x ALMs (94 %). Three of the four P258 seeds failed routing, all
with the router's "exceedingly large amount of congestion" warning. At 94 %
the P258 build is at the edge of routability. More seeds will mostly produce
more router failures.

### Seed 22 (P254): CPU failing endpoints

| slack | from | to |
|---:|---|---|
| −8.424 | `wombat_cpu|pres_v` | `ap040_core|mem_wdata[3]` |
| −7.470 | `pres_v` | `ap040_core|m_wdat[3]` |
| −7.226 | `pres_v` | `ap040_mmu|hq_ptag[9]` |
| −7.225 | `pres_v` | `ap040_mmu|hq_ptag[18]` |
| −7.221 | `pres_v` | `ap040_mmu|hq_ptag[16]` |

The worst path is a 38.0 ns route: `pres_v` → `mem_addr[10]` → cache
`fast_store` → `c_rdata` → ALU `bm`/`ShiftRight0` → `Mux28` → core
`Selector954` → `mem_wdata[3]`. Two of its interconnect hops are 7.5 ns and
8.3 ns. The placement spread that path across the die. Every one of the top 20
endpoints starts at `pres_v`. HDMI: `osd|osd_mux` → `vga_scaler_out` din1
altshift_taps (−1.338). RAM worst: `sdram|dout[5]` → `line_hold[3][21]` (+0.535).

### Seed 31 (P258): CPU failing endpoints

Only two endpoints fail:

| slack | from | to |
|---:|---|---|
| −0.226 | `ap040_core|debug_busy` | `ap040_core|epf_data[6][8]` |
| −0.030 | `debug_busy` | `epf_data[4][15]` |
| +0.022 | `debug_busy` | `epf_data[0][10]` |
| +0.061 | `debug_busy` | `epf_data[6][6]` |
| +0.069 | `debug_busy` | `epf_data[1][4]` |

Path (29.8 ns): `debug_busy` → `sel_instr` (fan-out 140) → `mem_fc[2]` → MMU
`lk_fresh` / `pipe_ent` → `m_addr[31]` → store buffer `Equal0` / `s_ack` →
`pipe_load_direct` → `integer_pipeline|fast_read_retire` (fan-out 179) →
`retire_next_pc` → `dbrf_a_early` (fan-out 118) → `Mux1583` → `epf_data`.
This is the same loop that failed at P253 seed 21 (MMU → store-buffer ack →
`fast_read_retire` → fetch), here ending at the prefetch queue instead of
`ifr_addr`. No FPU node is on it. HDMI: `ascal|o_hacc_next[3]` →
`o_hacc_next[13]` (−0.116), a framework scaler register. RAM worst:
`a_ram[23]` → `sdram|command[2]` (+1.121).

## Stop rule and what is left

The ordered list (22, 24, 27, 31, 23) is exhausted and no seed met the CPU
clock. The walk stops here as briefed. Seeds 25, 26, 28–30 and 32+ have not
been tried on P258. The 2026-09-27 history block in the `.qsf` shows seeds
21, 23, 26, 29, 30 and 32–35 failing to route even at the smaller pre-FPU
design. Two things look more likely to close timing than further seeds: (a)
recovering the ~230 ALMs P255..P258 added, and (b) cutting the
`s_ack → fast_read_retire` fan-out cone, which is the CPU-clock limiter in both
routed P25x builds that did not blow up on placement.

## Paths

- Seed trees: `scratch/fpu_p254_quartus_seed22_20260928/`,
  `scratch/fpu_p258_quartus_seed{24,27,31,23}_20260928/`. Each has `COMMIT.txt`,
  `qsf_seed.diff`, `input_manifest.sha256`, `prelaunch_check.txt`,
  `build_stdout.log`, `tree/output_files/build_*.log`,
  `tree/output_files/MacQuadra800.{fit,sta,map}.summary`, `.fit.rpt`, `.map.rpt`
- STA detail for the routed seeds is in `tree/p254_sta/` (the directory name is
  the script's, and it is the same in the P258 tree): `cpu_setup_top20_endpoints.txt`
  (one path per endpoint), `cpu_setup_top40_summary.txt`,
  `cpu_setup_top10_detail.txt`, `hdmi_setup_top10_summary.txt`,
  `ram_setup_top12_summary.txt`, `hold_top10_summary.txt`
- Crossings (`scripts/cpu/timequest_cross_domain.tcl`):
  `tree/scratch/cross_{sys2ram,ram2sys}_fpu_p254_seed22_20260928.txt`,
  `tree/scratch/cross_{sys2ram,ram2sys}_fpu_p258_seed31_20260928.txt`
- Normalised RAM Summary: `<seed dir>/ram_summary_norm.txt`, against
  `ram_summary_ref_p253s21_norm.txt`
- Walk tooling: `scratch/fpu_p254_seedwalk_tools/` (`setup_seed.sh <N> <commit>
  <tag>`, `launch_when_free.sh`, `sta_seed.sh`, `extract_seed.sh`)

## Ready-to-paste `.qsf` comment block

To go above `set_global_assignment -name SEED 21`. The `.qsf` itself was not
edited.

```
# 2026-09-28: FPU P250..P258.  P253 (7febb2d) seed 21: 39,021 ALMs, 45 DSP, CPU -0.381 (ifr_addr loop),
# HDMI -0.947, SDRAM +0.784.  P254 (2af6b30, dead F_MULT multiply dropped, 36 DSP) seed 22: 39,059 ALMs,
# CPU -8.424 (pres_v -> cache/ALU -> mem_wdata, 7-8 ns routes), HDMI -1.338, SDRAM +0.535.
# P258 (ad7a0d4, P255..P258 +~230 ALMs, 94 %): seeds 24, 27, 23 router failed (congestion);
# 31 CPU -0.226 (debug_busy -> MMU -> s_ack -> fast_read_retire -> epf_data), HDMI -0.116, SDRAM +1.121,
# crossings +1.195/+0.801, 39,191 ALMs, 468 M10K, 36 DSP, RBF md5 19beb5b2.  Walk stopped; SEED 21 unchanged.
```
