# P263 release bitstream on hardware: 6ce38c8 at seed 24, Mac OS 8.1 gate (2026-09-30)

This is the Mac OS 8.1 half of the release gate for the **shipped** P263 bitstream: `6ce38c8` at
seed 24, the clean fit. It is the same RTL as the seed 23 trial an hour earlier
(`docs/perf/p263_hw_20260930`), and it was run with that session's recipe and scripts.

**Verdict: the Mac OS 8.1 gate passes on the seed 24 release rbf.**

- **Stability:** 0 hangs, 0 bombs, 0 black screens, 0 MiSTer reboots.
- **Performance** matches seed 23 and P260 `f769b9e1` within run-to-run spread.
  - PR Disk is back at the P260 level (median 2.488).
  - The warm FPU runs came in at 0.961 and 0.968, against 0.975 expected. Only Matrix Multiply
    varies, which is the known run-to-run spread (see section 2).
- **Features:** Scale, 512x384 and back, ImageWriter printing at 9600, idle clock, keyboard and
  Shut Down all work, and the halt-screen glyphs are intact after both OSD resets.
- **One setup caveat for printing:** the ImageWriter's port was back on the **Printer port** after
  the core load, as it was at seed 23. The first job therefore went to the unconnected port with no
  bytes and no alert. After Modem Port was chosen in the Chooser, the job printed normally (section 5).
- **Still open:**
  - the HDMI output itself has to be looked at on the display;
  - the A/UX and CD-audio halves of the release gate were not part of this session.

| | **seed 24 `49951492`** (this) | seed 23 `920ffa2a` | P260 `f769b9e1` |
|---|---:|---:|---:|
| PR (median of 5) | **1.267** | 1.263 | 1.266 |
| CPU / Graphics / Math (medians) | **0.896 / 1.166 / 21.451** | 0.896 / 1.161 / 21.476 | 0.896 / 1.167 / 21.457 |
| PR Disk (median of 5) | **2.488** (2.467-2.499) | 2.414 (2.377-2.484) | 2.462 (2.447-2.532) |
| FPU Benchmarks cold | **0.953** | 0.939 | 0.951 |
| FPU Benchmarks warm (after the Mix) | **0.961**, extra run 0.968 | 0.975 | 0.976 |
| Benchmark Mix | **1.808** | 1.802 | 1.807 |
| Photoshop duplicate, median of 10 | **5.24 s** (4.98-5.27) | 5.11 s (4.95-5.25) | 4.95 s |
| hangs / bombs | **0 / 0** (10 copies) | 0 / 0 (10 copies) | 0 / 30 copies |

The operator did not load or deploy anything; the coordinator loaded the rbf. Nothing was
committed, and `rtl/` and the `.qsf` were not touched. The master `QuadSquad8.hda` was not touched
(mtime still 2026-09-19 16:22:36).

## Build and box

- **Build:** `6ce38c8` (P263) at **seed 24**, the `.qsf` release recipe (the committed `SEED 24`, `b89ab9e`).
  - rbf md5 **`49951492d3576add9470bc1d1ef28e5d`**, checked on the box as `_Unstable/MacQuadra800.rbf`.
  - Fit: 39,300 ALMs (94 %), 24,668 registers, 468 / 553 M10K, 36 DSP.
  - Setup slack, **every clock met**:
    - CPU `general[0]` **+0.507**;
    - RAM `general[1]` **+0.834**;
    - HDMI **+0.310**;
    - h2f_user0 +3.465.
  - Hold worst +0.219 (HDMI). Crossings +1.201 / +0.507.
  - Summaries: `MacQuadra800_6ce38c8_seed24.{fit,sta}.summary`.
- **Box:** `10.3.164.251`. The `.92` box was not touched.
  - Main is `/proc/PID/exe` md5 `75e00b65`, the tight-loop build.
  - The coordinator's `load_core` ran at 06:14:54 UTC (Main's `/proc` entry time).
