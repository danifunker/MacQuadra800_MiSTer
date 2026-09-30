# SCSI block cache back on: fits of the release RTL (2026-09-28/29)

These fits test whether the current release RTL still fits with the SCSI block
cache (`rtl/scsi_cache.sv`) turned back on, using the new fitter recipe
(`PLACEMENT_EFFORT_MULTIPLIER 2.0`, `ROUTER_TIMING_OPTIMIZATION_LEVEL MAXIMUM`,
`docs/perf/fpu_p258_fitter_settings/`). With `SCSI_CACHE_OFF`, the disk path
makes one Main round trip per 512-byte block (`docs/disk-main-path-20260928.md`).
The cache groups requests into 4 KB transfers with prefetch and write-behind.

**Result: no build met every clock.** Four builds were run, in the briefed
order:

- small@31 did not finish routing. It was stopped after 2 h 11 min in the
  router.
- tiny@31 failed routing.
- small@22 failed routing.
- small@21 routed but missed two clocks. The CPU clock missed by −0.089 ns
  (2 failing endpoints, TNS −0.125) and HDMI by −0.342 ns (TNS −3.274).

The CPU miss comes from a congestion detour. The worst path has one 10.2 ns
interconnect hop. The small@21 rbf is a timing-violated build. It is not a
release candidate. At most it could be a hardware trial with
`ALLOW_TIMING_VIOLATION=1`.

Nothing was deployed or committed. The main checkout's `.qsf` and `rtl/` were
not changed.

## Recipe

For each build, `git archive HEAD` was unpacked into
`scratch/disk_cacheon_<variant>_seed<N>_20260928/tree/`, with
`scripts/local.env` copied in at mode 0600. Only `MacQuadra800.qsf` was edited
(`qsf.diff` in each build dir).

HEAD moved during the run because another session made docs and release-note
commits:

| build | exported from |
|---|---|
| small@31 | `be71452` |
| tiny@31 | `ca328ad` |
| small@22, small@21 | `a18ab44` |

`git diff be71452 a18ab44` is empty for `rtl/`, `sys/`, the `.qsf`, `.qpf`,
`.sdc`, `.srf`, `MacQuadra800.sv` and `files.qip`. Every build's 178-file input
manifest also matches, apart from the edited `.qsf`. So all four builds come
from the same RTL and the same base `.qsf` (the release recipe).

The builds ran one at a time. Each ran as `systemd-run --user
--unit=disk-cacheon-<variant><N>-20260928 --collect bash scripts/build_only.sh`,
so the normal wait gate applied. Before each launch the launcher checked twice,
60 s apart, that the host had no `quartus_*` process. Each check found 0
(`prelaunch_check.txt`). After each launch, the cwd of the running `quartus_*`
processes was checked, and each was the build's own tree.

Tools are in `scratch/disk_cacheon_tools/` (`setup.sh <small|tiny> <N>`,
`launch_when_free.sh`, `sta.sh`, `extract.sh`). They are adapted from
`scratch/fpu_p258_fit_tools/`. `extract.sh` compares the RAM Summary against
B31, the cache-off release fit (`scratch/fpu_p258_fit_effort_seed31_20260928`).

`CACHE_TINY` takes precedence: `rtl/quadra800.sv` tests `` `ifdef CACHE_TINY ``
before `` `elsif CACHE_SMALL ``. The tiny variant still replaced the line, as
briefed.

### `.qsf` lines changed

Both variants, line 558:

```
< set_global_assignment -name VERILOG_MACRO "SCSI_CACHE_OFF=1"
> #set_global_assignment -name VERILOG_MACRO "SCSI_CACHE_OFF=1"
```

The tiny variant also changes line 564:

```
< set_global_assignment -name VERILOG_MACRO "CACHE_SMALL=1"
> set_global_assignment -name VERILOG_MACRO "CACHE_TINY=1"
```

For small@22 and small@21, line 412 also changes: `SEED 31` becomes `SEED 22`
or `SEED 21`. `CACHE_CD_OFF=1` and the fitter settings were left as they are.

