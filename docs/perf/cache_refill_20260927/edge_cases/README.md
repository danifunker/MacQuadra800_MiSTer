# AP040 bulk-line edge-case screen, 2026-09-27

This isolated direct-port cache bench extends the tracked
`tb_ap040_cache_snoop.v` memory model with a deterministic retained-line
sideband and a flat, distinguishable ROM array. It runs with the active
`AP040_EXPERIMENTAL_XSTORE` cache macro on Icarus Verilog 12.0. The baseline
is `rtl/ap68040/rtl/ap040_cache.v` (SHA-256 `7cba7f73f6f7f16fa7a45d439af6a786bd55c3ef2a3f8c876b400e10d4fb7747`).
The candidate is `scratch/fpu_bulk_line_candidate_20260927/ap040_cache.v`
(SHA-256 `6807b56c34ae5819402e277eac13404c655160672ede3acf82f97237a103745b`).
Neither RTL file was changed for this test.

Both sources pass:

- Five cross-line reads with the first line resident and the second line
  absent: longwords at offsets 13, 14, and 15; a word at offset 15; and a
  longword crossing set 127 to set 0. The second line is offered by the
  matching sideband before its first bus beat. All return the correct
  big-endian value and all four second-line words subsequently hit without
  backing-memory traffic. The candidate exercised `fill_line_bulk` on all
  five `r_xline` paths while `fill_acked` was still false.
- All 16 byte offsets, 15 in-line word offsets, and 13 in-line longword
  offsets against independently assembled byte expectations. The
  registered hint pair path was observed 12 times in each run.
- An instruction bulk fill, full 128-bit `c_line_data` offer, eviction of
  the private instruction line, and subsequent hits on all four words.
  The one-clock instruction hint path was observed four times in each run.
- Reset after the first retained-line write but before tag validation.
  Baseline was still in `C_FILL` (state 4, fill count 1); candidate had
  advanced to `C_TAGW` (state 5, fill count 3). Both swept the partial
  line, then refetched backing memory. The candidate observed eight bulk
  events in total, including this reset boundary.
- Stale RAM line tag while filling ROM, then stale ROM line tag while
  filling RAM. The mismatching sideband never supplied data from the
  wrong region, and both completed lines later hit. The mismatch
  predicate was observed 26 cycles per run.

`edge_baseline_run.log` and `edge_candidate_run.log` contain every checked
read and the coverage counters. Both end in `ALL EDGE CASES PASSED`.
`manifest.sha256` freezes all archived text inputs and outputs plus the
external RTL, ROM-free testbench dependency, and candidate patch.

From the repository root, reconstruct the candidate if needed and rerun:

```bash
mkdir -p scratch/fpu_bulk_line_candidate_20260927
patch -o scratch/fpu_bulk_line_candidate_20260927/ap040_cache.v \
  rtl/ap68040/rtl/ap040_cache.v \
  < docs/perf/cache_refill_20260927/bulk_candidate.diff
bash docs/perf/cache_refill_20260927/edge_cases/run_edge.sh \
  rtl/ap68040/rtl/ap040_cache.v edge_baseline baseline
bash docs/perf/cache_refill_20260927/edge_cases/run_edge.sh \
  scratch/fpu_bulk_line_candidate_20260927/ap040_cache.v edge_candidate candidate
sha256sum -c docs/perf/cache_refill_20260927/edge_cases/manifest.sha256
```

The runner generates `tb_edge_cases.sv` and writes build artifacts and new
logs under `scratch/fpu_refill_edge_cases_20260927`. The archived generated
bench allows review without running the generator. The ROM array and
retained-line delivery are direct-port models: this screen does not test
the full production ROM bridge, arbitration, MMU, or actual SDRAM timing.
The existing integrated RAM/SDRAM and platform workload screens cover
different portions of that path; no FPGA fitting or hardware test is
claimed here.
