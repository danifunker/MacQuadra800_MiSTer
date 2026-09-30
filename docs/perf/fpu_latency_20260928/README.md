# FPU latency and issue interval, 2026-09-28

Measured in simulation on the vendored AP68040 (`rtl/ap68040/rtl`) at
commit `0b2d265`, exported with `git show` so working-tree edits cannot leak
in, through `rtl/wombat_cpu.sv`: real core, FPU, MMU (off), 8+8 KB
caches (`SETW = 7`) and the two-entry store buffer, built with the release
`AP040_*` macros from `MacQuadra800.qsf` (XSTORE, LEA, PIPELINE,
PIPELINE_LOADS/STORES/PEA/P6, PIPELINE_MEMORY_ENTRY, PIPELINE_COMPARE,
PIPELINE_EARLY_DRAIN). `ce` is tied high, so one clock here is one 33 MHz CPU
clock. No RTL was changed.

## Table

Clocks per instruction, steady state, caches warm. **Issue** = 16/32/64
independent copies (different destination registers); **latency** = the same
number of dependent copies (each uses the previous result). Memory rows use a
bus model with 3 wait clocks per transaction (`+latency=3`); rows that change
at `+latency=1` show both as `lat3 / lat1`. Everything else is identical at
both latencies.

| Instruction | Issue | Latency (dep) | 68040 UM ref | Notes |
|---|---:|---:|---:|---|
| FMOVE.X FPm,FPn | 5 | 5 | – | |
| FADD.X, equal exponents | 6 | 6 | 3 | dep chain = FADD.X FP0,FP0 |
| FADD.X, exponent diff 5 | 7 | 7 | 3 | dep chain drifts to diff 6 |
| FADD.X, exponent diff 40 | 7 | 7 | 3 | any nonzero diff costs one alignment clock |
| FSUB.X, heavy cancellation | 7 | 7 | 3 | (1+2^-60) − 1.0, normalize by 60; derived, see below |
| FSUB.X, no cancellation | 8 | 8 | 3 | 1000.5 − 1.1 (diff 9) |
| FMUL.X FPm,FPn | 7 | 7 | 5 | 1.2345 × 1.0000123 |
| FMUL.X by 2.0 | 5 | – | – | power-of-two fast path |
| FDIV.X FPm,FPn | 29 | 29 | 37.5 | |
| FSQRT.X | 29 | 29 | 103 | |
| FMUL.X (A0),FPn | 11 | 11 | – | operand in D-cache |
| FMUL.D (A0),FPn | 12 | 12 | – | |
| FMUL.S (A0),FPn | 11 | 11 | – | |
| FADD.D (A0)+,FPn | 12 | 12 | – | 64 distinct doubles |
| FMOVE.X FPn,(A0) | 18 / 12 | 18 / 16 | – | latency column = FADD.X + store of its result, per pair |
| FMOVE.D FPn,(A0) | 12 / 9 | 16 / 16 | – | same pair form |
| FMOVE.S FPn,(A0) | 7 | 14 | – | same pair form |
| FMOVE.L FPn,(A0) | 9 | 16 | – | same pair form |
| FMOVE.D (A0),FPn | 9 | 9 | – | "dep" = same destination FP0 (a load reads no FP register) |
| FCMP.X FPm,FPn | 5 | 7 | – | latency column = FCMP.X + FBEQ.W on its result, per pair |
| FBEQ.W not taken | 2.3 | – | – | |
| FBNE.W taken (to next insn) | 2.2 | – | – | |
| ADD.L D0,Dn alone | 1 | – | – | integer reference |
| FMUL.X reg + 1 ADD.L | 7 per pair | 7 per pair | – | ADD fully hidden |
| FMUL.X reg + 4 ADD.L | 9 per group | – | – | = 5 + 4 |
| FMUL.X reg + 8 ADD.L | 13 per group | – | – | = 5 + 8 |
| FDIV.X reg + 8 ADD.L | 29 per group | – | – | hidden |
| FDIV.X reg + 24 ADD.L | 29 per group | – | – | = 5 + 24, still hidden |
| FINTRZ.X → vec 11, handler RTE | 65 | – | – | round trip |
| FINTRZ.X → vec 11, handler FSAVE -(SP); FRESTORE (SP)+; RTE | 167 / 163 | – | – | |
| FMOVECR #0 → vec 11, handler RTE | 65 | – | – | same as FINTRZ |
| FMOVECR #0 → vec 11, handler FSAVE/FRESTORE/RTE | 167 / 163 | – | – | |
| TRAP #0, handler RTE | 58 | – | – | |
| A-line $A000, handler ADDQ.L #2,2(SP); RTE | 62 | – | – | the ADDQ is needed: the frame PC is the A-line word |
| BSR.W to RTS (not a trap) | 10 | – | – | reference |

