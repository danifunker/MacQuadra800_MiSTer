# Resume here: timing closure and disk profiling, 2026-09-25

**Newer: `RESUME-disk-and-area-20260925.md` (the Main write buffer, the SCSI cache off, room for the pipeline).**

## LATEST (2026-09-25 evening): timing closed, PR #7 open

`a0b3072` meets timing on every clock: CPU +0.007, SDRAM +0.082, HDMI +0.044 ns,
all holds and crossings positive, 38,329 ALMs.  The build has every feature,
with the second integer pipeline out, speed physical synthesis, and the
IOSB-to-MLAB change.  On hardware: Mix median 1.670, and pings, CD data, CD
audio transport and shutdown pass.  PR: https://github.com/danifunker/MacQuadra800_MiSTer/pull/7
(branch `alanswx:full-feature-timing-clean-20260925`).  Still open: audible CD
output and the OSD (user), FTP round trip, A/UX (Dani).  The MiSTer runs Main
`MiSTer.bak_pre_fujinet` (d5b50fc4, Quadra + printer); the FujiNet Main is
kept as `MiSTer.fujinet-20260925`.  The guest is at the safe screen.  Details:
`docs/TIMING_CLOSURE_20260925_B.md`, `docs/perf/fullfeature_clean_20260925/`.
Everything below is the earlier checkpoint.

## Current state — authoritative checkpoint

User requested a crash-safe checkpoint because credits are nearly exhausted.
Branch: `add-ethernet`. Latest code change: `a75b300`; progress through
`0995724` was pushed before this documentation checkpoint. No new full fit is
running. The latest three full fits all failed routing; **no new RBF or timing
pass exists**. Do not deploy the stale `output_files/MacQuadra800.rbf` as new.

The isolated CPU-only one-hot-row map completed in its separate scratch project:

- Candidate: `scratch/brf_row_onehot_20260925/ap040_core.v`.
- SHA256: `a54b34f16b92c092d6243b5db2d26e8201d8c4ab43d14fceacf34d8bf81e7443`.
- Project: `scratch/cpu_area/p_brf_row_onehot_0995724_20260925/`.
- Snapshot: `scratch/cpu_area/snap_brf_row_onehot_20260925/`.
- Map result: **25,574 ALMs / 8,966 registers**, +164 ALMs versus the
  25,410-ALM X-BRF comparison. This is an area regression and the candidate is
  rejected; no full fit was started.
- Logs/reports: `scratch/cpu_area/p_brf_row_onehot_0995724_20260925/map.log`,
  `cpu.map.rpt`, `cpu.map.summary`, and `scratch/cpu_area/results.txt`.
- Candidate/snapshot hash and launch command are recorded in
  `scratch/brf_row_onehot_20260925/MAP_STATUS.md`.
- Luna `alu_rotate_sharing` owns mapping; `interim_validation` owns its tests.
  Do not blindly kill a process or assume the PID still identifies this job.

Production source currently contains the **X-default BRF address CPU** plus
**SDRAM ready bits**. Neither combination has routed successfully. No hardware
change occurred during this timing task. No PR for these timing experiments
has been created: the user's gate is **create it once timing passes**.

## User authorization and operating rules

- Continue timing closure with all Mac features; then create a new PR to Dani.
- Commit and push progress to `origin/add-ethernet`.
- Use Luna for builds, simulations and hardware operations. User specifically
  requested parallel Luna disk profiling; that work is now complete.
- Independent Quartus projects may run concurrently in separate directories.
  Never share a build DB, blindly kill Quartus, or use git worktrees.
- During a full fit, freeze **all tracked** HDL/QSF/QIP/SDC/Tcl inputs, including
  test fixtures: `scripts/cpu/fit_dev.sh` manifests all of them. Docs/Python/sh
  edits are safe. Wait for wrapper and post-fit reports before changing inputs.
- Read CLAUDE.md and BUILD.md. Old Windows/address/default-cache details are
  stale; current user instructions and this checkpoint take precedence.
- Local sandbox execution previously failed with bwrap; commands used
  `sandbox_permissions=require_escalated` with specific justifications.
- Physical CD-audio listening and OSD checks are explicitly deferred by user.
  A/UX is unavailable and deferred to Dani. Do not ask about them again.

