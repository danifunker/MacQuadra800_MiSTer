# P263 release candidate on hardware: 6ce38c8 at seed 23, Mac OS 8.1 gate (2026-09-30)

`6ce38c8` (P263) keeps one copy of the FPU state frame: the core's FRESTORE staging and the FPU's
duplicate copies are gone. It sits on top of the P261/P262 features (OSD without the Dbg lines,
framework integer scaling, the 12in 512x384 monitor) and the CTS polarity fix `4e21a99`. The fit
is seed 23 from `docs/perf/p263_fpga_20260930`. It misses HDMI timing by 0.157 ns on the
framework's scaler register only, so this is a timing-override trial under the CLAUDE.md rule.

**Verdict: the Mac OS 8.1 half of the gate passes.**

- **Stability:** 0 hangs, 0 bombs, 0 black screens, 0 reboots.
- **Performance:** unchanged against P260 `f769b9e1` within run-to-run spread.
- **Features:** all work, and **ImageWriter printing works with the corrected CTS polarity**.
  With RTS asserted the job goes straight through. When the daemon drops RTS, the Mac holds off
  and reports "not responding", and the job resumes once RTS is back.
- **Still open:**
  - the HDMI output itself has to be looked at on the display (see section 1);
  - the A/UX and CD-audio halves of the release gate were not part of this session;
  - the fit is an HDMI-only timing miss, not a clean seed.

| | this build (`920ffa2a`) | P260 `f769b9e1` |
|---|---:|---:|
| PR (median of 5) | **1.263** | 1.266 |
| CPU / Graphics / Math | 0.896 / 1.161 / 21.476 | 0.896 / 1.167 / 21.457 |
| PR Disk (median of 5) | **2.414** (2.377-2.484) | 2.462 (2.447-2.532) |
| FPU Benchmarks | **0.939 cold / 0.975 warm** | 0.951 cold / 0.976 warm |
| Benchmark Mix | **1.802** | 1.807 |
| Photoshop duplicate, median of 10 | **5.11 s** (4.95-5.25) | 4.95 s (copies 1-10: 4.94) |
| hangs | **0 / 10 copies** | 0 / 30 |

The operator did not load or deploy anything; the coordinator deployed the rbf. Nothing was
committed, and `rtl/` and the `.qsf` were not touched. The master `QuadSquad8.hda` was not touched
(mtime still 2026-09-19).

## Build and box

- **Build:** `6ce38c8` at seed 23 (`.qsf` release recipe, only `SEED` changed).
  - rbf md5 `920ffa2aaac3f936a58244e020c9bac7`, 4,478,776 B.
  - Fit: 39,335 ALMs (94 %), 24,704 registers, 468 / 553 M10K, 36 DSP.
  - Setup slack:
    - CPU `general[0]` **+0.073**;
    - RAM `general[1]` **+0.943**;
    - HDMI **-0.157** (TNS -0.180, two endpoints, `ascal` → the `mask_bypass` shift-tap M10K);
    - h2f_user0 +3.885.
  - Hold worst +0.227. Crossings +0.943 / +0.815, 0 violated.
  - Summaries: `MacQuadra800_6ce38c8_seed23.{fit,sta}.summary`.
- **Box:** `10.3.164.251`. The `.92` box was not touched.
  - Main is `/proc/PID/exe` md5 `75e00b65`, the tight-loop build.
  - The core is `_Unstable/MacQuadra800.rbf`, md5 `920ffa2a` on the box. The coordinator loaded it
    with `load_core` at 05:16:57 UTC (01:17 EDT).
- **Guest:**
  - Slot 0 was the disposable `QuadSquad8-pipeline-test-20260919.hda`.
  - CFG byte 0 was `0x40` (32 MB, Ethernet on). Speedometer showed Physical RAM 32768K (`speedo_main.png`).
  - The HDMI mode was 1280x720.
- **UART at the start:**
  - Printer mode (`uartmode.MacQuadra800` = 7), saved speed 57600.
  - The daemon ran as `mister_printerd -d /dev/ttyS1 -b 57600 -m auto`, with RTS asserted.