Trap rows are 65-66 per copy depending on alignment; 65 is the mean
(65.2-65.3). FBcc rows are 2 or 3 clocks per copy by alignment.

The reference column is only the MC68040 User's Manual execution-stage
figures that `docs/FPU_PROFILE_20260927.md` already quotes (section 10.7.3:
FADD/FSUB 3, FMUL 5, FDIV 37.5, FSQRT 103). Those are the FPU execute stage,
not full instruction cost; the other rows were not looked up.

FSUB with cancellation cannot be chained on its own (its result no longer
cancels), so the bench alternates FSUB.X FP7,FPn and FADD.X FP7,FPn with
FP7 = 1.0 and FPn = 1+2^-60: the subtract cancels to 2^-60 and the add
restores the value exactly (exponent difference 60). The pair average is
7.00 in both forms, and FADD with a nonzero difference is 7, so FSUB with
cancellation is 2 × 7 − 7 = 7. Its operands have equal exponents (no
alignment clock) but every effective subtract takes a normalize clock.

## What the numbers say

- **Issue interval equals latency for every FP op.** The FPU runs one
  operation at a time. The core holds the next FP instruction in
  `S_FPU_DEC` until the released (background) operation reports `done`.
  There is no FP pipelining, so independent code gains nothing.
- **No FP instruction takes fewer than 5 clocks.** FMOVE.X, FCMP.X and
  FMUL by 2.0 all take 5. A per-clock trace (`+tracecyc`) of back-to-back
  instructions shows where the clocks go:
  - FMOVE.X: the FPU spends one clock in `F_IDLE` accepting the request,
    then `F_EXEC`, `F_ROUND`, `F_WB`, and one more idle clock. The core
    spends 3 clocks in `S_FPU_GO` and 2 in `S_FPU_DEC`.
  - FMUL.X (7 clocks): the FPU goes `F_IDLE`, `F_BIN`, `F_MULT` ×2,
    `F_ROUND`, `F_WB`, idle. The core spends 3 clocks in `S_FPU_GO` until
    `accepted`, then 4 in `S_FPU_DEC` waiting for `done`.

  The request/accept handshake costs two clocks per operation in which no
  arithmetic happens: the FPU's idle clock after `F_WB`, while the core sees
  `done` and raises `fpu_req`, and its `F_IDLE` accept clock.
- **Integer overlap is real but small for short ops.** The core is blocked
  for at least 5 clocks per FP instruction (3 in `S_FPU_GO`, at least 2 in
  `S_FPU_DEC`). Integer instructions can only fill the rest of the FPU's
  time. For FMUL.X that is 2 clocks, so every ADD beyond two adds a clock
  (FMUL + 4 ADD = 9, + 8 ADD = 13). FDIV/FSQRT hide 24 integer clocks
  (FDIV + 24 ADD = 29 = FDIV alone).
- FADD alignment is one clock for any exponent difference (single-clock
  barrel shift), and zero for equal exponents. Normalize is one clock
  regardless of how far.
