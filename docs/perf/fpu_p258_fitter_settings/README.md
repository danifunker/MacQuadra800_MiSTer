# P258 fitter-settings trials (2026-09-28)

These trials looked for a fit of `ad7a0d4` (P258, the FPU head) that meets the
33 MHz CPU clock (`emu|pll general[0]`) by changing Quartus fitter settings
only. The RTL was not touched. The plain seed walk had found two routed seeds,
and both missed: seed 31 by 0.226 ns and the no-pipeline-loads/stores seed 21
by 0.317 ns (`docs/perf/fpu_p254_seed_walk/`,
`docs/perf/fpu_p258_nopipels_builds/`).

**Result: variant B at seed 31 (placement effort 2.0 + router timing
optimisation MAXIMUM) meets every clock.** CPU +0.103 ns, RAM +0.612 ns,
HDMI +0.006 ns, worst hold +0.220 ns, and no negative slack anywhere in the
STA summary. Variant A (register duplication on) did nothing: at seed 31 its
rbf is byte-identical to the plain seed-31 build, and at seed 21 the router
failed. Nothing was deployed or committed. Neither the main checkout's `.qsf`
nor `rtl/` was changed.

## Recipe

For each build, `git archive ad7a0d4` was unpacked into
`scratch/fpu_p258_fit_<variant>_seed<N>_20260928/tree/`, with
`scripts/local.env` copied in at mode 0600. Only `MacQuadra800.qsf` was edited
(`qsf.diff` in each build dir). The builds ran one at a time, in the briefed
order A31, A21, B31. Each ran as `systemd-run --user
--unit=fpu-p258-fit-<variant><N>-20260928 --collect bash
scripts/build_only.sh`, so the normal wait gate applied. Before each launch
the script checked twice, 60 s apart, that the host had no `quartus_*`
process; each check found 0 (`prelaunch_check.txt`). After launch, the cwd of
the running `quartus_*` processes was confirmed to be the build's tree. After
each run the tree's 176-file input manifest was hashed again, and it matched.
Tools are in `scratch/fpu_p258_fit_tools/`: `setup.sh <variant> <N>`,
`launch_when_free.sh`, `sta.sh`, `extract.sh`, adapted from the nopipels
run's.

### `.qsf` lines changed

Variant A, "dup" (line 46):

```
< set_global_assignment -name PHYSICAL_SYNTHESIS_REGISTER_DUPLICATION OFF
> set_global_assignment -name PHYSICAL_SYNTHESIS_REGISTER_DUPLICATION ON
```

plus `SEED 21` -> `SEED 31` for A31 (A21 left `SEED 21` as it was).

Variant B, "effort" (lines 32-33). `FITTER_EFFORT` was already
`"STANDARD FIT"` at line 30, so it was left alone. That value has been there
since the MiSTer-template scaffold (`d525370`), and Quartus logs it as "Standard
Fit compilation using maximum Fitter effort". The `.qsf` history records
nothing else about it; the only effort note is the 2026-09-24 line above
`PLACEMENT_EFFORT_MULTIPLIER` (effort 3.0 did not fix a routing failure,
`b0681d3`). `ROUTER_TIMING_OPTIMIZATION_LEVEL` was absent and was added:

```
< set_global_assignment -name PLACEMENT_EFFORT_MULTIPLIER 1.0
> set_global_assignment -name PLACEMENT_EFFORT_MULTIPLIER 2.0
> set_global_assignment -name ROUTER_TIMING_OPTIMIZATION_LEVEL MAXIMUM
```

plus `SEED 21` -> `SEED 31`. The fit report's settings table confirms that
both values took effect (Router Timing Optimization Level MAXIMUM, Placement
Effort Multiplier 2.0).

## Results