- **Method:** the P260/P262 scripts, copied to `scratch/p263_hw_20260930/scripts/`, with two
  changes and two new scripts:
  - **`speedo_launch.sh`** now double-clicks the Speedometer alias with `m:127,180`. P262's
    512x384 boot had re-laid the desktop icons, so the old `m:246,248` landed on empty desktop.
    With home at 0,0, vmouse moves the pointer about 1.66 px per count.
  - **The duplicate target** was selected by hand: a click on the folder's title bar, then on the
    `Adobe Photoshop™ 3.0` icon. `ps_open.sh` was not used.
  - **`bench.sh`** (new) runs the FPU and Mix tests. It uses the `hw_p258` `fpu_run.sh` /
    `mix_run.sh` timing: 45 s for FPU, 90 s for Mix.
  - **`psamp.sh`** (new, on the box) samples the daemon's `rchar` and the ttyS1 counters once a
    second. It never opens ttyS1, so it does not touch RTS.
  - Every Speedometer value below was read by eye from pixel-enlarged crops.

## 1. Boot and HDMI

- **Boot:** the Finder desktop was up at the first look, 05:17:59 UTC, about a minute after the
  load, with no bomb (`boot_finder.png`).
- **The spooler did not grab the CPU.** The menu-bar clock read 5:17, then 5:18, then 5:19 at
  05:19:41. Whether the StyleWriter session's job is still queued was not checked; it did not hold the CPU.
- **Screenshots:** three consecutive screenshots at boot, and five over the four-minute idle,
  differ from one another only in the menu-bar clock digits (pixel diff box 580-594 x 4-15). The
  captures during the four Scale modes show the same desktop.
- **Limit of this evidence:**
  - Main's screenshot copies the scaler's **input** frame buffer in DDR3, before the output path.
  - The failing HDMI register (`ascal` output → `mask_bypass`) is after that buffer.
  - **An artefact from the -0.157 ns miss cannot appear in these screenshots. The display itself is
    the real check, and it needs a look by the user.**

## 2. Speedometer 4.02

**Performance Rating, all four tests** (`pr{1..5}_done_crop.png`, `pr5_done.png`):

| PR run | CPU | Graphics | Disk | Math | PR |
|---:|---:|---:|---:|---:|---:|
| 1 | 0.893 | 1.161 | 2.377 | 21.476 | 1.258 |
| 2 | 0.897 | 1.159 | 2.484 | 21.476 | 1.266 |
| 3 | 0.896 | 1.160 | 2.424 | 21.450 | 1.262 |
| 4 | 0.896 | 1.162 | 2.414 | 21.470 | 1.263 |
| 5 | 0.896 | 1.162 | 2.414 | 21.484 | 1.263 |
| **median** | **0.896** | **1.161** | **2.414** | **21.476** | **1.263** |
| P262 trial `48a23a78` (1 run) | 0.895 | 1.162 | 2.394 | 21.475 | 1.261 |
| P260 `f769b9e1` median (5) | 0.896 | 1.167 | 2.462 | 21.457 | 1.266 |

- **CPU and Math are unchanged**, as expected: P263 touches only the FSAVE/FRESTORE frame path.
- **PR Disk** has a median of 2.414 (range 2.377-2.484).
  - Two of these runs overlap P260's range (2.447-2.532), and three fall under it.
  - The P262 trial's single run was 2.394.
  - Both post-P260 builds therefore sit about 2 % under P260. P263 does not touch the disk path.
    The likelier causes are the fuller disposable disk (63 items at P260, 105 now) or boot-to-boot
    spread. This is an inference.
- **Graphics** is 0.5 % under P260, still inside the historical 1.159-1.168.
- Five valid runs: no timer anomaly, and every "tests are done" alert was up at the screenshot.

**FPU Benchmarks** (Whetstone, Matrix Multiply and Fast Fourier checked, Iter. 1, `fpu1_setup.png`):

| FPU run | KWhet/s | Matrix s | FFT s | **Average** |
|---|---:|---:|---:|---:|
| 1 (first after launch) | 4513.103 (0.866) | 0.747 (0.945) | 0.286 (1.006) | **0.939** |
| 2 (after Mix, warm) | 4588.460 (0.881) | 0.682 (1.036) | 0.285 (1.009) | **0.975** |
| P260 cold / warm | 4610.462 / 4573.749 | 0.724 / 0.690 | 0.289 / 0.280 | 0.951 / 0.976 |

- **The warm run matches P260** (0.975 against 0.976).
- **The cold first run is lower** (0.939 against 0.951), mostly from Whetstone (-2 %) and Matrix
  (0.747 s against 0.724).
  - The brief asked for one run. The first came in low, so one warm run followed after the Mix, as
    in the P260 session.
  - First-run values have varied between boots before (P258: 0.951 / 0.965 cold; `dc281d64`: 0.955).
  - One sample cannot separate a real cold-path cost of the compaction from that spread.
- Screens: `fpu1_done_crop.png`, `fpu2_done_crop.png`.

