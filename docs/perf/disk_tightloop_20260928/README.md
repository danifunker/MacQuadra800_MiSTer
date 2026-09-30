# Tight-loop Main experiment, 2026-09-28 evening: variant (a) only, and a hang

Release core `b7e88b81`, disposable QuadSquad8 copy, 32 MB, Ethernet OSD option On.
Main variants built in `scratch/mac_main_sdprof_20260928/` (see
`docs/disk-main-path-20260928.md`): (a) `MiSTer_sdprof` (counters only, md5
`1603be2f`), (b)-(e) the tight-loop build at several spin/budget settings. Only
(a) ran; the tight-loop variants are still unmeasured.

## Install mechanism (reusable)

busybox init starts Main from `/etc/inittab` line 21 (`::sysinit:/media/fat/MiSTer &`),
before rcS. `/` is read-only by default. `/media/fat/linux/tl_install_main.sh <binary> "<vars>"`
remounts `/` rw, rewrites the line to
`::sysinit:/usr/bin/env $(cat /media/fat/linux/main_env.txt 2>/dev/null) /media/fat/MiSTer &`,
writes the variables to `main_env.txt`, installs the binary and remounts ro. Main
execs `/proc/self/exe` on a core load, so the environment reaches the core.
Backups on the box: `/media/fat/MiSTer.ff404af9`, `/etc/inittab.orig-20260928`.
Local scripts: `scratch/disk_tightloop_20260928/{reboot_verify.sh,tl_pr.sh,tl_dup.sh,analyze.py}`.

## Boots

Attempt 1: "bus error" over Welcome to Mac OS on the first core boot after the
Main install (the first-boot flake `RESUME-20260927.md:1622` records). A clean
MiSTer reboot and a second boot reached the Finder.

## Variant (a) results, before the hang

| measure | result |
|---|---|
| PR (CPU / Graphics / Disk / Math / PR), 3 runs | 0.896 / 1.118 / 1.526 / 21.432 / 1.176; 0.895 / 1.166 / 1.474 / 21.407 / 1.184; 0.895 / 1.155 / 1.527 / 21.473 / 1.187 |
| Photoshop duplicate 1, 2 | 7.62 s (519 kB/s), 7.38 s (536 kB/s) |
| read / write phase | 1.83-1.89 / 0.96 MiB/s |

PR Disk about 6 % under the `ff404af9` baseline (1.623): the counters cost about
ten `clock_gettime` calls per request. PR CPU 0.895 again, so the baseline
session's 0.796 was a one-boot effect.

sdprof over duplicate 2 (40 s): 9,979 reads, 7,747 writes; 192 us of Main service
per request; SPI 109 us per read sector, 154 per write; pass 110 us average, 46 ms
max; **`mac_poll` 19.06 s of 40 s (48 % of Main's time, about 53 us per pass with
the Ethernet option on)**; 78 write-buffer flushes, 835 ms, max 45 ms; ack-to-next-
request gaps: 0 under 50 us, 5,077 under 100, 6,918 under 200, 5,617 under 500,
113 above.

## The hang (duplicate 3, 01:14 UTC)

Source read completely (3,958,784 B); writes stopped at 2,442,240 B (62 %); the
copy dialog froze at about 85 %; the menu-bar clock stopped; the pointer still
followed vmouse (interrupt level alive), the Finder was stuck; Main kept polling
(pass 99 us) and **never saw another request: the 53C96 engine stopped asking**;
every written byte had been flushed to the card. Screens `dup3_after.png`, log
`sdprof_full_at_hang.log`. The baseline session on `ff404af9` had run five PRs
and five duplicates cleanly, so this is a core-side stall in the write path that a
slightly slower Main service exposed, or an intermittent one. To be reproduced in
the full-machine sim with randomised sector-service latency before the tight-loop
variants are measured further. The original Main and inittab were restored.

---

