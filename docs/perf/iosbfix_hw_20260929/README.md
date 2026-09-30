# The IOSB interrupt fix on hardware: f9f6da6 at seed 31 (2026-09-29)

`f9f6da6` makes two changes in `rtl/iosb.sv`
(`docs/scsi-write-hang-20260928.md`):

- A VIA2 IFR write now carries the live 53C96 INT/DRQ levels and a same-clock
  ASC edge.
- The PDMA watchdog is frozen through the platform ack.

**Result:**

- **Fit:** the release recipe meets every clock. CPU is +0.864 ns.
- **Hang gate:** ten Finder duplicates of Photoshop 3.0.1 in a row
  completed, with **0 hangs**. A second boot of the same bitstream ran
  twenty more (section "Second session"): **30 of 30 clean, 0 hangs**.
- **Speed:** unchanged within run-to-run spread. PR Disk median 1.699, FPU
  0.955 / 0.960 / 0.981.
- **Idle and shutdown:** the 8.1 idle check passed, and Shut Down reached
  "It is now safe to switch off your Macintosh".

Nothing was committed. `rtl/` and the `.qsf` in the checkout were not
touched.

## Build

- **Tree:** `git archive f9f6da6` into
  `scratch/iosbfix_quartus_seed31_20260929/tree/`. The `.qsf` is identical
  to HEAD: seed 31, `PLACEMENT_EFFORT_MULTIPLIER 2.0`,
  `ROUTER_TIMING_OPTIMIZATION_LEVEL MAXIMUM`.
- **Input manifest:** 178 files, re-verified after the flow.
- **Launch:** `systemd-run --user --unit=iosbfix-seed31-20260929 --collect bash scripts/build_only.sh`,
  after two checks 60 s apart that found no `quartus_*` process on the host.
- **Run time:** 01:59:37 to 02:22:19 EDT. Analysis & Synthesis took 5m16s,
  the Fitter 16m39s, and the whole flow 22m21s.
- **Only one seed was needed.**

| | b7e88b81 (ad7a0d4, same recipe) | **f9f6da6 seed 31** |
|---|---:|---:|
| fitter | OK | OK (one 16684 congestion warning, routed) |
| ALMs | 39,191 (94 %) | **39,102 (93 %)** |
| registers | 24,675 | 24,660 |
| M10K | 468 / 553 | 468 / 553 |
| DSP | 36 | 36 |
| CPU `general[0]` setup | +0.103 | **+0.864** |
| RAM `general[1]` setup | +0.612 | **+0.409** |
| HDMI setup | +0.006 | **+0.110** |
| h2f_user0 setup | – | +2.633 |
| worst hold | +0.220 (HDMI) | **+0.250** (pllv); CPU +0.252, HDMI +0.256, RAM +0.448 |
| recovery / removal / min pulse | all positive | all positive (worst +0.505, CPU VCO pulse width) |
| crossings sys→RAM / RAM→sys | +1.432 / +0.586 | **+1.128 / +0.867** (`req_tgl→req_handoff`, `line_handoff→line_data`; 0 violated) |
| RAM Summary | 99 rows, 6 uninferred | 99 rows, **0 diff** against the P253 s21 reference; the same 6 uninferred (open_row, hparam, vparam, kbdFifo, m16buf, ras) |
| rbf | 4,463,260 B, md5 `b7e88b81` | **4,486,932 B**, md5 `dc281d649d54f1cbbddd4650423e204b`, sha256 `c12571b540f0f1c34165f608499c1d759f626b1b33f894f23c3190c64fed1273` |

SOF sha256: `d0258fc5252ccf1532085675260b685ee267a938990837863dde8cc855266607`.
Every setup, hold, recovery, removal and pulse-width slack in
`MacQuadra800.sta.summary` (in this directory, with `MacQuadra800.fit.summary`)
is positive.

**Worst paths:**

- **CPU:** `ap040_core|mem_addr_q[13]` → `epf_data[0][5]` at +0.864. The
  sys→RAM line hand-off comes next at +0.867.
- **HDMI:** `ascal|o_v_poly_t.r1[16]` → `o_v_poly_pix.r[7]` at +0.110.
- **RAM:** `sdram_beat32|rd_burst` → `sdram|SDRAM_A[12]` at +0.409.

The reports are in the tree's `p254_sta/` and `scratch/cross_*`.

This is a different placement from b7e88b81, even with the same seed and
settings: 89 fewer ALMs and a different rbf size. The CPU margin grew by
0.76 ns, and the RAM margin fell by 0.2 ns while staying positive.

## Hardware

### Box, deploy and guest

