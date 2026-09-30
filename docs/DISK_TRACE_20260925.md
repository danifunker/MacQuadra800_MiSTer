# Disk channel trace, 2026-09-25: where the Quadra 800's disk time goes

Core: the timing-clean full-feature build (`a0b3072`, RBF md5 46b85dcc).
Main: `../Mac_Main_MiSTer` branch `mac-disk-trace` (`7f158ba`, on the
Quadra fork `0cb45be`), which adds an opt-in per-request log of the sector
channel to `user_io.cpp` (`touch /tmp/mac_disk_trace` turns it on; records go
to `/tmp/mac_disk_trace.csv`).  For each request it logs the slot, the
operation, the LBA and block count, the SPI transfer time, and the file I/O
time before and after the acknowledge.  Raw traces and the summarizer are in
`docs/perf/disk_trace_20260925/`.

(Kernel uprobes on libc were tried first and abandoned: the MiSTer's glibc is
Thumb code, which ARM uprobes cannot single-step.  The `lseek64` probe broke
`lseek` system-wide.  All probes were removed before any guest disk I/O.)

## Results

| workload | requests | data | Main time in the service | notes |
|---|---|---|---|---|
| cold boot to Finder (56 s) | 10,942 reads (all 8 x 512 B), 78 writes | 44.8 MB read, 40 KB written | 12.2 s | reads: SPI 837 us per 4 KB (**~4.9 MB/s**), file read 61 us median (page cache), 26 % Main-buffer misses |
| Finder duplicate of SimCity2000 (2.8 MB) | 910 reads, **1,894 writes (1,386 single-sector, 508 x 8)** | 3.7 MB read, 2.8 MB written | 11.2 s of a 12 s write phase | **writes: 3.8 ms median each, p95 9.3 ms**; 91 % continue the previous write's LBA; **~250 KB/s** |

- **Writes are the bottleneck.** `/media/fat` is mounted `sync,dirsync`
  (and images are opened `O_SYNC`), so every `write()` completes on the SD
  card.  That costs ~4 ms per call almost regardless of size.  The earlier
  host test measured 3.97 ms for 512 B, 3.77 ms for 4 KB and 4.45 ms for
  16 KB.  A sequential copy therefore runs at (call size) / 4 ms: 130 KB/s
  in single sectors, 1 MB/s in 4 KB, 3.6 MB/s in 16 KB.
- **The core flushes in small pieces.** `scsi_cache.sv` writes a wholly
  dirty aligned 8-sector group as one request.  A partly dirty group goes out
  one sector at a time once the engine has been quiet for 4,096 clocks
  (~120 us).  Mac OS's File Manager writes in short bursts separated by
  more than that, so 73 % of the copy's write requests were single sectors,
  although 91 % of them extended the previous write.
- **Reads are near the channel limit.** SPI moves 4 KB in ~837 us, about
  4.9 MB/s, which is already in the range of a real Quadra 800's internal
  SCSI disk.  Main's 16 KB read-ahead buffer serves three of every four
  8-block reads, and file reads are fast (page cache).

## What would help, in order

1. **Fewer, larger write calls.**  Two places can coalesce:
   - **In Main:** accept a write into a RAM buffer, extend it while the
     following writes are contiguous, and issue one `write()` of up to
     16-64 KB when the run breaks, the buffer fills, or the channel has
     been idle for a few ms.  Reads of a buffered range must be served from
     the buffer.  This needs no FPGA change, so it leaves the timing-clean
     bitstream alone.  Durability is the same kind of trade the core's
     write-behind cache already makes (the guest's write is acknowledged
     before it reaches the card).  Every buffered write must be flushed
     before shutdown or unmount.
   - **In the core:** flush contiguous dirty runs (not only whole aligned
     groups) as one multi-block request, and wait longer before flushing a
     partial run.  This is simpler, but it changes the fitted design, whose
     CPU clock margin is 7 ps.
2. **The mount option.**  A `sync` mount is a MiSTer-wide choice meant to
   protect the card on power loss.  Changing it is not this core's call.