# Resumed 2026-09-28 21:20-22:45 EDT: variants (b), (c), (d), with a reboot-on-hang rule

**Summary:**
- **Adopt spin 250 µs, budget 2000 µs (c).** It raises PR Disk by about 11 % (1.52 to 1.70) and makes the Photoshop duplicate about 7 % faster (7.34 to 6.80 s).
- **The gain is all on the read side.** Writes stay at about 0.98 MiB/s.
- **(d) gains almost nothing over (c)** and makes Ethernet latency worse.
- **Ethernet only costs the disk path without the loop.** With the Ethernet option Off, (b) gains 0.5 s per copy, while (c) and (d) gain nothing.
- **Two hangs in total.** The write-path hang recurred once in (d). Together with the one in (a) that makes 2 hangs in 19 copies, both after the read phase. So it is not caused by the tight loop.
- (e) was skipped as instructed.

## Setup and procedure

- **Core and disk:** same core `b7e88b81`, the disposable QuadSquad8 copy, 32 MB, CD slot holding `Marathon CD.iso` (idle).
- **Main:** `MiSTer_sdprof_tightloop` (md5 `9be9c37b`) installed with
  `sh /media/fat/linux/tl_install_main.sh MiSTer_sdprof_tightloop "<vars>"`.
  - The vars below end up in `/media/fat/linux/main_env.txt`.
  - Each install was followed by a MiSTer reboot. The running binary's md5 and its `/proc/PID/environ` were checked every time.

  | variant | `main_env.txt` |
  |---|---|
  | (b) | `SDPROF=1 MAC_SD_SPIN_US=0` |
  | (c) | `SDPROF=1` (the defaults: spin 250, budget 2000) |
  | (d) | `SDPROF=1 MAC_SD_SPIN_US=500 MAC_SD_BUDGET_US=4000` |

- **Core load:** `echo load_core /media/fat/_Unstable/MacQuadra800.rbf > /dev/MiSTer_cmd`, with the box at the menu or the halt screen.
- **Ethernet-Off duplicate:** with the guest halted, CFG byte 0 was set from `0x40` to `0x00` (`scripts/ethcfg.sh off`: O[6] Off, RAM bits unchanged). The core was then loaded again, so the option is latched by the load's reset.
  - Off was confirmed on the guest by the ping failing and `eth0` not being promiscuous.
  - Set back to `0x40` afterwards.
- **Per variant:**
  1. Boot and launch Speedometer.
  2. Three PR runs (`tl_pr.sh`).
  3. Quit Speedometer (Cmd-Q, No).
  4. Photoshop alias, then Cmd-R (Show Original), then three timed Cmd-D duplicates (`dups.sh`).
  5. One untimed feel-check duplicate (`feel.sh`).
  6. Finder Shut Down.
  7. Ethernet Off: load, select the original, one timed duplicate, Shut Down, Ethernet On.
- **Timing and counters:**
  - sdprof counters were reset (USR2) right before each measure. The table uses the report at 40 s, which covers the whole measure.
  - Duplicate time runs from the Cmd-D keypress to the middle of the 0.26 s sampler window that holds the last `write()` of the copy (`analyze.py`). The baseline dup4 re-derived this way gives 7.16 s.
- **Scripts:** in `scripts/`. vmouse moves about 1.67 px per count from `home`.

## Results