## Results

| build | fit (fitter / whole flow) | ALMs | regs | M10K | DSP | CPU `general[0]` | RAM `general[1]` | HDMI | worst hold | sys→RAM / RAM→sys | RAM Summary | rbf |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|---|
| B31 cache off (reference, release) | 13m14s / 19m00s | 39,191 (94 %) | 24,675 | 468 | 36 | +0.103 | +0.612 | +0.006 | +0.220 | +1.432 / +0.586 | 99 rows | md5 `b7e88b81` |
| small@31 | **stopped in the router** after 2h11m (placement 1m41s; previous P258 fits routed in 3m30s–8m56s) | – (25,345 regs at synthesis) | – | 508 expected (same memory bits as small@22/21) | 36 | – | – | – | – | – | 100 rows; +1 row, the cache RAM 20480×16 | none |
| tiny@31 | **router failed** (188026/170143/11802, congestion warning 16684; routing 52m32s; fitter 79m46s / 88m48s) | 39,766 (95 %) placed | 24,707 | 492 | 36 | – | – | – | – | – | 100 rows; +1 row, the cache RAM 12288×16 | none |
| small@22 | **router failed** (188026/170143/11802; routing 5m33s; fitter 15m58s / 22m36s) | 39,823 (95 %) placed | 24,785 | 508 | 36 | – | – | – | – | – | 100 rows; +1 row, the cache RAM 20480×16 | none |
| **small@21** | routed (routing 21m10s; fitter 29m17s / 35m46s) | 39,862 (95 %) | 25,267 | 508 | 36 | **−0.089** (TNS −0.125, 2 failing) | +0.441 | **−0.342** (TNS −3.274) | +0.148 (CPU) | +1.189 / +0.430 | 100 rows; +1 row, the cache RAM 20480×16 | 4,572,400 B, sha256 `401f3f7b855d57ccc999f5cc004ff19f04e2a01dc81a2d4bbc25bcfb87743487`, md5 `bd9afd35e6d27e815fc346fba41754e8` (timing-violated) |

The small@21 SOF sha256 is
`b4b337eba47e9d72a277c153c4460ff3e4096c5885d89ef75b364b601a171c82`.

At small@21, every recovery, removal, hold and minimum-pulse-width slack is
positive. Only the CPU and HDMI setup slacks are negative. The cross-domain
reports (`timequest_cross_domain.tcl`) have no negative path. The worst
paths are:

- sys→RAM: +1.189, from `sdram_beat32|req_tgl` to `req_handoff`.
- RAM→sys: +0.430, from `data_handoff[9]` to `rdata[9]`.

**RAM Summary check.** Each of the four `.map.rpt`s differs from the B31
cache-off reference by exactly one added row. That row is
`quadra800:machine|scsi_cache:scsi_cache|altsyncram:ram`, a True Dual Port
M10K:

- small: 20480×16, which is 40 M10K (468 → 508).
- tiny: 12288×16, which is 24 M10K (468 → 492).

The 6 "uninferred RAM" notes are unchanged: open_row, hparam, vparam, kbdFifo,
m16buf and ras. No array fell out to registers. The normalised summaries are
`ram_summary_norm.txt` in each build dir.

**Area.** With the cache on, the design uses about 575–670 more ALMs than B31
(39,766–39,862 against 39,191). That is more than the ~437 ALMs that
`docs/AREA_BUDGET_20260924.md` gives for the cache. The chip moves from 94 % to
95 %. The router's estimated interconnect use rises from 46 % average / 72 %
peak (B31) to 48–50 % / 75–78 %.

### small@21: top 5 CPU endpoints

The paths are in `wombat_cpu:cpu`.

| slack | from | to |
|---:|---|---|
| −0.089 | `ap040_core|ir[1]` | `ap040_mmu|hq_ok` |
| −0.036 | `pres_v` | `ap040_core|p_dreg[1]` |
| +0.168 | `ap040_core|ir[1]` | `ap040_mmu|hq_wok` |
| +0.367 | `pres_v` | `ap040_core|ifr_addr[8]` |
| +0.430 | `sdram_beat32|data_handoff[9]` | `sdram_beat32|rdata[9]` (RAM→sys crossing) |

