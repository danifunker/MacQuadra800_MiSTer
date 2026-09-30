# Native FPMm baseline, 2026-09-28

One bounded baseline execution of pinned Speedometer tEsT12000 selector3,
embedded name FPMm. This is the actual native FPU Matrix kernel with preserved
ROM allocation runtime, not SANE CODE3 WStone and not an OS-timed FPU suite.
Static provenance/ABI are archived in ../fpu_completion_eligibility/provenance.
No optimized RTL, independent numerical oracle, FPGA fit or hardware test.

The exact3,784-byte resource enters at600000 through its original main/A055
initialization. Globals600ea0..600ec7 and localA4=608ea0 retain resource layout;
entry630000, stack640000, ABI captures625000. The frozen Whet image generator
was copied with WORDselector3 instead of1; all other stub/source/runtime/ROM
settings match. InitialFPCR is recorded00000000; no stub FPCR write. This is
a reset-start fixture with retained OS memory/runtime, not the complete
architectural environment of a live Mac process.

## Result and qualification

Loop31,634,431, returned31,635,207; simulation122.483wallsec. One two-job build,
one baseline run, no rerun. Cap80Mclocks/600wallsec per phase.600D and all host
ABI gates pass: known D3-D7/A2-A6 and seeded FP4-FP7(11..14) preserved,
A4 restored600000, SP640000 before/after caller selector cleanup, returned
D0=608ea0, resource code unmodified. Chip/BERR/IRQ errors are0. Source manifest
was verified unchanged after execution. run/identity.json records consumed
RTL/model/image/ROM hashes and all ten release CPU flags; no live full-machine
or previously completed fixture inputs were modified.

The Matrix monitor pairs exact nativeA31E call PCs18c/1ae/1d0 with their own
+2 resumes and A01F call PCs260/270/280 with262/272/282. Primary events use
post-NBA actualPC/IR validated against pinned resource bytes; secondary events
use pre-edge pipe_rf_owner&&pipe_input&&pipe_ready with pc/epf_data[head].
Register snapshots overlay RF written/bank, pending write and current core
RF write. No wrapper bus acknowledge is treated as an allocation return.
The actual decoder proof includes3243/3043/5243 supported andA31E/A01F
unsupported. All246 observed resumes were primary; the secondary observation
path is present but not exercised by these trap returns.

All123 allocation returns were nonzero with D0error0; each164-byte payload is
unique/nonoverlapping and inside original TheZone=ApplZone3f1890..bkLim492078,
below MemTop517754 and outside private arena600000..642000. All123 frees
matched allocated pointers exactly once and returnedD0error0. The123 row
pointers still in the guest frame atA6=63ffea, offsets-a4/-148/-1ec, independently
match the trap records. TheZone/ApplZone/MemTop/bkLim and zcbFree3ff10 restored.
The64-byte zone header has6 changed bytes at offsets31/32/33/3d/3e/3f; allocator
metadata is mutable. The64-byte neighborhood around bkLim is byte-identical.
These scoped checks are not a full heap-damage or numerical oracle.

Actual vector11PC/unimp counts are0, appropriate for this hardware arithmetic
kernel. The inherited runner's final stdout label `native_FPSP_coverage=1`
is inaccurate for Matrix: the TB requires native-body coverage, while reporting
actual FPSP samples. Frozen runner/inputs were retained; the strict checker and
this report do not infer FPSP activity from that label.

## Profile

| Observation | Clock samples |
| --- | ---: |
|Window/core/cache/FST histogram sum|31,634,431 each|
|Native main-body PC|272,924|
|Entire native resource PC|30,493,768|
|ROM PC|454,917|
|Non-IDLE FPU|7,673,636 (24.257%)|
|CPU GO160|8,052,476 (25.455%)|
|DEC153 with bg&&!done|1,974,168 (6.241%)|
|CPU MRD9|3,932,643 (12.431%)|
|Cache FILL4|624,064 (1.973%)|
|Cache TAGW5|45,492|
|MRD9+FILL4|437,957;350,777 without fill_acked|
|ROUND14|1,538,168|
|Reviewed exact ROUND guard|1,510,148 (4.774% local sample opportunity)|
|Guard coincident GO/bg/blockingDEC|1,088,956 /421,192 /421,192|
|STDONE17 disabled/no-sideport/CE-reset-valid at that edge|524,800 (1.659%)|

PCs are occupancy, not invocations. Core256/cache16/FST32 histograms reject
out-of-range samples without masking and each sum is checked against the
window. Busy-op total equals all non-IDLE FPU samples. The window excludes
start-marker edge/includesstop, and contains callback entry/exit and caller
cleanup, allocation/free/runtime service, but no OS UI/dialog/idle/timers.
The existing CORE_LAT and external bus/bridge/SDRAM counters remain in run.log.
There were38,476 first-miss data reads (mean8.80),30,801 bus32 reads (allLONG
offsetE),16,235 external instruction requests,414 walker transactions.

The ROUND predicate is unchanged from the reviewed Whet baseline. These are
local eligibility/occupancy samples, not saved CPU clocks or a speedup bound.
STDONE is observed at that state, not at preceding conversion exit. No shortcut
was implemented or measured. This fixture does not measure native FFT or the
full OS FPU timing brackets and does not establish the refill goal.

## MOVE attribution and corrected interpretation

rInnerproduct has four FMOVE.S memory→FP operations at11a/132/142/148 per inner
iteration. Four passes*40rows*40cols*40elements =256,000iterations, thus1,024,000
single loads. rInitmatrix adds12,800 FMOVE.W operations. The observed MOVE
ROUND count1,036,800 matches their sum; MOVE busy4,160,000 matches4*1,024,000+
5*12,800. This connects the count to actual native code, but does not partition
GO by instruction class or show all MOVE busy clocks are blocking.

Correction to an earlier analysis message: accepted is STATE-only, includes
F_ROUND for MOVE as well as arithmetic (ap040_fpu.v:279), and can release a
MOVE to background there. Thus a direct-WB shortcut that drops ROUND could
alter fetch overlap; existingROUND/WB semantics must be considered explicitly.
A prospective narrow normal-single FMOVE input shortcut from F_IDLE to existing
F_ROUND would skip source conversion/execution setup and retain accepted/WB.
That is a static candidate for primary review, not approved/implemented here.
Normal input guard, exact working fields and shadow/status/sideport handling
need their own review and independent arithmetic tests. Input eligibility is
not proved merely by the1,510,148 ROUND samples; future integer-oracle/input
analysis must distinguish zeros, source formats and normal single values.

## Reproduction and evidence

Original scratch: scratch/native_fpu_matrix_20260928. From repository root,
with preserved external prerequisites, create a fresh image/output:

    python3 scratch/native_fpu_matrix_20260928/prepare_image.py
    CCACHE_DISABLE=1 TREE=scratch/fpu_refill_platform_workload_20260927/baseline \
      python3 scratch/native_fpu_matrix_20260928/run_platform_whet.py --out NEW_EMPTY_PATH

The runner requires the pinned native image and fresh output; it preserves
failure logs and has no automatic rerun. It uses no SANE numerical reference or
fixed loop expectation. FullRAM/ROM, generated model and binary stay in scratch.
Small code/globals/stack/ABI and zone/limit captures are diagnostics, not a
numerical oracle. check_result.py verifies the archived qualification, pointer
records/frame tables, heap scalar captures, code/ABI and profile totals; it
compares an existing measurement.json without changing it. source_manifest
retains original absolute paths; an archive manifest checks archive-local text.