| | (a) counters only | (b) spin 0 (control) | **(c) spin 250 / budget 2000** | (d) spin 500 / budget 4000 |
|---|---|---|---|---|
| boots to Finder | 2 (first: bus error at Welcome) | 1 | 2 (first: no screenshots, see below) | 1 + 1 after the hang |
| hangs | 1 of 3 duplicates | 0 of 5 copies | 0 of 5 copies | **1** of 6 copies (dup 1) |
| PR Disk | 1.526 / 1.474 / 1.527 | 1.517 / 1.521 / 1.525 | **1.685 / 1.695 / 1.706** | 1.709 / 1.725 / 1.702 |
| PR Disk median | 1.526 | 1.521 | **1.695 (+11.4 %)** | 1.709 (+12.4 %) |
| PR CPU | 0.895-0.896 | 0.895-0.897 | 0.894-0.896 | 0.895-0.896 |
| PR | 1.176 / 1.184 / 1.187 | 1.192 / 1.191 / 1.191 | 1.209 / 1.213 / 1.210 | 1.210 / 1.213 / 1.211 |
| duplicate (first after boot, cold source) | 7.62 s | 7.59 s | 6.83 s | 7.03 s (after the hang reboot) |
| duplicates (warm) | 7.38 s | 7.34 / 7.33 s | 6.80 / 6.59 s | 6.81 / 6.75 s |
| duplicate median of the three, file rate | - | 7.34 s, 539 kB/s | **6.80 s, 582 kB/s (-7.4 %)** | 6.81 s, 581 kB/s |
| **Ethernet Off** duplicate (cold source) | - | **7.10 s** (557 kB/s) | 6.82 s (580 kB/s) | 7.01 s (565 kB/s) |
| read phase, warm (whole phase) | 2.88 s, 1.44 MiB/s | 2.85-2.87 s, 1.44-1.45 MiB/s | 2.60-2.61 s, 1.59-1.60 MiB/s | 2.59-2.60 s, 1.61-1.65 MiB/s |
| read, best 0.26 s window | 2.23-2.29 | 2.23-2.28 MiB/s | 2.59-2.63 MiB/s | 2.58-2.65 MiB/s |
| write phase (whole / median window) | 4.15-4.4 s / 0.96 MiB/s | 4.14-4.40 s / 0.96-0.97 MiB/s | 3.62-3.87 s / 0.97-1.09 MiB/s | 3.85-3.86 s / 0.97-1.00 MiB/s |

PR run 2 of (c) had Math 41.778, the known intermittent Speedometer timer anomaly. It does not touch Disk.

### sdprof over the warm duplicates (40 s windows)