- **Guest:**
  - Slot 0 was the disposable `QuadSquad8-pipeline-test-20260919.hda`.
  - CFG byte 0 was `0x40`: 32 MB, Ethernet on. Speedometer showed Physical RAM 32768K (`speedo_main.png`).
  - HDMI was 1280x720, Monitor 13in 640x480, Scale Normal.
- **UART at the start:**
  - Printer mode, saved speed 57600.
  - The daemon ran as `mister_printerd -d /dev/ttyS1 -b 57600 -m auto` with RTS asserted.
- **Method:** the seed 23 script set, copied to `scratch/p263_release_hw_20260930/scripts/` with only
  `T=` changed: `p_pr.sh`, `bench.sh`, `p_dup.sh` + `armfine.sh`, `speedo_launch.sh` (`m:127,180`),
  `speedo_quit.sh`, `shutdown.sh`, `schdr.py` and `psamp.sh`.
  - Every Speedometer value below was read by eye from pixel-enlarged crops.
  - Every "tests are done" alert was checked present in the done screenshot.

## 1. Boot

- **Boot:**
  - At 06:15:45 UTC, 51 s after the load, the desktop pattern was drawn.
  - The Finder was up at 06:16:36, about 100 s after the load, with no bomb (`boot_finder.png`).
- **The spooler did not grab the CPU:** the menu-bar clock read 6:16, 6:17 and 6:18 at 06:16:36,
  06:17:41 and 06:18:30 (`boot_clocks.png`). The scaled capture draws the 6 and the 8 alike.
- **Core-load page:** the load again produced the usual 92,808-byte near-blank
  `Print_2026-09-30_06-15-08.pdf`, with 16 bytes on ttyS1 (rx 63,358 → 63,374).
- **Limit of the screenshots:**
  - They copy the scaler's input buffer, so they cannot show an output-side HDMI artefact.
  - This fit meets HDMI timing (+0.310), so no such artefact is expected. A look at the display is
    still the real check.

## 2. Speedometer 4.02

**Performance Rating, all four tests** (`pr{1..5}_done_crop.png`, `pr5_done.png`):

| PR run | CPU | Graphics | Disk | Math | PR |
|---:|---:|---:|---:|---:|---:|
| 1 | 0.896 | 1.167 | 2.493 | 21.489 | 1.269 |
| 2 | 0.894 | 1.164 | 2.499 | 21.451 | 1.266 |
| 3 | 0.897 | 1.166 | 2.467 | 21.416 | 1.267 |
| 4 | 0.897 | 1.164 | 2.473 | 21.485 | 1.267 |
| 5 | 0.896 | 1.166 | 2.488 | 21.434 | 1.268 |
| **median** | **0.896** | **1.166** | **2.488** | **21.451** | **1.267** |
| seed 23 `920ffa2a` median | 0.896 | 1.161 | 2.414 | 21.476 | 1.263 |
| P260 `f769b9e1` median | 0.896 | 1.167 | 2.462 | 21.457 | 1.266 |

- **CPU, Graphics and Math match P260.**
- **PR Disk** has a median of 2.488 (2.467-2.499), inside P260's range (2.447-2.532).
  - Seed 23's lower 2.414 was therefore boot-to-boot spread, not a disk-path cost of the build.
  - That fits P263 not touching the disk path.
  - The disposable disk now holds 105-115 items against 63 at P260, and even so Disk is at the P260 level.

**FPU Benchmarks** (Whetstone, Matrix Multiply and Fast Fourier checked, Iter. 1, `fpu1_setup.png`):

