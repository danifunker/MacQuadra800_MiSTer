# P258 without PIPELINE_LOADS / PIPELINE_STORES: seed builds (2026-09-28)

This run tried to close the CPU clock on `ad7a0d4` (P258, the FPU head). It
dropped the two CPU macros that `docs/AREA_BUDGET_20260924.md` measured as free:
`AP040_EXPERIMENTAL_PIPELINE_LOADS` and `AP040_EXPERIMENTAL_PIPELINE_STORES`.
That document found about 200 ALMs saved and no loss of speed. Seeds 31, 22 and
21 were built in that order. **None met the CPU clock (`general[0]`).** Seeds 31
and 22 failed routing. Seed 21 routed and missed by 0.317 ns. Nothing was
deployed or committed, and the main checkout's `.qsf` and `rtl/` were not
touched.

## Recipe

For each seed, `git archive ad7a0d4` was unpacked into
`scratch/fpu_p258_nopipels_seed<N>_20260928/tree/`, with `scripts/local.env`
copied in at mode 0600. Only the `.qsf` was edited (`qsf.diff` in each seed
dir):

```
401c401
< set_global_assignment -name SEED 21
---
> set_global_assignment -name SEED <N>          (unchanged for seed 21)
537,538c537,538
< set_global_assignment -name VERILOG_MACRO "AP040_EXPERIMENTAL_PIPELINE_LOADS=1"
< set_global_assignment -name VERILOG_MACRO "AP040_EXPERIMENTAL_PIPELINE_STORES=1"
---
> #set_global_assignment -name VERILOG_MACRO "AP040_EXPERIMENTAL_PIPELINE_LOADS=1"
> #set_global_assignment -name VERILOG_MACRO "AP040_EXPERIMENTAL_PIPELINE_STORES=1"
```

All the other `AP040_*` macros stayed on: XSTORE, LEA, PIPELINE, PIPELINE_PEA,
PIPELINE_P6, PIPELINE_MEMORY_ENTRY, PIPELINE_COMPARE and PIPELINE_EARLY_DRAIN.
The builds ran one at a time. Each ran as `systemd-run --user
--unit=fpu-p258-nopipels-seed<N>-20260928 --collect bash scripts/build_only.sh`,
so `build_only.sh`'s normal wait gate applied. Before each launch the script
checked twice, 60 s apart, that the host had no `quartus_*` process; the result
is in `prelaunch_check.txt`, and each check found 0. The running flow's cwd was
then confirmed to be the seed tree. After each run the tree's 176-file input
manifest was hashed again and matched. Tools:
`scratch/fpu_p258_nopipels_tools/` (`setup_seed.sh`, `launch_when_free.sh`,
`sta_seed.sh`, `extract_seed.sh`), adapted from the P254 seed walk's.

## Results

| seed | fit | ALMs | regs | M10K | DSP | CPU `general[0]` | RAM `general[1]` | HDMI | worst hold | sys→RAM / RAM→sys | RAM Summary | rbf |
|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|---|
| 31 | **router failed** (16684/16618 congestion; fitter 13m34s) | 39,301 (94 %) placed | 24,231 | 468 | 36 | – | – | – | – | – | 99 rows, 0 diff vs P253 s21; 6 uninferred | none |
| 22 | **router failed** (16684 congestion; fitter 2h00m13s) | 39,359 (94 %) placed | 24,231 | 468 | 36 | – | – | – | – | – | same | none |
| 21 | OK (fitter 13m32s) | 39,214 (94 %) | 24,627 | 468 | 36 | **−0.317** (TNS −2.130, 12 failing endpoints) | +0.303 | +0.447 | +0.188 (HDMI) | +0.541 / +1.062 | same | 4,468,008 B, sha256 `1858947a0e36b98f3140a4c99c39ac2fefab3ec1a7b3e4a69adcc09db16d2893`, md5 `4953a396` |

Seed 21 SOF sha256:
`91a9f9ecdd729aaf502560bb46e71c0926b311ac7f07e2284b56ec08dbb5967b`. For the
two router failures the fit summary reports placement-stage figures, which is
why their register count (24,231) is below that of the routed build. "RAM
Summary" means the normalised `.map.rpt` RAM Summary (`ram_summary_norm.txt`
in each seed dir). All three seeds match the P253 seed-21 reference, and each
has the same 6 "uninferred RAM" notes: open_row, hparam, vparam, kbdFifo,
m16buf and ras. No array fell out to registers.

### Seed 21: CPU failing endpoints

| slack | from | to |
|---:|---|---|
| −0.317 | `ap040_core|rr_a[0]` | `ap040_core|epf_data[4][2]` |
| −0.254 | `rr_a[0]` | `epf_data[2][5]` |
| −0.240 | `rr_a[0]` | `epf_data[6][5]` |
| −0.234 | `rr_a[0]` | `epf_data[6][7]` |
| −0.222 | `rr_a[0]` | `epf_data[0][5]` |