## Repository and PR boundary

Existing PR: https://github.com/danifunker/MacQuadra800_MiSTer/pull/6
It is ready for review, not merged at last check. Its branch
`alanswx:cpu-full-feature-interim-20260925` is **frozen** at
`165e2a72da8c3d2c4827ec2ddf46c3650b081e64`. Do not push experiments there.
Refresh upstream/main and PR state before creating the later timing PR; if #6
is still unmerged, explicitly explain overlap/dependency.

Leave these unrelated untracked files alone:
`cr_ie_info.json`, `docs/disk-speed-vs-minimig-ao486.md`,
`docs/scsi-ddr3-disk-plan.md`, `worst_detail.txt`, `worst_paths.txt`.
The root worst-path reports are from an older different build; they are NOT
the installed artifact's timing evidence. Old untracked disk plans also contain
stale cache assumptions; do not adopt their redesign conclusions blindly.

## Installed, tested baseline

- Built source: `15a14497817ad8479bad91bf47d97e2163124d63`; inputs match
  baseline `165e2a7`.
- RBF: `test-builds/MacQuadra800_interim_20260925_15a1449.rbf`.
- SHA256: `4687167a16beb4077b970bf1cb46f0ba08a2fac724d2367f5d91e1390045da6c`.
- Installed at `/media/fat/_Unstable/MacQuadra800.rbf`.
- Correct archive: `scratch/interim_mac_wqmlab_fit_20260924/`.
- Fitted required ALMs 40,651; placed 40,489; LABs 4,182/4,191; M10K 509/553.
- Setup CPU **−2.406 ns**, SDRAM **−0.697 ns**, HDMI **−0.426 ns**.
  Holds positive, minimum +0.200 ns. Full map estimate 38,816 ALMs.
- CPU path: `cpu_timing/worst_detail.txt` inside that archive,
  `ifr_addr[16] → epf_data[6][0]`, 28 levels, 71% routing, through MMU/cache
  acknowledgement and refill address/row selection.
- RAM detail: `scratch/timequest_wq_interim_mac_wqmlab/ram_domain_worst_setup.rpt`,
  worst `bank_age[0][1] → chip`. Older five-bit age-shift design failed routing;
  do not repeat it without new evidence.
- Normal Ethernet/CD-ROM/CD-audio/video/OSD paths enabled. I/D caches 8 KiB;
  hard-disk cache 32 sectors with aligned 8-sector groups; CD bypasses cache.
- Seed 21; CPU 33 MHz, SDRAM 99 MHz. Do not relax clocks or false-path
  functional paths to manufacture a pass.

Speedometer CPU mix five-run median **1.828** (fresh single 1.816), versus real
Quadra reference **1.897**. FPU average .681 versus real 1.011. Earlier Disk
rating .565 versus real 3.443; new repeated Disk+Math runs .589/.585.
These ratings are not MB/s. Comparison and photos:
`docs/perf/INTERIM_VS_REAL_QUADRA800_20260925.md`,
`docs/perf/real_quadra800.jpg`, `docs/perf/speedometerrealquadra.png`.

## Hardware state

Only `mister.local` / **10.3.89.233** is authorized. Never stale .143/.92.
Only mounted disposable HDA:
`/media/fat/games/MacQuadra800/QuadSquad8-pipeline-test-20260919.hda`.
Protect original `QuadSquad8.hda`. Last observed guest: Speedometer completion
modal on original tested core after Disk+Math; **not shut down**. Look first
before interacting. Prefer normal shutdown before deploying the eventual core.
No Main restart/replacement, mounted-image hashing, or original-disk writes.

Main PID at profiling:31518, start ticks12925872; FD5 identifies disposable HDA.
Main binary SHA256:
`6db4851b939dbef32297c3fcce47d37531daddf5214e9a28a54412afd6586fd0`.
Exact matching source revision unknown. Empty CD slot4 was restored earlier;
no CD changes in this task. Physical audio/OSD and A/UX remain deferred.
Baseline hardware passed boot/shutdown/input/clocks, Ethernet ping/FTP hash,
CD data and CD-audio transport controls; see prior handoff for evidence.

## Timing experiments and evidence