| | (b) | (c) | (d) |
|---|---|---|---|
| requests (read / write) | 7.7-10.0k / 7.7k | 7.7k / 7.7k | 7.7k / 7.7k |
| Main service per request | 189-201 µs | 197-200 µs | 200-204 µs |
| SPI per read / write sector | 108 / 154 µs | 108 / 152-153 µs | 107-108 / 152 µs |
| `file_write_us` per write (memcpy plus forced flushes) | 103-110 µs | 104-108 µs | 113-120 µs |
| mwb flushes (count / total / max) | 75-76 / 0.78-0.84 s / 45-47 ms | 75-77 / 0.83-0.85 s / 46-63 ms | 75-79 / 0.88-0.93 s / 47 ms |
| pass avg / max | 108-110 µs / 46-47 ms | 115 µs / 48-66 ms | 114 µs / 49-50 ms |
| `mac_poll` share of Main time | 47-48 % (Ethernet Off: 42 %) | 46 % (Off: 40 %) | 45-46 % (Off: 40 %) |
| gap hist <50 / <100 / <200 / <500 / <1000 / <2000 / >=2000 µs | 0-3 / 4.3-5.2k / 6.2-7.4k / 4.8-5.3k / 15-32 / 16-32 / 73-98 | 1 / **6.5k** / 6.7-6.9k / **1.9-2.2k** / 6-29 / 15-28 / 72-89 | 0-2 / **6.8-6.9k** / 6.8-7.0k / **1.6-1.8k** / 2-19 / 17-29 / 77-86 |
| gap_avg (includes idle gaps, see note) | 375-395 µs | 337-372 µs | 351-381 µs |
| tl_hits / tl_waits | - | 13.6k / 13.9k (98.2-98.5 %) | 14.5k / 14.5-14.6k (99.7 %) |
| tl_wait per wait (= the guest's own drain/fill time) | - | **111 µs** | **112 µs** |
| tl_budget_exits | - | 1,613-1,628 | 946-958 |

Over the PR runs the picture is the same:
- (b): gap hist 3.6k / 7.9k / 4.4k in the <100 / <200 / <500 buckets.
- (c): 6.0k / 8.3k / 1.5k.
- (d): 6.3k / 8.5k / 1.1k.
- tl hit rate 97-98 % (c) and 97.5 % (d). The misses are about one per SCSI command, as expected.

**How to read gap_avg:** the ≥2 ms bucket also collects the pauses between SCSI commands and the Finder's pauses, so gap_avg moves little (about 10 %). The histogram shows the effect directly: the tight loop moves about 3,000 gaps per copy out of the 200-500 µs bucket into the 50-100 µs one.

### Ethernet-Off duplicate: how much of the turnaround is the Ethernet poll

The Ethernet-Off copies were the first copy after a boot (cold source). So compare them with the cold first duplicates:

| variant | Ethernet On (cold) | Ethernet Off (cold) | change |
|---|---|---|---|
| (b) | 7.59 s | 7.10 s | **-0.49 s (-6.5 %)** |
| (c) | 6.83 s | 6.82 s | none |
| (d) | 7.03 s | 7.01 s | none |

- **Without the tight loop, the Ethernet poll costs about half a second per 4 MB copy.** It sits in front of every sector's next pass.
- **With the loop, the disk streams without going back through `mac_poll`,** so Ethernet costs the disk nothing.
- **`mac_poll` is mostly not Ethernet:** it is still 40-42 % of Main's time with Ethernet Off, and pass_avg only drops from 108-115 to 96-101 µs.
  - The rest is the CD, cdchanger and Toolbox polls, with a CD image in slot 4.
  - This matters for any other per-pass latency, but no longer for disk streams under the tight loop.

## Feel checks (one untimed duplicate per variant)

**Ping from the build host to the guest** (10.3.231.233, MAC `08:00:07:05:06:07`) at 0.2 s intervals during the copy:
- (b): median 1.93 ms, p90 4.8, max 243.
- (c): median 1.51, p90 5.1, max 221.
- (d): median 1.91, p90 **12.7**, max 162.
- Idle: 1.5-2.0 ms. No loss in any variant.
- The 160-240 ms maxima coincide with the mid-copy screenshot, which blocks Main for about a second in all variants.
- **(d)'s 4 ms budget shows in the p90; (c)'s 2 ms budget does not.**

**Ping from the MiSTer itself does not work** (100 % loss): the guest is bridged on the MiSTer's own `eth0`.

**Mouse:** the pointer followed a vmouse move made during the copy in all variants, with the copy dialog still up (`*/feel_during.png`).

**Keyboard:** a type-select key sent during the copy never reached the list window in any variant, including (b). The Finder's copy dialog is in front, so this does not measure latency. Keyboard latency during a copy was therefore not measured.

**Input-latency proxy (pass_max over a copy, no screenshots):** 46-66 ms in every variant, including the (b) control. It is the O_SYNC 64 KiB write-buffer flush (`mwb_flush_max` 45-63 ms), not the tight-loop budget. The budget adds at most 2-4 ms per pass on top of that. OSD and keyboard latency are unchanged in practice.

## Hangs and oddities

- **(d) duplicate 1, 02:21:14.5 UTC (22:21 EDT), 3.3 s after Cmd-D:**
  - The source was read completely (3.98 MB). Writes stopped after 78 sectors (39,936 B, all flushed). The dialog stayed at about 50 %.
  - The clock was frozen, the pointer alive (watch cursor), and Main saw no request.
  - This is the same signature as (a)'s hang: a write-phase stall with the engine not asking.
  - `d/dup1_hang.png`, `d/sdprof_full_at_hang.log`.
  - Recovery: clean MiSTer reboot, core reloaded, "not shut down properly" notice dismissed, no disk-check dialog, and the run continued. A 4th duplicate replaced the hung one.
- **Hang count:**
  - (a): 1 of 3 copies.
  - (b): 0 of 5.
  - (c): 0 of 5.
  - (d): 1 of 6.
  - The one hang with no tight loop at all, (a), rules the loop out as the cause. The rate on this core and disk is about 1 in 10 copies under these Mains. The 20:00 EDT `ff404af9` session ran 5 copies and 5 PRs clean.
- **(c) first boot, 01:45 UTC:**
  - Main took no screenshots at all: API and `/dev/MiSTer_cmd` both silent, no file written.
  - That boot's `pass_max` was 336 ms, against 18-25 ms on every other boot.
  - The guest booted normally (49k reads). I shut it down blind with the vmouse Shut Down recipe; the disk counters showed the shutdown signature and the next boot had no unclean-shutdown notice.
  - Rebooted the MiSTer; the second (c) boot was normal.
  - Cause unknown. Main's frame callbacks (which run the screenshot) apparently never fired. Worth watching, because a 336 ms pass at core start could also upset video setup.
- **Boot bombs:** none after (a)'s first boot.
- **After the final restore reboot, wlan0 (10.3.89.233) did not come back** within 10 minutes. The box is up on `eth0` 10.3.164.251: it answers ping, the mrext API reports no core running, and its screenshot shows the menu.

## What remains of the per-sector cost

With the Main-loop turnaround gone (98-99.7 % of next requests caught by the spin), one sector costs:

**Reads, about 230 µs per sector** (best windows 2.6 MiB/s, about 190 µs):
- about 108 µs SPI (`SECTOR_RD`, 256 GPO words);
- about 110 µs waiting for the guest to drain the 512-byte `sbuf` by PDMA and the engine to raise the next request (`tl_wait` per hit);
- about 10 µs of status reads and bookkeeping.

The two halves are serial, because the engine has one sector buffer.

**Writes, about 500 µs per sector, unchanged by the loop:**
- about 152 µs SPI (`SECTOR_WR`);
- about 105-120 µs of O_SYNC card time amortised per sector: 64 KiB runs at about 11 ms each, which block Main;
- the guest's fill time.

The loop removes neither, so the write phase stays at 0.97-1.0 MiB/s.

**Next levers, in order of what they would buy:**
1. **Overlap the SPI with the guest's drain/fill** (a ping-pong `sbuf` in `ncr53c96.sv`). This hides the 110 µs.
2. **Flush the write buffer from a worker thread**, so the O_SYNC write does not stall the SCSI service.
3. **Cut the per-sector SPI cost:** command-sized requests, or the DDR3 mailbox (`docs/scsi-ddr3-disk-plan.md`), which moves the 108/152 µs to DMA.

Against a real Quadra 800 (PR Disk 3.443), (c) is at 49 %.

## Box state at the end

- `/media/fat/MiSTer` restored from `MiSTer.ff404af9` (md5 `ff404af9` checked on disk before the reboot).
- `/etc/inittab` restored from `/etc/inittab.orig-20260928` (`cmp` clean), `/` remounted ro, `main_env.txt` deleted.
- CFG byte 0 back to `0x40` (Ethernet On, 32 MB).
- Rebooted; the MiSTer menu is up (screenshot over `eth0`). The running process's md5 could not be re-read over ssh while wlan0 is down.
- Left on the box: `MiSTer.ff404af9`, `MiSTer_sdprof`, `MiSTer_sdprof_tightloop`, `/media/fat/linux/tl_install_main.sh`, `/etc/inittab.orig-20260928`.
- The disposable disk holds about 20 more Photoshop copies plus two partial ones from the hangs.

Files: per-variant `b/`, `c/`, `d/` (sdprof lines, samplers, logs, pings, `pr_all.png` crops, feel screenshots), and `scripts/`.