| build | fit (fitter / whole flow) | ALMs | regs | M10K | DSP | CPU `general[0]` | RAM `general[1]` | HDMI | worst hold | sys→RAM / RAM→sys | RAM Summary | rbf |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|---|
| A31 dup, seed 31 | OK (9m51s / 15m35s) | 39,191 (94 %) | 24,615 | 468 | 36 | **−0.226** (TNS −0.256) | +1.121 | **−0.116** (TNS −0.166) | +0.209 (HDMI) | +1.195 / +0.801 | 99 rows, 0 diff vs P253 s21; 6 uninferred | 4,457,520 B, sha256 `72bc7ca45078045f4f1f87ca1778588b777b4f4f8996825e482a397d65e3acf6`, md5 `19beb5b2`: **byte-identical to the plain seed-31 rbf** |
| A21 dup, seed 21 | **router failed** (16684/16618 congestion, 188026/170143/11802; fitter 14m04s / 19m24s) | 39,207 (94 %) placed | 24,231 | 468 | 36 | – | – | – | – | – | same | none |
| **B31 effort, seed 31** | OK (13m14s / 19m00s; 16684 congestion warning, but routed) | 39,191 (94 %) | 24,675 | 468 | 36 | **+0.103** (0 failing) | +0.612 | **+0.006** | +0.220 (HDMI); CPU +0.258, RAM +0.434 | +1.432 / +0.586 | same | 4,463,260 B, sha256 `7f6c835be1ed5bc4944cd697b01237838dbf3b92803a6e2c0ba5ae37787fe79c`, md5 `b7e88b81` |

B31 SOF sha256:
`643ad503c4f9e2cc386565f0d0c473d1ec78c1938bfdff3949260e2c0910a7b0`. Every
setup, hold, recovery, removal and minimum-pulse-width slack in B31's
`.sta.summary` is positive. "RAM Summary" means the normalised `.map.rpt` RAM
Summary (`ram_summary_norm.txt` in each build dir). All three builds match the
P253 seed-21 reference, and each has the same 6 "uninferred RAM" notes:
open_row, hparam, vparam, kbdFifo, m16buf and ras. No array fell out to
registers. For the router failure, the fit summary gives placement-stage
figures (hence 24,231 registers).

### A: register duplication is a no-op here

With `PHYSICAL_SYNTHESIS_REGISTER_DUPLICATION ON`, the fit report's settings
table shows "Perform Register Duplication for Performance: On". Even so, the
physical-synthesis log runs the same algorithms as the recipe does: register
retiming and combinational resynthesis. No register-duplication pass appears.
At seed 31 the fitter produced the same bitstream, bit for bit. At seed 21 the
netlist is also presumably unchanged. That fit failed routing, which is new
information about `ad7a0d4` as committed at seed 21, not an effect of the
setting. On this Quartus 17.0 Lite / Cyclone V flow, the setting does not
change the fit.

### A31: CPU failing endpoints (same as the plain seed 31)

| slack | from | to |
|---:|---|---|
| −0.226 | `ap040_core|debug_busy` | `ap040_core|epf_data[6][8]` |
| −0.030 | `debug_busy` | `epf_data[4][15]` |
| +0.022 | `debug_busy` | `epf_data[0][10]` |
| +0.061 | `debug_busy` | `epf_data[6][6]` |
| +0.069 | `debug_busy` | `epf_data[1][4]` |

HDMI: `ascal|o_hacc_next[3]` → `o_hacc_next[13]` (−0.116). RAM:
`a_ram[23]` → `sdram|command[2]` (+1.121).

### B31: CPU worst endpoints (all met)

| slack | from | to |
|---:|---|---|
| +0.103 | `ap040_core|ifr_addr[12]` | `ap040_core|epf_data[0][3]` |
| +0.375 | `ifr_addr[12]` | `epf_data[6][0]` |
| +0.400 | `ifr_addr[12]` | `epf_data[6][15]` |
| +0.486 | `ifr_addr[12]` | `epf_data[0][12]` |
| +0.545 | `ifr_addr[12]` | `epf_data[2][1]` |

The worst path takes 29.5 ns. It starts at `ifr_addr[12]` and goes through
`mem_addr[12]` and cache `a_set[0]` (fan-out 96). It then passes the ATC
`u_hit` and `m_addr[30:22]`, the store buffer `Equal0` and `s_ack`,
`pipe_load_direct`, `empty_after_retire`, `rd_bcc_fl` and `Mux99`,
`epf_super` (25), `brf_seed_a` (30) and `Add182`, and ends at `epf_data`.
This is the same MMU → store-buffer ack → retire → branch-target →
prefetch-queue loop that limited both earlier routed builds, now closed with
0.103 ns to spare. No FPU node is on it. HDMI worst: `ascal|o_hcpt[7]` →
`o_radl1[9]` (+0.006). RAM worst: `sdram_beat32|wq_wp_handoff[3]` →
`a_ram[23]` (+0.612). Worst hold: `ascal` `mask_bypass` shift taps →
`o_h_poly_phase.t3[8]` (+0.220).