| Candidate | Isolated CPU ALMs | Full map ALMs | Full outcome |
|---|---:|---:|---|
| Tested baseline | 25,514 | 38,816 | Routed; timing failures above |
| Early duplicated dgo payload, `6bd3c33` | 25,955 | 39,075 | Routing congestion |
| Address-only carrier + SDRAM ready, `aff6dfd` | 25,463 | 38,640 | Routing congestion |
| X-default carrier + SDRAM ready, `8cbbe45` | 25,410 | 38,824 | Routing congestion |
| X-default + mgo address-X (scratch) | 25,486 | — | Rejected area growth |
| X-default + one-hot row (scratch) | 25,574 | — | Rejected: +164 ALMs vs X-default base |

Full archives:
- `scratch/brf_dgo_seed21_20260925_fit_20260925/`: first larger candidate,
  required40,865 ALMs, placed39,438, LAB4,178; failed after16m31 overall.
- `scratch/brf_addr_tras_seed21_20260925_fit_20260925/`: required39,875,
  placed39,463, LAB4,190, regs28,006; final routing65.6% average/91.1% peak.
- `scratch/brf_dc_tras_seed21_20260925_fit_20260925/`: source8cbbe45,
  required40,009, placed39,555, LAB4,184, regs28,001; final routing58.9%/87.6%.
  Early47%/75% figures are estimates, not the final utilization.
All failed wrappers preserved reports, source-after checks passed, and STA
was correctly skipped on unrouted databases. All use509 M10Ks. Do not confuse
lower total ALMs with routability: nearly every LAB is occupied.

Current CPU SHA256:
`6dface16365ae0c0d820897ffb8dfcfd7ef9161a63f3ed64b273fb7933d47a0f`.
Only the unused per-edge `brf_seed_a` default becomes X; every consuming
request assigns a known address. It is not architectural state. Full strict
legacy replay and active pipeline tests pass. Active test checks15,045 requests /
119,313 seeded words, same phase cycles138988/161098/161098.

Current SDRAM SHA256:
`a7117892cc6b319f5ea3f7a03a91227ff2e63705381e38ee319536768146f7ae`.
Keeps numeric age counters and adds8 ready bits, invariant ready == age>=5.
Standalone622ALMs/966regs vs618/958, same488MLABbits. Passes87 invariant checks,
174 chip-model checks, registered-first-miss64reads+2048mixedops and line-DMA
20,512reads/5,381stores/11,423DMAbeats. No measured routed timing improvement.
Original SDRAM available via `git show 165e2a7:rtl/sdram.sv`, SHA256
`f4994aeb153e69c9fd5893acf75c0d5744424f7f23683f89b917f6d921a2e7e0`.

Detailed validation: `docs/TIMING_BRF_EARLY_20260925.md` and
`docs/TIMING_SDRAM_READY_20260925.md`.
Legacy test runner previously hid vvp failures through tee/grep. Commit501fbbe
fixes simulator status checks and has a7-case runner regression. **Only strict
replays are authoritative** for current/address-only CPU. Initial X test wrongly
required every program to seed BRF and failed zero-coverage LEA programs; those
masked logs are invalid. Corrected strict replay allows zero coverage but checks
every actual request. Addresses/log paths are in the validation document.

Other rejected/scratch alternatives:
- Opcode sharing25,782ALMs, greater than baseline; no full fit.
- mgo address-X SHA c66f58c9…: active65,370 memory-command checks passed, but
  +76ALMs; strict legacy was deliberately stopped and is **incomplete**, not PASS.
- Count-X (`brf_seed_n`) is not selected: decode_dbcc_brf_now reads it outside
  the request guard. Requires stronger same-stream/caller proof.
- One-hot row candidate preserves row arithmetic, rotation, count and write
  priority. Generic8,320-case equivalence and no-request hold with unknown address/count
  pass. Full regression is not run. Reconstructable patch is preserved at
  `scripts/cpu/refill_row_onehot.patch` against current CPU; do not apply it
  blindly or promote based on an unfinished map/test.

## Concrete next steps

1. Inspect active one-hot CPU map and validation results. If area grows, reject.
   If useful, finish active pipeline/strict CPU tests before promotion. Archive
   source hashes and results; no assertion is a substitute for a routed fit.
