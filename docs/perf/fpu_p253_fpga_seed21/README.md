# P250..P253 FPU commits: Quartus fit at seed 21 (2026-09-28)

A full compile of commit `7febb2d` (RTL head `3e3cc44`: P250..P253 on
`0b2d265`) in an isolated scratch project, using the committed `.qsf` as it
stands (the release recipe, `SEED 21`). Only fit and timing were checked here.
Nothing was deployed or run on hardware.

- Project: `scratch/fpu_p253_quartus_seed21_20260928/tree/` (a `git archive 7febb2d`
  export, with `scripts/local.env` copied in at mode 0600)
- Input manifest: `scratch/fpu_p253_quartus_seed21_20260928/input_manifest.sha256`
  (176 files: `rtl/`, `sys/`, `.qpf/.qsf/.sdc/.srf/.sv`, `files.qip`), sha256
  `cb064265cacbc063b3aa433bfcd5b1488c3199269f90667e99a5b6fbaf3ee08e`.
  After the run, rehashing the inputs gave the same manifest.
- Key inputs: `ap040_fpu.v` `93a89370…`, `ap040_core.v` `b3910e41…`,
  `ap040_cache.v` `7cba7f73…` (committed, not cache-v2), `.qsf` `75c69f93…`,
  `.sdc` `b2f5bd18…`
- Flow: systemd unit `fpu-p253-quartus-20260928`, 10:48–11:22 EDT (33 min 37 s),
  Quartus exit 0, log `tree/output_files/build_20260928_104830.log`
- RBF: `tree/output_files/MacQuadra800.rbf`, 4,483,492 bytes, sha256
  `62b410f329f59dd58c3b0b8718d6df34770d87324aaee6defc3ebc8c7a2a628e` (md5 `7d7db4ad`).
  SOF sha256 `2b376d8619c62c1ee0f3b7589beefa41ead28646d17cb8cccfd7774972151f74`.
  **Timing is not met, so this rbf must not be flashed as a release.**

## Result

| metric | P253 seed 21 (this) | cache-v2 seed 31 (HANDOFF-20260928) |
|---|---:|---:|
| ALMs | 39,021 / 41,910 (93 %) | 38,760 (92 %) |
| Registers | 24,647 | 24,659 |
| RAM blocks / bits | 468 / 553, 3,389,411 | 468, 3,389,411 |
| DSP blocks | 45 | 36 |
| CPU clk (`general[0]`) setup | **−0.381 ns** (TNS −0.536) | +0.623 |
| RAM clk (`general[1]`) setup | +0.784 | +0.693 |
| HDMI setup | **−0.947 ns** (TNS −1.308) | +0.206 |
| worst hold | +0.212 (HDMI) | +0.226 |
| sys→RAM / RAM→sys crossing | +1.519 / +0.623 | +0.712 / +0.759 |

These are two different seeds and two different sets of inputs. The seed-31
tree had cache-v2 and the older 6c FPU, and differs from this one in
`ap040_fpu.v`, `ap040_core.v` and `ap040_cache.v`. The table is context, not a
matched A/B.

The per-entity usage in the fitter report shows what the FPU commits cost.
`ap040_fpu` grew from 4,558.5 to 4,949.5 ALMs (+391) and from 9 to 18 DSP
blocks. The 9 extra DSPs are the design's whole DSP increase (36 -> 45).

The RAM Summary in the `.map.rpt` matches the seed-31 build's entry for entry;
only two auto-generated altshift_taps instance names trade places. The same 6
"uninferred RAM" notes appear (open_row, hparam, vparam, kbdFifo, m16buf, ras),
so no array fell out to registers.

## CPU clock failing endpoints (setup, one path per endpoint)

| slack | from | to |
|---:|---|---|
| −0.381 | `ap040_core|ifr_addr[13]` | `ap040_core|ifr_addr[2]` |
| −0.080 | `ifr_addr[13]` | `ifr_addr[10]` |
| −0.058 | `ifr_addr[13]` | `ifr_addr[20]` |
| −0.017 | `ifr_addr[13]` | `ifr_addr[28]` |
| +0.031 | `ifr_addr[13]` | `epf_data[0][4]` |
| +0.073 | `ifr_addr[14]` | `ifr_addr[13]` |
| +0.079 | `ifr_addr[13]` | `epf_data[6][4]` |
| +0.083 | `ifr_addr[13]` | `ifr_addr[9]` |
| +0.093 | `ifr_addr[13]` | `ifr_addr[18]` |
| +0.108 | `ifr_addr[13]` | `ifr_addr[11]` |

Every one of the 40 worst CPU endpoints is the instruction-fetch loop. For the
worst endpoint the 30.0 ns route is: `ifr_addr` -> `mem_addr` -> MMU
`a_set`/`u_hit`/`atc_fault` -> cache `m_req` -> store buffer `s_ack` ->
`integer_pipeline` `wb_ready`/`fast_read_retire` (fan-out 171) -> `refill_hit` ->
`ifr_size` -> `ifr_addr`. **No FPU node is on any failing CPU path.** P250's
core diff does not touch these signals either, so this looks like a seed-21
placement miss rather than an FPU regression.

P252's rounding-to-register-file logic is not among the failures. Two
FPU-related checks:
- The worst path launched from an FPU register has **+3.078 ns** slack (26.5 ns),
  and it is the P252 cone: `a_m[29]` -> `rnd_sum` adder (Add6) -> `rnd_er`
  (Add8) -> `rnd_ovf`/`rnd_unf` compare -> `round_wb_now`/done -> core
  `hint_store` -> `mem_hint_addr` -> MMU hint lookup -> `mmu|hq_ptag[16]`.
  It is not critical now, but it runs from the rounder into the MMU in one clock.
- The worst path ending in an FPU register has +5.104 ns slack
  (`sh_cnt[2]` -> `acc_hi[*]`).

## HDMI failing endpoints

`ascal|o_r[0]` -> `mask_bypass_rtl_0` altshift_taps `porta_datain_reg16`
(−0.947) and `ascal|o_r[4]` -> `…datain_reg20` (−0.361). These are framework
video registers, the seed-sensitive HDMI endpoint the `.qsf` history describes.

## Reports

All paths below are under `scratch/fpu_p253_quartus_seed21_20260928/tree/`:
`output_files/MacQuadra800.{fit,sta,map}.summary`, `.sta.rpt`, `.map.rpt`;
`p253_sta/` (CPU top-40 endpoints, top-10 detail, FPU into/out-of paths, the
worst FPU-launched path in detail, HDMI and RAM top paths);
`scratch/cross_{sys2ram,ram2sys}_fpu_p253_seed21_20260928.txt`
(`scripts/cpu/timequest_cross_domain.tcl`).
