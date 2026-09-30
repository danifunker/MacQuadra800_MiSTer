# Write-queue availability handoff: paired digital qualification

This archive preserves the baseline/candidate digital qualification for the
`wq_available` timing proposal. The candidate moves the queue-empty comparison
from the RAM falling-edge capture path to a registered availability bit. It is
an equivalence/timing experiment, not a demonstrated throughput gain. Production
RTL, guest inputs and FPGA fit inputs remain untouched by this package.

Both variants passed the production-oriented tests with matching counters and
reported timing:

- SDRAM/controller test: 174 checks, zero failures and zero chip protocol
  errors; startup mode-register setup, read/write ordering, byte enables,
  refresh, queue wrap and stream cases.
- Registered-first-miss memory-path test: 64 sequential reads plus 2,048
  mixed posted-write/read operations, zero failures and protocol errors.
- Line/DMA integration test: 4,000 rounds; 20,512 reads, 5,381 stores,
  15,374 line acknowledgements, 11,423 DMA beats, 9,408 direct pushes,
  1,434 spanning stores and zero errors.
- Passive handoff/ownership monitor: 22,320 rising-edge comparisons,
  2,707 nonempty decisions, 373 pushes/consumes/pops, 46 slot wraps,
  occupancy eight, 150 full samples and zero mismatches/overwrite/payload
  errors. The old falling-edge comparison and candidate registered availability
  decision were checked against the actual handoff.
- Standalone Intel `altdpram` primitive tests: edge capture and 256 writes /
  32 wraps passed. The deliberately wrong-address mutation failed as expected
  at its first write (negative control, exit 1).

The matching digital timing metrics were 6/4/1 `clk_sys` for cold/page-hit/
retained reads, one clock for posted write acceptance, 5,847/4,757 ns for
64-read/64-write streams and 4,878 ns for integrated 64 reads. The 4,096-store
DMA bench took 9,712 clocks in both variants. These unchanged values establish
no speedup.

Scope limits matter for the next gate. Startup `init` was observed for 11 RAM
rising edges while the queue was empty; dynamic reinitialization with queued or
partially completed traffic was not tested. The three Intel primitive tests use
the actual Quartus Lite `altera_mf.v` model, but run standalone and do not join
that primitive to the full bridge/controller. Verilator bridge integration
uses the synchronous-write/asynchronous-read behavioral queue branch. Existing
full-guest runs use a simplified RAM model and do not exercise this physical
bridge. These simulations are not STA, MLAB collision/timing qualification,
FPGA operation or arbitrary asynchronous-clock proof. The related production
1:3 clocks are tested. The changed half-cycle paths still require STA before any
fit or hardware claim.

The original validation README, checker, source/input/evidence manifests,
commands, tool identities, launch records, terminal exits and logs are retained.
Two infrastructure attempts that did not execute simulations are kept in
`baseline/invalid_tool_version_attempt/` and
`baseline/invalid_ccache_attempt/`. Generated models, executables, object
folders, `.vvp` files and caches are omitted. `tool_identity.json` records the
external Intel model path/hash; the library itself is not bundled.

Run `python3 check_archive.py .` here to validate the archived source/evidence
hashes, terminal outcomes, counters and exclusions using only files in this
archive. The original `check_results.py` is retained unchanged as provenance;
it refers to the original scratch location and external Intel model.
