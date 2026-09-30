# Guest disk throughput on the release recipe (2026-09-28)

This is step 0 of `docs/disk-speed-vs-minimig-ao486.md`: disk throughput measured from inside
the guest on the shipped recipe, which has `SCSI_CACHE_OFF` and relies on the write-buffer Main.
All runs are Mac OS 8.1 on the MiSTer, with the ARM side sampled at the same time.

Units: KiB and MiB are from byte counters (1024-based). "kB/s" is file bytes / 1000 per second.

## Results

| measure | result |
|---|---|
| **Speedometer 4.02 PR Disk**, 5 runs | 1.579, 1.623, 1.621, 1.626, 1.625: **median 1.623** (real Quadra 800: 3.443, so we are at **47 %**) |
| **Finder duplicate, Photoshop 3.0.1** (3,958,171 B), 4 runs | 7.0 / 7.2 / 7.0 / 7.06 s: **median 7.0 s = 565 kB/s (552 KiB/s)** file rate. Each byte is read once and written once |
| **Finder duplicate, Illustrator 6.0.1** (5,209,581 B), source not in Linux's page cache | 9.03 s = **577 kB/s (563 KiB/s)** |
| **guest read, sustained** (copy read phase) | **1.55-1.93 MiB/s**; best 0.26 s window 630 KiB = **2.4 MiB/s** |
| **guest write, sustained** (copy write phase) | **0.94-0.98 MiB/s**, steady at 256 KiB per 0.26 s |
| **per 512 B sector** | read **~205 µs** at best and ~275-305 µs sustained; write **~510 µs** |
| SD card served the reads or not | **no difference.** An uncached source (read_bytes = rchar) reads exactly as fast as a cached one, so the card does not limit reads |
| Main's CPU | a busy-poll loop. It uses **one full core all the time**: ~105 ticks/s at idle, 100 % during reads, and 80-90 % during writes, where it sleeps in O_SYNC `write()`. `top` shows 43-54 % because the box has two cores |

## Session and state

- **Core:** release rbf md5 `b7e88b81` (`ad7a0d4`, seed 31, SCSI_CACHE_OFF recipe), running as
  `_Unstable/MacQuadra800.rbf`. The coordinator loaded it at ~19:53 EDT.
- **Main:** `/media/fat/MiSTer` md5 `ff404af92e4aa55116ee61a98941e73b` (has the Mac write buffer).
- **Disk:** slot 0 is the disposable `games/MacQuadra800/QuadSquad8-pipeline-test-20260919.hda`
  (`.s0` checked).
  - Main's fd 5 has flags `06410002` (O_RDWR | O_SYNC).
  - `/media/fat` is exFAT mounted `rw,sync,dirsync`.
  - The master `QuadSquad8.hda` was not touched.
- **RAM:** `.CFG` byte 0 is `0x40`, so 32 MB. Speedometer shows Physical RAM 32768K
  (`speedo_hwinfo.png`).
- **SD card** (`/sys/block/mmcblk0/device`):
  - name `GE4S5`, manfid `0x1b`, oemid `0x534d` ("SM"). That is a Samsung 239 GiB SDXC card made
    05/2023, probably an EVO Plus/Select.
  - It runs as a "high speed" card at a **50 MHz** bus clock (dmesg), so its interface ceiling is
    about 25 MB/s. It is not in UHS mode.
- **Boot:** the Finder was up at 19:53:20 EDT (`finder_up.png`), with no error dialog.

## 1. Speedometer 4.02 Performance Rating

**What the test does:**
- Tests -> Performance Rating... is **Cmd-R** (`tests_menu.png`). Speedometer 4.02 has no separate
  Disk item.
- The setup dialog has CPU, Graphics, Disk and Math checked, Iter. 1. It was left like that on
  every run, because unchecking needs mouse clicks.
- Before the tests start, a file dialog asks "Choose which drive to test. 1 Meg of space is
  required for the temp file." (`pr_drive_dialog.png`). Quad Squad was chosen with OK.
- On the ARM side, the Disk phase is **about 6-7 s**. In it Main reads 5.95 MB (`rchar`) and writes
  4.38 MB (`wchar`), in 124 `write()` calls averaging 36 KiB.
  - So the test writes and re-reads its 1 MB temp file several times.
  - Those totals are the same to 0.02 MB in all five runs (`arm/pr*_arm.txt`).

**Method:**
1. Return dismisses the previous "tests are done" alert.
2. Cmd-R, then a screenshot of the setup.
3. Return, then a screenshot of the drive dialog.
4. Start the ARM sampler.
5. Return to start the tests.
6. Wait 42 s with no input or screenshots, then take the result screenshot.

