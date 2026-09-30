# Native Whetstone joint profile — frozen preparation, not launched

Two fresh projects, `uninstrumented/` and `profile/`, reuse the qualified actual native selector1 tEsT12000 FPUWStone image, entry, ROM/runtime, original TB and checker. Both isolated113-file RTL copies use exactFPU6c157b3bc045e74a90416f4764f35cf65024e77577019a100b8aa9b5bdd9ce9b; the sole RTL difference from the prior qualified73bc source is ap040_fpu.v. Paired RTL/image/assets/entry/runner/checker are identical; uninstrumented TB is byte-exact the qualified original. Profile TB adds one include and two passive calls, shown in monitor.diff; next_monitor.svh is explicitly hash-covered despite being a transitive include. No RTL compilation, native simulation or fixture launch occurred during preparation.

All original runtime/ABI/code/FP sentinel/stack/600D/chip/bus/IRQ/FPSP/histogram gates remain. The original checker and its recorded-result construction are preserved. Its output/measurement scope still uses inherited “baseline” wording; supervisor variant/candidate metadata provides actual6c identity. Neither phase is the earlier2d53 or73bc reference; paired6c loop time must be measured and must match between the two variants. There is no independent numerical oracle.

Runner changes are identical and local-pin only: consume frozen localRTL/assets/QSF/ROM, prohibit EXTRA_FLAGS/EXTRA_PLUSARGS, require6c hash, add HERE include path. Original ROMlat6,40M-cycle bound,300s build/run phase timeouts, Verilator5.050/unroll256, all10 releaseCPU flags and8+8cache recipe remain. The native ROMlat6 response is a fixture stub, not the top-level DDR3/retained-ROM-line path or physical ROM latency. ROM PC occupancy is not ROM wait time. Do not derive a speedup proposal by changing this stub.

The monitor samples first in the original main preedge block, before cycle or marker updates. It uses mutually exclusive ROM/body/restresource/other PC and MRD/DECblocked/GO/other CPU buckets, exact32-bin FPU state and busy-operation cross-tabs. Direct joint/marginal reconciliation preserves overlapping background predicates separately. No added clock/eval/CE/pause or kernel operation is introduced.

Logical wrapper and physical cache-input episodes are separately labeled; their occupancy/latencies are not additive. Physical cache-input policy uses actual c_nocache/ena/bypass, not stale MMU attributes at logical request start. Wrapper fault cleanup is exactly mem_flt OR berr; there is no invented downstream fault port. Sampled requestPC is sequencer context, not proven issuing/retired instruction PC. Logical/physical address labels stay distinct. External posted/walker source ownership/cacheability is not reconstructed; existing external/queue counters remain unchanged.

Histograms are fixed:2planes×4start-PC×5address-regions×3kinds×4policies×65bins=31,200 uint64 cells (bin64 is>=65). Each of480 groups has exact count/sum/max, so overflow does not lose attribution of service cycles. Per-plane sum/max/EVER/BYPASS/diagnostic/partial reconciliation is required. Diagnostic completed-episode rows are capped64 perplane and drops counted. Request fields must remain stable until completion; immediate request+ack has latency1; held requests are not recounted. Window-crossing episodes contribute only measured intersections to partial occupancy and are excluded from whole-episode latency aggregates. Active episodes at report are separately reported, not silently completed.

np_finish is called BEFORE the original WHETSTONE_RETURNED report and400-edge drain. That drain blocks the original always block, so no monitoring after this handoff is claimed. Original draining/captures/gates remain untouched. Initial reset is outside the window; any later reset interrupting a window/active episode fails instrumentation. Indexes are checked without masking before array writes. Actual sampler behavior/field-stability assumptions remain to be qualified by the real paired run; Python fixtures only qualify parsing/reconciliation.

Host checker fixtures passed: immediate latency1,70-cycle overflow with exact group sum/max, boundary partial and finish-active intersection, plus15 corruptions rejected. Python syntax checks passed. No testbench/model was compiled. Source/evidence manifests pin preparation inputs and this small host-test evidence.

Prepared, NOT authorized for execution yet:

```
python3 scratch/native_whet_next_measurement_20260928/uninstrumented/supervise.py
python3 scratch/native_whet_next_measurement_20260928/profile/supervise.py
python3 scratch/native_whet_next_measurement_20260928/check_pair.py
```

Each proven-pattern supervisor guards new output paths, verifies source hashes, records actual native child/executable SHA, applies a650s runner deadline, cleans its processgroup on failure/signal, waits the runner and requires native child absent. Postchecks have separate60s bounds;650s is not a total supervisor deadline. No automatic retry. Pair checker requires exact clocks, original report lines and all four small memory captures between6c variants, then strict passive reconciliation. Root must review final monitor diff/manifests before authorizing build/run. No production, previous completed, or fullguest input was modified.
