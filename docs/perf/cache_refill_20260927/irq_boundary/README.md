# Release-macro CPU IRQ boundary screen with retained cache lines

This focused A/B screen uses the exact baseline cache SHA-256
`7cba7f73f6f7f16fa7a45d439af6a786bd55c3ef2a3f8c876b400e10d4fb7747`
and bulk-line candidate SHA-256
`6807b56c34ae5819402e277eac13404c655160672ede3acf82f97237a103745b`.
Both runs use the current tracked CPU core and pipeline module, the same test
program, and all ten enabled AP040 CPU macros plus `CACHE_CD_OFF=1` and
`CACHE_SMALL=1` from `MacQuadra800.qsf`. The only A/B RTL difference is the
cache source. `manifest.sha256` records the other source identities and the
archived test files.

The tracked CPU program bench normally ties `m_line_valid` low. Here,
`prepare.py` copies its wrapper and bench into scratch and adds test-only
retained-line ports. `retained_stim.sv` publishes a 16-byte line with the
cache's physical tag from the bench's 16-bit big-endian backing memory after
the first completed cache beat. Reset and any bus, walker, or cache write
deassert the offered-valid signal; writes clear it before another sample. No
issued bus beat is abandoned. This is the CPU's direct 16-bit memory bench,
not the production SDRAM bridge/controller or the full OS-driven FPU suite.

The independent assembly oracle in `irq.s` checks the interrupt frame's
saved SR `$2010`, PC `$00000604`, and format/vector word `$0068`; `D3=1` and
`D7=0` in the handler; and memory word `$C100=1` after return. Success writes
`$600D` to the bench's result port `$F102`; failure writes `$BAD0`. The
monitor separately requires three IRQ injections and three load commits at
PC `$600`, one per memory timing phase. Both A/B runs print `ALL TESTS PASSED`,
`BOUNDARY commits=3 injections=3`, and `HANDOFF entries=3 commits=3`.

The baseline offers 48 retained lines and observes 144 matching fill edges,
with no bulk edges. The candidate offers 48 lines and observes 48 actual
`fill_line_bulk` edges. Three of those edges coincide with both pending IRQ
and active pipeline load at PC `$604` (cycles 353, 1006, 1716). At the next
clock the `pipe_cancel` control pulses; the separate handoff monitor records
`cancelled=0`, so this screen **does not prove an entered speculative load was
killed**. It does exercise pending-IRQ/load ordering and the cancel control
boundary while the cache shortens the fill. The program then passes its
architectural interrupt-frame and resumed-load checks.

For every candidate bulk edge, the monitor arms `tb_wait_busy_release`. It
asserts there is no second bulk before `mm_busy` deasserts, then asserts that
deassertion occurs exactly two clocks after the bulk edge. The final counter
requires `busy_releases == bulk_edges`; observed values are 48 and 48. In the
three IRQ overlaps, the corresponding release edges are cycles 355, 1008,
and 1718, while IRQ remains pending. Six offered lines were withdrawn at
writes in the candidate run (12 in baseline), and sideband valid is also
gated combinationally by reset/write signals. No stale line or wrong
architectural result was observed in this program; the screen does not
cover all write/IRQ arbitration or a killed speculative entry.

To reproduce from the repository root, use the archived candidate diff and
copy these small test sources into scratch so generated wrappers and binaries
stay out of the evidence directory:

```bash
mkdir -p scratch/fpu_bulk_line_candidate_20260927 scratch/fpu_bulk_irq_20260927
patch -o scratch/fpu_bulk_line_candidate_20260927/ap040_cache.v \
  rtl/ap68040/rtl/ap040_cache.v \
  < docs/perf/cache_refill_20260927/bulk_candidate.diff
cp docs/perf/cache_refill_20260927/irq_boundary/{prepare.py,retained_stim.sv,run_branch_boundaries.py} \
  scratch/fpu_bulk_irq_20260927/
python3 scratch/fpu_bulk_irq_20260927/prepare.py
python3 scratch/fpu_bulk_irq_20260927/run_branch_boundaries.py \
  --core rtl/ap68040/rtl/ap040_core.v \
  --cache rtl/ap68040/rtl/ap040_cache.v \
  --out scratch/fpu_bulk_irq_20260927/boundary_baseline
python3 scratch/fpu_bulk_irq_20260927/run_branch_boundaries.py \
  --core rtl/ap68040/rtl/ap040_core.v \
  --cache scratch/fpu_bulk_line_candidate_20260927/ap040_cache.v \
  --candidate --out scratch/fpu_bulk_irq_20260927/boundary_candidate
```

The runner uses Icarus Verilog, `bin2hex.py`, and the existing external
`vasmm68k_mot` fixture path shown in `run_branch_boundaries.py`. Archived
`baseline_run.log` and `candidate_run.log` are the exact output of this run.
