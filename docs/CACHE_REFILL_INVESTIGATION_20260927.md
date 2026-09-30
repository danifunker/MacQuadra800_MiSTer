# Cache refill investigation, 2026-09-27

**2026-09-28 update:** the later cache-v2 crossing-read candidate, combined
with the 6c FPU and original SDRAM bridge, passes correctness checks and FPGA
timing. Native Whetstone throughput improves 2.139%; full-machine guests are
running and hardware speed is unmeasured. See the
[current handoff](../HANDOFF-20260928.md). The investigation below records the
earlier bulk-refill experiment and its rejection; that decision remains valid.

Baseline implementation: `6456c62` (includes the prefetch-fault fix). The
profiler and corrected background notes are committed as `b18fd07`.
The performance target remains in `NEXT_PERFORMANCE_PLAN_20260927.md`;
at this earlier checkpoint there was no new FPU hardware score or fitted candidate.

## Corrections to the initial hypothesis

The original full-machine simulation connects the ROM retained line but
omits the RAM retained-line interface used on hardware. Its 41% C_FILL
occupancy and roughly 15-clock average do not directly measure the FPGA
refill path. Agreement of the aggregate FPU scores was insufficient evidence
for agreement of those internal costs.

The MMU walker already snoops page-table writes through `wsnp_pend` in
`wombat_cpu.sv`. Subsequent architectural review ruled out retaining selected
clean lines across CPUSH: the MC68040 manual requires their invalidation too.
Write-through operation and snooping do not remove that requirement; see
`NEXT_PERFORMANCE_PLAN_20260927.md` for the source and decision.

## Native workload measurement scope

The native `tEsT12000` selector-1 Whetstone callback now executes in the
preserved ROM/runtime fixture: 8,726,508 loop clocks, passing ABI/code and
chip/bus checks, with no independent numerical oracle. Evidence is in
`docs/perf/cache_refill_20260927/native_fpu_whetstone/`.

Its 8,294 C_FILL clocks (0.095%) are only fill-state occupancy. Crossing
longword reads whose first line misses can use C_PASS directly, without
allocating a line; a second-line miss after a first-line hit may instead
fill that next line. The native log contains 9,773 bus32 long reads at
line offset E, taking 173,150 aggregate request clocks. Their pattern is
compatible with the crossing path but is not per-transaction proof of the
cache cause. Do not call C_FILL occupancy the total memory penalty or use
it alone to rule out memory-path optimization. Cache lookups, tag commit,
bypass transfers and overlap with core execution remain relevant.

## Production memory-path measurement

An isolated bench connects the actual cache, transaction adapter, SDRAM
bridge/controller and SDRAM chip model. Its RAM service FSM is mechanically
derived from `tb_memory_path.sv`, with the registered-first-miss settings.
This is a RAM-only subset, not the complete CPU/MMU/DMA machine.

The control bench passes 64 sequential reads and 2,048 mixed posted writes
and reads with zero chip protocol errors. The integrated cache bench passes
38 cases per implementation with `AP040_EXPERIMENTAL_XSTORE=1`: all four
requested word rotations, a spanning data longword, both cache banks, and
all four ways plus replacement. The instruction-way checks displace the
private instruction-line buffer before checking the installed words.
Subsequent word reads must be correct cache hits without a bus request.

Representative warm-row aligned read, CPU clocks from request presentation
to the rising-edge observation (all columns use the same convention):

| Event | Baseline, cache sideband disabled | Baseline, hardware sideband enabled | Bulk candidate, sideband enabled |
|---|---:|---:|---:|
| SDRAM first-word acknowledgement | 7 | 7 | 7 |
| Registered bus acknowledgement | 8 | 8 | 8 |
| Retained line valid | 9 | 9 | 9 |
| CPU critical-word acknowledgement | 9 | 9 | 9 |
| Cache tag commit | 15 | 12 | 10 |

The existing sideband saves three tail clocks. The candidate saves two more,
without changing first-word latency. Row/refresh state can change first-word
latency between cases as the earlier completion shifts later requests; compare
tag commit relative to the first bus acknowledgement to isolate this change.
The baseline tail is four clocks and the candidate tail is two.

Disabling the cache sideband here does not disable the platform's retained
line; it serves subsequent words through registered bus acknowledgements.
This is not identical to the old full-machine model, which omits both RAM
retained-line connections.

## Scratch candidate

`scratch/fpu_bulk_line_candidate_20260927/prepare.py` generates a candidate
cache from the production source without editing production RTL. Candidate
SHA256: `6807b56c34ae5819402e277eac13404c655160672ede3acf82f97237a103745b`.

When the existing `fill_line_match` is true and no bus error is present, all
four word-interleaved data arrays receive the completed line on one edge.
Their pair/instruction mirrors use the same writes. The existing C_TAGW
state still validates the tag and arbitrates against snoops. The candidate
does not consume the sideband while a bus transaction is outstanding and
does not add an early acknowledgement from a live memory input.

The 38-case integrated comparison and existing cache-snoop tests pass for
both sources. A separate boundary bench also passes with the release XSTORE
macro: same-row snoops at local installation and tag commit, a bus error
coincident with sideband eligibility, delayed sideband while a bus beat is
outstanding, and a free-running snoop while CE is stopped. It checks that
updated backing data is refetched and that victim tags are not revived over
overwritten data. The candidate exercises six bulk installations; the
baseline exercises none. The delayed-sideband case completes exactly two
bus reads, rather than abandoning the outstanding second beat.