- FDIV and FSQRT are both fixed 29 clocks, faster than the 68040's execute
  stage alone (37.5 / 103). FADD (6-8) and FMUL (7) are about twice the
  68040's 3 and 5.
- Memory-operand forms add 4-5 clocks over the register form (FMUL.X (A0)
  11 against 7), with the operand in the D-cache.
- Stores are bus-bound in this model: FMOVE.X writes three longwords and
  takes 18 clocks at 3 wait clocks, 12 at 1. A store of a just-computed
  result waits for the op: FADD + FMOVE.S = 14 = 7 + 7, FADD + FMOVE.D/.L =
  16.
- The unimplemented-instruction trap with a bare RTE costs about as much as
  TRAP #0 (65 vs 58). FSAVE/FRESTORE of the UNIMP frame raises it to ~165,
  and that part depends on store latency. FINTRZ and FMOVECR behave the same.
  The bench counts one vector-11 exception per copy. FRESTORE of the saved
  UNIMP frame did not re-raise the trap.

## Speedometer Matrix / FFT forms, 0b2d265 and 2af6b30

These rows were added later on 2026-09-28 for the instruction forms the
timed-window breakdown found dominant in Speedometer's Matrix and FFT tests.
They were measured on `0b2d265` and on `2af6b30` (add-ethernet HEAD,
P250..P254). All are straight-line copies with independent destinations and
a cache-warm operand. `A0` points at single-precision data, and stores go to
a separate buffer. Every row is identical at bus latency 3 and 1: a single
S or D store fits the store buffer.

| Form | 0b2d265 | 2af6b30 |
|---|---:|---:|
| FMOVE.S (A0),FPn | 8 | 5 |
| FMOVE.S d16(A0),FPn | 12 | 9 |
| FMOVE.S d8(A0,D0.L),FPn | 12 | 9 |
| FMOVE.S FPn,(A0) | 7 | 7 |
| FMOVE.S FPn,d16(A0) | 11 | 11 |
| FMOVE.D d16(A0),FPn | 13 | 10 |
| FMOVE.D FPn,d16(A0) | 13 | 13 |
| pair FMOVE.S d16(A0),FP0 ; FMUL.X FP0,FP1 | 19 | 13 |
| pair FMUL.X FP1,FP2 ; FMOVE.S FP2,d16(A0) | 18 | 15 |
| Matrix group FMOVE.S 0(A0,D0.L),FP0 ; FMUL.X FP1,FP0 ; FADD.X FP0,FP2 ; ADDQ.L #4,D0 | 26 | 19 |
| FFT group: FMOVE.S 16(A0),FP0 ; FMOVE.S 20(A0),FP1 ; FSUB.X FP1,FP0 ; FMUL.X FP3,FP0 ; FADD.X FP0,FP1 ; FMOVE.S FP0,24(A0) ; FMOVE.S FP1,28(A0) | 65 | 53 |

Pair and group rows are clocks per pair or group.

On 2af6b30 the pairs and groups are the plain sums of their parts, with no
overlap:
- load feeding an op: 13 = 9 + 4;
- op feeding a store: 15 = 4 + 11;
- Matrix: 19, one clock more than 9 + 4 + 4 + 1 for the parts;
- FFT: 53 = 2×9 + 5 + 4 + 4 + 2×11.

The register-op figures used here (FMUL 4, FADD 4, FSUB 5) are from
`results_2af6b30_lat3.txt`.

A displacement or index costs 4 clocks on both the load and the store. P253
took 3 clocks off S/D loads but none off stores.

Clock-by-clock core state for one FMOVE.S d16(A0),FPn on 2af6b30, from
`+tracecyc`, steady state. The FPU state is `F_IDLE` throughout except for
the last clock.

