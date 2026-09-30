# Native6c Whetstone joint profile

The serial uninstrumented/passive pair qualified with identical8,724,166 loop clocks, original reports, ABI/code/global/stack captures and zero chip/bus/IRQ errors. Both use the actual pinned tEsT12000 selector1 FPUWStone kernel, FPU6c157b..., original OS RAM/ROM environment, actual SDRAM bridge/controller/chip fixture, original all10 releaseCPU flags/cache8+8KB, Verilator5.050/unroll256 and ROMlat6 stub. There is no independent numerical oracle. This is not the SANE CODE3 fixture or an OS-timed full FPU suite measurement.

The uninstrumented child2554830 (SHA763a01ee...) and profile child2555594 (SHAe195f0c0...) completed once; bounded userunit native-whet-joint-pair-20260928, invocationd541e38c..., launcher2554533 qualified09:18:58UTC. All launcher/supervisor/runner/native processes were absent afterward, unit inactive/exit0. Original source262-file manifest e5393d16... validated unchanged after both phases. No retry/source edit occurred. Original checker/measurement strings retain inherited “baseline” wording; supervisor and execution metadata identify both actual6c variants. Runtime and passive pair checkers passed independently.

Exclusive PC×CPU categories rank as follows. CPU “Other” includes all states outside MRD/blockedDEC/GO and is not labeled an idle or stall cost. FPU non-IDLE is a joint subset of each row, not another additive duration.

| PC context / CPU category | Samples | % loop | FPU non-IDLE subset |
|---|---:|---:|---:|
| ROM / OtherCPU | 3,362,789 | 38.546 | 60,331 |
| Native body / OtherCPU | 1,365,664 | 15.654 | 11,962 |
| Rest resource / OtherCPU | 875,558 | 10.036 | 0 |
| ROM / MRD | 786,978 | 9.021 | 6,043 |
| Rest resource / MRD | 615,581 | 7.056 | 0 |
| ROM / GO | 529,958 | 6.075 | 383,249 |
| Rest resource / GO | 408,820 | 4.686 | 268,430 |

Full ranked cells and source-state/op histograms are in result_summary.json and profile/run/run.log. Total MRD1,556,905, blockedDEC487,278, GO1,075,899 remain mutually exclusive; background/FPU-state occupancy remains a separate joint dimension. PC ranges are the existing pinned ROM/body/resource regions. PC is sequencer context, not proven issuing/retired-instruction ownership.

Translated physical cache-input whole-episode attribution uses actual c_nocache/ena policy; all observed groups have policy0 (not inhibited, enabled). Writes can still bypass because bypass includes write/misalignment separately. Inclusive latency sum includes one sampled edge per completion; `sum−count` is the arithmetic excess over that one-edge floor. It is **not** predicted removable clocks, a cache miss count, or an additive CPU/FPU stall total.

| Physical address / request class | Count | Inclusive latency sum | Sum−count | Max |
|---|---:|---:|---:|---:|
| Private arena / data read | 594,271 | 837,086 | 242,815 | 49 |
| Private arena / write | 579,928 | 719,378 | 139,450 | 31 |
| ROM / instruction | 389,921 | 550,319 | 160,398 | 42 |
| Resource / data read | 96,271 | 331,334 | 235,063 | 25 |
| Resource / instruction | 208,377 | 224,053 | 15,676 | 37 |
| ROM / data read | 106,010 | 118,305 | 12,295 | 43 |

All translated groups total1,979,851 episodes/2,790,718 inclusive samples, excess810,867 (9.294% of loop). ROM-request groups total495,931/668,624, excess172,693 (1.979% of loop). This differs sharply from4,912,061 ROM-PC occupancy samples (~56.3%); ROM execution context does not establish ROM service wait. The largest excess groups are private-arena reads and resource reads, ahead of ROM fetches. Their exact group sums preserve attribution despite histogram overflow. ROMlat6 is a fixture response stub rather than the top-level DDR3/retained-ROM-line path or physical ROM latency; this evidence does not justify a hardware ROM timing change.

Logical wrapper episodes are a separate plane:1,979,850 whole episodes, sum2,815,362, plus one boundary partial contributing37 in-window edges (occupancy2,815,399). Translated episodes have zero partial/active/fault entries. Do not add these planes or assume equal whole counts at window boundaries. Both reconciliation chains preserve request+ack same-edge latency1, held-request metadata, window intersections and final-active state. Diagnostic rows are capped64 perplane,1,979,787 completed diagnostics dropped perplane; aggregate cells remain complete. np_finish precedes the original400-edge drain, during which the blocking TB monitor is not sampling; no postdrain completion observation is claimed.

The dominant exclusive category is ordinary ROM-context CPU activity outside the three targeted states, largely while the FPU is IDLE. GO contains significant FPU-IDLE samples, and DEC-blocking remains smaller than the largest ordinary CPU categories. These findings rank areas for source review; they do not identify a safe optimization or forecast fullguest/FPGA gain. Existing marginal fill/queue counters remain in the original reports and must not be summed with these episode costs. No further run is part of this archive.

Included: original TB/runner/checker/entry source, passive header/diffs/parser/host fixtures, source identities, runtime/supervision logs and small captures. Full RAM/ROM images, complete RTL trees, generated objects/models/executables and large compiler logs remain frozen in scratch/native_whet_next_measurement_20260928; not duplicated here. Original manifests are historical scratch source identities; archive_manifest validates included relative artifacts. Copied supervisors are recipe references, not launch commands for this archive. A fresh replay requires complete pinned RTL/assets/images and its own bounded supervision/output directories.

Verify saved artifacts and checks from any directory:

```
python3 docs/perf/cache_refill_20260927/native_fpu_whetstone_joint_profile_6c/check_archive.py
```

PREPARATION_README.md/PLAN.md preserve the approved preparation scope; execution.json records actual terminal status. The result concerns native runtime/ABI/profile validity, not independent arithmetic correctness or hardware qualification.
