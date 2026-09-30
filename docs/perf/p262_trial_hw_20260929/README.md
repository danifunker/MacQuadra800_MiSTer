# Trial build 0063c59 at seed 23 on hardware: OSD clean-up, Scale, 512x384, live CTS (2026-09-29)

A functional gate of the four new features in `b40acdd` (OSD: Dbg lines out,
framework integer scaling, 512x384 back) and `0063c59` (SCC RR0 CTS follows
`UART_CTS`; the self-test baud shortcuts only in loopback). This is **not** a
release gate: the fit misses HDMI timing by 0.339 ns.

**Verdict:**

| feature | result |
|---|---|
| Dbg lines gone | **PASS**. The CONF_STR the running core gave Main has no Dbg lines, and the OSD item indices match it. |
| Scale | **PASS**. All four modes switch live, and the scaler's output size changes. |
| 512x384 | **PASS** (with one open observation). A reset brings up a 512x384 desktop; switching back gives 640x480. |
| CTS / printing | **FAIL: the polarity is inverted for the Mac.** The ImageWriter driver reports "The Printer is not responding" and sends 0 bytes while the daemon asserts RTS. With RTS dropped by hand, the job went through at full 9600 and the daemon wrote a correct PDF. |

- **No regressions:** PR Disk 2.394, CPU 0.895, PR 1.261. The Photoshop duplicate took 5.26 s cold and 5.22 s warm.
- **Stability:** 0 hangs, 0 bombs, 0 black screens, no reboot. The operator did not load or deploy anything. Nothing was committed, and `rtl/` and the `.qsf` were not touched.

## Build and box

