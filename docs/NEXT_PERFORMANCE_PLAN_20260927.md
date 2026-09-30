# Next performance goal: reduce cache refill overhead

Updated 2026-09-28 after the final guest screenshots. **Goal paused.**
The 6c FPU + cache-v2 candidate passes directed/core checks and seed31 FPGA
fit/timing. Native Whetstone throughput improves 2.139% with byte-exact final
captures. All three full-machine runs finished, but FPU and Mix contain
impossible timings and are **invalid performance results**. Color8 reports
9.856 seconds versus 9.878 previously (about 0.22% faster in one run).
Hardware speed remains unmeasured. Full-machine qualification has not passed.

The user requested the experiment proposals below **as documentation only**.
None is authorized to start by this list. No reruns, RTL edits, additional
builds, or hardware operations are implied. Finish the already-requested
report/evidence preservation, then wait for the user's choice. See the
[current handoff](../HANDOFF-20260928.md) for evidence and constraints.

## Proposed experiments, ranked for the next decision

These are future experiments, not completed checks or a claim that the cause
is known. Prefer the cheapest experiment that distinguishes competing causes.
Keep the full-feature 8+8 KB configuration and prefetch-fault fix throughout.

| Priority | Experiment and question | Proposed method | Decision / stop condition |
|---|---|---|---|
| 1 | **Audit benchmark timing and result storage.** Are the impossible numbers caused by counter arithmetic, bad reads, overwritten result data, or a reporting defect? | First inspect existing logs, screenshots and saved observer data against the valid 6c runs. Identify the actual timer routine, counter format, start/end values, result addresses and conversion path from the benchmark code. If those values were not captured, document exactly which observations are missing before proposing another run. | A label such as “timer glitch” is insufficient. Establish whether the evidence can distinguish timing failure from cache/data corruption; do not accept apparently plausible rows from an invalid suite. |
| 2 | **Matched cache A/B diagnostic.** Does the failure follow cache-v2? | If another run is approved, use the valid 6c FPU baseline cache and cache-v2 with identical guest input, controls, model, feature flags and instrumentation. Start with one affected subtest or the shortest faithful reproducer. Capture raw timer reads and result writes, not only the final screenshot. | Baseline valid / candidate invalid isolates the cache change under those conditions. Both invalid points toward a common fixture or measurement issue. A valid rerun alone does not explain or erase the preserved failure. |
| 3 | **Independent memory oracle around affected accesses.** Does crossing-line allocation return or retain incorrect bytes? | After identifying relevant addresses, build a short directed replay using independently computed byte values. Cover writable timer/result/stack data, first-line misses, both cache-line halves, intervening writes, snoops, replacement, retained-line loss and bus errors. Include instruction-side cases only where the observed failing access path warrants them. | Find the first wrong byte or state transition and minimize it. Extend tests around the actual failure, rather than merely adding more copies of existing passing cases. |
| 4 | **Locate the earliest guest divergence.** Where does execution become incorrect? | If the short reproducer is inconclusive, compare bounded baseline/candidate traces around timer calls and result stores. Align by instruction/transaction events rather than equal cycle numbers, since a speed change shifts timestamps. Include PC, address, byte enables, data, cache state and snoop/invalidation events. | Identify the first unexplained architectural data/control difference. Keep expected elapsed-time differences separate. Stop tracing once a small reproducible cause is found. |
| 5 | **Controlled bypass or feature isolation.** Which part of the new allocation path matters? | Only after the preceding evidence, test one diagnostic switch at a time: disable the new first-line allocation while retaining the rest of the candidate, or narrow it to the observed access class. Compare the same failing sequence. These are diagnostic variants, not acceptable performance fixes by themselves. | A disappearance of the failure narrows the cause but does not prove correctness. Any eventual fix must preserve general memory semantics and pass the original failing sequence plus existing error/snoop/store regressions. |
| 6 | **Requalify speed after correctness.** Is the native benefit present in valid guest measurements? | After a diagnosed fix or a demonstrated measurement correction, rerun the native fixture and all FPU/Mix/Color guest suites with strict guest-result validation. Report each row, raw timings and identities against a matched baseline. Add explicit rejection of nonpositive elapsed times and invalid arithmetic; investigate implausible positive values too. | No speed claim from negative/zero/impossible timings. Require valid suite completion and no material CPU/graphics regression before considering hardware. The native +2.139% and prior FPU +4.44% cannot simply be added. |
| 7 | **Matched FPGA test, if the user chooses it.** Does a fully qualified candidate help on the real board? | Reuse the timing-clean image only if its exact RTL passes qualification; a changed RTL fix needs a new reviewed fit. Once shared hardware is authorized and free, use identical Main/disk/32MB/33MHz settings and five valid repetitions per variant, including every FPU/Mix row and Color8. Complete the existing OS/CD/shutdown gates. | Target FPU >=0.759 and report gain against the actual matched baseline. Investigate Mix loss >1% or Color time increase >2%. A passing fit is not a hardware speed or correctness result. |

