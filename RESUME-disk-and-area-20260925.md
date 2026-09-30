# Resume here: disk speed, the SCSI cache and room for the pipeline (2026-09-25 night)

Supersedes the top of `RESUME-timing-closure-20260925.md` for everything after
PR #7.  Branch `add-ethernet`.

## Where things stand

| thing | state |
|---|---|
| **Timing-clean full-feature core** | `a0b3072`: pipeline out, SCSI cache on, 8+8 KB CPU caches.  CPU +0.007 / SDRAM +0.082 / HDMI +0.044 ns.  Mix median 1.670.  **PR #7** to danifunker/MacQuadra800_MiSTer (open).  RBF `test-builds/MacQuadra800_fullfeature_timingclean_20260925_a0b3072.rbf` |
| **Better candidate (not yet in the qsf)** | the same plus `SCSI_CACHE_OFF=1`, CPU caches 16+16 KB (`SETW = 8`), seed 23 (recipe: `docs/perf/cacheoff_s23_20260925/build/recipe.diff`).  37,532 ALMs, 485 M10K, **CPU +0.360 / HDMI +0.290 / SDRAM +0.583 ns**, every hold/recovery/crossing met.  **Mix median 1.684, Disk 1.604.**  RBF `test-builds/MacQuadra800_cacheoff_c16_s23_20260925.rbf` (md5 cdd92e98).  **Needs the write-buffer Main**; with an old Main the cache must stay on |
| **Main write buffer** | `alanswx/Main_MiSTer` branch **`mac-disk-writebuffer-min`**: one commit (`b0248f8`) on MiSTer-devel `master` (`aa271e4`, which already has the Mac Ethernet/SCSI/Quadra work, #1321).  3 files, +160 lines.  Branch `mac-disk-writebuffer` = the same on `alan/master` plus printer support and the opt-in disk trace |
| **Disk measurements** | `docs/DISK_TRACE_20260925.md` (everything: the trace method, the bottleneck, the buffer, the A/B, integrity, cache-off) |

Disk results on the same core (`a0b3072`), only Main changed: Speedometer
PR Disk **0.568 -> 1.758**; a 2.8 MB Finder copy's write phase 11 s -> 3.3 s.
Copies were verified byte-identical offline (machfs; `hfs_compare.py`).

## The MiSTer (10.3.89.233)

- Main: **write-buffer build `3dd49cd2`** (Quadra + printer + opt-in trace).
  Also on the box: `MiSTer.bak_pre_fujinet` (d5b50fc4, Quadra + printer, the
  previous one), `MiSTer.fujinet-20260925` (FujiNet, **no Quadra support**:
  every Quadra core stays black with it), `MiSTer.disktrace`,
  `MiSTer.writebuffer`.
- Core loaded: `_Unstable/MacQuadra800_cacheoff_s23.rbf`, guest in
  Speedometer at the Performance Rating result.  Shut it down (Speedometer:
  Cmd-Q, click No at about (263,215) with vmouse `home m:162,129`, then the
  Finder Special -> Shut Down vmouse recipe) before loading anything.
- `_Unstable/MacQuadra800.rbf` is the `a0b3072` timing-clean build.
- Disk trace: `touch /tmp/mac_disk_trace` on the MiSTer, run the workload,
  `rm` it, and read `/tmp/mac_disk_trace.csv`.  Summarize it with
  `docs/perf/disk_trace_20260925/analyze.py`.
- Driving the guest: keys with `scripts/mister_ws.py`; the mouse only with
  `ssh ... python3 /media/fat/Scripts/q800tools/vmouse.py` (about 1.6 px per
  unit; `home` pins the top-left corner).  Speedometer: Cmd-B = Benchmark
  Mix, Cmd-R = Performance Rating (then Return, and Return at the drive
  chooser).
- Do not use kernel uprobes on libc here: glibc is Thumb code and a probe
  on `lseek64` broke `lseek` system-wide (see the trace doc).

## Room for the pipeline (1.67 -> ~1.83)

The pipeline costs about 1,700 ALMs (CPU-only synthesis).  Fits so far:

| fit | recipe | ALMs | result |
|---|---|---|---|
| A (morning) | pipeline + SCSI cache | 39,626 (95 %) | routed after 2 h, CPU −2.76 ns |
| P1 | pipeline + cache off, 8 KB | 39,323 (94 %) | **router fails** |
| P2 s21 | P1 + the three release-lite framework trims (`MISTER_BYPASS_AUDIO_FILTER`, `MISTER_DISABLE_VIDEO_CALC`, `VIDEO_512_OFF`; map 38,139 -> 37,113) | 38,375 (92 %) | **routes**; CPU −2.499, HDMI −0.171, SDRAM +0.359 |
| P2 s23 | same | 38,393 | router fails |
| P3 s21 | P2 without PIPELINE_LOADS/STORES | 38,022 | routes; CPU −7.293 (a bad draw) |
| P4 s21 | P2 + the read acknowledge that ignores `buffer_req` (`wombat_store_buffer.sv`, logically equivalent) | 38,346 | routes; CPU −2.545, HDMI −0.078, SDRAM +0.619 |
| P4 s23 | same | 38,341 | router fails |

**Area is solved:** with the SCSI cache off and the three framework trims,
the pipeline build routes at 91-92 %, where the timing-clean builds sit.
**Timing is not:** the CPU clock misses by ~2.5 ns.

- In P2 the worst path ran from `ifr_addr` through the MMU translation copy
  (`u_hit`), the cache, the store buffer's `buffer_req` (the RAM/VRAM window
  decode), `ifr_ack`, and the core's issue logic to `mem_addr_q`.