**Benchmark Mix** (all ten tests at Iter. 1, `mix1_setup.png`, `mix1_table_crop.png`):

| | KWhet/s | Dhry/s | Towers | QSort | Bubble | Queens | Puzzle | Perm | Int. Matrix | Sieve | **Mix** |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| **this build** | 1852.716 | 19545.068 | 0.476 | 0.538 | 0.634 | 0.362 | 0.785 | 0.705 | 0.460 | 1.046 | **1.802** |
| P260 `f769b9e1` | 1847.493 | 19356.302 | 0.477 | 0.511 | 0.632 | 0.362 | 0.775 | 0.704 | 0.463 | 1.049 | 1.807 |

The Mix is unchanged (1.802 against 1.807). QSort 0.538 against 0.511 is the known boot-to-boot
layout effect: `b7e88b81` had 0.544.

Speedometer was quit with Return, Cmd-Q, and No to the Machine Record. The pointer was checked on
the button first, and an explicit button-up followed.

## 3. Photoshop 3.0.1 Finder duplicates

Each copy was a Cmd-D (keycode 56 + D) of the selected `Adobe Photoshop™ 3.0`. The time runs to the
sampler window that holds the copy's last `write()`. A copy counts as complete when Main's `wchar`
delta is at least 3,958,000 B.

| copy | time (s) | kB/s | written (B) | read phase | write phase |
|---:|---:|---:|---:|---|---|
| 1 (cold) | 5.24 | 756 | 3,966,464 | 2.88 s, 1.59 MiB/s | 2.84 s, 1.33 MiB/s |
| 2 | 5.22 | 758 | 3,969,536 | 2.08 s, 2.00 | 2.84 s, 1.33 |
| 3 | 5.25 | 754 | 3,964,928 | 1.82 s, 2.28 | 2.84 s, 1.33 |
| 4 | 5.25 | 754 | 3,965,952 | 1.82 s, 2.27 | 2.86 s, 1.32 |
| 5 | 4.96 | 798 | 3,966,976 | 2.09 s, 1.98 | 2.57 s, 1.47 |
| 6 | 4.95 | 799 | 3,964,928 | 1.81 s, 2.29 | 2.58 s, 1.46 |
| 7 | 5.22 | 759 | 3,968,512 | 1.83 s, 2.27 | 2.83 s, 1.33 |
| 8 | 4.96 | 798 | 3,966,976 | 2.08 s, 1.99 | 2.56 s, 1.48 |
| 9 | 4.99 | 793 | 3,964,928 | 1.83 s, 2.26 | 2.60 s, 1.45 |
| 10 | 5.24 | 755 | 3,965,952 | 1.82 s, 2.27 | 2.85 s, 1.32 |
| **median** | **5.11** | **776** | | warm 1.82-2.09 s | 2.56-2.86 s |

- **All ten completed. Hangs: 0 of 10, bombs: 0.** The folder went from 95 to 105 items and from
  832.5 to 794.6 MB free (`dup10_after.png`).
- **The same two modes as P260**, one sampler window apart:
  - four copies ran at 4.95-4.99 s, with a 2.56-2.60 s write phase;
  - six ran at 5.22-5.25 s, with a 2.83-2.86 s write phase.
- **Comparison with P260:**
  - P260's copies 1-10 fell mostly in the fast mode (median 4.94). Its copies 11-30 fell more often
    in the slow mode (median 5.07, max 5.20).
  - The P262 trial had 5.26 s cold and 5.22 s warm.
  - Read phases are unchanged: warm 1.81-2.09 s, 1.98-2.29 MiB/s (P260: 1.76-2.02 s, 2.06-2.36).
    The cold read is 2.88 s (P260: 2.77).
- **Conclusion: no disk-path regression.** P263 does not touch the 53C96 or the SD path. The slower
  mode mix fits the fuller disk. That is an inference; one boot cannot settle it.

## 4. Features

### Scale (live, guest running)

Each mode was set with F12, Down x6, Enter, F12. `schdr.py` then read the ascal header, read-only.

| Scale | scaler input | scaler **output** (1280x720 HDMI) |
|---|---|---|
| Normal (start) | 640x480 | **960x720** |
| V-Integer | 640x480 | **640x480** |
| Narrower HV-Integer | 640x480 | 640x480 |
| Wider HV-Integer | 640x480 | 640x480 |
| Normal again | 640x480 | **960x720** |

- **This matches P262 exactly.** Narrower and Wider are equal on a 720-line output, as expected.
- The desktop screenshot was unchanged throughout (`scale_normal_again.png`), and nothing went black.
- Scale was left at **Normal**.

