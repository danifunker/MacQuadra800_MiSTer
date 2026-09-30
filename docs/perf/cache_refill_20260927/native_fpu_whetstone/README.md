# Native FPUWStone baseline, 2026-09-28

One bounded baseline execution of pinned Speedometer tEsT12000 selector1,
not the SANE CODE3 WStone fixture and not an OS-timed full FPU suite. Static
mapping and ABI proof are in ../fpu_completion_eligibility/provenance when
archived; scratch originals are in the sibling eligibility provenance_review.
The complete3,784-byte resource enters at600000, including its main/A055 init
and mutable globals600ea0..600ec7; localA4 anchor608ea0, stack640000,
entry630000 and ABI captures625000. No resource code was optimized or patched.

The source image is frozen SANE fixture RAM6822b728..., retaining its original
32MB low-memory/ROM runtime, MMU tables and vector11=4088d9fe. prepare_image.py
changes only resource bytes, new entry and ABI capture area; checked remaining
ranges equal the source. All consumed baseline RTL is from frozen platform
baseline/rtl. ShippedROM, romlat6, actual quadra800/SDRAM bridge/controller/chip
models and all ten release CPU flags are unchanged. FPCR is not written by
entry; actual startingFPCR00000000 reflects this fixture's reset environment.
It does not reproduce the OS callback's complete CPU/FPU/process environment.

One build (two jobs) and one simulation passed: loop8,726,508, returned8,727,284,
600D marker, zero chip/BERR/IRQ errors. Simulation wall37.357sec. Bounds were
40Mcycles and300wallsec per build/run; no timeout, rerun or candidate occurred.
No input changes were made during execution; source_manifest.sha256 verified
unchanged after completion. run/identity.json records every consumed source
and release flag; qualification_identity.json pins input/code/binary identity.

Success requires host ABI checks after600D: known D3-D7/A2-A6 sentinels
preserved, seeded FP4-FP7(11..14) preserved byteexact, A4 restored600000,
SP640000 before and after selector cleanup, returnedD0=608ea0, code unmodified.
Native globals/code/stack/ABI captures are small diagnostic windows. They are
not an independent arithmetic oracle. No numerical correctness or FPGA
qualification is claimed from this run, and baseline identity alone is not a
numerical reference for a future candidate.

## Occupancy and local completion opportunities

| Observation | Clock samples |
| --- | ---: |
|Native Whetstone body PC|1,729,593|
|Entire native resource PC|3,812,032|
|ROM PC|4,914,403|
|ROM vector11 entry PC|162,035|
|FPU unimp asserted|5,060|
|All non-IDLE FPU|1,266,996 (14.52%)|
|CPU FPU GO160|1,077,759 (12.35%)|
|CPU DEC153 with bg&&!done|487,279 (5.58%)|
|CPU MRD9|1,556,905 (17.84%)|
|Cache XSTORE8+9|269,286 (3.086%)|
|Cache FILL4|8,294 (0.095%)|
|MRD9+FILL4|4,148;1,186 without fill_acked|
|ROUND14|258,827|
|Reviewed exact ROUND guard|141,674 (1.624% of loop samples)|
|Guard coincident GO/bg/blockingDEC|109,870 /31,804 /30,711|
|STDONE17 disabled/no-sideport/CE-reset-valid at that edge|3,489 (0.040%)|

PC counts are occupancy, not handler invocations. unimp counts are sampled
assertions, not reconstructed accepted transactions. Core256/cache16/FST32
histograms reject out-of-range indices without masking, then each sum is
checked equal8,726,508; busy-op totals equal all non-IDLE samples. Cache8/9 are
retained explicitly. Sampling excludes start-marker edge and includes stop,
matching the pre-existing in_loop bookkeeping. The window includes callback
call/return and selector cleanup, and no UI/timer/idle/dialog workload.

ROUND eligibility is the prior reviewed predicate: numeric normal integerbit,
GRS0, extended precision, signed exponent1..32766, enabled exceptions0,
MOVE/ABS/NEG/SQRT/DIV/ADD/MUL/SUB only, CE/reset valid, no conflicting control,
FMOVEM,BSUN,reset,restore/save/pending-frame sideports. This is sampled at the
proposed ROUND bypass edge. STDONE samples do not establish guard truth at
preceding conversion exit. These opportunities and CPU/FPU overlap counts do
not establish saved end-to-end clocks. Neither optimization was implemented.

Existing CORE_LAT/external bus/store-buffer/bridge statistics remain in
run/run.log:9773 reads via bus32 (allsizeLONG, offsetE),627 external instruction
requests,292 tag clocks,42 walker transactions. These observations indicate
hit/transfer sequencing and FPSP execution deserve attention; no new RAM
latency or arithmetic optimization is approved by this report.

## Reproduction and evidence

From repository root with frozen prerequisites available:

    python3 scratch/native_fpu_kernel_20260928/prepare_image.py
    python3 scratch/native_fpu_kernel_20260928/prepare_monitor.py
    CCACHE_DISABLE=1 TREE=scratch/fpu_refill_platform_workload_20260927/baseline \
      python3 scratch/native_fpu_kernel_20260928/run_platform_whet.py --out NEW_EMPTY_PATH

The runner requires the pinned native image identity and a fresh output path.
It does not use the old SANE numerical captures or fixed loop count. Use the
archived runner/TB with --image pointing to frozen native ram.bin when those
inputs exist; full32MB image, ROM, compiled binary and generated models stay
in scratch and are not archived. Preparation scripts record their original
scratch locations and need those prerequisites; text copies are audit evidence.
check_result.py is read-only and checks archived result/captures/histogram/ABI
invariants without requiring full images; when ram.bin exists it also checks
its pinned identity. source_manifest.sha256 retains original absolute paths;
archive_manifest.sha256 checks archive-relative text only.