| FPU run | KWhet/s | Matrix s | FFT s | **Average** |
|---|---:|---:|---:|---:|
| 1 (first after launch, cold) | 4589.450 (0.881) | 0.690 (1.024) | 0.301 (0.953) | **0.953** |
| 2 (after the Mix, warm) | 4600.260 (0.883) | 0.723 (0.976) | 0.281 (1.024) | **0.961** |
| 3 (extra warm run) | 4621.136 (0.887) | 0.711 (0.994) | 0.280 (1.024) | **0.968** |
| seed 23 cold / warm | 4513.103 / 4588.460 | 0.747 / 0.682 | 0.286 / 0.285 | 0.939 / 0.975 |
| P260 cold / warm | 4610.462 / 4573.749 | 0.724 / 0.690 | 0.289 / 0.280 | 0.951 / 0.976 |

- **The cold run is at the P260 level:** 0.953 against 0.951. Seed 23's low 0.939 was not a
  cold-path cost of the P263 compaction.
- **The warm run is 0.961, under the 0.975 expected.**
  - Whetstone (4600) and FFT (0.281) match P260's warm values.
  - The difference is all Matrix Multiply: 0.723 s against 0.690.
- **So one extra FPU run was made.** It gave 0.968 with Matrix 0.711.
- **Matrix is the noisy subtest.** Across these three runs and seed 23's two, one build and one RTL,
  it ranges 0.682-0.747 s (±5 %) while Whetstone stays within 2 % and FFT reads 0.280-0.286 s warm.
  - The first-run 0.301 s FFT is the cold outlier.
  - This is spread in the one timed Matrix window, not a build difference. The RTL is the same as
    seed 23.
- Screens: `fpu{1,2,3}_done_crop.png`.

**Benchmark Mix** (all ten tests at Iter. 1, `mix1_setup.png`, `mix1_table_crop.png`):

| | KWhet/s | Dhry/s | Towers | QSort | Bubble | Queens | Puzzle | Perm | Int. Matrix | Sieve | **Mix** |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| **seed 24** | 1850.600 | 19387.705 | 0.477 | 0.511 | 0.632 | 0.361 | 0.774 | 0.702 | 0.467 | 1.044 | **1.808** |
| seed 23 | 1852.716 | 19545.068 | 0.476 | 0.538 | 0.634 | 0.362 | 0.785 | 0.705 | 0.460 | 1.046 | 1.802 |
| P260 `f769b9e1` | 1847.493 | 19356.302 | 0.477 | 0.511 | 0.632 | 0.362 | 0.775 | 0.704 | 0.463 | 1.049 | 1.807 |

The Mix is 1.808, equal to P260 (1.807). QSort is back at 0.511, which confirms that seed 23's
0.538 was the known boot-to-boot layout effect.

Speedometer was quit with Return, Cmd-Q, and No to the Machine Record. The pointer was checked on
the No button first, and an explicit button-up followed.

## 3. Photoshop 3.0.1 Finder duplicates

**Method**

- The target was selected by hand: a click on the folder's title bar (`m:120,22`), then a click on
  the `Adobe Photoshop™ 3.0` icon (`m:29,58`), not on the name.
- Each copy was a Cmd-D (keycode 56 + D).
- The time runs to the sampler window that holds the copy's last `write()`.
- A copy counts as complete when Main's `wchar` delta is at least 3,958,000 B.

**Results**

| copy | time (s) | kB/s | written (B) | read phase | write phase |
|---:|---:|---:|---:|---|---|
| 1 (cold) | 5.21 | 759 | 3,967,488 | 3.14 s, 1.46 MiB/s | 2.57 s, 1.47 MiB/s |
| 2 | 5.27 | 752 | 3,971,072 | 1.82 s, 2.30 | 2.84 s, 1.33 |
| 3 | 4.99 | 793 | 3,967,488 | 1.83 s, 2.27 | 2.59 s, 1.46 |
| 4 | 4.98 | 795 | 3,964,928 | 1.83 s, 2.26 | 2.58 s, 1.46 |
| 5 | 5.24 | 756 | 3,964,928 | 1.82 s, 2.27 | 2.83 s, 1.33 |
| 6 | 5.23 | 757 | 3,966,976 | 1.82 s, 2.28 | 2.83 s, 1.33 |
| 7 | 5.25 | 754 | 3,969,024 | 1.83 s, 2.28 | 2.84 s, 1.33 |
| 8 | 5.26 | 753 | 3,965,952 | 1.83 s, 2.27 | 2.85 s, 1.33 |
| 9 | 5.24 | 755 | 3,966,976 | 1.83 s, 2.25 | 2.85 s, 1.33 |
| 10 | 5.20 | 761 | 3,964,928 | 1.82 s, 2.26 | 2.80 s, 1.35 |
| **median** | **5.24** (5.235) | **756** | | warm 1.82-1.83 s | 2.57-2.85 s |

