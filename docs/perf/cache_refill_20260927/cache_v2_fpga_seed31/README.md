# Cache v2 seed-31 FPGA fit evidence

This archive records one full Quartus seed-31 fit of the reviewed cache-v2
candidate, using the full-release source set, the 6c FPU, and the original
SDRAM bridge. Against the matched seed-31 6c FPU-only base manifest, the only
changed RTL path is `rtl/ap68040/rtl/ap040_cache.v` (base SHA-256
`7cba7f73f6f7f16fa7a45d439af6a786bd55c3ef2a3f8c876b400e10d4fb7747`, cache v2
SHA-256 `9e8c0582db1b0bb88428e56fec63e99029b61faffac62c6f3dda9326b5191481`).
The QSF/SDC, feature flags, FPU, and original bridge remain byte-identical.
The QSF seed is 31. Both complete 1,892-entry source manifests and the
reviewed cache diff are retained.

Quartus full compilation completed with flow and wrapper exit 0. The fit used
38,760/41,910 ALMs, 24,659 registers, 468/553 RAM blocks, 3,389,411 block-memory
bits, 36 DSPs, and 4 PLLs. Under the unchanged release constraints, minimum
setup slack was CPU +0.623 ns, RAM +0.693 ns, and HDMI +0.206 ns; minimum hold
slack was +0.226 ns. Cross-domain worst setup slack was system→RAM +0.712 ns
and RAM→system +0.759 ns. The separate 12-path RAM setup report's worst path
was +0.693 ns from `sdram|saved_wr` to `sdram|dq_oe~_Duplicate_10`.

The STA report also shows zero illegal clocks and zero unconstrained clocks,
but 26 unconstrained input ports / 145 input paths and 90 unconstrained output
ports / 157 output paths. The input list includes `SDRAM_DQ[0..15]`. The
matched 6c-only seed-31 baseline report has the identical input/output port
lists, counts, and eight normalized SDC warnings. This is the existing
constraint scope, not a candidate regression: positive slack here is not
board-level external I/O or SDRAM timing signoff. The candidate and baseline
full STA reports and a compact scope comparison are included.

The RBF (4,440,380 bytes, SHA-256
`85db1130b61fa21eb4129c41b032d23c26ec3407f94dc283b3c3eb14eebcabe7`) and SOF
(6,690,368 bytes, SHA-256
`cfcd19b624b5b043ae306cc6e42beebc33ca948eeb05342630808639093a7c6a`) are
identified in the terminal metadata; neither binary is included. Quartus
databases and private environment files are also omitted. No hardware test or
deployment was performed. A single fit does not establish a hardware speedup
or repeatability across seeds.

The archived raw reports are the map, fit, and full STA summaries; full
candidate and matched-baseline STA reports; both six-path cross-domain
reports; and the 12-path RAM summary plus three detailed RAM paths. Provenance
records the supervised full-flow, cross-domain, and RAM-path invocations and
the exact RBF/SOF identities. One launcher PID marker was malformed by shell
quoting; `full_process_identity.json` records the PIDs observed directly from
the host process list and describes that marker issue.

Verify from the repository root with:

```sh
python3 docs/perf/cache_refill_20260927/cache_v2_fpga_seed31/check_archive.py
```

The checker validates the archive checksum inventory, byte-compares copied
raw evidence with its scratch originals, verifies the 1,892-entry sole-cache
delta and source identities, checks the terminal fit and artifact metadata,
and compares the archived full STA port lists and SDC warning signatures.
It does not run Quartus or certify hardware behavior.