The worst path starts at `ir[1]` (fan-out 74) and passes through
`Equal192~0`, `comb~13/14`, `mem_hint_addr[20:12]`, MMU `hn_set[0]` (48),
`Mux77`, `uh_hit` (23) and `hq_ok`. One interconnect hop, `Equal192~0` →
`comb~13` (X27_Y22 → X28_Y11), takes **10.208 ns**. That is a congestion
detour and not logic depth. This is not the `ifr_addr → epf_data` loop that
limited B31. The block cache is not on this path. Its extra ALMs change the
placement and push the routing into congestion.

HDMI worst: `ascal|o_vcpt_pre3[4]` → `o_vcpt_pre3[8]`/`[10]` (−0.342). RAM
worst: `a_ram[23]~DUPLICATE` → `sdram|command[2]` (+0.441).

## Reading

- With the new fitter recipe, the cache-on design routes at only one seed in
  three for small (31 did not converge, 22 failed, 21 routed). tiny@31 failed
  too, although tiny uses fewer ALMs and M10K. Going to 95 % ALMs puts the
  router over the edge. The M10K budget is not the problem: 45 blocks remain
  free with small, and M10K was never the limit.
- small@21 misses by very little on the CPU clock (−0.089 ns, 2 endpoints),
  and the cause is congested routing. Two cheap next steps are more seeds for
  small (seeds 21 and 22 were tried) and trimming about 500 ALMs elsewhere to
  get back to the 94 % where B31 routed. The trim could be `CACHE_CD_OFF`,
  which is already set, `VIDEO_512_OFF`, which is already set, or a
  CPU-experimental macro. By the release bar, small@21 is not clean. The
  −0.089 CPU miss is the kind that CLAUDE.md warns can corrupt memory
  silently.
- The small@21 rbf could be used only for a disk-throughput hardware trial
  with `ALLOW_TIMING_VIOLATION=1`. It is not a shippable build.

## Paths

- Build dirs: `scratch/disk_cacheon_{small_seed31,tiny_seed31,small_seed22,small_seed21}_20260928/`.
  Each has `COMMIT.txt`, `qsf.diff`, `input_manifest.sha256`,
  `prelaunch_check.txt`, `build_start.txt`, `build_done.txt`,
  `build_stdout.log` and `ram_summary_norm.txt`. small@31 also has
  `stopped.txt`.
- small@21 rbf: `scratch/disk_cacheon_small_seed21_20260928/tree/output_files/MacQuadra800.rbf`.
  It is timing-violated.
- small@21 STA: `tree/p254_sta/`, and the crossings are in
  `tree/scratch/cross_{sys2ram,ram2sys}_disk_cacheon_small_seed21_20260928.txt`.
- Tools: `scratch/disk_cacheon_tools/`.

## Ready-to-paste `.qsf` comment block

This goes after the 2026-09-28 fitter-settings block, above
`set_global_assignment -name SEED 31`:

```
# 2026-09-28: SCSI block cache back on (SCSI_CACHE_OFF commented out; CACHE_CD_OFF kept) on the
# release RTL + recipe (docs/perf/disk_cacheon_builds_20260928).  CACHE_SMALL: seed 31 router did
# not converge (stopped after 2h11m), 22 router failed, 21 routed but CPU -0.089 (ir[1] -> MMU
# hq_ok, one 10.2 ns congested hop) / HDMI -0.342, SDRAM +0.441, hold +0.148, crossings
# +1.189/+0.430, 39,862 ALMs (95 %), 508 M10K, RBF md5 bd9afd35.  CACHE_TINY seed 31 router failed
# (39,766 ALMs, 492 M10K).  The cache costs ~600 ALMs here and tips the router; SCSI_CACHE_OFF kept.
```
