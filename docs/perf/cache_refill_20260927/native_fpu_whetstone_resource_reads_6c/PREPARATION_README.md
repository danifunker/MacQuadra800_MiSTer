# Prepared resource read attribution

Preparation only: no model build or simulation has been launched. Primary must review the source manifest and monitor diff before authorizing the single bounded replay.

`profile/` copies only hash-verified source inputs from the completed 6c joint-profile variant. All113 RTL files, the original TB, entry/image, ROM, runner, original checker and existing joint-profile checker are byte-identical. The two changed shared files are `profile/next_monitor.svh` (passive resource hooks) and `profile/supervise.py` (additional strict report checker/output guard). `profile/resource_read_monitor.svh` is new. No generated objects, executables or old outputs were copied. See `preparation_identity.json`, `monitor.diff` and `supervisor.diff`.

The metadata hook order is creation → original window-edge accounting → resource sample → original completion handling with resource completion before clearing active. Everything uses original saved translated addr/size/policy/PC bucket and pre-NBA signals; no independent request tracker, competing always block or clock/control drive. The sampler covers first-edge events and acknowledgments. Only measured-window branch events are included; marker partials retain window edges without inventing a complete path. Global invalidation-mask/row metadata describes concurrent blockers; it cannot prove historical tag invalidation caused a later miss. `PLAN.md` gives exact predicates, dimensions and limits.

Host tests (saved-report fixtures only):

```
python3 scratch/native_whet_resource_reads_20260928/test_checker.py
```

Two valid reports, including one with no boundary intersections, exercises every first-line failure mask, second-line clean hit/miss and hazard masks, immediate-completion totals, idle-second shortcut, odd address/size separation and boundary/finish partials. Twenty-one corruptions are rejected. This tests producer-schema expectations and reconciliation, not execution of the HDL monitor. No model/RTL build has been performed.

The original NEXT checker, new resource checker and exact reference comparison all run after the preserved original qualification checker in `profile/supervise.py`. The new checker requires zero unclassified whole cross-line paths and exact target96271/331334/max25, saved rest-resource90990/311506/max25, and loop8724166. With no boundary intersections it requires exact per-address whole cross-line completion and event-chain equality; qualification requires zero partial/active contributions. It validates address-level first-failure/event and second-mask/outcome consistency, projected path counts, invalidation metadata, partial occupancy and the independent original NEXT_GROUP totals. The original ABI/code/global/stack/error checks remain required. `check_comparison.py` additionally requires all original selected report lines, every NEXT row and four small memory captures to be byte-exact against copied immutable reference artifacts. `reference/identity.json` links them to the completed profile/source/binary. `test_comparison.py` exercises exact acceptance plus corrupted original/NEXT/duplicate rows and capture rejection, without running a model. A failure is retained and cleaned up; no automatic retry.

After authorization only, the prepared command is `python3 profile/supervise.py` from this directory, through durable bounded supervision. The copied runner retains40M cycle /300s compile+run phase caps,2 workers,ROMlat6 and the unchanged full release CPU recipe; the supervisor bounds its runner at650s and postchecks at60s each. It records actual native child/executable hash, verifies the frozen source manifest before and after, and rejects all existing output paths. Its result retains the original checker's inherited baseline text but metadata explicitly identifies6c and the passive probe.

The completed reference pair and its archive remain immutable. This is native resource-read attribution, with no numerical oracle, whole-OS timing attribution, top-level DDR3/ROM timing claim, or prediction of removable cycles.
