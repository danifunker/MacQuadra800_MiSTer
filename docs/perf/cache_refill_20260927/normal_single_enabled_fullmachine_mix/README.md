# Enabled normal-single FMOVE — matched OS Mix regression

Candidate6c completed all ten Mix tests. Root reviewed setup4277 (allten selected, iteration1) and final7382 (“The tests are done!”, aggregate1.798). The final dialog obscures middle ratings/iteration cells; this archive does not infer those fields. All ten absolute values are visible:

| Test | Original baseline | Candidate6c |
|---|---:|---:|
| KWhetstones/sec | 1762.002 | 1762.139 |
| Dhrystones/sec | 17931.816 | 17932.324 |
| Towers, sec | .479 | .479 |
| Quicksort, sec | .507 | .507 |
| Bubble Sort, sec | .602 | .602 |
| Queens, sec | .362 | .362 |
| Puzzle, sec | .755 | .756 |
| Permutations, sec | .712 | .712 |
| Integer Matrix, sec | .495 | .495 |
| Sieve, sec | .845 | .845 |

Aggregate1.798 is unchanged. Setup PNG is byte-exact originalbaseline. Final PNG and standard profile differ from originalbaseline, but both are byte-exact the prior73bc candidate (after removing newly added passive `FPU_GUARD_` rows from this profile). Original differences are retained rather than claiming exact baseline equality. The older73bc archive's comparison JSON omitted the leading7 in the Dhrystones values; the table here uses the preserved baseline/current PNGs and leaves that older archive unchanged.

Actual child2462621 exited0 at2026-09-28T08:55:15UTC; independent host check found allthree original guest children gone. Frozen223-input source manifest6ce6d469... and binary2f16b5... validated unchanged. Supervisor and independent refill/v2allow-empty checkers passed:1,304,100,000edges,334,088raw branch events,1,280normal-single events accepted by all73bc/55ff/6c predicates,1,280actualROUND and zero mismatch. These fullwindow counts are reconciliation/guard observations, not unique instructions or individual subtest execution times. Separate manual review preserves root's finding; original terminal metadata retains its PENDING_SCREENSHOT_REVIEW label.

Matched recipe: all10 releaseCPU flags plusSCSI_CACHE_OFF,8+8KBcache, Verilator5.050/unroll256, calibrated RAM first4/publication2, identical original control eafdd1b9..., ROMhex045c027..., fresh90,224,128-byte golden HDA80d84794.... Fullguest host RAM modeling is not production SDRAM/controller or FPGA timing qualification. Mix is a separate CPU/graphics regression gate; this result makes no hardware or independent numerical FPU claim.

Compact archive contains controls/TSVs, scheduled setup/final PNGs, originalbaseline and previous73bc comparison, source/build/recipe/terminal identities, strict checkers and manual review. Source/package/prelaunch manifests retain historical absolute scratch paths; archive_manifest checks relative artifacts. `inputs.json` retains its prelaunch preparation label, not terminal status. Full executable/generatedmodel/ROM/completed mutable disk/huge rawlog remain in frozen scratch; they are excluded here. The copied supervisor is a recipe reference, not runnable inside this archive. Fresh reproduction requires pinned source/model/assets, new disk/output directory and bounded child supervision.

Verify from any working directory:

```
python3 docs/perf/cache_refill_20260927/normal_single_enabled_fullmachine_mix/check_archive.py
```
