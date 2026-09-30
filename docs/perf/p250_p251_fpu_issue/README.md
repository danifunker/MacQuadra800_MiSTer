# P250 + P251 FPU issue and tail trims: qualification (2026-09-28)

**Candidate:** `3c3ade857d99e7a25b6bbb29908aa3061c41a0da` (P251 on top of P250
`bfc0516`). **Baseline:** `0b2d265`. Both were exported with `git archive` into
`scratch/p251_qual_20260928/{base,cand}`, not taken from the working tree.

**P252 (`47a4888`, "FPU rounds and writes back in one clock") is NOT covered.**
It became HEAD after these runs had started. None of the results below apply to it.

| File | 0b2d265 SHA256 | 3c3ade8 SHA256 |
|---|---|---|
| `rtl/ap68040/rtl/ap040_core.v` | `82601eae9e14908ba2944b6e1e0f2d1d869135bb68e791d2b65c45fc88aa0a16` | `b3910e410802dea27b75234554cd06e8c694985b926dacd2116ffeb179f59c9a` |
| `rtl/ap68040/rtl/ap040_fpu.v` | `2d53db3ae4a04310add04eeb7919f0219197a98827ed92e410e6d4a4a90f5465` | `57173730255e63ae501581fe91cdfac2e8158db9a71281e6ad337f5809b0d419` |

All results are simulation. No Quartus, FPGA or hardware run was done.

## 1. Paired program regressions (tb_ap040_program, release CPU macros)

This follows the recipe in `docs/perf/cache_refill_20260927/xline_v2_core_regressions/`:
iverilog `-g2012`, all ten `AP040_*` macros from `MacQuadra800.qsf`,
`CACHE_CD_OFF=1 CACHE_SMALL=1 SIMULATION=1`, and the experimental integer
pipeline. vasm is `wombat-vasm/vasmm68k_mot -m68040 -no-opt`. The five recipe
targets plus `t_cache` are listed first. The other eleven programs from
`run_tests.sh` were run the same way as extra coverage. The table gives
bus-phase cycles for phases 0/1/2. Scripts: `logs/run_prog_pair.sh`,
`logs/run_prog_extra.sh`. Raw output: `logs/program_phases.txt`.

| Target | 0b2d265 | 3c3ade8 | Δ | Both pass |
|---|---|---|---|---|
| fpu | 103656 / 148702 / 148702 | 103314 / 148358 / 148358 | −342 / −344 / −344 | yes |
| fpu_frames | 8488 / 12820 / 12820 | 8488 / 12820 / 12820 | 0 | yes |
| fpu_resume | 14090 / 21162 / 21162 | 14092 / 21164 / 21164 | **+2** / +2 / +2 | yes |
| mmu | 340160 / 505494 / 505494 | same | 0 | yes |
| exceptions | 140688 / 213186 / 213182 | same | 0 | yes |
| cache | 2294 / 3382 / 3382 | same | 0 | yes |
| integer, bitfield_mmu, bitfield_cache, moves_fc, movem_restart, atcprobe, branch_early, loops_irq, refill_load, lea_d16, lea_fault | — | identical to baseline for every phase | 0 | yes (11/11) |

`tb_ap040_fpu_normalize` (release flags) passes on both: 10,336 cases.
`verilator/Makefile` has no FPU-specific `tb_*` target (its benches are
SDRAM, SCSI, CD, EASC, SONIC and the memory path, none of which the two
commits touch), so none were run. `rtl/ap68040/tb/run_tests.sh` had
already passed on HEAD in the default and LEA+XSTORE configurations
(`scratch/p250/`).

`fpu_resume` is two clocks slower. That program resumes FPSP-prepared BUSY
frames through FRESTORE. FRESTORE is one of the control and FMOVEM classes
that P250 keeps on the old wait, so this looks like a small fixed cost of the
new issue path on those instructions. It passes. It was not traced further.

## 2. FPU latency harness (`docs/perf/fpu_latency_20260928/run.sh --rev`)

Both commits were built with Verilator 5 and the release macros. The program
hex is identical for both. Every exception-count check passed. The figure is
steady-state clocks per instruction (BODY slope). Raw tables:
`logs/latency_*_lat{3,1}.txt`.

| Row | lat3 0b2d265 | lat3 3c3ade8 | lat1 0b2d265 | lat1 3c3ade8 |
|---|---:|---:|---:|---:|
| FMOVE.X FPm,FPn | 5 | 4 | 5 | 4 |
| FADD.X equal exp | 6 | 5 | 6 | 5 |
| FADD.X exp diff 5 / 40 | 7 | 5 | 7 | 5 |
| FSUB.X cancel/FADD pairs | 7 | 5.5 | 7 | 5.5 |
| FSUB.X no cancel | 8 | 6 | 8 | 6 |
| FMUL.X FPm,FPn | 7 | 5 | 7 | 5 |
| FMUL.X by 2.0 | 5 | 4 | 5 | 4 |
| FDIV.X / FSQRT.X | 29 | 28 | 29 | 28 |
| FMUL.X (A0),FPn | 11 | 8 | 11 | 8 |
| FMUL.D (A0),FPn | 12 | 9 | 12 | 9 |
| FMUL.S (A0),FPn | 11 | 8 | 11 | 8 |
| FADD.D (A0)+,FPn | 12 | 9 | 12 | 9 |
| FMOVE.X FPn,(A0) indep | 18 | 18 | 12 | 12 |
| FADD.X + FMOVE.X pair | 18 | 18 | 16 | 14 |
| FMOVE.D FPn,(A0) indep | 12 | 12 | 9 | 9 |
| FADD.X + FMOVE.D pair | 16 | 14 | 16 | 14 |
| FMOVE.S FPn,(A0) indep | 7 | 7 | 7 | 7 |
| FADD.X + FMOVE.S pair | 14 | 12 | 14 | 12 |
| FMOVE.L FPn,(A0) indep | 9 | 9 | 9 | 9 |
| FADD.X + FMOVE.L pair | 16 | 14 | 16 | 14 |
| FMOVE.D (A0),FPn | 9 | 8 | 9 | 8 |
| FCMP.X | 5 | 4 | 5 | 4 |
| FCMP.X + FBEQ.W pair | 7 | 6 | 7 | 6 |
| FMUL.X + 1 ADD.L | 7 | 6 | 7 | 6 |
| FMUL.X + 4 / + 8 ADD.L | 9 / 13 | 9 / 13 | 9 / 13 | 9 / 13 |
| FDIV.X + 8 ADD.L | 29 | 28 | 29 | 28 |
| FDIV.X + 24 ADD.L | 28.94 | 28.94 | 28.94 | 28.94 |
| FINTRZ / FMOVECR trap, RTE | 65.28 | 65.28 | 65.28 | 65.28 |
| same, FSAVE/FRESTORE/RTE | 167.22 | 167.22 | 163.22 | 163.22 |
| TRAP #0 / A-line / BSR-RTS | 58 / 62 / 10 | same | same | same |
| FBcc, ADD.L | unchanged | | | |