2. **Isolate CPU from SDRAM in the next full fit.** Restore only rtl/sdram.sv
   from165e2a7, retaining validated X-BRF CPU (or one-hot only if it earns
   promotion). Both latest failed fits combined CPU/SDRAM changes. This can
   establish routed CPU path evidence; original RAM timing may still fail.
   Do not claim this step closes all timing.
3. Commit exact inputs; confirm no same-project Quartus flow. Launch detached
   `bash scripts/cpu/fit_dev.sh <unique-tag>` with durable logs. The script
   archives identity, pre/post manifests and fresh reports. Use its
   `--allow-other-projects` only for separate authorized projects. Record launch
   source/tag/PID immediately. Freeze tracked HDL/config/fixtures until wrapper
   and post-fit reports end.
4. If routing fails again, use fit packing/congestion and independently screened
   area changes to select the next step. Avoid repeating rejected larger muxes
   or blind seed walks. If routed but timing fails, use **new** CPU/RAM/HDMI
   critical paths to choose a targeted change; do not extrapolate old paths.
5. After routing, archive setup/hold for every clock, CPU↔RAM crossings and
   explicit worst CPU/RAM/HDMI path details. Also run corrected supplemental
   MLAB collector `scratch/timequest_wq_hierarchy_20260925.tcl` with a unique
   tag. Original `*sdram_beat32:sdr|wq_mem*` pattern missed the `altdpram:`
   hierarchy; corrected `|*wq_mem*` collects it. Do not change timing constraints.
6. Only after timing passes, coordinate MiSTer ownership, inspect/shut down guest,
   copy/hash/load exact fresh artifact, validate boot/peripherals and five CPU
   Speedometer runs against1.828 median. Preserve deferred physical checks.
7. Create new PR to Dani with exact source/artifact/timing/tests and limitations.
   Keep PR6 frozen. Then advance disk work below. No new PR yet.

## Disk profiling complete; ready for the next phase

Authoritative report: `docs/DISK_PROFILE_20260925.md`.
Raw counters, screenshots, live-device evidence and reproducible scripts:
`docs/perf/disk_profile_20260925/`. No profiling process remains active and no
host test file remains. Guest/core unchanged.

- Disk+Math ratings .589/.585. Second run's sampling was armed correctly;
  first run missed workload and is not attributable measurement evidence.
- Live HDA opened O_RDWR|O_SYNC; actual exFAT mount is sync/dirsync. Dropping
  O_SYNC alone would not remove synchronous mount behavior.
- During sampled run, device wrote4,596,736bytes in3,682 completed writes;
  Main write activity spanned roughly22seconds. Device and process totals are
  aggregate, not per-HDA latency or guest bandwidth. Physical reads stayed
  flat; cached reads remain possible. Exact running Main source is unknown.
- Exclusive temporary host-file test, same4MiB per size: 512B writes31.327s,
  4KiB3.636s, 16KiB1.426s. File and directory removed. One pass per size;
  strong batch-size effect, not proof of the guest bottleneck.
- Controlled existing-cache simulation with fixed4ms backend: eight sequential
  sectors at10/100µs post-write idle gaps became one8-sector request; at200µs/
  1ms became eight single-sector requests. FLUSH_IDLE4096 is122.88µs at bench
  clock33.333MHz. Request-start intervals include about23µs engine data phase;
  they are NOT idle-counter quiet intervals. Counts and written data checked.
  Fixed-latency/backpressure assumptions limit the conclusion; no real guest
  cadence was measured. Reproducer `profile_scsi_cache_gap.py` emits only
  ignored scratch HDL; checked and original raw logs are preserved.

After timing closure: measure real engine write/data completion cadence,
platform request LBA/count/ack, cache dirty/idle state or equivalent low-overhead
Main per-call sizes/durations. Use controlled guest read/write workloads with
known boundaries and cache conditions. Then test batching/coalescing within
existing transport/cache while preserving ordering, coherence and durability.
Do not jump to a DDR disk cache or change the timeout solely from this model.
Broader SDRAM/DDR/VRAM/ROM/L1 placement tradeoffs remain a later analysis;
no memory-layout change or disk fix has been implemented in this task.