### Monitor 12in 512x384 and back (latched under reset)

**Switch to 512x384**

- The guest was shut down cleanly first, to the safe screen, with Main's `write_bytes` flat.
  - That halt, after the `load_core` boot, had every glyph.
- F12, Down x4, Enter set 12in 512x384. Down x6, Enter selected **Reset and close OSD** at 05:58:38 UTC.
- At 20 s the scaler input was **512x384** (line 1536), output 960x720.
- **The Finder came up at 512x384** by 90 s (`m512_finder.png`: a 512x384 capture, with the icons
  re-laid to fit).
- **Clock:** the menu bar read 5:18 at 06:00 and 5:19 at 06:01. **The guest clock re-seeded** to the
  core-load TIMESTAMP (05:16:57) and ran on from there. This is the known P262 behaviour of
  `rtc3430042.sv`, older than these commits.
- **Halt screen:** Shut Down from the 512x384 desktop reached "It is now safe to switch off your
  Macintosh" **with every glyph present**: I, f and M are all drawn (`m512_halt_text_zoom.png`).
  **The missing-glyph effect did not recur.**

**Switch back to 640x480**

- Monitor was set back to 13in 640x480, then Reset and close OSD at 06:02:34 UTC.
- At 20 s the scaler input was 640x480, output 960x720.
- The Finder came up at **640x480** by 90 s, with the original icon layout (`m640_finder_after_reset.png`).
- **Clock:** re-seeded again. It read 5:18 at 06:04:34.
- **Halt screen:** the final Shut Down (section 6) was also **complete**, with f and M drawn
  (`halt_final_text_zoom.png`). The pointer's tail overlaps the capital I there.

**So after both OSD resets the halt text was intact, where P262 lost I, f and M after both.** The
cause of the P262 effect is still unknown; it may be intermittent rather than fixed.

## 5. Printing at 9600 with the corrected CTS

**Daemon setup**

- The OSD path was F12, Right (System), Down x4 (UART mode), Enter, Down x2 (Baud), Enter,
  Up x5 (57600 → 9600), Enter, then F12, F12. The path was worked out from `menu.cpp` in
  `../Mac_Main_MiSTer`: the Printer mode uses the 13-entry mlink speed list.
- `/tmp/UART_SPEED` went to 9600, and `/sbin/uartmode 7` restarted the daemon as
  `mister_printerd -d /dev/ttyS1 -b 9600 -m auto`.
- `stty` showed 9600, cs8, -parenb, cread, clocal, **crtscts**.
- `/proc/tty/driver/serial` showed ttyS1 **RTS**|CTS|DTR|DSR|CD|RI.
- **No `rts.py` was used** for the first job.

**Guest setup**

- Chooser → ImageWriter. Its port had reverted to the Printer port, so **Modem Port** was selected
  (`chooser_modem.png`), and the "You have changed your current printer" alert was dismissed.
- The ImageWriter is now the default desktop printer again, replacing the Color SW 2500. This is a
  change to the disposable disk only.

**Job 1: daemon RTS asserted.** File → Print Desktop… → ImageWriter 7.0.1, Faster (`print_dialog.png`), Print at 05:52:06.

- **The Mac printed without any "not responding" alert.**
- **19,146 bytes** went out from 05:52:15 to 05:52:48 at the full 9600 rate, about 950 B/s (daemon
  `rchar` 1,849 → 20,995; ttyS1 rx 25,058 → 44,204; `psamp_job1b.txt`).
- The daemon wrote **`Print_2026-09-30_05-52-08.pdf`** (226,973 B, two Letter pages, copied here).
  Page 1 is a correct rendering of the Finder desktop, and page 2 is the right-hand strip
  (`printed_pdf_pages.png`).
- The job is smaller than P262's 24,978 B because the desktop now has fewer icons on the right.

**Job 2: daemon RTS cleared by hand** (`rts.py off` at 05:54:21; serial flags `CTS|DTR|DSR|CD|RI`). Print Desktop again at 05:55:15.

- **The Mac showed "The Printer is not responding. Check the 'select' switch."** within 30 s
  (`print_not_responding.png`).
- **0 bytes were sent** (rx held at 44,204). **This is the handshake working the right way:** a
  dropped RTS holds the Mac off.
- `rts.py on` restored RTS at 05:55:56. Within a second, **2 bytes** that the SCC had held back went
  out (rx 44,206).