No row got slower.

## 3. Corpus gate

`scripts/cpu_corpus100_gate.sh` (first-100 CPU corpus, Verilator 5, every
`CPU_GATE_*` release flag) **passes on both commits**: "100 rows: 1900
field-groups match; REAL diffs: 0". Both finish in the same 28,020,490
cycles. The corpus is integer-only, so it checks that the P250 decode change
does not disturb non-FPU instructions. It does not exercise the FPU. Logs:
`logs/corpus100_*_score.log`.

## 4. Full-machine guest benchmarks (Verilator, HEAD 3c3ade8)

The sim is the production RTL from `3c3ade8`: 8+8 KB caches, all ten CPU
macros plus `SCSI_CACHE_OFF`, `--unroll-count 256`, and the RAM model
`+ram_line_model +ram_first_latency=4 +ram_line_publish_delay=2`. Each run
used a fresh copy of the golden Speedometer disk (`80d84794…`) and the
fastboot ROM hex (`045c0274…`). Controls are identical to the prior runs:
FPU `33108dcd…`, Mix `eafdd1b9…`, Color8 `fae07029…`. Each test ran one
iteration. Vemu SHA256 is `51959be7…`. The three runs ran in parallel as
systemd user units, and each exited 0 (script: `logs/run_guest.sh`).

All three setup screens (f4277) are byte-identical to the prior runs'. I
reviewed every final screen: each shows "The tests are done!", iteration 1,
and only positive, plausible times. **All three runs are valid.**

| Benchmark | 0b2d265 production (breakdown agent, `docs/perf/fpu_subtest_breakdown_20260928/`) | 6c candidate (rejected) | **3c3ade8** | 3c3ade8 vs 0b2d265 |
|---|---:|---:|---:|---:|
| FPU average | 0.698 | 0.729 | **0.745** | +6.7 % |
| Whetstone KWh/s | 3849.262 (0.739) | 3850.048 | **4057.996 (0.779)** | +5.4 % |
| Matrix Mult. s | 0.991 (0.713) | 0.928 | **0.921 (0.767)** | 7.6 % faster |
| Fast Fourier s | 0.447 (0.642) | 0.418 | **0.417 (0.688)** | 7.2 % faster |
| CPU Mix average (10 tests) | 1.798 | 1.798 | **1.809** | +0.6 % |
| Color 8-bit s | 9.878 | 9.878 | **9.878** (1.072) | unchanged (final PNG byte-identical) |

Against the original production Mix baseline, only two absolute values
change: KWhetstones 1762.002 → 1793.609 (+1.8 %) and Dhrystones 17931.816 →
17932.407. The other eight are identical: Towers .479, Quick .507, Bubble
.602, Queens .362, Puzzle .755, Permutations .712, Int. Matrix .495, Sieve
.845. The dialog
covers some middle rating cells, as in the earlier runs.

Screens are in `screens/`: `fpu_final_f7382.png`, `mix_final_f7382.png`,
`color8_final_f5525.png` and the three setup screens. Run metadata is in
`logs/*_run.meta.txt`. The full scratch runs, with gzipped logs and
`refill.tsv`, are in `scratch/p251_qual_20260928/{fpu,mix,color8}_run/`.
The `run.hda` copies and the Verilator obj_dir have been deleted.

## Verdict

At 3c3ade8, P250 + P251 pass every correctness check run here against
0b2d265 with the full release macros:

- all 17 program targets and the normalize bench pass;
- the corpus-100 gate passes;
- the latency harness's exception checks pass;
- the three full-machine guest runs complete with valid displayed results.

In the program benches the only cycle changes are FPU ones: `t_fpu` is 344
clocks faster, and `t_fpu_resume` is 2 clocks slower on the FRESTORE resume
path. In the latency harness every FPU register op is 1 to 2 clocks faster,
memory-operand ops are 1 to 3 faster, and no row regresses.

In the guest sim, the Speedometer FPU average rises from 0.698 to 0.745
(+6.7 %). That beats the rejected 6c candidate (0.729), and all three
subtests improve. CPU Mix rises to 1.809, only because its Whetstone
subtest gains. Color8 is unchanged.

This qualifies 3c3ade8 in simulation for an FPGA build. The ≥0.759 hardware
target, Quartus fit and timing, and the hardware regression gate are still
open. P252 needs its own run of this qualification.