- Runs 2-5 ran this as `pr_run.sh`. Run 1 did the same by hand, but its sampler window also holds
  four screenshots taken at 30 s intervals *after* the tests had ended.
- The whole PR series finishes in under 30 s.
- Values were read from 2x crops of the result windows.

| run | CPU | Graphics | **Disk** | Math | PR | screens |
|---|---:|---:|---:|---:|---:|---|
| 1 | 0.796 | 1.159 | **1.579** | 21.464 | 1.120 | `pr1_setup`, `pr_drive_dialog`, `pr1_done` |
| 2 | 0.795 | 1.163 | **1.623** | 21.472 | 1.125 | `pr2_{setup,drive,done}` |
| 3 | 0.796 | 1.157 | **1.621** | 21.426 | 1.124 | `pr3_*` |
| 4 | 0.797 | 1.154 | **1.626** | 21.483 | 1.124 | `pr4_*` |
| 5 | 0.795 | 1.159 | **1.625** | 21.417 | 1.124 | `pr5_*` |
| **median** | **0.796** | **1.159** | **1.623** | **21.464** | **1.124** | |

- Every run ended with "The tests are done!" and Iter. 1 on all four rows.
- Run 1 is the low one, as in earlier sessions.
- **Earlier Disk values:**

  | build | Disk |
  |---|---:|
  | `faf9d98` (write-buffer Main) | 1.619 |
  | K2 cache-off, 2026-09-25 | 1.604 |
  | cache on + write-buffer Main | 1.758 |
  | cache on + old Main | 0.568 |
  | real Quadra 800 | 3.443 |

  These are in `docs/DISK_TRACE_20260925.md` and `docs/perf/VS_REAL_QUADRA_20260926.md`.

**Side finding: PR CPU is 0.796.** `31b6e99` measured 0.895 (`VS_REAL_QUADRA_20260926.md`),
and the 2026-09-25 builds 0.891-0.896. That is **-11 %**, while the Benchmark Mix on this same RTL
went *up* (1.803). One boot cannot tell whether this is P250..P258 or the boot-to-boot layout
effect described in `hw_p258_seed31_20260928/README.md`. It deserves a PR run on another boot.

## 2. Timed Finder duplicates

**Files:**
- **Adobe Photoshop™ 3.0** in `Quad Squad:Programs:Adobe Photoshop 3.0:`. It is 3,958,171 bytes,
  "3.7 MB on disk" (`info_photoshop.png`). It was reached with Cmd-R (Show Original) on the desktop
  alias.
- **Adobe Illustrator® 6.0.1**, 5,209,581 bytes (`info_illustrator.png`), reached the same way.
- SimCity2000 (2,778,382 B, `info_simcity.png`) was also over 2 MB, but the larger files were
  used.

**Method:** the file is selected in its folder window and duplicated with Cmd-D
(`down:56 raw:32 up:56`). The script is `dup_run.sh`:
1. Take a screenshot.
2. Start the ARM sampler and eight `top -b -n 1` snapshots at 4 s intervals.
3. Log the MiSTer's `date +%s.%N` together with the keypress.
4. Take the after-screenshot 44 s later.

**Timing:**
- **Start:** the Cmd-D keypress on the MiSTer clock, which matches the local clock to within
  0.25 s.
- **End:** the end of the last `write()` to the image, taken from the sampler.
- **Resolution:** dup1-3 used 1 s samples (`armsample.sh`), so ±0.5 s. dup4-5 used ~0.26 s
  samples (`armfine.sh`), so ±0.15 s.
- The ~0.3-0.5 s from keypress to the first sector is included.
- dup2 also triggered a screenshot about every 2 s. The trigger `curl` blocks for ~1 s, so a
  1 s cadence is not possible.

| run | file | source | sampling | Cmd-D (UTC) | duration | file rate |
|---|---|---|---|---|---:|---:|
| dup1 | Photoshop | partly cached (read_bytes 1.6 of 4.4 MB) | 1 s | 00:09:42.05 | 7.0 s | 565 kB/s |
| dup2 | Photoshop | cached | 1 s + screenshots | 00:12:04.74 | 7.2 s | 550 kB/s |
| dup3 | Photoshop | cached | 1 s | 00:14:02.09 | 7.0 s | 565 kB/s |
| dup4 | Photoshop | cached | 0.26 s | 00:15:46.07 | 7.06 s | 561 kB/s |
| dup5 | Illustrator | **uncached** (read_bytes ≈ rchar) | 0.26 s | 00:18:13.85 | 9.03 s | 577 kB/s |