- **All ten completed. Hangs: 0 of 10, bombs: 0.** The folder went from 105 to 115 items and from
  794.6 to 756.8 MB free (`dup10_after.png`).
- **The same two write modes as seed 23 and P260**, one sampler window apart:
  - a 2.57-2.59 s write phase: copies 1, 3 and 4;
  - a 2.80-2.85 s write phase: the other seven.
  - This boot fell more often into the slow mode, as P260's copies 11-30 did (median 5.07, max 5.20).
- **Read phases are the best yet:** warm 1.82-1.83 s at 2.25-2.30 MiB/s, against seed 23's 1.81-2.09 s
  and P260's 1.76-2.02 s. The cold read took 3.14 s, against 2.88 s at seed 23 and 2.77 s at P260.
- **Conclusion: no disk-path regression.**
  - The median is 5.24 s, against 5.11 s at seed 23 and 4.95 s at P260 copies 1-10.
  - The difference is only which of the two write modes each copy fell into; the fast-mode copies
    take 4.98-4.99 s.
  - PR Disk on this boot is at the P260 level.

## 4. Features

### Scale (live, guest running)

Each mode was set with F12, Down x6, Enter, F12. `schdr.py` then read the ascal header, read-only
(`scale_log.txt`).

| Scale | scaler input | scaler **output** (1280x720 HDMI) |
|---|---|---|
| Normal (start) | 640x480 | **960x720** |
| V-Integer | 640x480 | **640x480** |
| Narrower HV-Integer | 640x480 | 640x480 |
| Wider HV-Integer | 640x480 | 640x480 |
| Normal again | 640x480 | **960x720** |

- **This matches seed 23 and P262 exactly.**
- Each capture differs from the desktop only in the menu-bar clock digits (`scale_normal_again.png`).
- Scale was left at **Normal**.

### Monitor 12in 512x384 and back (latched under reset)

**Switch to 512x384**

- The guest was shut down cleanly first, after the load boot, to the safe screen with Main's
  `write_bytes` flat.
  - That halt had every glyph; the pointer's tail overlaps the capital I (`sd1_halt_text_zoom.png`).
- F12, Down x4, Enter set 12in 512x384. Down x6, Enter selected **Reset and close OSD** at 07:00:11 UTC.
- At 20 s the scaler input was **512x384** (line 1536), output 960x720.
- **The Finder came up at 512x384** by 90 s, as a 512x384 capture (`m512_finder.png`).
- **Clock:**
  - The menu bar read 6:16 at 07:01:41 and 6:17 at 07:02:45.
  - **The guest clock re-seeded** to the core-load TIMESTAMP (06:14:54) and ran on from there. This
    is the known P262 behaviour of `rtc3430042.sv`.
- **Halt screen:** Shut Down from the 512x384 desktop reached "It is now safe to switch off your
  Macintosh" **with every glyph present** (`m512_halt_text_zoom.png`). The pointer overlaps the a of "safe".

**Switch back to 640x480**