- **Box:** `10.3.164.251` (eth0). Main `75e00b65` (the tight-loop build) was
  running, checked through `/proc/PID/exe`. The `.92` box was not touched.
- **Before the deploy:** the core was at "It is now safe to switch off", and
  Main's `write_bytes` did not change over 5 s.
- **Rbf staging:**
  - The new rbf, `fit.summary` and `sta.summary` were copied into the
    checkout's `output_files/`.
  - The previous files (rbf md5 `b7e88b8163679a607680e2e80669f396`) are kept
    in `scratch/iosbfix_hw_20260929/prev_output_files/`.
- **Deploy:** `bash scripts/deploy_screenshot.sh` at 02:24 EDT with no
  override. It reported "Timing OK — worst slack +0.110 ns", verified md5
  `dc281d64` on the box, and loaded the core.
- **Disks:** slot 0 was the disposable
  `QuadSquad8-pipeline-test-20260919.hda`; `.s0` was already set and left
  intact. The master `QuadSquad8.hda` was not opened. Slot 4 held
  `Marathon CD.iso`, idle.
- **Config:** CFG byte 0 was `0x40` (32 MB, Ethernet On).
  Speedometer showed Physical RAM 32768K.
- **Boot:** the Finder desktop came up by 95 s, first try, with no bomb.
  The volume had 1 GB free, far above the 60 MB floor.

### Hang gate: ten Finder duplicates in a row

**Recipe:** `ps_open.sh` (close the window, open the Photoshop alias, then
Cmd-R to select the original), then `p_dup.sh run 1..10`. Each copy is a
Cmd-D, timed from the keypress to the sampler window that holds the copy's
last `write()` (`analyze.py`). Completion is judged from Main's `wchar`
delta, which must be at least 3,958,000 B. The scripts are copies of
`scratch/disk_tightloop_20260928/` in `scratch/iosbfix_hw_20260929/scripts/`.

| copy | time (s) | kB/s | written (B) | read phase | write phase |
|---:|---:|---:|---:|---|---|
| 1 (cold) | 6.73 | 588 | 3,966,976 | 3.56 s, 1.28 MiB/s | 3.75 s, 1.01 MiB/s |
| 2 | 6.66 | 594 | 3,964,928 | 2.51 s, 1.63 | 3.73 s, 1.01 |
| 3 | 6.67 | 593 | 3,965,952 | 2.51 s, 1.64 | 3.74 s, 1.01 |
| 4 | 6.69 | 592 | 3,968,512 | 2.51 s, 1.63 | 3.76 s, 1.01 |
| 5 | 6.64 | 596 | 3,964,928 | 2.51 s, 1.65 | 3.75 s, 1.01 |
| 6 | 6.66 | 595 | 3,965,952 | 2.51 s, 1.65 | 3.74 s, 1.01 |
| 7 | 6.70 | 591 | 3,966,976 | 2.52 s, 1.64 | 3.99 s, 0.95 |
| 8 | 6.69 | 592 | 3,964,928 | 2.25 s, 1.82 | 4.00 s, 0.94 |
| 9 | 6.64 | 596 | 3,969,024 | 2.51 s, 1.65 | 3.98 s, 0.95 |
| 10 | 6.69 | 592 | 3,968,000 | 2.51 s, 1.63 | 3.74 s, 1.01 |
| **median** | **6.68** | 592 | | | |

- **All ten completed.** The folder went from 33 to 43 items
  (`dup10_after.png`).
- **Hangs: 0 of 10. Bombs: 0.** No reboot was needed.
- **Copy time is unchanged:** the production tight-loop run on `b7e88b81` had
  6.94 / 6.68 / 6.69 s.
- **Caveat on the evidence.** At the previous rate of about 1 hang in 10-20
  copies, a clean ten happens by chance 35-60 % of the time on the old RTL.
  Ten clean copies meets the agreed bar but is weak evidence on its own. The
  strong evidence is the sim: g14's deterministic reproduction completes on
  the fix, and the directed bench passes all 24 offsets. More copies on this
  bitstream would tighten the hardware bound: 30 clean copies would put the
  old rate below 5 % chance. The second session below brings the total to 30.

### Speedometer 4.02 (after the copies, Speedometer launched from its alias)

| PR run | CPU | Graphics | Disk | Math | PR |
|---:|---:|---:|---:|---:|---:|
| 1 | 0.896 | 1.165 | 1.699 | 21.464 | 1.210 |
| 2 | 0.896 | 1.166 | 1.697 | 21.405 | 1.211 |
| 3 | 0.895 | 1.167 | 1.708 | 21.448 | 1.211 |
| **median** | 0.896 | 1.166 | **1.699** | 21.448 | 1.211 |