Expected gain for writes: from ~250 KB/s towards 2-3 MB/s on sequential
copies, i.e. about 10x.  The Speedometer Disk rating (0.59 against the real
machine's 3.44) should move with it; that is the before/after benchmark to
run.

## The Main write buffer: result (2026-09-25 evening)

Branch `mac-disk-writebuffer` on `alanswx/Main_MiSTer` (`59ed66e`).  It is
based on `alan/master` (Quadra 800 + Ethernet + printer), carries the trace
commit, and adds a write buffer in `user_io.cpp`:

- **Scope:** the Mac SCSI family's hard-disk slots only.
- **Buffering:** up to eight runs of up to 64 KB per slot.  A write that
  continues a run is appended to it; a write inside a run updates it in
  place; a write that partly overlaps a run flushes that run first.
- **Flushes:** a run reaches the card as one `write()` when it fills, when
  all eight runs are in use (least recently used first), before any file
  read that could overlap it, after 20 ms without writes (all runs, in LBA
  order), on remount, and before Main restarts for a core load.
- **Host test:** `support/mac/mac_wbuf_test.cpp` checks the logic against a
  reference image.  It found one bug (an extension overlapping another
  run), which is fixed; six seeds now pass with zero mismatches.

Same core (`a0b3072`), same disposable disk, only Main changed:

| | Speedometer PR Disk | PR | 2.8 MB Finder copy: write phase | Main time in `write()` |
|---|---|---|---|---|
| old Main (`d5b50fc4`) | **0.568** | 0.918 | ~11 s (~250 KB/s) | 9.6 s |
| write buffer, one run | | | ~4.5 s | 3.2 s |
| **write buffer, eight runs** | **1.758** | **1.174** | **~3.3 s (~850 KB/s)** | 1.65 s |

CPU (0.891 / 0.894), Graphics and Math are unchanged, as expected.  The real
Quadra 800 reference is Disk 3.443.

Integrity: after a clean shutdown and a menu-core load, the image was copied
to the host and read with machfs (`hfs_compare.py`; hfsutils cannot open
this volume, and fails the same way on the pristine image).  Three Finder
copies of SimCity2000 were compared with the original: one with the old
Main, one with a one-run buffer, one with the eight-run buffer.  All three
match it byte for byte through the whole 2.78 MB resource fork, except
bytes 48-95 of the resource-file header.  The Finder rewrites that reserved
area on every copy, and it differs identically in the old-Main copy.

What is left: the core still flushes mostly single sectors (Main now
absorbs them), and SPI moves ~4.9 MB/s.  The next steps would be larger
flushes from `scsi_cache.sv` (an FPGA change) or relaxing the sync mount.

## The SCSI block cache off, with the write-buffer Main (2026-09-25 night)

The timing-clean recipe (`a0b3072`) with `SCSI_CACHE_OFF=1`.  Variant K2 also
restores the 16+16 KB CPU caches (`SETW = 8`), using the M10K the SCSI cache
freed.  Scratch projects are `scratch/fitK1_cacheoff`, `fitK2_*`.

| build | ALMs (fit) | M10K | CPU | HDMI | SDRAM | result |
|---|---|---|---|---|---|---|
| timing-clean baseline (`a0b3072`) | 38,329 | 509 | +0.007 | +0.044 | +0.082 | met |
| K1: cache off, seed 21 | 37,738 | 469 | −1.167 | +0.210 | +0.779 | missed |
| K2: cache off + 16 KB CPU caches, seed 21 | 37,616 | 485 | −0.925 | +0.241 | +0.403 | missed |
| K2 seed 22 | 37,563 | | −0.832 | +0.108 | +0.392 | missed |
| **K2 seed 23** | **37,532** | **485** | **+0.360** | **+0.290** | **+0.583** | **met**: every setup, hold (min +0.203), recovery and removal; crossings +0.597 / +0.360 |
| K2 seed 24 | 37,597 | | | | | Quartus failed |

K2 seed 23 on hardware (RBF md5 `cdd92e98`, write-buffer Main `3dd49cd2`):

- **Speedometer Mix: 1.667, 1.684, 1.685, 1.684, 1.684; median 1.684.**
  The timing-clean baseline had a median of 1.670.  Whetstones rose to 6.14
  from 6.06, because the 16 KB data cache is back.
- **Performance Rating: Disk 1.604, CPU 0.896, Graphics 1.115, Math 20.978,
  PR 1.183.**  K2 seed 21 gave Disk 1.555.  With the cache (and the same Main)
  Disk was 1.758; with the cache and the old Main it was 0.568.
- **Finder copy of SimCity2000:** the trace spans 5.4 s without the cache
  against 5.7 s with it.  Everyday copies do not need the cache any more.

Without the cache, the SCSI engine asks Main for one 512 B sector per request:
~110 us of SPI for a read, ~150 us for a write, and ~100-200 us between
requests.  Main serves 96 % of the reads from its 16 KB read-ahead and
absorbs the writes in its buffer.  Only Speedometer's Disk test, which is
dominated by small reads, notices the difference (about −10 %).

**Caveat:** this depends on the write-buffer Main.  With an old Main every
engine write waits the ~4 ms synchronous card write, so the cache must stay
on for anyone who does not have the new Main.

**The pipeline back in the freed room: does not route.**  `fitP1_pipe_cacheoff`
is the cache-off recipe with 8 KB CPU caches and all eight pipeline macros
on.  It synthesizes to 38,139 ALMs and places at 39,323 (94 %, 4,161 / 4,191
LABs, peak vertical interconnect 96.4 %).  The router then fails ("Can't fit
design in device"), the same wall fit A hit at 39,626.  Turning the SCSI cache
off buys ~800 ALMs; the pipeline needs ~1,700 plus routing slack.  Returning
it needs about another 1,500 ALMs out first.