- Monitor was set back to 13in 640x480, then Reset and close OSD at 07:04:24 UTC.
- At 20 s the scaler input was 640x480, output 960x720.
- The Finder came up at **640x480** by 90 s, with the original icon layout (`m640_finder_after_reset.png`).
- **Clock:** re-seeded again. It read 6:16 at 07:05:55.
- **Halt screen:** the final Shut Down (section 6) was also complete, with I, f and M drawn
  (`halt_final_text_zoom.png`).

**So the P262 missing-glyph effect did not recur after either OSD reset**, the same as at seed 23.

## 5. Printing at 9600 with the corrected CTS

**Daemon setup**

- The OSD path was F12, Right (System), Down x4 (UART mode), Enter, Down x2 (Baud), Enter,
  Up x5 (57600 → 9600), Enter, then F12, F12 (UART submenu → System page → closed; from
  `menu.cpp` in `../Mac_Main_MiSTer`).
- `/tmp/UART_SPEED` went to 9600, and the daemon restarted as
  `mister_printerd -d /dev/ttyS1 -b 9600 -m auto` (`daemon_9600.txt` in scratch).
- `/proc/tty/driver/serial` showed ttyS1 **RTS**|CTS|DTR|DSR|CD|RI.
- `uartspeed.MacQuadra800` was unchanged: 57600, mtime 2026-09-27.
- **No `stty` or `rts.py` was run**, so nothing opened ttyS1 beside the daemon.

**Job 0: the ImageWriter's port had reverted to the Printer port.** File → Print Desktop… →
ImageWriter 7.0.1, Faster, Print at 06:49:45.

- The Mac put up "To cancel printing, hold down the ⌘ key and type a period" and finished within
  45 s with **no alert** (`print_printerport_done.png`).
- **0 bytes** reached ttyS1 in 110 s (rx held at 63,374; `psamp_job0_printerport.txt`).
- A double-click on the ImageWriter desktop printer said "this kind of printer cannot print in the
  background" (`print_foreground_only.png`), so nothing was queued.
- **The Chooser showed the ImageWriter on the Printer port** (`chooser_port_reverted.png`). The job
  had gone out of the unconnected Printer port.
- **Seed 23 saw the same reversion.** The ImageWriter's port choice evidently does not survive a
  core load, most likely because it lives in PRAM and the core's PRAM starts fresh at each load.
  That is an inference. This is a guest-setup property, not a regression of this build.
- **Modem Port was selected** (`chooser_modem.png`). The Chooser closed with no "changed your
  current printer" alert, because the ImageWriter was already the chosen driver.

**Job 1: Modem port, daemon RTS asserted.** Print Desktop again (`print_dialog.png`), Print at 06:56:52.

- **The Mac printed without any "not responding" alert** (`print_modem_done.png`).
- **19,146 bytes** went out from 06:57:04 to 06:57:27 (daemon `rchar` 1,849 → 20,995; ttyS1 rx
  63,374 → 82,520; `psamp_job1_modem.txt`):
  - about 900-1,000 B/s, the full 9600 rate;
  - 2 bytes at 06:56:53, the moment of the press;
  - no framing errors (fe stayed at 3).
- The daemon wrote **`Print_2026-09-30_06-56-53.pdf`** (226,973 B, two Letter pages, copied here).
  - It is the same size as seed 23's job 1 and **pixel-identical to it when rendered** (both pages
    at 72 dpi, zero differing pixels). 26 bytes differ, in the embedded timestamps.
  - Page 1 is the Finder desktop, and page 2 is the right-hand strip (`printed_pdf_pages.png`).
- The RTS-dropped test was not repeated (brief: done at seed 23).

**Side finding:** the two OSD resets and three Shut Downs after the job put **8 more bytes** on
ttyS1 (rx 82,520 → 82,528), with no new framing error and no PDF. Seed 23 saw 8 bytes there too, with one framing error.

## 6. Idle, type-select, Shut Down