The production reference (`b7e88b81` with the same Main,
`docs/perf/disk_tightloop_20260928/production.md`) had PR Disk 1.704 /
1.745 / 1.741, median 1.741, and PR 1.210 / 1.214.

- **PR Disk is 2.4 % under that median** but at the reference's own low run.
- **PR, CPU, Graphics and Math match.**
- **The copies, the more direct disk measure, are unchanged.**
- Nothing in the change touches a data path: the IFR write and the watchdog
  counter only. The likely difference is that the disk now holds more files.
  That is an inference, not measured.

| FPU run (Whet / Matrix / FFT, 1 iter.) | KWhet/s | Matrix s | FFT s | **Average** |
|---:|---:|---:|---:|---:|
| 1 | 4620.986 (0.887) | 0.691 (1.023) | 0.301 (0.955) | **0.955** |
| 2 | 4620.047 (0.887) | 0.726 (0.973) | 0.281 (1.020) | **0.960** |
| 3 | 4578.461 (0.879) | 0.682 (1.036) | 0.279 (1.028) | **0.981** |

- The brief asked for one run. Run 1 came out low (FFT 0.301 s), so two
  more were made.
- The ramp repeats the first runs on the marginal P258 build: 0.951 / 0.965
  / 0.978, then 0.982, both run after PR.
- The warm run, 0.981, is in the b7e88b81 range (0.972-0.978, median 0.973).
- All runs were valid. The values were read from enlarged crops
  (`fpu*_done_crop.png`, `pr*_done_crop.png`).

### Idle check and shutdown

- **Speedometer quit:** Return, Cmd-Q, then "No" to the Machine Record save,
  with the pointer checked on the button first.
- **Idle:** the Finder then idled with no input from 06:47:15 to 06:51:34
  UTC by the MiSTer's clock.
  - The menu-bar clock read Tue 6:47, then 6:49, then 6:51, in step with the
    MiSTer.
  - Screenshot artefact: the scaled screenshot drops a pixel column of the
    clock font, so a 9 looks like a 5 and a 0 like a C. 6:49 reads "6:45",
    and 6:39 on `pr1_done` reads "6:35". The 2026-09-28 production
    screenshot has the same artefact: 2:59 reads "2:55".
  - Main's `write_bytes` rose 62,246,912 → 62,427,136: idle housekeeping
    only.
  - After the idle, type-select "tra" highlighted the Trash, so the keyboard
    responded.
- **Shut Down:** the vmouse Special-menu recipe (`shutdown.sh`, with an
  explicit button-up at the end) reached "It is now safe to switch off your
  Macintosh" (`halt.png`). After that, `write_bytes` did not change.

## Second session: twenty more duplicates (same rbf `dc281d64`)

- **Redeploy:** from the halt screen at 06:56 UTC, with Main's
  `write_bytes` flat over 5 s, `bash scripts/deploy_screenshot.sh` pushed the
  same rbf. It reported "Timing OK", verified md5 `dc281d64` on the box and
  loaded the core.
- **Boot:** the Finder came up by 95 s with no bomb (`boot2_95s.png`). The
  folder showed 43 items and 1 GB free.
- **Copies:** `ps_open.sh run2`, then `p_dup.sh run2 1..20` in four batches
  of five: the same scripts, timing and completion test as above.
- **Free space:** 991.3 MB after copy 10 and 953.5 MB after copy 20, far
  above the 100 MB stop line.