## Reading

- Placement effort 2.0 with router timing optimisation MAXIMUM turned seed
  31's −0.226 ns CPU miss into +0.103 ns. The ALMs stayed the same (39,191)
  and 60 registers were added (24,675 vs 24,615). It cost about 3.4 minutes
  more fitter time (13m14s vs 9m51s). All four clocks meet, so B31 is
  timing-clean under the release bar. HDMI has only +0.006 ns of margin.
- This is one seed. The router still printed the "exceedingly large amount of
  congestion" warning at B31, and 94 % ALMs remains at the edge of
  routability. Placement effort 3.0 failed routing on the 2026-09-24 interim
  design. The settings help once a seed routes. They do not stop other seeds
  from failing to route.
- B31 still needs the hardware gate before it can be a release (Mac OS 8.1,
  A/UX 3.1 at 32 MB, CD audio). The next step is to deploy B31's rbf from
  `scratch/fpu_p258_fit_effort_seed31_20260928/tree/output_files/` with plain
  `deploy_screenshot.sh`; `ALLOW_TIMING_VIOLATION` is not needed.
- To adopt it, put the two variant-B lines and `SEED 31` in the main `.qsf`
  and rebuild. A rebuild of the same tree is expected to reproduce this
  bitstream (A31 reproduced the plain seed-31 rbf exactly). Check its sha256
  against the one above.

## Paths

- Build dirs: `scratch/fpu_p258_fit_{dup_seed31,dup_seed21,effort_seed31}_20260928/`.
  Each has `COMMIT.txt`, `qsf.diff`, `input_manifest.sha256`,
  `prelaunch_check.txt`, `build_start.txt`, `build_done.txt`,
  `build_stdout.log`, `ram_summary_norm.txt`,
  `tree/output_files/{MacQuadra800.*.summary,.fit.rpt,.map.rpt,build_*.log}`.
- STA for the routed builds is in `tree/p254_sta/`: `cpu_setup_top20_endpoints.txt`,
  `cpu_setup_top40_summary.txt`, `cpu_setup_top10_detail.txt`,
  `hdmi_setup_top10_summary.txt`, `ram_setup_top12_summary.txt`,
  `hold_top10_summary.txt`.
- Crossings: `tree/scratch/cross_{sys2ram,ram2sys}_fpu_p258_fit_<variant>_seed31_20260928.txt`.
- Tools: `scratch/fpu_p258_fit_tools/`.

## Ready-to-paste `.qsf` comment block

This goes under the 2026-09-28 FPU blocks, above `set_global_assignment -name SEED 21`:

```
# 2026-09-28: P258 (ad7a0d4) fitter-settings trials (docs/perf/fpu_p258_fitter_settings).
# PHYSICAL_SYNTHESIS_REGISTER_DUPLICATION ON is a no-op on this flow: seed 31 rbf byte-identical
# (CPU -0.226), seed 21 router failed.  PLACEMENT_EFFORT_MULTIPLIER 2.0 + ROUTER_TIMING_OPTIMIZATION_LEVEL
# MAXIMUM (FITTER_EFFORT stays STANDARD FIT) at seed 31: all clocks met -- CPU +0.103 (ifr_addr ->
# ATC -> s_ack -> brf_seed_a -> epf_data), SDRAM +0.612, HDMI +0.006, hold +0.220, crossings
# +1.432/+0.586, 39,191 ALMs, 468 M10K, 36 DSP, fitter 13m14s, RBF md5 b7e88b81.
```

To adopt B31 as the recipe, change lines 32 and 401 of the `.qsf` to:

```
set_global_assignment -name PLACEMENT_EFFORT_MULTIPLIER 2.0
set_global_assignment -name ROUTER_TIMING_OPTIMIZATION_LEVEL MAXIMUM
...
set_global_assignment -name SEED 31
```