| Clock | Core state | FPU state |
|---:|---|---|
| 1 | S_FPU_DEC | F_IDLE |
| 2 | S_EA_DISP | F_IDLE |
| 3 | S_IMMF (fetch the displacement word) | F_IDLE |
| 4 | S_EA_D16 | F_IDLE |
| 5 | S_FPU_EA | F_IDLE |
| 6 | S_FPU_RD | F_IDLE |
| 7 | S_MRD (D-cache hit, one clock) | F_IDLE |
| 8 | S_FPU_GO | F_IDLE (accepts) |
| 9 | S_FPU_GO | F_ROUND (writes back) |

Two related sequences from the same trace:
- FMOVE.S (A0),FPn is `S_FPU_DEC, S_FPU_RD, S_MRD, S_FPU_GO ×2` = 5.
  Clocks 2-5 above (`S_EA_DISP`, `S_IMMF`, `S_EA_D16`, `S_FPU_EA`) are the
  whole displacement cost.
- The indexed form d8(A0,D0.L) takes the same 9 clocks, with `S_EA_EXTW2`
  in place of `S_EA_D16`.

The d16 store FMOVE.S FPn,d16(A0) is 11 clocks:

| Clocks | Core state | FPU state |
|---:|---|---|
| 1 | S_FPU_DEC | |
| 3 | S_EA_DISP, S_IMMF, S_EA_D16 | |
| 1 | S_FPU_EA | |
| 4 | S_FPU_GO | F_IDLE, F_SRC, F_STDONE, F_IDLE |
| 1 | S_MWR | |
| 1 | S_FPU_WR | |

Full per-commit results, with the old rows re-measured in this layout:
- `results_0b2d265_lat3.txt`
- `results_0b2d265_lat1.txt`
- `results_2af6b30_lat3.txt`
- `results_2af6b30_lat1.txt`

For this extension the program moved to $10000 (bench RAM is now 256 KB).
The old rows on 0b2d265 reproduce the table above to within 0.1 clock,
except two that changed with the new layout:
- the BSR/RTS reference, whose RTS is now next to the block: 8.3;
- A-line, 63.

## Trap and FSAVE/FRESTORE traces, b2ed1b0

This section is one steady-state copy of each row, traced clock by clock on
`b2ed1b0` (add-ethernet HEAD, P256) at bus latency 3. `trace_copy.py` makes
the traces; the full per-clock tables, with every state, request, address and
written word, are in `traces_b2ed1b0.md`.

**How to read the tables:**
- **SP** is the supervisor stack pointer when the copy starts ($3F000).
- **data** counts clocks in `S_MRD`/`S_MWR`, the core waiting for a data
  access. Every access here is a D-cache hit or a store-buffer write, so each
  takes 2 clocks.
- **ifetch** counts clocks waiting for an instruction fetch: `S_EPF_FILL`,
  or `S_FETCH` with a fetch outstanding.
- **internal** counts every other clock, which is sequencing.
- The phase "refetch" is the fetch of the next copy's instruction after the
  previous copy's RTE. It is counted at the start of each copy.

The two new rows (4) were added to the harness for this (keys `fsnull` and `fsidle`; full b2ed1b0 results in `results_b2ed1b0_lat{1,3}.txt`). On b2ed1b0 at both
bus latencies, FSAVE -(A7) ; FRESTORE (A7)+ is 11 clocks per pair with a
NULL frame and also 11 with an IDLE frame. The trap rows on b2ed1b0 are
unchanged from the first table: TRAP 58, A-line 63, FINTRZ + RTE 65-66,
FINTRZ + FSAVE/FRESTORE/RTE 167 (163 at latency 1).

### (1) TRAP #0 → handler RTE: 58 clocks