| copy | time (s) | kB/s | written (B) | read phase | write phase |
|---:|---:|---:|---:|---|---|
| 1 (cold) | 6.95 | 570 | 3,964,928 | 3.51 s, 1.30 MiB/s | 3.77 s, 1.00 MiB/s |
| 2 | 6.92 | 572 | 3,966,464 | 2.51 s, 1.65 | 4.00 s, 0.94 |
| 3 | 6.67 | 593 | 3,966,976 | 2.51 s, 1.65 | 3.74 s, 1.01 |
| 4 | 6.67 | 593 | 3,968,000 | 2.52 s, 1.65 | 3.74 s, 1.01 |
| 5 | 6.66 | 595 | 3,965,952 | 2.50 s, 1.65 | 3.98 s, 0.95 |
| 6 | 6.60 | 599 | 3,966,976 | 2.51 s, 1.65 | 3.73 s, 1.01 |
| 7 | 6.70 | 591 | 3,964,928 | 2.51 s, 1.65 | 3.74 s, 1.01 |
| 8 | 6.44 | 615 | 3,965,952 | 2.52 s, 1.64 | 3.75 s, 1.01 |
| 9 | 6.65 | 595 | 3,971,584 | 2.51 s, 1.65 | 3.74 s, 1.01 |
| 10 | 6.64 | 597 | 3,964,928 | 2.51 s, 1.65 | 3.99 s, 0.95 |
| 11 | 6.68 | 593 | 3,965,952 | 2.50 s, 1.66 | 3.73 s, 1.01 |
| 12 | 6.68 | 593 | 3,966,976 | 2.51 s, 1.65 | 3.75 s, 1.01 |
| 13 | 6.71 | 590 | 3,964,928 | 2.53 s, 1.64 | 4.01 s, 0.94 |
| 14 | 6.67 | 594 | 3,968,512 | 2.52 s, 1.64 | 3.75 s, 1.01 |
| 15 | 6.92 | 572 | 3,968,512 | 2.50 s, 1.66 | 4.00 s, 0.94 |
| 16 | 6.66 | 594 | 3,964,928 | 2.50 s, 1.64 | 3.74 s, 1.01 |
| 17 | 6.69 | 592 | 3,965,952 | 2.51 s, 1.65 | 3.75 s, 1.01 |
| 18 | 6.70 | 591 | 3,966,976 | 2.51 s, 1.65 | 3.75 s, 1.01 |
| 19 | 6.68 | 593 | 3,967,488 | 2.51 s, 1.63 | 3.74 s, 1.01 |
| 20 | 6.69 | 592 | 3,965,952 | 2.53 s, 1.64 | 3.75 s, 1.01 |
| **median** | **6.68** | 593 | | min 6.44, max 6.95 | |

- **All twenty completed.** The folder went from 43 to 63 items
  (`run2_dup20_after.png`).
- **Hangs: 0 of 20. Bombs: 0.** No reboot was needed.
- **The median is the same 6.68 s as the first session.** The 6.9 s copies
  (1, 2, 15) carry one extra 0.25 s write-phase window, the same pattern as
  the first session's 3.98-4.00 s write phases.
- **Shut Down:** `shutdown.sh run2` reached "It is now safe to switch off
  your Macintosh" (`run2_halt.png`). After that, `write_bytes` was flat at
  90,017,792.

**Both sessions: 30 of 30 duplicates clean, 0 hangs.**

What that rules out:

- The old RTL hung in about 1 of 10-20 copies (1 in 8, then 2 in about 25,
  across the earlier sessions). At that rate it would have come through 30
  copies clean only 4 % of the time at 1 in 10, 11 % at 1 in 14, and 21 %
  at 1 in 20.
- Together with the sim (g14's deterministic stop completes on the fix) and
  the directed bench (all 24 offsets pass), the hang is fixed with good
  confidence.

## Box state at the end

- Guest halted at "safe to switch off" (07:19:50 UTC). The core
  `MacQuadra800` is running from `_Unstable/MacQuadra800.rbf`, md5
  `dc281d64`.
- Main `75e00b65`. MiSTer uptime 4:27; no reboot was needed in either
  session.
- `.s0` is still the disposable disk. It now holds thirty more Photoshop
  copies: 63 items in the folder, 953.5 MB free. Nothing was deleted.
- CFG byte 0 is `0x40`. `/media/fat` is 99 % full, with 2.9 GB free.
- The checkout's `output_files/` holds this build: rbf `dc281d64`, plus its
  fit and sta summaries.

## `.qsf` seed-history line (ready to paste above `set_global_assignment -name SEED 31`)

```
# 2026-09-29: + the IOSB interrupt fix (f9f6da6: VIA2 IFR write keeps the live 53C96 INT/DRQ and a same-clock ASC edge;
# PDMA watchdog frozen through the ack).  Seed 31, same recipe, MET: CPU +0.864, SDRAM +0.409, HDMI +0.110, hold +0.250,
# crossings +1.128/+0.867, 39,102 ALMs (93 %), 468 M10K, 36 DSP, fitter 16m39s, RBF md5 dc281d64.  Hardware: 10/10 Finder
# duplicates + 20/20 on a second boot, 0 hangs (docs/perf/iosbfix_hw_20260929).  SEED 31 kept.
```

## Files

- `scratch/iosbfix_quartus_seed31_20260929/`: the tree, build logs,
  manifest, pre-launch check and STA outputs.
- `scratch/iosbfix_hw_20260929/`:
  - `scripts/`, `deploy.log`;
  - `run/`: every screenshot, the `dup*_arm.txt` samplers, `log.txt`;
  - `run2/`, `deploy2.log`, `boot2_95s.png`: the second session;
  - `prev_output_files/`.
