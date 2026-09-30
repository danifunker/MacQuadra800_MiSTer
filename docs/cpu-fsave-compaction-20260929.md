# FSAVE/FRESTORE state-frame compaction, 2026-09-29

**Result, CPU-only synthesis (`scratch/cpu_area/run.sh`, release `AP040_*`
macros): 26,579 -> 26,420 ALMs (-159), 9,052 -> 8,457 registers (-595),
40,431 -> 40,254 ALUTs (-177).** That is short of the 500 ALM target and
under the 300 ALM bar set for a full fit, so no fit was run. No test or
harness changed by a single clock or a single frame word, except in one
case: a FRESTORE that bus-faults part-way through its frame while an
unsaved exception frame is pending (see "Behaviour change" below).

The change removes the duplicate copies of the frame and one of the two
FSAVE word multiplexers. That frees registers but little logic. The
remaining FSAVE/FRESTORE cost is mostly the capture and resume logic in
the FPU, which a register-level compaction cannot remove (see "Where the
family's area is").

The RTL is uncommitted in the working tree: `rtl/ap68040/rtl/ap040_core.v`,
`rtl/ap68040/rtl/ap040_fpu.v`, and the port list of
`rtl/ap68040/tb/tb_ap040_fpu_normalize.v`. The baseline is `82694ab`. The
branch has since moved to `74c9d06`, but those commits do not touch
`rtl/ap68040`, `wombat_cpu.sv`, `wombat_store_buffer.sv` or `dpram.v`, so
HEAD's CPU is the same.

## Data flow at HEAD (82694ab), with line numbers

### Frame storage (the three copies)

| copy | where | fields |
|---|---|---|
| FPU operand shadows | `ap040_fpu.v:572-583` `sh_cmd`, `sh_src`, `sh_stag`, `sh_dst`, `sh_dtag`; `wb_s/e/m/grs` | written by the arithmetic path itself: dispatch fast paths `:1155`, `:1200`; `F_RESTORE_A/B` `:1562`, `:1574`; `F_EXEC` `:1606`; `F_BIN` `:1676`; every dispatch writes `sh_dst` `:1042`; `F_ROUND` writes `wb_*` `:2103` |
| FPU frame registers (outputs) | `ap040_fpu.v:86-115` `fstate_cmd1/cmd3/stag/dtag/flags/fpt/et/grs/wbte15/busy/wbt/fpiar_c` | written by `capture_unimp` `:728`, `capture_datatype` `:775`, `pend_capture` `:867-919` (copies `sh_*`/`wb_*`), and the FRESTORE install `:939-980` (copies the core's staging) |
| core FRESTORE staging | `ap040_core.v:1423-1427`, `:1460-1464` `fp_restore_cmd1/cmd3/stag/dtag/flags/fpt/et/cusavepc/et15/fpt15/grs/wbte15/wbt/fpiar/busy` | written a longword at a time by `S_FREST_U` `:7859` and `S_FREST_B` `:7888` from `m_val` |

### FSAVE

`S_FSAVE1` (`ap040_core.v:7749`) waits for `fpu_bg`/`fpu_pendcap`. It then
takes one of four paths:

- a frameless pending exception;
- the BUSY frame (`S_FSAVE_B`, `:7806`);
- the UNIMP frame (`S_FSAVE_U`, `:7794`);
- the IDLE/NULL header.

Each loop issues one `mwr` per longword. The data comes from
`fsave_busy_word(fpb_n)` (`:1570`) or `fsave_unimp_word(fp_n)` (`:1599`),
two separate 32-bit multiplexers over the FPU's `fstate_*` outputs. The
last write raises `fsave_ack` (FPU `:930`).

### FRESTORE

1. `S_FREST1` (`:7818`) waits for `fpu_bg` and reads the header.
2. `S_FREST2` (`:7822`) handles the header:
   - NULL goes to `fp_reset`.
   - IDLE goes to `frestore_idle` (FPU `:934`).
   - UNIMP starts `S_FREST_U`; BUSY starts `S_FREST_B`.
   - Anything else raises FMTERR.
3. The loops write the staging registers.
4. `S_FREST_UD` (`:7938`) or `S_FREST_BD` (`:7924`) pulses
   `fpu_frestore_unimp` and computes `fpu_pend_exc` / `fpu_bg` from the
   FPU's combinational `frestore_e1_pend` (`:707`) and `frestore_resume`
   (`:685`). Both are functions of the staging.
5. On the strobe, the FPU copies all of the staging into `fstate_*`
   (`:960-971`). If `frestore_resume` (BUSY with CU_SAVEPC = $fe) is set,
   `F_IDLE` (`:983-1007`) unpacks `frestore_et/fpt` into `a_*/b_*`. The
   sequence then runs `F_SHR` -> `F_RESTORE_A` (`:1557`) -> `F_SHR` ->
   `F_RESTORE_B` (`:1571`) -> `F_RESTORE_N` -> `F_NORM` -> `F_EXEC`.

### Pending exceptions

`fpu_pendcap` is set in the core at `ap040_core.v:5558`. On it,
`pend_capture` copies the shadows into `fstate_*`:

- **e1 arm** (SNAN/OPERR/DZ or a non-arith5 op): ETEMP = `sh_src`,
  FPTEMP = 0.
- **e3 arm** (OVFL/UNFL/INEX of the five arithmetic ops): ETEMP =
  `sh_src`; FPTEMP = `sh_dst` if dyadic, else 0; WBTEMP = `wb_*`;
  FPIARCU = `fpiar`.

## What changed, and why it preserves behaviour

**(a) The core no longer stages the frame.** The FPU has a word write port
(`frame_we`, `frame_idx`, `frame_wd`) that stores each longword into the
frame registers as it arrives.

- The index is the longword's position in the 100-byte BUSY frame. The
  UNIMP frame is exactly that frame's tail: $41 word n is BUSY word n+12,
  and $40 word n is BUSY word n+14.
- The strobe is combinational from `state == S_FREST_B` with data `m_val`.
  It lands on the same clock edge the staging register used to, so
  `frestore_e1_pend` / `frestore_resume`, now computed from the FPU's own
  registers, see the last word in `S_FREST_BD` exactly as before.
- The install strobe now only sets the format (`fstate_busy`, `fstate_e1`,
  `fstate_unimp`). It also zeroes CMDREG3B for a $40 UNIMP frame
  (`frestore_nocmd3`), which the core used to do in `S_FREST2`.
- CU_SAVEPC is kept as one bit (`frame_cusave_fe`), and ETE15/FPTE15 as two
  bits. FSAVE never stores them.
- For precision, the first word written hides any prepared frame
  (`fstate_unimp <= 0`). The frame becomes visible only at the install
  strobe, which comes after the last read succeeded.

**(b) One copy of ETEMP, FPTEMP and WBTEMP.**

- `fstate_et` and `fstate_fpt` are gone. The captures and the write port
  write `sh_src` / `sh_dst` directly, and `pend_capture` no longer copies
  them. It only zeroes `sh_dst` where FPTEMP was 0.
- `fstate_wbt` is gone. FSAVE reads `wb_s/wb_e/wb_m` directly. A 1-bit
  `wbt_zero` stands for the all-zero WBTEMP of a datatype frame, and the
  write port loads `wb_*`.

This is safe because every other writer of those registers only runs while
no frame is visible:

- A new dispatch clears `fstate_unimp` in the same clock, or replaces the
  frame through a capture that is later in the always block.
- The resume path clears `fstate_unimp` at install.
- `F_ROUND` and `F_BIN` only run for an operation in flight, after one of
  those two.
- No capture lets its operation continue.

Every path that can defer an exception rewrites `sh_src` inside its own
operation: the P253 fast path at dispatch, `F_EXEC`, `F_BIN`, or
`F_RESTORE_A` on resume. So the frame content at `pend_capture` is the same
as before. None of the code inside
`F_BIN/F_ADDX/F_MULT/F_ROUND/F_WB` or the dispatch fast paths changed;
only the registers they already wrote gained write sources outside those
states.

**(c) One FSAVE loop, one FRESTORE loop, one word multiplexer.**

- The FPU formats every payload word (`frame_rd` at index `fpb_n`). The
  core adds only the two headers.
- The UNIMP loops start `fpb_n` at the UNIMP header's BUSY index and bias
  `t_a` by the same amount, so every address is `t_a + 4*fpb_n`:
  - For FSAVE -(An) the base is `ea_addr - 96` for both frames.
  - For FRESTORE it is `ea_addr + 4 - 4*hdr`.
  - The (An)+ writeback is `t_a + 4*24`.
- `S_FSAVE_U`, `S_FREST_U` and `S_FREST_UD` are gone, along with their
  state constants 182, 184 and 185.
- The P258 store/read hints follow the same `t_a + 4*fpb_n`.
- Every loop still issues one access per longword from the same state, so
  the clock counts are unchanged.

Tried and reverted:

- **(g)** Not loading `a_m`/`b_m` in the resume's `F_IDLE` step, because
  `F_RESTORE_A/B` overwrite them. It measured 0 ALUTs saved and +82 on the
  ALM estimate.
- **`cmd3` derived from `cmd1`.** Not done: a restored frame must return
  its own CMDREG3B, so the 16 bits have to stay.

### Behaviour change (one corner case)

Suppose a FRESTORE takes a bus error on a payload longword while the FPU
holds an unsaved exception frame. At HEAD that old frame survived, and a
later FSAVE extracted it. Now the first payload longword hides it:

- An FSAVE afterwards takes the pending exception frameless (vector 53 in
  the test) and then saves IDLE.
- If no frame was pending, the result is identical: the frame was already
  invisible.

The first bullet is case 91 of the differential test below. Its stream is
the only difference between the two runs, in all three bus phases. Keeping
the old frame across a faulted FRESTORE would need exactly the holding copy
this change removes.

## Gates

All were run on each step and again on the final tree (step f).

- **Self-tests:** `sh rtl/ap68040/tb/run_tests.sh`. 32/32 pass in the default
  configuration and 32/32 with `CPU_TEST_LEA=1 CPU_TEST_XSTORE=1`,
  including `t_fpu_frames` and `t_fpu_resume`.
- **$40 frame ABI:** `t_fpu_frames` assembled with `-DREV40=1` against the
  core with `AP040_FPU_REVISION = 8'h40`
  (`scratch/fsave_compact_20260929/rev40.sh`). It passes at HEAD and in the
  final tree with identical cycles: 8142 / 12326 / 12326.
- **FPU latency harness:** `docs/perf/fpu_latency_20260928/run.sh
  --worktree`. The results for latency 1 and 3 match HEAD's line for line
  (all 67 rows). That includes the FSAVE/FRESTORE rows: NULL and IDLE
  pairs 10.00 clocks; FINTRZ and FMOVECR to vector 11 with handler
  FSAVE/FRESTORE 141.38.
- **Paired program tests:** the release macros (the `xline_v2` recipe:
  `iverilog` with the `AP040_*` macros plus `CACHE_CD_OFF`, `CACHE_SMALL`,
  `SIMULATION`; `scratch/fsave_compact_20260929/pair.sh`), HEAD against the
  working tree. Bus phases 0 / 1 / 2:

  | test | HEAD | working tree |
  |---|---|---|
  | `fpu` | 101556 / 146602 / 146602 | identical |
  | `fpu_frames` | 8240 / 12526 / 12526 | identical |
  | `fpu_resume` | 13352 / 20312 / 20312 | identical |

- **Differential frame dump** (new, in `docs/perf/fsave_compact_20260929/`):
  `t_fsave_diff.s` sends every FSAVE frame, the FPSR/FPIAR and all eight FP
  registers through the bench's `$F108` stamp port. It covers:
  - vector 11 unimplemented instructions from every operand class;
  - vector 55 datatype frames, including packed values and opclass-011
    stores;
  - every deferred class: e1 via SNAN/OPERR/DZ/non-arith5 and e3 via
    OVFL/UNFL/INEX on dyadic, monadic and FSGLMUL. Each is reached both
    through the pre-instruction trap and through a direct FSAVE, including
    the fast F_BIN, F_ROUND and P221 memory paths;
  - FRESTORE + FSAVE round trips of every frame in the handler;
  - a CU_SAVEPC = $fe resume;
  - an FRESTORE over a pending frame.

  `run_diff.sh` compares the word stream and the per-word cycle stamps.
  HEAD and the final tree give 14,235 identical words and identical
  cycles (SHA-256 of tags `e745acef...`, cycles `6b8afee7...`). The `berr`
  bench variant, which faults the read at $5040 once, differs only in
  case 91 as described above: HEAD's tags are `ee9af5b8...`, the final
  tree's `e504b3cd...`.

## Area (CPU-only, `wombat_cpu` with the release macros)

| tree | ALMs (estimate) | registers | ALUTs | core own ALUTs / regs | FPU ALUTs / regs |
|---|---:|---:|---:|---|---|
| HEAD 82694ab | 26,579 | 9,052 | 40,431 | 23,361 / 4,415 | 7,533 / 1,617 |
| (a) write port | 26,758 | 8,696 | 40,467 | 23,321 / 4,056 | 7,547 / 1,620 |
| (a)+(c) one word mux | 26,518 | 8,696 | 40,129 | 23,009 / 4,056 | 7,581 / 1,620 |
| +(b) ET/FPT merged | 26,456 | 8,536 | 40,140 | 23,002 / 4,056 | 7,538 / 1,460 |
| +(d) one loop each | 26,386 | 8,536 | 40,051 | 22,852 / 4,056 | 7,606 / 1,460 |
| +(e) WBTEMP from `wb_*` | 26,461 | 8,457 | 40,303 | 22,990 / 4,056 | 7,664 / 1,381 |
| **+(f) shared (An)+ adder: final** | **26,420** | **8,457** | **40,254** | 22,888 / 4,056 | 7,675 / 1,381 |

The ALM estimate moves by +/-100 to 200 between runs that change nothing
near the logic in question. Step (e) touched only the FPU, yet the core's
own ALUTs rose by 138. So read the trend, not the individual steps.
Removing the 360 core staging registers barely moved the ALUT count: they
were loaded straight from `m_val` with clock enables, and needed no LUTs.
The logic that did go was the two FSAVE word multiplexers, now one inside
the FPU, and the duplicated loop and address logic.

### Where the family's area is

The family ablation (`scratch/ablate_family.py 'S_FSAVE.*' 'S_FREST.*'`)
makes every FSAVE/FRESTORE state dead. That also prunes every frame
register and capture, because nothing reads them any more.

| tree | family ALMs | family registers | family ALUTs |
|---|---:|---:|---:|
| HEAD | 1,540 | 996 | 2,415 |
| step e | 1,471 | 401 | 2,367 |

A second ablation on the final tree ties `frestore_resume` low, so the
CU_SAVEPC = $fe resume can never happen. That alone is **471 ALMs**
(26,420 -> 25,949) and 616 ALUTs, 538 of them in the FPU:

- the `F_IDLE` unpack of ETEMP/FPTEMP;
- `F_RESTORE_A/B/N`;
- `restore_shift`;
- the `norm_m` input for `F_RESTORE_N`;
- everything gated by `r_resume` in the arithmetic states.

The rest of the FPU's ~1,400 family ALUTs is the capture logic:

- `sh_src`/`sh_dst` input multiplexers with about nine sources each;
- the `frame_tag_x` instances;
- the command and tag fields;
- the FSAVE word multiplexer.

To take out another 300 or more ALMs, the options are:

- make the resume cheaper;
- serialize the captures through the write port, which changes the
  trap-path clock counts;
- make the FPSP resume a build option.

None of these is a register compaction.

## Full fit

Not run. The saving is below the 300 ALM bar in the brief. If it is wanted
anyway, a copy of the checkout's tracked files at `74c9d06` or later with
this diff applied is the candidate. That tree includes `4e21a99`'s
`scc.v`/`MacQuadra800.sv`.

## Files

- `docs/perf/fsave_compact_20260929/t_fsave_diff.s`, `run_diff.sh`: the
  differential frame test. Outputs go to `scratch/fsave_diff/`.
- `scratch/fsave_compact_20260929/`: gate scripts (`selftest.sh`,
  `pair.sh`, `rev40.sh`), latency results (`lat_*`), per-step RTL
  snapshots, and area logs. The map reports are in
  `scratch/cpu_area/p_fsc_*`.