If these establish correctness but the measured gain remains below target,
the next performance experiment should come from a **new timed bottleneck
breakdown**: arithmetic occupancy versus instruction/data cache misses,
first-word wait, line installation and replay. Optimize the largest measured
recoverable cost with one change at a time. Do not default to larger caches,
revive the unsafe external-tail draft, repeat failed queue-bridge seed walks,
or weaken feature/correctness requirements to obtain a passing result.

For cost control, use a cheaper agent for evidence extraction, proposed test
implementation and approved scripted runs; primary review is for diagnosis,
architectural correctness and final acceptance. Long jobs should use durable
scripts checking about every ten minutes and reporting terminal/failure events,
not repeated model-driven status polling.

## Historical plan and rationale

The remaining sections preserve the original plan and dated experiment
reasoning. They do not override the pause or authorize the proposals above.

Created 2026-09-27. This plan follows `RESUME-20260927.md` and
`FPU_PROFILE_20260927.md`. It is a plan, not evidence of completed validation.

## Goal and acceptance criteria

Improve the full-feature core's FPU benchmark by reducing cache refill cost.
Aim for at least 10% relative improvement over the timing-clean `faf9d98`
hardware score of 0.690: FPU average >= 0.759. This is an engineering target,
not a predicted gain. Preserve the prefetch-fault correctness fix in `6f0f159`,
8+8 KB caches, Ethernet, CD-ROM, and the current release recipe.

Accept a candidate only after correctness checks, timing closure and hardware
validation. Compare against paired baseline runs with the same Main, guest,
RAM setting and benchmark configuration. Collect five valid FPU runs and five
valid Mix runs, plus five Color 8-bit runs; retain individual subtests.
Exclude and report known impossible timer readings, replacing those runs.
Investigate a median Mix regression greater than 1% or Color time regression
greater than 2%; do not waive regressions as noise without evidence.

The goal is not complete merely because a simulation improves or an RBF boots.
If the target proves infeasible, record measured limits and the next decision.

## Why this comes next

The FPU suite is at about 68% of real-Q800 speed. The old fixed-window
simulation reported 41% of clocks in cache fill, but omitted the hardware's
retained RAM line and included post-test activity. That figure does not
establish a timed FPU bottleneck. Disk is the largest percentage gap (47%), but
its Main/SCSI work is a separate project; pursue it after this bounded cache
investigation rather than mixing changes and measurements.

Larger caches, the ROM-line fill-port experiment and P246 line-scoped
invalidation already failed to show useful gains within timing constraints.
Do not repeat them without a new, specific explanation.

## Historical measurement decision after the first bulk-refill candidate

The calibrated retained-line A/B runs completed successfully. Bulk cache
installation saves two refill-tail clocks in the integrated SDRAM bench,
but the OS FPU average is **0.698 for both variants**. Whetstone is
3849.262 versus 3848.418 KWhetstones/sec; Matrix Multiply is 0.991 versus
0.990 seconds; FFT is 0.447 seconds for both. Color takes 9.878 versus
9.807 seconds (about 0.72% faster). These are single paired simulations,
not hardware measurements or evidence of repeatable sub-percent gains.

Do not advance this candidate to Quartus on these results. Keep its patch
and correctness evidence for reuse. The next task is to identify the actual
timed FPU subtest boundaries and collect arithmetic, cache and CPU-wait
measurements within those boundaries. Fixed-window dispatch/fill totals
must not be interpreted as benchmark speedup. Review existing traces and
instrumentation first; only launch another long simulation once a concrete
measurement method can separate timed work from setup and idle activity.
The hardware improvement target remains unmet.

The first targeted capture completed normally on 2026-09-28 and reproduced
the baseline screenshot and full-window counters exactly, but its strict
checker rejected zero recognized timed spans. The host observer mixed
wrapper request/ack signals with obsolete core instruction/address fields;
the separate instruction-fetch channel therefore never populated its code
recognizer. Correct and verify the actual generated-model adapter, including
recognition diagnostics, before repeating the long workload. Host-only
recognizer tests and a zero-span boot smoke did not prove this integration.

The corrected capture launched at 01:04:11 UTC on 2026-09-28 after real-model
boot, selector/helper/timer fixtures, an early-branch boundary regression,
and an actual decoder eligibility check passed. The live adapter sanity gate
now sees instruction fetches and known opcodes. Actual OS benchmark coverage
remains unproven until all three timed sites pass strict validation; see the
active-run handles and frozen identities in `RESUME-20260927.md`.

## Original work sequence (use current checkpoint above for remaining work)

1. **Establish the baseline and profile the path.** Preserve the existing
   timing-clean RBF and source identities. Use current RTL with the prefetch
   fix as the implementation baseline. Reproduce the FPU simulation using
   the saved control stream and disk fixture, retaining exact source hashes,
   commands and results. Split fills by instruction/data and RAM/ROM;
   measure first-word latency, inter-word gaps, cache installation and
   restart cost. Distinguish fill occupancy from actual CPU stall time and
   account for overlap. The observed 41% is not automatically recoverable.
   Deliver a cycle breakdown and a ranked list of specific changes before
   modifying production RTL.

   Follow-up inspection found that `sim.v` omits the RAM retained-line
   sideband present on hardware. Measure the actual cache plus SDRAM path
   with that sideband before interpreting the old ~15-cycle average or
   launching repeated full-machine runs. A functional retained-line model
   alone must not be described as cycle-accurate SDRAM.

