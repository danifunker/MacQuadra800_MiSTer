# Baseline FPU completion eligibility measurement, 2026-09-28

Simulation-only counters in a copied platform-fixture TB; no optimized FPU or
production RTL edits. Sources are read-only from
`scratch/fpu_refill_platform_workload_20260927/baseline/rtl`. This is the isolated SANE-based CODE3 `WStone` CPU fixture, with actual
quadra800, MMU/cache/store buffer,
service FSM, sdram_beat32, sdram controller and two chip models. ROM uses a
six-clock latency model; overlay is forced off. There are no OS-driven
Speedometer FPU subtests, interrupts, DMA, display scanout or device workload.
It does not execute the native FPU-suite `FPUWStone` resource kernel and does
not replace the ongoing full-machine timed profile. The original generator
`scripts/cpu/build_whetstone_image.py` calls CODE3+0008 at600008 and retains
its SANE A9EB traps. In contrast, CODE3 DoFPUBenchMarks loads external resource
`tEsT`12000; selector1 enters its native `FPUWStone` at resource+29a.
`provenance/PROVENANCE_ABI.md` and pinned `provenance/provenance.json` establish
that distinction and the three native callback mappings.

Reproduce one baseline run from repository root into a fresh output directory:

    CCACHE_DISABLE=1 TREE=scratch/fpu_refill_platform_workload_20260927/baseline \
      python3 docs/perf/cache_refill_20260927/fpu_completion_eligibility/run_platform_whet.py \
      --out scratch/fpu_completion_eligibility_20260928/fresh_run

Verilator 5.050, --unroll-count256, two build jobs. All ten release CPU macros,
CACHE_CD_OFF/CACHE_SMALL/SIMULATION, image, ROM, generated chip model and
romlat6 match the previous frozen platform baseline. `run/identity.json`
records all source/input hashes and flags; `source_comparison.json` checks
the matches. `*.diff` record the exact TB/runner changes. The only RTL source
content difference consumed by the build is the testbench counter addition.
The runner additionally hard-fails differing loop clocks, any of the three
existing memory oracles, chip errors or an IRQ/bus-error observation.

Counters sample the existing pre-edge `in_loop` interval in the same always
block as the fixture's other counters. Start-marker edge is excluded and
stop-marker edge included. Total sampled clocks must equal loop_cycles.
FST is occupancy; BUSY_OP samples r_op only while fst!=IDLE. Neither is an
accepted-operation count.

ROUND predicate, sampled in F_ROUND14 on the proposed early-writeback edge:
T_NUM0, mantissa integer bit set, GRS0, actual prec_of(op)==extended, signed
e_w within1..32766, FPCR enables[15:8]0, op in
00/18/1A/04/20/22/23/28 (MOVE/ABS/NEG/SQRT/DIV/ADD/MUL/SUB), reset deasserted
and CE1, no cr_we/fm_we/bsun_req/fp_reset/frestore_idle/frestore_unimp/
fsave_ack/pend_capture. Precision replication excludes FSGL24/27 and explicit
single/double opcodes>=40; FPCR precision11 is correctly excluded as double.
IA_WE only updates FPIAR and is not part of this reviewed guard. Counts also
show eligible samples coincident with background activity, S_FPU_DEC153
bg&&!done, and S_FPU_GO160. These overlapping occupancies do not measure the
number of CPU clocks a bypass would save.

ROUND_REJECT reasons are independent:0 nonnumeric,1 integerbitclear,2 GRS,
3 precision,4 exponentbelow1,5 exponentabove32766,6 enables,7 opcode whitelist,
8 sideport,9 reset/CE. Their counts can overlap and need not sum to samples.

STDONE17 reports total samples, enableszero, enablesnonzero, sideport and
reset/CE separately. Its field named `eligible` means only enableszero + no
sideport + CE/reset valid **at the F_STDONE edge**. A proposed shortcut would
be decided at the preceding conversion-exit edge. These counters do not prove
that preceding edge met the guard and are not eligible-bypass transaction
counts. That distinction matters for concurrent FPCR/sideport changes.

No candidate was implemented or run. An eligible exact ROUND could locally
remove one CE-enabled completion clock, but overlap with integer execution,
requests, memory and next-FPU admission prevents equating counts with an
end-to-end gain or making a workload speedup upper-bound claim. The measurement
is evidence for ranking the next narrowly scoped experiment only.