- P4's read-acknowledge change takes `buffer_req` off every read path.
  `tb_store_buffer` gives identical results with and without it (the same
  pre-existing T4 failures on HEAD); the memory-path and line-DMA benches pass.
  That family is gone from P4's report.
- The new worst family starts at the cache tag RAM: the one-clock hit, then
  `c_rdata`, the ALU, the flags, the next-instruction decision, and finally
  `rr_b` and `epf_data`.  It is the family P241/P242 shortened (at 2-28 %
  kernel cost).

**P243/P244 (the CPU fixes, 2026-09-25 night)** -- diffs in
`docs/perf/pipeline_p243_p244/`:

- **P243:** the lookahead Bcc's producer flags come from a small dedicated
  fast-flag unit whose operands never include this cycle's memory data.  An
  ALU op retiring on an S_MRD memory operand, or a pipeline fast read retire,
  resolves its Bcc in S_DECODE instead.  The pipeline's branch flags use only
  its registered WB copy.
- **P244:** CAS/CAS2 decide "equal" from their registered operands, not the
  ALU's fast flags.
- **Checks:** CPU self-tests pass, and `t_cas_lifo` passes with results
  identical to HEAD.  All fixture oracles pass (MEMSUM, memchecks).
- **Cycle cost:** Puzzle +7.1 %, Quick +8.2 %, Bubble +8.4 %, Queens +6.4 %,
  Dhrystone +3.0 %, Sieve +2.8 %, others within 0.6 % (P244 adds nothing).
  That is about −3.7 % against the pipeline's ~+9.5 %.

| fit | recipe | ALMs | CPU | HDMI | SDRAM |
|---|---|---|---|---|---|
| P5 s21 | P4 + P243 | 38,386 | −0.845 | −0.091 | +0.783 |
| P6 s21 | P4 + P243 + P244 | | **+0.224** | −0.091 | −0.010 |
| P6 s23 | same | | **+0.483** | −0.143 (ascal `o_vcpt_pre3`) | +0.427 |
| P6 s22, s24-26 | same | | running | | |

The CPU clock passes with the pipeline in; what remains is the framework
scaler's HDMI counter, which depends on the seed.  A full-machine boot sim of
the P244 core with the pipeline and cache-off macros is in `scratch/sim_p6`.

Ways forward (before P243): shorten that family at a measured cycle cost (the pipeline is
worth ~10 %, a cut that costs 2-3 % would still net ~1.78); more seeds (the
spread is wide, −2.5 to −7.3 plus router failures); or the disk-target
commands to Main for more slack.  The P4 read-ack change is worth keeping in
any build.  Scratch projects: `scratch/fitP2_s21`, `fitP4_s21`
(`cpu_paths40.txt`, `cpu_top300.txt` in each).