2. **Implement one focused candidate.** Prefer removing demonstrated
   handshake or bookkeeping delays and using existing retained-line/burst
   information. Keep the interface registered where timing requires it.
   Architectural design and review stay with the primary agent. Do not
   disable cache invalidation as a shortcut. The initial notes incorrectly
   said MMU U/M-bit writes lacked snooping; the wrapper already queues these
   invalidations. Any future cache-push optimization still requires a
   separate all-writers coherence/ordering audit, any necessary snooping
   fixes and A/UX validation. The MC68040 manual section 4.2 explicitly
   requires selected clean lines to be invalidated too: preserving them
   across CPUSHA is ruled out, not merely awaiting a snoop audit. See the
   source and constraint in `FPU_PROFILE_20260927.md`.

3. **Qualify correctness and simulation benefit.** Run CPU self-tests and
   applicable cache, store-buffer, memory-path, line-DMA and SDRAM benches.
   Include refill/snoop collisions, errors on later beats, backpressure,
   reset/invalidation during fills, RAM/ROM transitions and MMU behavior
   when affected. Record baseline failures separately. Run matched FPU and
   Color full-machine simulations and a CPU regression workload. Advance
   only for a reproducible benefit, with no unexplained correctness failure.
   Run Analysis & Synthesis and inspect inferred memories before a full fit.

4. **Fit a bounded candidate.** Preserve Ethernet/CD and current trims;
   inspect ALMs, M10Ks, all clock domains and SDRAM crossings. Do not restart
   the stopped seed walk on unchanged RTL. For a qualified new candidate,
   run one initial fit and at most two alternative seeds before reviewing
   critical paths and deciding whether structural work is needed. Serialize
   this project's fits, check other live flows, and freeze each build's
   inputs. No worktrees. A timing-marginal run is diagnostic, not acceptance.

5. **Validate on hardware and document.** Only use the shared MiSTer after
   availability is established; inspect a fresh screen and cleanly shut down
   the current guest before loading anything. Use the disposable benchmark
   disk and write-buffer Main. Measure the paired benchmark set above,
   Mac OS boot/idle/input/shutdown, Ethernet integrity and CD data/transport.
   Complete A/UX at 32 MB and arrange human audible-CD and OSD checks before
   release acceptance. Save source/RBF hashes, timing reports, screenshots,
   scores and a concise handoff. Publishing a release or PR is a separate
   action governed by the existing handoff and user authorization.

## Model and execution budget

The user explicitly requested cheaper models for routine work.

| Work | Default model | Boundaries |
|---|---|---|
| Documentation summaries, result tables, targeted web research | `gpt-6-luna` | Cite evidence; flag uncertainty; research only when a specific question requires it |
| Scripted test/simulation orchestration and log collection | `gpt-6-luna` | Fixed recipes, exact hashes, explicit pass/fail checks; escalate novel failures |
| Routine test harness changes or difficult runner failures | `gpt-6-sol` | Primary reviews changes and interpretation |
| Authorized hardware operation | `gpt-6-sol` | One operator; obey shutdown/shared-device rules; never infer availability |
| Architecture, coherence, critical paths, acceptance decisions | Primary agent | Review evidence rather than delegating final correctness judgment |

Use independent agents for documentation and isolated simulations where
useful; do not duplicate long runs or allow competing hardware operators.
Keep orchestration messages compact. Reuse completed results by source hash.
Do not rerun ~90-minute full-machine workloads until a directed screen and
cycle-level measurement justify them. Escalate reasoning complexity, not
every routine task, to the expensive model.

## Existing evidence and entry points

Focused existing checks (from `verilator/`):

```sh
make tb_sdram tb_wombat_bus32 tb_store_buffer tb_memory_path tb_memory_path_registered_first_miss tb_line_dma
```

CPU checks: `sh rtl/ap68040/tb/run_tests.sh`. Full-machine profiles use
`--cpu-profile profile.tsv --max-cycles 20000000000`, the saved control
stream, fast-boot ROM and `MacQuadra800-Speedometer402-profile.hda` fixture.
Confirm the current Linux runner and fixture paths before launching; older
documents retain WSL commands. Keep `--unroll-count 256` for MMU ATC clearing.
The full-machine sim omits the top-level `emu` glue, so hardware remains
necessary for changes affecting it.

- `docs/FPU_PROFILE_20260927.md`
- `docs/perf/fpu_profile_20260927/fpu_control.txt`
- `docs/perf/fpu_profile_20260927/sim_fpu_profile.tsv`
- `docs/GRAPHICS_PROFILE_20260926.md`
- `docs/perf/graphics_profile_20260926/color8_control.txt`
- `docs/perf/VS_REAL_QUADRA_20260926.md`
- [HANDOFF-20260928.md](../HANDOFF-20260928.md) (current state and next actions)
- `RESUME-20260927.md` (chronological evidence and full-machine recipes)
- `CLAUDE.md` and `BUILD.md` (build and hardware rules)