| Phase | Clocks | data | ifetch | internal | States |
|---|---:|---:|---:|---:|---|
| refetch | 3 | | 3 | | S_FETCH |
| TRAP decode | 1 | | | 1 | S_DECODE |
| exception entry | 15 | 8 | | 7 | S_EXC0, S_EXC1, S_MWR (W SP−8 SR), S_EXC2, S_MWR (W SP−6 PC), S_EXC3, S_MWR (W SP−2 format/vector), S_EXC5, S_EXC_VEC, S_MRD (R vector $80), S_EXC_JMP |
| handler prefetch fill | 26 | | 18 | 8 | 8 × S_EPF_FILL (one halfword each, 2-3 clocks) with S_EPF_GAP between, S_EPF_READY |
| RTE | 13 | 6 | | 7 | S_FETCH, S_DECODE, S_RTE_SR, S_MRD (R SP−8), S_RTE_PC, S_MRD (R SP−6), S_RTE_FMT, S_MRD (R SP−2), S_RTE_FIN, S_RTE_FIN2 |
| **total** | **58** | 14 | 21 | 23 | |

### (2) A-line $A000 → handler ADDQ.L #2,2(SP); RTE: 63 clocks

| Phase | Clocks | data | ifetch | internal | States |
|---|---:|---:|---:|---:|---|
| refetch | 3 | | 3 | | S_FETCH |
| A-line decode | 1 | | | 1 | S_DECODE |
| exception entry | 15 | 8 | | 7 | as TRAP (format 0, vector read $28) |
| handler prefetch fill | 26 | | 18 | 8 | 8 × S_EPF_FILL / S_EPF_GAP, S_EPF_READY |
| ADDQ.L #2,2(SP) | 6 | 3 | | 3 | S_FETCH, S_DECODE, S_PIPE_START, S_MRD (R SP−6, 1 clock), S_MWR (W SP−6, 2) |
| RTE | 12 | 6 | | 6 | S_DECODE, then as TRAP's RTE |
| **total** | **63** | 17 | 21 | 25 | |

### (3) FINTRZ.X → vector 11 → handler FSAVE -(SP); FRESTORE (SP)+; RTE: 167 clocks

| Phase | Clocks | data | ifetch | internal | States |
|---|---:|---:|---:|---:|---|
| refetch | 3 | | 3 | | S_FETCH |
| FINTRZ dispatch | 5 | | | 5 | S_DECODE, S_IMMF, S_FPU_DEC, S_FPU_GO ×2 (FPU reports unimp) |
| exception entry (format $2) | 18 | 10 | | 8 | S_EXC0_F2, S_EXC1, S_MWR (W SP−12 SR), S_EXC2, S_MWR (W SP−10 PC), S_EXC3, S_MWR (W SP−6 format/vector $202C), S_EXC4, S_MWR (W SP−4 address), S_EXC5, S_EXC_VEC, S_MRD (R vector $2C), S_EXC_JMP |
| handler prefetch fill | 26 | | 18 | 8 | 8 × S_EPF_FILL / S_EPF_GAP, S_EPF_READY |
| FSAVE -(SP) | 60 | 30 | | 30 | S_FETCH, S_DECODE, S_EA_DISP, S_FSAVE1, then 13 × (S_FSAVE_U, S_MWR, S_FSAVE_UD): 13 longwords, the 52-byte $41 UNIMP frame at SP−64..SP−16 |
| FRESTORE (SP)+ | 43 | 26 | | 17 | S_DECODE, S_EA_DISP, S_FREST1, S_MRD (SP−64), S_FREST2, then 12 × (S_MRD, S_FREST_U), S_FREST_UD |
| RTE | 12 | 6 | | 6 | S_DECODE, S_RTE_SR, S_MRD (SP−12), S_RTE_PC, S_MRD (SP−10), S_RTE_FMT, S_MRD (SP−6), S_RTE_FIN, S_RTE_FIN2 |
| **total** | **167** | 72 | 21 | 74 | |

At latency 3 the last two FSAVE writes take 4 clocks each instead of 2,
because the two-entry store buffer is full. At latency 1 FSAVE is 56 and the
round trip 163.