The worst path takes 29.9 ns. It starts at `rr_a[0]` (fan-out 29), goes through
the register-file read mux and `rdata_a[8]` / `rf_capture_a` / `la_src`, then
the `Add13` → `Equal73` compare and the `rd_bcc_fl` branch condition, then
`Mux99` and `dgo` (fan-out 91), then `brf_seed_a` → `Add183` (branch target),
and ends at `Mux1648`/`Mux1760` → `epf_data`. This is a register-to-branch-
target-to-prefetch-queue loop. No FPU node or pipeline load/store node is on
it. All 12 failing endpoints are `epf_data` bits, the same prefetch-queue
destination as the macros-on P258 seed 31, reached here by a different
launcher. HDMI worst: `ascal` `o_line3` → `o_vpix_outer` (+0.447). RAM worst:
`sdram_beat32|wq_wp_handoff[3]` → `d_ram[21]` (+0.303). Worst hold: `ascal`
`mask_bypass` shift taps → `o_h_poly_phase` (+0.188).

### The area saving did not appear at P258

`ap040_pipeline_integer` did shrink (1,490 → 1,484 ALUTs), so the macros took
effect, but the saving the ablation table measured did not appear.
Synthesis (`.map.rpt`) on `ad7a0d4` gives:

| | combinational ALUTs (whole design) | `wombat_cpu` ALUTs | `ap040_core` ALUTs (own) | registers |
|---|---:|---:|---:|---:|
| macros on (P258 seed-walk tree) | 58,955 | 39,422 | 34,183 (22,591) | 24,785 |
| LOADS + STORES off | 59,105 | 39,508 | 34,293 (22,712) | 24,785 |

The core got about 110 ALUTs *larger*. Each fitted build still used 39.2 to
39.4 k ALMs (94 %), no better than the macros-on P258 seeds (39,191 to
39,304). The ablation table's −216 ALMs was measured on the pre-FPU HEAD
(29,366 CPU ALMs). On P258 the difference is synthesis noise or worse, so
routability was unchanged: 2 of 3 seeds failed to route, against 3 of 4 with
the macros on.

## Harness check (Verilator, before the builds)

Two runs of `docs/perf/fpu_latency_20260928/run.sh --rev ad7a0d4`, each at bus
latencies 3 and 1:

- **base**: the stock `run.sh` with `--out
  scratch/fpu_p258_nopipels_harness_20260928/base_out`.
- **nopls**: a copy in `scratch/fpu_p258_nopipels_harness_20260928/nopls/`.
  `fpu_latency.py` hardcodes its Verilator `FLAGS`, so the copy drops
  `PIPELINE_LOADS` and `PIPELINE_STORES` from that tuple and pins `ROOT` to the
  repo. Everything else is unchanged.

Both builds used the same program hex (sha256 `1d3b4df4…`), and both result
files are **byte-identical**: lat3 md5 `6a6c1a8e571e1a10b246433acc7acf15`, lat1
md5 `c093ec48240a7650161b4a91bd43af7b`. That covers all 67 rows, including
every FP row and the integer `add_i` / `mulint*` / `divint*` rows. No ERROR
lines appeared in either run, and no row changed. The main checkout was clean
after both runs; the regenerated `fpu_latency.s` was identical. This harness
has little integer memory-operand traffic. The ablation table's kernel suite,
at the older HEAD, is the evidence that LOADS/STORES off costs no integer
speed.

## Stop rule and what is left

The ordered list (31, 22, 21) is used up, and no seed met the CPU clock, so
the run stops as briefed. Seed 21 (−0.317 CPU, HDMI and RAM met) is at best a
marginal `ALLOW_TIMING_VIOLATION=1` hardware trial. It is not better than the
macros-on P258 seed 31 (−0.226 CPU, −0.116 HDMI). Dropping these two macros
does not recover area at P258, so more seeds of this variant are not expected
to do better than more seeds of `ad7a0d4` as committed. The limiting paths in
both routed P258 builds end at the prefetch queue `epf_data` (here via the
branch target `brf_seed_a`, there via `fast_read_retire`/`dbrf_a_early`).

## Paths

- Seed dirs: `scratch/fpu_p258_nopipels_seed{31,22,21}_20260928/`. Each has
  `COMMIT.txt`, `qsf.diff`, `input_manifest.sha256`, `prelaunch_check.txt`,
  `build_stdout.log`, `build_done.txt`, `ram_summary_norm.txt`,
  `tree/output_files/{MacQuadra800.*.summary,.fit.rpt,.map.rpt,build_*.log}`
- Seed 21 STA: `tree/p254_sta/` (`cpu_setup_top20_endpoints.txt`,
  `cpu_setup_top10_detail.txt`, `hdmi_setup_top10_summary.txt`,
  `ram_setup_top12_summary.txt`, `hold_top10_summary.txt`), crossings in
  `tree/scratch/cross_{sys2ram,ram2sys}_fpu_p258_nopipels_seed21_20260928.txt`
- Harness: `scratch/fpu_p258_nopipels_harness_20260928/{base_out,nopls_out,nopls}/`

## Ready-to-paste `.qsf` comment block

To go under the 2026-09-28 FPU block, above `set_global_assignment -name SEED 21`:

```
# 2026-09-28: P258 (ad7a0d4) with AP040_EXPERIMENTAL_PIPELINE_LOADS/_STORES commented out (no area
# saving at P258: synthesis +150 ALUTs; FPU latency harness byte-identical).  Seeds: 31 and 22 router
# failed (congestion, 39,301 / 39,359 ALMs placed); 21 CPU -0.317 (rr_a -> rd_bcc_fl -> brf_seed_a
# -> epf_data), HDMI +0.447, SDRAM +0.303, crossings +0.541/+1.062, 39,214 ALMs, 468 M10K, 36 DSP,
# RBF md5 4953a396.  Walk stopped; macros kept on, SEED 21 unchanged.
```