- **Idle:** after a click on the empty desktop, the Finder sat with no input from 07:06:29 to
  07:10:38 UTC by the MiSTer's clock.
  - Screenshots once a minute read **6:16, 6:18, 6:19, 6:20, 6:21** (`idle_clocks.png`).
  - That is one guest minute per MiSTer minute, with the constant offset from the re-seed in section 4.
    Samples 0 and 1 are 62 s apart across a minute boundary. The scaled capture draws the 8 like a
    6, the 9 as a 5 and the 0 as a C.
  - The five captures differ only in the clock digits.
  - Main's `write_bytes` rose 76,783,616 → 77,127,680 (about 86 kB/min): housekeeping only.
- **Keyboard:** type-select "tra" selected the Trash (`idle_keyboard.png`).
  - The keys went in one `mister_ws.py raw:20 raw:19 raw:30` call.
  - A first try with one call per letter selected Applications instead. Each process start took
    longer than the Finder's type-select gap, so only the "a" counted. This is a method artefact.
- **Shut Down:**
  - The vmouse Special-menu recipe (`shutdown.sh`, explicit button-up) reached **"It is now safe to
    switch off your Macintosh"** at about 07:12 UTC (`halt_final.png`).
  - `write_bytes` was then flat at 77,479,936 over 5 s, and no vmouse process was left.
- **Shut Downs this session:** three, all clean: after the load boot, after the 512x384 boot, and
  this one.

## Box state at the end

| | |
|---|---|
| guest | halted at the safe screen |
| core | `49951492` still loaded |
| live settings | Monitor 13in 640x480, Scale Normal |
| UART | Printer at **9600 for this session only**. `uartspeed.MacQuadra800` still holds **57600** (mtime 2026-09-27), so the next core load returns to 57600. |
| daemon | `-b 9600`, running, RTS asserted |
| CFG byte 0 | unchanged, `0x40` |
| disposable disk | 10 more Photoshop copies (115 items, 756.8 MB free). The ImageWriter is on the Modem port for this boot; it will likely revert at the next core load. |
| `/media/fat/printers` | `Print_2026-09-30_06-15-08.pdf` (core-load glitch) and `…06-56-53.pdf` (the job) added |
| hangs / bombs / black screens / reboots | **0 / 0 / 0 / 0** |

## .qsf seed-history line (ready to paste after the P263 seed-24 entry)

```
# 2026-09-30: hardware, 49951492 (6ce38c8 seed 24, the CLEAN release fit; Main 75e00b65, 32 MB): PR 1.267, CPU
# 0.896, Disk 2.488 median of 5 (seed 23 1.263 / 0.896 / 2.414; f769b9e1 1.266 / 0.896 / 2.462); FPU 0.953 cold /
# 0.961 and 0.968 warm (Matrix spread 0.690-0.723 s; f769b9e1 0.951 / 0.976), Mix 1.808 (1.807); Photoshop duplicate
# 5.24 s median of 10 (4.98-5.27, two write modes; f769b9e1 4.95), 0 hangs; Scale 960x720 / 640x480, 512x384
# through an OSD reset and back, halt glyphs intact; ImageWriter prints at 9600 on the Modem port with RTS asserted
# (19,146 B, PDF identical to seed 23; the port reverts to Printer at each core load); idle clock and Shut Down clean
# (docs/perf/p263_release_hw_20260930).  8.1 gate PASS; A/UX, CD audio and the HDMI display look still owed.
```

## Files

- **This directory:**
  - the screenshots named above;
  - `psamp_job0_printerport.txt` and `psamp_job1_modem.txt`: the once-a-second daemon and ttyS1 samples;
  - the job PDF;
  - `scale_log.txt`;
  - the seed 24 fit and sta summaries.
- **`scratch/p263_release_hw_20260930/`:** every capture (`boot/`, `run/`, `scale/`, `print/`,
  `sd1/`, `m512/`, `m640/`, `idle/`, `final/`), the per-copy sampler logs `run/dup*_arm.txt`, and the
  script set. The scripts are those in `docs/perf/p263_hw_20260930`.
