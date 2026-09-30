# Native 6c resource-read attribution

One passive baseline replay qualified at8,724,166 loop clocks. All original runtime/ABI/code/global/stack gates passed; original selected reports, all NEXT rows and four memory captures are byte-exact against the completed 6c joint-profile reference. The source manifest remained unchanged. All translated target episodes are whole:96,271 reads /331,334 inclusive latency edges; saved rest-resource start context90,990 /311,506. No partial, active-at-finish, fault, unclassified path or measured invalidation event occurred.

| Physical address | Size | Reads | Inclusive latency sum | Maximum | Observed path |
|---|---|---:|---:|---:|---|
|00600eae|LONG|9,630|199,716|25|All first-line C_LOOK miss→C_PASS, failure mask1|
|00600ec2|LONG|22,460|66,091|6|Ordinary non-cross-line remainder|
|00600eba|LONG|22,460|23,783|14|Ordinary non-cross-line remainder|
|00600ebe|LONG|22,460|22,472|13|22,459 fast cross-line hits; one first-line hit→clean second-line fill|
|00600eb2|LONG|9,630|9,630|1|Ordinary remainder, all latency1|
|00600eb6|LONG|9,630|9,630|1|Ordinary remainder, all latency1|
|0060001c|WORD|1|12|12|Ordinary remainder|

At EAE the mean is20.73894 inclusive edges;190,086 edges beyond one per episode. Every first-line failure has missing tag and no concurrent latched/current snoop or inv_wren. This proves the repeated selected path, not why the tag was absent historically: earlier stores/snoops/sweeps/replacement or never-allocation remain possible. These addresses are physical resource-range reads, not a proven read-only-constant classification. Do not equate the9,630 resource passes with the9,773 external LONG episodes or claim external ownership. Latency sum/excess is accounting, not removable clocks or an end-to-end speed estimate.

The passive task uses original episode metadata after creation and before completion cleanup, with unchanged pre-edge/window sampling. It classifies only approved fast/shortcut and exact first/second lookup branches; ordinary reads remain a remainder. All113 RTL files and the original TB/entry/image/ROM/runner/checker are unchanged; shared changes are the monitor hooks and postcheck supervision. See `source/resource_read_monitor.svh`, `monitor.diff`, `supervisor.diff` and `preparation_identity.json`. Detailed plan and prior preparation status are preserved separately in `PLAN.md` and `PREPARATION_README.md`.

Unit `native-whet-resource-read-20260928.service`, invocation4c868eb748154e2d9e3eb0a28e580af0: supervisor2573599, runner2573601, actual native2574362, executableSHA7b1d12958db240a90085d02b46d0554e5316aee1472ea3834824aabbb6acb571. Started09:42:33UTC, qualified09:43:42.968UTC; all children gone, service inactive/dead/exit0. `runtime/supervisor.json` preserves actual identity and terminal checks; `execution/result_summary.json` records counts/cleanup/limits.

Portable archive check:

```
python3 docs/perf/cache_refill_20260927/native_fpu_whetstone_resource_reads_6c/check_archive.py
```

It verifies every included hash, strict resource and original joint reports, exact reference reports/NEXT/captures and terminal identities. Host fixtures include two valid reports,21 rejected corruptions plus four reference-comparison negatives; they test saved-report validation, not HDL branch execution. The qualified replay supplies actual path evidence.

`original_source_manifest.sha256` identifies the145 frozen scratch inputs (SHA7082248bdd0ec877b3a673ffe1b8dd21c91789fdf0afefe0ecb7ce877590610e). Its paths belong to the original scratch package; it is historical identity, not an archive-relative replay manifest. `archive_manifest.sha256` covers included archive-relative files. Full RTL, RAM/ROM images, executables and generated objects remain excluded; the source runner/supervisor require original frozen scratch inputs to rerun. The archive retains text sources/checkers/diffs, original/reference reports, identities and small captures; build summary only, full compile log remains scratch.

This is native selector1 FPUWStone runtime/profile evidence with unchanged ROMlat6 stub, no independent numerical oracle, full-OS attribution, top-level DDR3-ROM timing, synthesis or hardware qualification. No optimization was implemented and no additional run is authorized by this archive.