## Results

One build and baseline simulation, exit0. Loop17,641,650 and returned17,642,118
clocks exactly match the prior baseline. The guest600D marker passed; globals,
code and stack match all three existing oracle captures byte-for-byte. Bus,
IRQ and chip-protocol errors are zero. Build19.4sec; simulation84.2sec.

| Observation | Samples |
| --- | ---: |
| F_ROUND |236,066|
| Reviewed ROUND predicate true |66,688|
| Predicate true with CPU S_FPU_GO |57,929|
| Predicate true while background active |8,759|
| Predicate true with blocking S_FPU_DEC |4,351|
| F_WB occupancy |242,356|
| F_STDONE occupancy |930|
| F_STDONE enableszero/no-sideport/CE-reset-valid **at that edge** |930|

ROUND eligibility is28.25% of ROUND samples. Most eligible samples are MOVE
(44,953); ABS642, NEG2,532, DIV930, ADD5,427, MUL7,298, SUB4,906 and SQRT0.
Rejections: GRS119,568; enabled exceptions80,475; nonnumeric/integerbitclear933
each; exponentbelow1=3. Other rejection counts are zero. Rejections overlap.
These are local applicability/occupancy observations, not a speedup forecast.

`stdout.log` has the concise result/oracle summary, `run/run.log` the full log,
`run/compile.log` exact compiler invocation, and `measurement.json` parsed
counts. `check_measurement.py` checks occupancy totals, opcode totals, counts,
qualification and all consumed-source hashes after completion. No second
simulation or optimization was run. `scratch_source_manifest.sha256` and `scratch_evidence_manifest.sha256` are
unchanged copies of the original scratch manifests; their absolute paths are
provenance references, not archive-local paths. `archive_manifest.sha256`
checks the files stored here. Compiled binaries, full RAM/ROM images and the
generated model remain only in scratch and are not archived here.


## Decision and archive scope

Park ROUND-to-WB and STDONE shortcuts for the measured SANE-based CODE3
`WStone` CPU fixture. This decision does **not** deprioritize either shortcut
for the native FPU-suite Whetstone, Matrix or FFT kernels; this screen supplies
no measurement of those kernels. The66,688 ROUND guard samples are0.3780% of17,641,650 loop clocks;
930 STDONE samples are0.00527%. Those ratios describe sample opportunities,
not saved CPU time. All non-IDLE FPU samples total1,365,203 (7.7385% of loop
clocks). Integer/background overlap and completion interlocks still matter.
This screen does not measure native FPUWStone/FPMm/FPUFFT or Mac OS
cache-maintenance costs, and cannot settle their bottlenecks. No candidate implementation, rerun,
synthesis or hardware qualification follows from these counts.

This directory is a small text archive. Paths written as `run/...`,
`oracle/...`, report, checker, runner and monitor diffs refer to files here.
The full working output remains at
`scratch/fpu_completion_eligibility_20260928/run/`; frozen input RTL remains
at `scratch/fpu_refill_platform_workload_20260927/baseline/rtl`. Reproduction
requires those external source/input prerequisites and the original fixture
RAM/ROM/default reference described by the runner. This archive does not
contain a self-contained RTL tree or full-machine image.

The three small guest-memory window captures in `run/whet_*.hex` and the
checked reference windows in `oracle/whet_*.hex` permit independent byte
comparisons without the32MB RAM image. `oracle_validation.json` records their
original paths, checked byte counts and hashes. Run this archive checker:

    python3 docs/perf/cache_refill_20260927/fpu_completion_eligibility/check_measurement.py
    cd docs/perf/cache_refill_20260927/fpu_completion_eligibility
    sha256sum -c archive_manifest.sha256

The checker validates archived logs/counters and compares all three actual
capture/reference windows. It leaves the archived measurement file unchanged.
Optional `--check-sources` additionally verifies the original absolute-path
source inputs when their frozen scratch tree remains available. The original
scratch checker already verified those inputs after completion. No immutable
scratch inputs or other archives were modified for this copy. The scope
correction and static native-resource audit were added only here and in a new
scratch provenance_review subdirectory; measured logs remain unchanged.