Screens: `dup{1..5}_{before,after}.png`. Each run leaves "... copy", "... copy 1" and so on in
the folder (`dup1_after.png`). Those copies are on the disposable disk and were left there.

**Guest-visible progress** (dup2, `dup2_shots/`; the names are Main's UTC timestamps):

| screenshot | after Cmd-D | screen |
|---|---:|---|
| 00:12:06 | +1.3 s | no dialog yet |
| 00:12:08 | +3.3 s | "Copy to 'Adobe Photoshop 3.0'", bar about half |
| 00:12:10 | +5.3 s | bar nearly full, "About 5 seconds" |
| 00:12:12 | +7.3 s | dialog gone |
| 00:12:14 | +9.3 s | "copy 1" listed |

Screenshots were not taken during the timed runs, because each one costs Main about a second of
work (see Screenshot cost below).

### The two phases (0.26 s samples, `arm/dup4_arm.txt`, `arm/dup5_arm.txt`)

The Finder reads the file first (in one or two big chunks) and then writes it. The last column of
the sampler, Main's fd-5 offset, shows the source around 41-49 MB into the image and the
destination around 886-894 MB.

| phase | dup4 (cached source) | dup5 (uncached source) |
|---|---|---|
| read | 4,236 KiB in 2.61 s = **1.59 MiB/s** incl. one ~0.4 s pause; full windows 596-647 KiB/0.26 s = **2.3-2.4 MiB/s** | 4,081 KiB in 2.64 s = **1.51 MiB/s**, then 1,544 KiB in 0.8 s = **1.88 MiB/s**; full windows 613-630 KiB/0.26 s |
| write | 3,873 KiB in 4.13 s = **0.92 MiB/s**; steady 256 KiB/0.26 s = **0.96 MiB/s** | ~5,150 KiB in ~5.2 s = **~0.97 MiB/s** |
| `write()` size | 64 calls for 3,958,784 B = **61.9 KiB per call**; the write buffer coalesces into 64 KiB runs | same pattern |

- **Read-only measures:**
  - The read phase is a pure sequential read of 4-5 MB. dup5's source was not in Linux's page
    cache: read_bytes tracks rchar, so the card really was read. Its full-window read rate
    (613-630 KiB/0.26 s) is the same as the cached dup4. So the SD card does not limit reads;
    Main's round trip does.
  - dup1 (partly cached) and dup3 (cached) also have identical read phases at 1 s resolution.
- **Post-copy read-back:** 1.0-1.5 s after the last write of every Photoshop copy, Main reads
  another ~1.45 MB (1484-1501 KiB) at ~1.4 MiB/s.
  - The fd offset shows the reads come from the **just-written copy** (886-889 MB).
  - They happen after the progress dialog closes, so they are Finder or File Manager work, not
    part of the copy.
  - The Illustrator copy had none. They are not counted in the durations.

## 3. ARM side

The sampler columns are `/proc/$(pidof MiSTer)/io` (rchar wchar syscr syscw read_bytes
write_bytes cancelled) plus utime stime from `/proc/PID/stat`, and from dup3 on the fd-5 offset.
Raw files are in `arm/`.

- **Main is a busy-poll loop, not a saturated worker:**
  - At idle it uses 104-106 ticks/s: one whole core. It issues ~11,950 read syscalls/s, which are
    timerfd, input and SPI status polls, not disk reads.
  - **Reading sectors:** CPU stays at 100 %, and syscalls fall to ~5,000/s (1,250-1,330 per
    0.26 s). Each loop pass gets longer while it moves sectors.
  - **Writing:** CPU falls to 80-90 % (17-22 of 26 ticks per 0.26 s), and one `top` snapshot
    caught Main in `D` state. So **~15-20 % of the write phase is Main blocked in O_SYNC
    `write()`** on the `sync`-mounted card. The other 80 % is the per-sector round trip.
- **Speedometer Disk phase:** CPU drops to 80-94 ticks/s and syscalls to ~5,000/s, the same
  signature.
- **`top`** (`arm/dup*_top.txt`): Main shows 43-54 % of the two-core total throughout. Nothing
  else on the box uses measurable CPU.
- **Screenshot cost:** each MiSTer screenshot (`grab.sh` or the API trigger) makes Main write a
  ~65-74 KB PNG to the sync-mounted card. `grab.sh` is followed ~4 s later by a 1.44-1.48 MB
  non-disk read in Main, with syscr going *up*, not down (`arm/idle_grab_arm.txt`,
  `arm/pr1_explore_with_grabs_arm.txt`). Screenshots were kept out of every timed window except
  dup2's.

## 4. Reading

**Throughput:** On the release recipe the guest gets about **1.6-1.9 MiB/s reading** sequentially
(2.4 MiB/s at best), **~0.96 MiB/s writing**, and **~560 kB/s for a Finder duplicate**, which
reads and writes every byte.

**Per-sector round trip:** With `SCSI_CACHE_OFF` every 512-byte sector is one round trip from the
53C96 engine through hps_io to Main and back. The rates above convert to:

| path | per sector | round trips/s |
|---|---:|---:|
| read, best | ~205 µs | ~4,850 |
| read, sustained | ~275-305 µs | ~3,300-3,600 |
| write | ~510 µs, of which ~80-100 µs is Main's share of the O_SYNC 64 KiB writes | ~2,000 |

`docs/DISK_TRACE_20260925.md` traced the same path with an instrumented Main. It found ~110 µs of
SPI per read sector and ~150 µs per write sector, and 100-200 µs between requests. That adds up to
what the guest sees here: about **half of each read round trip is SPI transfer and half is waiting**
(Main's poll gap plus the guest draining the single sector buffer).
- At 512 B per trip, reads could not exceed ~4.4 MiB/s even with zero gap (SPI alone).
- The observed gap costs a factor of ~1.5-2 on top of that.
- Writes pay a larger per-sector gap plus the card.

The SD card is not the limit for reads: uncached reads run as fast as cached ones. For writes,
Main's buffer turns the 512 B writes into ~62 KiB `write()`s, so the card costs only ~15-20 % of
the write phase.

**Against a real Quadra 800:**
- Speedometer's Disk test scores the real machine 3.443 against our 1.623. That is **2.1x our
  throughput on the same test**, with our reads and writes both included.
- A period Quadra 800 moves data from the 53C96 by pseudo-DMA. With the stock 230/500 MB
  drives, sustained sequential rates are usually quoted at roughly 2-3 MB/s. That is not measured
  here, and the disk in the photographed real machine is unknown.
- **So our sequential read (1.6-1.9 MiB/s) is within reach of a period drive. The gap is mainly
  on writes (~1 MiB/s, half the read rate) and on the per-sector turnaround that Speedometer's
  small-transfer mix exposes.**

The levers in `disk-speed-vs-minimig-ao486.md` fit this:
- Its step 2 (command-sized requests) and step 3 (a tight ARM loop per command) both cut the
  per-sector gap, which is the dominant term.
- Its step 4 (overlapping the next sector's fetch with the guest's drain) hides the rest.

**Note on step 0:** it was not completely unmeasured. `docs/DISK_TRACE_20260925.md` has a cache-off
PR Disk (1.604) and a cache-off SimCity2000 copy (5.4 s trace span, ~515 kB/s), which agree with
the numbers here. `docs/PERFORMANCE_MEASUREMENTS.md` still has no disk section.

## 5. Shutdown

1. **Quit Speedometer:** Return, Cmd-Q, then "Save before quitting?". The pointer was placed with
   vmouse `home m:162,129` and checked on **No** (`quit_ptr.png`), then clicked with
   `down 0.3 up`. The Finder came to the front (`quit2.png`).
2. **Pointer check:** `home m:111,-10` put the pointer on Special (`sd_ptr.png`).
3. **Dry run:** `home m:111,-10 0.5 down 0.8 m:13,66 10 m:0,-90 0.5 up`.
   - Shut Down was lit during the hold (`sd_dry_hold.png`).
   - The release happened on the title, so the menu closed with nothing selected
     (`sd_dry_end.png`).
4. **Real run:** `home m:111,-10 0.5 down 0.8 m:13,66 8 up`.
   - Shut Down was lit before the release (`sd_menu_lit.png`).
   - The screen reached **"It is now safe to switch off your Macintosh."** at 00:22:04 UTC =
     20:22 EDT (`halt.png`).
5. **After the halt:**
   - No vmouse process was left.
   - Main's write_bytes held at 57,368,576 across 5 s.
   - Main's only image fd is the disposable `.hda`.
   - The box was left at the halt screen with nothing loaded.

## Files

| file | what |
|---|---|
| `pr_run.sh` | one PR run |
| `dup_run.sh` | one duplicate. As saved it calls `armfine.sh 200`; dup1-3 ran it with `armsample.sh 45` |
| `armsample.sh` | the 1 s sampler (runs on the MiSTer) |
| `armfine.sh` | the ~0.26 s sampler |
| `arm/` | all raw samples |
| screenshots | the `*.png` files, named as above |