For comparison, the same trap with a bare-RTE handler is 66:
- refetch 3;
- dispatch 6;
- entry 18;
- prefetch fill 26;
- RTE 13.

### (4) FSAVE -(A7) ; FRESTORE (A7)+ with the FPU idle: 11 clocks per pair

| Phase | Clocks | data | internal | States |
|---|---:|---:|---:|---|
| FSAVE -(A7) | 5 | 2 | 3 | S_DECODE, S_EA_DISP, S_FSAVE1, S_MWR (W SP−4, 2 clocks) |
| FRESTORE (A7)+ | 6 | 2 | 4 | S_DECODE, S_EA_DISP, S_FREST1, S_MRD (R SP−4, 2 clocks), S_FREST2 |

The NULL frame (FPU never used, written as $00000000) and the IDLE frame
after an FMOVE ($41000000, checked in the trace) take identical sequences,
both 4-byte frames.

### What the traces show

- **The handler prefetch fill is the largest single phase of every trap:
  26 clocks.** Before the handler's first instruction decodes, the core
  fills its prefetch queue with 8 halfword fetches from the I-cache. Each
  takes 2-3 clocks, with a gap clock between. The handler's RTE is one word.
  Exception entry itself is 15 clocks (18 for the format-2 FP frame), and
  RTE is 12-13.
- A TRAP round trip is 58 clocks: 14 data, 21 instruction fetch, 23
  sequencing.
- The FPU part of vector 11 is small: FINTRZ dispatch is 5 clocks, and the
  format-2 frame's extra longword costs 3 (S_EXC4 plus its write). FSAVE of the UNIMP frame is 60 clocks (13 × 4 +
  8) and FRESTORE is 43 (13 × 3 + 4). Together they are 103 of the 167
  clocks, and each longword spends 1-2 sequencing clocks beside its 2-clock
  access.

To reproduce:

```bash
docs/perf/fpu_latency_20260928/run.sh --rev b2ed1b0 --out scratch/fpu_latency_20260928/rev_b2ed1b0 --keep-obj
python3 docs/perf/fpu_latency_20260928/trace_copy.py scratch/fpu_latency_20260928/rev_b2ed1b0 b2ed1b0 trap
#   rows: trap aline fintrz_rte fintrz_fs; add --per 2 for fsnull fsidle; --latency 1 for the other bus latency
```

## Harness

- `tb_fpu_latency.sv` is modelled on `verilator/tb_cpu_permute.sv`. It has
  `wombat_cpu` with `ce` = 1, 256 KB of RAM (program at $10000,
  data at $38000, stack below $3F000; 128 KB with code at $400 for the first table), and a fixed-latency responder
  (`+latency=N` wait clocks per 32-bit transaction). It is **not** the
  quadra800 SDRAM path, so memory-bound rows are model numbers.
  - A word write to `$F108` is a stamp. At its bus acknowledge the bench
    prints the clocks since the previous stamp, plus the exception entries
    (`S_EXC0*`) and the last vector.
  - The **BODY** line gives the clocks from the decode PC (`pc_i`) reaching
    the first body instruction to it reaching the closing `FNOP`. It
    excludes the stamp stores and the closing FNOP's wait.
  - `+tracelo=/+tracehi=` (hex) with optional `+tracecyc` prints a PC, core
    state and FPU state trace for a window. `+tracec0=/+tracec1=` (decimal
    clocks) prints every clock in a range. Each line also has the core-side
    memory request: fetch/read/write, address, write data and acknowledge.
    `trace_copy.py` uses the clock range to trace exactly one copy.