Both CPU suites pass all 31 legs with XSTORE and LEA enabled; their summary
logs are byte-identical. That suite does not enable every release pipeline
macro. No timing, synthesis or full-workload qualification is claimed from
these directed measurements. The small text evidence, candidate patch and
reproduction scripts are archived in `perf/cache_refill_20260927/`.

An additional direct-port edge screen passes both sources: five cross-line
reads (including set wrap), 44 byte/word/long offsets, instruction-line and
pair-hint paths, reset between data installation and tag commit, and stale
RAM/ROM sideband tags in both directions. All five cross-line cases exercise
the candidate's bulk response before acknowledgement, checking the retained
first-line word combined with the next line. The expected values are assembled
independently from backing bytes. The ROM service is synthetic in this screen;
it does not qualify the production ROM bridge or whole-machine arbitration.
The reviewed logs and source manifest are in `perf/cache_refill_20260927/edge_cases/`.

A focused whole-CPU interrupt screen also passes with all ten release CPU
macros. The ordinary CPU bench ties the retained-line input off, so this
screen uses a test-only wrapper and a write-invalidated retained-line offer
from its 16-bit memory model. The candidate performs 48 bulk installations,
including three edges with a pending IRQ and active pipeline load; all 48
busy releases occur exactly two clocks later. Three IRQ injections and
load commits complete with the independently checked exception frame,
register values, handler count and `$600D` success marker. Cancel-control
pulses occur, but the pipeline monitor records zero cancelled entries;
this covers IRQ ordering through the load boundary, not discarded speculative
work. The full platform bus/MMU/DMA path remains outside this screen.
Evidence is in `perf/cache_refill_20260927/irq_boundary/`.

The full-CPU platform Whetstone fixture also passes on both sources with
the current release CPU macros and actual SDRAM bridge/controller. Loop
clocks are 17,641,650 baseline and 17,637,468 candidate (4,182 fewer,
0.0237%). Both return `$600D`, report zero chip protocol errors, and match
the independent globals/CODE3/stack oracle byte-for-byte. All 32 source
identities match except the intended cache replacement. This is the CPU Mix
Whetstone fixture, with only 1,984 first RAM read misses and no interrupts
or DMA; its small gain is not a prediction for the OS-driven FPU suite.
Evidence and a reproducible runner patch are in
`perf/cache_refill_20260927/platform_workload/`.

## Simulation instrumentation and next gates

`sim_refill_profile.h` records fill samples by physical region, instruction/
data bank, beat count, issued state and requester-release state. It separates
tag-write clocks and complete fill duration histograms from partial brackets.
Core S_MRD overlap is labelled as overlap, not total stall time. Host tests
cover bracket boundaries and the report checker rejects missing or
inconsistent instrumentation.

A fresh Verilator 5.050 build with the current ten CPU release macros and
`--unroll-count 256` passes a short smoke test: 620 fill samples, 62 tag-write
samples and 62 completed fills reconcile exactly. That smoke uses the old
RAM model and does not establish an FPU baseline. Its source and fixture
identities are under `scratch/fpu_refill_baseline_20260927/`.

An opt-in abstract retained-RAM-line model now passes directed tests for
held requests, latency, publication, reset and write invalidation, including
write/publication collisions. With `+ram_first_latency=4` and
`+ram_line_publish_delay=2`, its controlled cache-path trace matches the
warm-row timing milestones above. It does not model SDRAM row/refresh
contention or replace final hardware measurements. Both workload builds use the
same model, current release CPU macros and `SCSI_CACHE_OFF`, with independent
writable copies of the golden disk. Benchmark completion must be checked in
screenshots as well as profiler output. The saved control stream has a fixed
profiling interval; extra idle time after a faster run must not be mistaken
for a change in benchmark work. Use guest scores and subtest times as the
primary workload comparison.

After collision tests and matched workload measurements, advance only if
the benefit justifies the area/timing cost. Analysis & Synthesis, a bounded
fit attempt, and the hardware release gates remain outstanding.

## Completed Color screen

The first matched Color 8-bit pair completes with exit status zero, visible
"The tests are done" dialogs, and reconciled refill reports. Baseline is
9.878 s (rating 1.072), candidate 9.807 s (rating 1.080): about 0.72% faster
by the guest elapsed-time ratio. This is one paired simulation, not a
repeatability study or hardware result. Its small gain shows no regression
in this screen but does not qualify the FPU target.

Completed RAM data fills average 11.010 versus 8.993 clocks, and RAM
instruction fills 11.165 versus 9.175. ROM timing is essentially unchanged.
Each fixed profile window is 524,160,000 sampled clocks with one partial
start and no partial end or aborted fill. The candidate executes more fills
and instructions within that window; those counts do not compare identical
amounts of benchmark work. Exact inputs, screenshots, profiles and exit
evidence are archived in `perf/cache_refill_20260927/full_machine_color/`.
## Completed FPU screen and decision

Both FPU runs also exit zero with visible completion dialogs and validated
reports. Baseline/candidate Whetstone is 3849.262/3848.418 KWhetstones/sec,
Matrix Multiply 0.991/0.990 s, FFT 0.447/0.447 s; both averages are 0.698.
This single pair shows no meaningful FPU gain despite the measured refill
tail reduction. Evidence is in `perf/cache_refill_20260927/full_machine_fpu/`.

Do not advance this candidate to synthesis or fitting on these results.
The next measurement must identify timed FPU subtest boundaries and separate
arithmetic, cache and CPU-wait costs from setup and post-test idle. Keep the
scratch patch and passing correctness screens for reuse; production CPU RTL
is unchanged, and the hardware improvement target remains unmet.