- OK on the alert then **resumed the job**: 19,144 more bytes (rchar 20,997 → 40,141, done by 05:56:39).
- The daemon wrote `Print_2026-09-30_05-56-12.pdf`, **the same 226,973 B** as job 1.

**Verdict: `4e21a99` fixes the ImageWriter regression of the P262 trial.**

- An open daemon reads as ready.
- A daemon that drops RTS makes the Mac wait, and it resumes cleanly once RTS is back.

**Side findings**

- **The core-load page is still there.** The 05:16:57 load left the usual 92,808-byte near-blank
  `Print_2026-09-30_05-16-57.pdf`.
- **More bytes after the resets.** Between 05:57 and 06:10 (the two OSD resets and three Shut Downs),
  ttyS1 received **8 more bytes, with one more framing error** (rx 63,350 → 63,358, fe 2 → 3). No
  PDF resulted. This is likely the same reset-time output as the core-load glitch, at a baud where
  it framed badly. That is an inference.

## 6. Idle, type-select, Shut Down

- **Idle:** after a click on the empty desktop, the Finder sat with no input from 06:04:34 to 06:08:43 UTC by the MiSTer's clock.
  - Screenshots once a minute read **5:18, 5:19, 5:20, 5:21, 5:22** (`idle_clocks.png`). That is one
    guest minute per MiSTer minute.
  - The offset is a constant 46 minutes because of the re-seed after the OSD reset in section 4. The
    scaled capture draws the 9 as a 5 and the 0 as a C, the known artefact.
  - Main's `write_bytes` rose 76,668,928 → 77,033,472 (about 86 kB/min): housekeeping only.
- **Keyboard:** type-select "tra" selected the Trash, and the clock had moved on to 5:23 (`idle_keyboard.png`).
- **Shut Down:**
  - The vmouse Special-menu recipe (`shutdown.sh`, explicit button-up) reached **"It is now safe to
    switch off your Macintosh"** at about 06:10 UTC (`halt_final.png`).
  - `write_bytes` was then flat at 77,385,728 over 5 s, and no vmouse process was left.
- **Shut Downs this session:** three, all clean: after the load boot, after the 512x384 boot, and
  this one.

## Box state at the end

| | |
|---|---|
| guest | halted at the safe screen |
| core | `920ffa2a` still loaded |
| live settings | Monitor 13in 640x480, Scale Normal |
| UART | Printer at **9600 for this session only**. It was not saved: `uartspeed.MacQuadra800` still holds 57600 (mtime 2026-09-27), so the next core load returns to 57600. |
| daemon | `-b 9600`, running, RTS asserted |
| CFG byte 0 | unchanged, `0x40` |
| disposable disk | 10 more Photoshop copies (105 items, 794.6 MB free); **ImageWriter on the Modem port is the default printer** again. The Color SW 2500 is still on the Modem port but no longer the default. |
| `/media/fat/printers` | `Print_2026-09-30_05-16-57.pdf` (core-load glitch), `…05-52-08.pdf` and `…05-56-12.pdf` (the two jobs) added |
| hangs / bombs / black screens / reboots | **0 / 0 / 0 / 0** |

## .qsf seed-history line (ready to paste after the P263 walk entry)

```
# 2026-09-30: hardware, 920ffa2a (6ce38c8 seed 23, HDMI-only -0.157 trial; Main 75e00b65, 32 MB): PR 1.263,
# CPU 0.896, Disk 2.414 median of 5 (f769b9e1 1.266 / 0.896 / 2.462); FPU 0.939 cold / 0.975 warm (0.951 /
# 0.976), Mix 1.802 (1.807); Photoshop duplicate 5.11 s median of 10 (4.95-5.25; f769b9e1 4.95), 0 hangs;
# Scale 960x720 / 640x480, 512x384 through an OSD reset and back, halt glyphs intact; ImageWriter prints at
# 9600 with RTS asserted, "not responding" with RTS dropped, resumes when restored (4e21a99 CTS fix good);
# idle clock and Shut Down clean (docs/perf/p263_hw_20260930).  HDMI output still to be judged at the display.
```

## Files

- **This directory:**
  - the screenshots named above;
  - `psamp_job1b.txt` and `psamp_job2.txt`: the once-a-second daemon and ttyS1 samples for the two jobs;
  - the job-1 PDF;
  - the seed 23 fit and sta summaries;
  - `bench.sh` and `psamp.sh`.
- **`scratch/p263_hw_20260930/`:** every capture (`run/`, `scale/`, `print/`, `m512/`, `m640/`,
  `idle/`, `sd1/`, `final/`), the per-copy sampler logs `run/dup*_arm.txt`, and the script set.