- `fpu_latency.py` generates `fpu_latency.s`, assembles it with vasm, and
  builds the bench with Verilator 5 using the production macros, as
  `scripts/cpu/run_whetstone_image.py` does. It runs the bench at latency 3
  and 1 and prints the tables. It also checks the exception counts: each
  trap row has exactly one exception of the expected vector per copy, and
  every other row has none.
  - Each test is a straight-line block of 16, 32 and 64 copies. Each block
    starts with `FNOP; NOP; move.w #1,$F108` and ends with
    `FNOP; move.w #tag,$F108`.
  - Each block runs twice, and only the second (warm-cache) pass is used.
  - The reported figure is `(BODY(64) − BODY(32)) / 32`, which removes all
    fixed start and end costs. The stamp-to-stamp slopes (`32-16`, `64-32`)
    and `(stamp16 − empty block)/16` are in the results files. They agree
    except where the closing FNOP's wait varies with code alignment (FBcc,
    FMOVE.D store at latency 3).
- `fpu_latency.s` is the generated program. It is committed so it can be
  read without running the generator. The per-test instruction bodies are
  defined in `fpu_latency.py` (list `T`).
- `results_lat3.txt` and `results_lat1.txt` hold the raw output of the run
  behind the first table (0b2d265, old layout); `results_<commit>_lat*.txt`
  hold the runs behind the Matrix / FFT section. Columns: stamp clocks for 16/32/64 copies, the 64-copy cold pass,
  the stamp slopes, per16, BODY clocks for 16/32/64 copies, and the reported
  `body` slope.

## Re-run

```bash
docs/perf/fpu_latency_20260928/run.sh              # ~1 min; latencies 3 and 1
docs/perf/fpu_latency_20260928/run.sh --latency 3 --keep-obj   # keep the Verilator build for tracing
docs/perf/fpu_latency_20260928/run.sh --worktree --out scratch/fpu_latency_20260928/worktree  # working-tree RTL
docs/perf/fpu_latency_20260928/run.sh --rev <commit> --out scratch/fpu_latency_20260928/rev_<commit>  # another commit's RTL
scratch/fpu_latency_20260928/obj/Vtb_fpu_latency +prog=scratch/fpu_latency_20260928/fpu_latency.hex \
    +latency=3 +tracelo=1BB38 +tracehi=1BB50 +tracecyc      # addresses from the .lst of that build
```

`run.sh` starts a transient user unit (`systemd-run --user --collect
--pipe --wait`). Outputs go to `scratch/fpu_latency_20260928/`: hex,
listing, logs and `results_lat*.txt`. The Verilator `obj` directory is
deleted afterwards unless `--keep-obj` is given. It needs vasm at
`/home/alans/mister/MacQuadra800_fixtures/wombat-vasm/vasmm68k_mot` (or
`$VASM`) and Verilator 5 at `/home/alans/verilator5/bin/verilator` (or
`$VERILATOR`).

## Side measurement: uncommitted P250 working tree

While this was being measured, another session had an uncommitted edit to
`rtl/ap68040/rtl/ap040_core.v` in the working tree ("P250: FPU issue
overlap"). It adds `S_FPU_ISSUE`, so the decode, EA and operand read of the
next FP instruction overlap the background operation. `run.sh --worktree`
measured that tree once (not qualified, and it may have changed since):

| Row | 0b2d265 | P250 tree |
|---|---:|---:|
| FMUL.X (A0),FPn | 11 | 8 |
| FMUL.D (A0),FPn | 12 | 9 |
| FMUL.S (A0),FPn | 11 | 9 |
| FADD.D (A0)+,FPn | 12 | 10 |
| FMOVE.D (A0),FPn | 9 | 8 |

Every other row, including all register-to-register rows, was unchanged.
Those rows are set by the handshake described above, not by the decode
wait.

## Limits

- Timing is from the 33 MHz CPU domain with a fixed-latency memory model;
  hardware SDRAM latency changes the store rows and the FSAVE handler row,
  not the register rows.
- Only data with ordinary operands was timed: no denormals, NaNs, infinities
  or zeros (FSUB x,x giving an exact zero takes a shorter path than the
  cancellation row).
- The FSQRT dependent chain converges towards 1.0. FSQRT is a fixed
  22-iteration loop, so the timing is not data dependent.