- **Build:** `0063c59` at seed 23, rbf md5 `48a23a786f69d40790b011f0fe28691b` on the box (`_Unstable/MacQuadra800.rbf`).
  - Setup slack: CPU +0.081, RAM +0.347, HDMI **-0.339** (the framework's video output register).
  - The coordinator deployed it with `load_core` at 02:24:45 UTC (22:24 EDT).
- **Box:** `10.3.164.251`. Main `/proc/PID/exe` md5 `75e00b65`, the tight-loop build (`../Mac_Main_MiSTer`, branch `mac-printer-fujinet-tightloop`). The `.92` box was not touched.
- **Guest:**
  - Slot 0 was the disposable `QuadSquad8-pipeline-test-20260919.hda`. The master `QuadSquad8.hda` was not touched.
  - CFG byte 0 was `0x40` (32 MB, Ethernet on), and Speedometer showed 32768K.
  - The HDMI mode is 1280x720 (`/sys/module/MiSTer_fb/parameters/mode`).
- **Scripts** are in `scratch/p262_trial_hw_20260929/scripts/`: copies of the P260 set, plus three new ones, all run on the box and all read-only apart from `rts.py`. Copies are in this directory.
  - `schdr.py` reads the ascal DDR3 header at `0x20000000` through `/dev/mem`, read-only. This is the same header Main's `scaler.cpp` reads. It gives the input size and the **scaled output size**.
  - `confstr.py` scans Main's writable memory through `/proc/PID/mem`, read-only, for the CONF_STR that Main read from the core over SPI.
  - `rts.py` sets or clears RTS on `/dev/ttyS1` through a second descriptor, leaving termios untouched.

## 1. Boot and HDMI

- **Boot:** the Finder was up by 02:26:11 UTC, about 85 s after the load, with no bomb (`boot_finder.png`).
- **Screenshots:** three consecutive screenshots, and every screenshot taken during the OSD and Scale changes, differ from one another only in the menu-bar clock digits. No tearing, colour or flicker artefacts appear in any capture.
- **Limit of this evidence:**
  - Main's screenshot copies the **scaler's input frame buffer** in DDR3, before the output path. A capture is 640x480 in every Scale mode, even when the HDMI output is 960x720.
  - The failing HDMI register is after that buffer. **An artefact caused by the -0.339 ns miss cannot appear in a screenshot**, so the HDMI output itself is unverified.
  - The HDMI output needs a look at the display by the user. The scaler kept reporting sane output geometry throughout, and nothing went black in the captured path.

## 2. OSD contents

The screenshots do not include the OSD, because the OSD is overlaid after the scaler. Instead, `confstr.py` recovered the CONF_STR that Main read from the running core (`confstr_from_main.txt`, 923 bytes, `V,v260929`). Page 0 of that string:

```
SC0 Mount SCSI disk 0 / SC1 disk 1 / SC4 CD-ROM / -
O[4:3]   RAM (on reset) 32MB,64MB,128MB
O[5]     Monitor (on reset) 13in 640x480,12in 512x384
O[122:121] Aspect ratio Original,Full Screen,[ARC1],[ARC2]
O[13:12] Scale Normal,V-Integer,Narrower HV-Integer,Wider HV-Integer
-  O[6] Ethernet (on reset) Off,On / O[8:7] Net interface
-  T[0] Reset / R[0] Reset and close OSD / - / P1 MT32-pi ...
```

- **No `Dbg` entries.**
- **The blind navigation agrees with this layout:**
  - F12, Down x6, Enter lands on **Scale** (section 3).
  - F12, Down x4, Enter lands on **Monitor**.
  - From Monitor, Down x6 lands on **Reset and close OSD**, and that reset the core (section 4). With the three Dbg lines still present, index 10 would have been "Dbg SDRAM line".

## 3. Scale (live)

Each mode was set with Enter on the Scale line, and `schdr.py` read the result:

| Scale | scaler input | scaler **output** (on 1280x720 HDMI) |
|---|---|---|
| Normal | 640x480 | **960x720** |
| V-Integer | 640x480 | **640x480** (1x: 720/480 = 1.5) |
| Narrower HV-Integer | 640x480 | 640x480 |
| Wider HV-Integer | 640x480 | 640x480 |
| Normal again | 640x480 | 960x720 |

- **Normal and V-Integer differ as intended.** The Scale bits reach `video_freak`.
- **Narrower and Wider are equal here.** On a 720-line display the only integer vertical factor is 1, and square 4:3 pixels leave nothing to round in the width. That is the expected result, not a fault.
- **Nothing went black.** The desktop screenshot was identical in every mode (`scale_vinteger.png`), as the capture limit in section 1 predicts.
- Scale was left at **Normal**.

## 4. 512x384 (Monitor, latched under reset)

The guest was shut down cleanly first (`halt_first.png`), because an OSD reset under a running guest is barred by binding rule 1.

**Switch to 512x384**

- Monitor was set to 12in 512x384, then "Reset and close OSD" was selected at 02:53:54 UTC.
- The scaler input was **512x384** (line 1536) at 20 s, with output 960x720.
- The Finder desktop came up at **512x384** by 90 s (`m512_finder.png`; the screenshot itself is 512x384). The menu bar spans the narrower screen, and the Finder re-laid the desktop icons to fit.

**Switch back to 640x480**

- Shut Down reached the halt screen (`m512_halt.png`). Monitor was set back to 13in 640x480, then "Reset and close OSD" was selected at 02:57:38.
- The scaler input was 640x480 at 20 s. The Finder came up at **640x480** by 95 s (`m640_finder_after_reset.png`).

**Two observations**

- **The guest clock goes back to the core-load time after an OSD reset.** The menu bar read 2:26 at 02:55 and again at 02:59.
  - `rtc3430042.sv` re-seeds on reset from the TIMESTAMP that Main sent at load, which was 02:24:45. That behaviour is older than these commits and is not caused by them.
  - It will confuse anyone who changes Monitor or RAM and resets.
- **The halt screen was missing glyphs after both OSD-reset boots.** It read "t is now sa e to switch o  your  acintosh." (`m512_halt_text_zoom.png`, `halt_final.png`):
  - the capital I, every f and the M are absent;
  - the text was stable over repeated captures;
  - it happened at 512x384 **and** at 640x480, so the monitor setting is not the cause;
  - the halt after the load_core boot was complete (`halt_first.png`);
  - the desktop text in the same boots was intact.

  The cause is not known. It looks like guest state after a warm reset, not video, but that is an inference. Shut Down itself worked every time.

## 5. Sanity

**Speedometer 4.02 Performance Rating** (`pr1_done_crop.png`):

| | CPU | Graphics | Disk | Math | PR |
|---|---:|---:|---:|---:|---:|
| **this build** | 0.895 | 1.162 | 2.394 | 21.475 | 1.261 |
| P260 median (`f769b9e1`) | 0.896 | 1.167 | 2.462 | 21.457 | 1.266 |

**Photoshop 3.0.1 Finder duplicates** (`dup_after.png`):

| copy | time | throughput | written | read phase | write phase |
|---|---:|---:|---:|---|---|
| cold | 5.26 s | 753 kB/s | 3,971,072 B | 2.91 s, 1.57 MiB/s | 2.84 s, 1.33 MiB/s |
| warm | 5.22 s | 758 kB/s | 3,964,928 B | 1.82 s, 2.29 MiB/s | 2.82 s, 1.34 MiB/s |

- **Disk:** PR Disk is inside P260's run-to-run spread (2.447-2.532), a little under its low end.
- **Duplicates:** P260 had 5.18 s cold, and its warm copies ran in two modes at 4.9-5.2 s. The warm copy here falls at the slow end, about one sampler window slower than P260's fast mode.
- **Conclusion:** the disk path has not regressed. The folder went from 93 to 95 items and 840.1 to 832.5 MB free.
- **Idle:** the Finder sat idle from 02:49:59 to 02:52:17 UTC. The menu-bar clock read 2:49, 2:51 and 2:52, in step with the MiSTer (`idle_clocks.png`).
  - The scaled capture turns the 9 into a 5, a known artefact.
  - Main's `write_bytes` rose 18,722,816 → 18,903,040 over the idle: housekeeping only.
- **Keyboard:** type-select "tra" selected the Trash (`idle_keyboard.png`).

## 6. Printing at 9600 through the modem port

**Daemon setup**

- UART mode was already **Printer** (`uartmode.MacQuadra800` = 7). The saved speed was 57600, and the daemon ran as `mister_printerd -d /dev/ttyS1 -b 57600 -m auto -c MacQuadra800 -o /media/fat/printers`.
- Baud was set to 9600 from the OSD (System → UART mode → Baud → 9600). The mode was not saved to the config, so a later core load returns to 57600.
- `/sbin/uartmode` then restarted the daemon with `-b 9600`. `stty -F /dev/ttyS1 -a` showed 9600, cs8, -parenb, cread, clocal, **crtscts**, -inpck.
- `/proc/tty/driver/serial` showed ttyS1 with **RTS|CTS|DTR|DSR|CD|RI**: the daemon holds RTS asserted.

**Guest setup**

- The default desktop printer is the ImageWriter (7.0.1 driver). In the Chooser it was on the **Printer** port (`chooser_printer_port.png`), which is SCC channel B and not wired to the HPS.
- Print Desktop to that port printed on the Mac side, but 0 bytes reached ttyS1, as expected for channel B.
- The ImageWriter was switched to the **Modem** port (`chooser_modem_port.png`). This is a change to the disposable disk only.

**Print Desktop through the modem port** (Faster quality, `print_dialog.png`)

- The Mac showed **"The Printer is not responding. Check the 'select' switch."** within 25 s (`print_not_responding.png`).
- ttyS1 rx stayed at 16 bytes and the daemon's `rchar` did not move: **no byte was sent.** The printer daemon never saw the job.
- **The diagnosis:** `rts.py off` cleared RTS on ttyS1, so `UART_CTS` went high and the new RR0 CTS bit went to 0. Return on the dialog's OK then continued the job.
  - The Mac sent **24,978 bytes** from 02:47:55 to 02:48:41 at the full 9600 rate (about 950 B/s).
  - The daemon read them all (`rchar` 1,849 → 26,827; `printerd_rx_during_job.txt`).
  - It wrote **`Print_2026-09-30_02-48-11.pdf`** (228,250 B, two Letter pages, copied here). Page 1 is a correct rendering of the Finder desktop, and page 2 is the right-hand strip (`printed_pdf_pages.png`).
  - RTS was restored with `rts.py on` afterwards.

**Conclusion: the Mac driver treats RR0 bit 5 = 1 as "printer busy/deselected".**

- Before `0063c59`, the bit was a constant 0, which reads as "ready", and that is why the ImageWriter always printed.
- The new code maps the daemon's asserted RTS (pin low) to RR0 CTS = 1, which the ImageWriter driver reads as not ready.
- On the Mac, the printer's DTR reaches the SCC through the HSKi receiver so that "ready" reads 0 in RR0. `rr0_cts_a` should therefore **not** be inverted in this core: `wire rr0_cts_a = cts_s2;` in place of `~cts_s2`.
  - Then an asserting daemon reads as ready, and a daemon that drops RTS (throttle) holds the Mac off.
  - Before the change the pin was not read at all; now it is read but inverted.
- **This is a user-visible regression: with this build, ImageWriter printing through Main's Printer mode does not work at all.**
- **For the StyleWriter:** with the polarity fixed, an open daemon reads the same as the old constant 0. So CTS alone cannot explain why the StyleWriter sent nothing. That part points to the missing status replies on the Main side. This is an inference; no StyleWriter job was run here.

**Side finding: every core load prints a page.**

- Every core load leaves a 92,808-byte `Print_*.pdf` in `/media/fat/printers`: at 02:24:45 for this load, and the same size at 06:56 and 18:17 on 2026-09-29.
- ttyS1 had received 16 bytes by the time of the load, and the PDF is a blank page with one stray glyph.
- The likely cause is the TX line glitching while the FPGA is configured, decoded by the daemon as a job. That is an inference and was not investigated.

## 7. Shut Down

- The vmouse recipe (`shutdown.sh`, with an explicit button-up) reached **"It is now safe to switch off your Macintosh"** at 03:00 UTC (`halt_final.png`; the glyph gaps are described in section 4).
- After that, `write_bytes` was flat at 20,443,136 over 5 s, and no vmouse process was left.

## Box state at the end

| | |
|---|---|
| guest | halted at the safe screen |
| core | `48a23a78` still loaded |
| live settings | Monitor 13in 640x480, Scale Normal |
| UART | Printer at 9600, not saved; the saved setting is still 57600 |
| daemon | running, RTS asserted |
| CFG byte 0 | unchanged, `0x40` |
| disposable disk | two more Photoshop copies (95 items, 832.5 MB free); ImageWriter now on the Modem port |
| `/media/fat/printers` | `Print_2026-09-30_02-48-11.pdf` added |
| hangs / bombs / black screens / reboots | 0 / 0 / 0 / 0 |

## Files

- This directory: the screenshots named above, `confstr_from_main.txt`, `printerd_rx_during_job.txt`, the printed PDF, and the three box-side scripts.
- `scratch/p262_trial_hw_20260929/`: every capture (`run/`, `idle/`, `m512/`, `m640/`, `sd1/`, `final/`), the samplers and the script copies.
