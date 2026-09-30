# Why our hard disk is slow: comparison with Minimig and ao486

Written 2026-09-24 as a read-only survey. No code was changed. Sources:
`MiSTer-devel/Minimig-AGA_MiSTer` and `MiSTer-devel/ao486_MiSTer` (shallow
clones of master, 2026-09-24), `../Mac_Main_MiSTer`
(`mac-ethernet-pr-with-SCSI-Optimizations-with-q800-eth`), and this tree at
`83177c7`.

## Short answer

1. **The wire is the same.** Minimig and ao486 move disk data over hps_io's
   `EXT_BUS` "DMA" commands (`UIO_DMA_WRITE` 0x61 / `UIO_DMA_READ` 0x62).
   On the ARM side those are `fpga_spi_fast_block_write/read`. Our hps_io
   sector path (`WIDE=1`) calls `spi_block_write/read`, which in
   `spi.cpp:200-210` call **the same two functions**. It is the same 16-bit GPO
   bit-bang at the same speed. Moving to `EXT_BUS` would not speed anything up
   by itself.
2. **The protocol is where they win.** Their data transfers are per command,
   not per sector. The ARM gets the whole ATA command (LBA and count), reads
   up to 8 KB per `FileReadAdv`, and **stays in a tight loop until the
   command is finished**. It does not go back through Main's main loop between
   chunks. The guest reads a 16 KB dual-port buffer at bus speed, and in "fast
   read" mode it can start before the ARM has finished filling the buffer.
3. **The build on the box right now uses the slowest path we have.**
   `MacQuadra800.qsf:425` sources `configs/cpu_development.tcl`, and that file
   sets **`SCSI_CACHE_OFF=1`** (commit `479d914`, added for P232's routing
   room). With that set, `rtl/quadra800.sv:226` wires the 53C96 engine straight
   to hps_io:
   - one 512-byte block per Main round trip;
   - no read-ahead;
   - no write-behind;
   - one O_SYNC SD-card write per 512 bytes.

   The engine also has a single sector buffer and fetches the next sector only
   after the guest has drained the current one (`rtl/ncr53c96.sv:842-844`).
   So every sector costs a full Main poll wait plus the guest drain, one after
   the other with no overlap. This is the behaviour `docs/scsi-block-cache.md`
   was written to get rid of.

   **Do this first:** get a disk-throughput number on a build with the cache
   in, before redesigning anything. The RESUME already suspects this switch
   for P232's Puzzle −25.8 % / Int. Matrix −11.1 %
   (`RESUME-cpu-speed-20260923.md:149`).

## How Minimig and ao486 do it

Both cores use **the same `ide.v`** (Sorgelig, 2020). A `diff` of
`Minimig-AGA_MiSTer/rtl/ide.v` against `ao486_MiSTer/rtl/soc/ide.v` shows no
differences. The ARM side is Main's shared `ide.cpp` / `ide_cdrom.cpp`, which
is also used by PCXT and Archie.

### FPGA side (`ide.v`, ~300 lines)

- ATA task-file registers only: features, count, LBA, drive, command,
  status, error. There is no protocol state machine beyond "command pending"
  / "data pending" / "reset", reported on a 3-bit `request`.
- A **16 KB data buffer**: two `dpram #(12,16)` halves, one for each 16-bit
  lane.
  - The guest port is `io_*`: 16- or 32-bit PIO at `io_address` 0, one access
    per bus cycle. ao486 does `rep insw/insd`. The Amiga's 68020 reads it
    through `fastchip`, on the 114 MHz CPU clock.
  - The ARM port is `mgmt_*`, driven from hps_ext's 0x61/0x62 stream.
- `blk_size` is set by the ARM for each chunk, so a single DRQ phase can
  cover many sectors.
- **Fast read** (`use_fast=1` in both cores, `ide.cpp:145/795`): the ARM
  writes the status registers (DRQ on) **before** it pushes the data. The
  guest starts reading straight away. `no_data` holds the guest's bus (Gayle
  `nrdy`; ao486 `ide0_nodata`) whenever its read pointer catches up with the
  ARM's write pointer (`mgmt_cnt <= io_cnt`). The SPI push and the guest's
  copy overlap.

### ARM side (`ide.cpp`)

- `process_read()` (`ide.cpp:772-828`):
  1. Seek once.
  2. `FileReadAdv` up to `spb` sectors (default **16 = 8 KB**; READ MULTIPLE
     can raise it; buffer `ide_io_max_size` = 32 sectors = 16 KB).
  3. Push the chunk.
  4. Read the **next chunk while the guest drains**.
  5. Spin on `while (!ide_req) ide_req = ide_check()` until the core asks
     for more.

  The whole command runs inside one call. Main's other work (input, video,
  OSD, Ethernet) does not run between chunks.
- `process_write()` is the mirror image: up to 16 sectors per
  `FileWriteAdv`. The image is opened `O_RDWR | O_SYNC` (`ide.cpp:109`), the
  same as ours (`user_io.cpp:2209`), but that is **one sync write per 8 KB**
  against our one per 512 B with the cache off (4 KB with it on).
- Read-ahead comes from Linux's page cache. There is nothing clever on the
  FPGA side.

### Per-command cost

| | Minimig / ao486 | Quadra 800, cache off (current dev build) | Quadra 800, cache on (release recipe) |
|---|---|---|---|
| Wire | EXT_BUS 0x61/0x62, 16-bit GPO | hps_io sector, 16-bit GPO (same functions) | same |
| Unit per ARM transaction | up to 8 KB (16 KB max) | **512 B** | 4 KB aligned groups (8 blocks) |
| Main-loop passes per 64 KB read | ~1 (tight loop inside `process_read`) | **~128** | ~16, of which up to 4 per poll (`user_io.cpp` `for (i<4)`) |
| Read-ahead | Linux page cache + next chunk read during drain | Main's 16 KB `buffer[disk]` only | FPGA prefetch 2 groups ahead + Main's 16 KB buffer |
| Write | 8 KB per O_SYNC write | **512 B per O_SYNC write**, guest waits | acked from M10K in ~25 µs; 4 KB flush behind |
| Overlap of ARM push and guest copy | yes (fast read + `no_data` stall) | none (one `sbuf`, next fetch after drain) | yes (cache hits at 3 cycles/word) |
| Guest bus side | 16/32-bit PIO from a dpram | 53C96 FIFO, PDMA bytes, ROM polls DREQ every 16 bytes | same |

## What this means for us

The guest side has to stay SCSI. The Quadra 800 has no IDE, and the ROM and
A/UX's `c94` driver talk to a 53C96. So "use their interface" really means
"use their **ARM/FPGA division of labour**". That can be done without changing
the transport. Suggested order:

0. **Measure.** Nobody has recorded a disk-throughput number for this core.
   `docs/PERFORMANCE_MEASUREMENTS.md` has no disk section.
   - Guest side: time a large Finder copy, or a disk benchmark, on the
     release recipe (cache on) and on the dev profile (cache off).
   - ARM side: there is ready-made instrumentation in the **uncommitted**
     working tree of `../Main_MiSTer`: `sdprof` in `user_io.cpp`, enabled
     with the `SDPROF` env var. It records the poll gap, request-size
     histograms, cache hits/misses, and file/SPI time. Porting it to the Mac
     fork would show whether the time goes to Main-loop latency, SD I/O or
     SPI.
1. **Keep the block cache in anything that runs guest disk I/O.** The cheaper
   alternatives are `CACHE_TINY` (16/16 sectors, 24 M10K), or cache on with
   `VIDEO_512_OFF`. `SCSI_CACHE_OFF` is the pre-2026-09-07 path.
2. **Command-sized requests (the `ide.cpp` idea, core side).** The engine
   knows the whole READ/WRITE length (`blocks_left`). Right now the cache
   guesses with fixed 8-block groups and a 2-group prefetch. Instead, pass
   `min(blocks_left, 32)` as `sd_blk_cnt`:
   - `hps_io`'s field is 6 bits, and Main clamps to `UIO_BUFFER_SIZE` =
     16 KB (`user_io.cpp:3361`).
   - Demand fetches and write flushes then match what the guest asked for.
   - Writes get 16 KB per O_SYNC write instead of 4 KB.

   Cost: the cache's group logic and window size (32 sectors per disk with
   `CACHE_SMALL`).
3. **Tight loop on the ARM (the `ide.cpp` idea, Main side; no RTL).** In
   `mac_sd_service` for disk slots 0/1 of `is_mac_scsi_optimized()`, after
   serving one request, keep polling `UIO_GET_SDSTAT` for a few hundred µs
   for the next request on the same slot before returning to the scheduler.
   This is what `process_read`'s `while (!ide_req)` does. The generic loop
   already takes up to 4 requests per poll, but only if the core has raised
   the next one by the time the ARM looks again.

   This is cheap to try and easy to measure with (0). Watch the effect on
   input/OSD latency and on `mac_eth_poll`, which share the poll coroutine.
4. **Overlap in the engine (only if the cache stays off).** Minimig's fast
   read hides the SPI push behind the guest's copy. The engine could do the
   same with a two-sector ping-pong `sbuf`: fetch sector n+1 while the guest
   drains sector n. That costs one more M10K. The cache already does this
   job, so this only matters if the cache is dropped for good.
5. **Guest bus side: probably not the bottleneck, but not measured.** The ROM
   moves 16 bytes per DREQ/flags poll through the PDMA window, and each long
   beat is 4 one-byte handshakes in `iosb.sv` `A_SDMA`. That is how the real
   IOSB/53C96 work, so it bounds us near real-Quadra speed. A full-machine sim
   trace of cycles per 512-byte sector (engine `sbuf` drain to last PDMA
   beat) would settle it before anyone optimizes it.

Not recommended:
- **Switching to `EXT_BUS`/`UIO_DMA`.** It is the same wire, and hps_io
  already delivers multi-block transfers. The only reason to switch would be
  to move the SCSI target's protocol onto the ARM, as `ide.cpp` does. That
  rewrite is the direction `docs/scsi-hps-offload-plan.md` already takes for
  the CD-ROM, and the plan says the disks stay in RTL for good reason.
- **A per-core copy of `ide.cpp`.** It speaks ATA, and the 53C96 contract
  is what the ROM and A/UX validated.

## File pointers

- Minimig: `rtl/ide.v`, `rtl/gayle.v:144-201`, `rtl/fastchip.v:211-241`,
  `hps_ext.v` (0x61/0x62/0x63 and `ide_req`).
- ao486: `rtl/soc/ide.v` (identical to Minimig's), `rtl/hps_ext.v:47-103`,
  `rtl/system.v:567,599` (`use_fast(1)`).
- Main: `ide.cpp:58-75` (`ide_sendbuf/recvbuf`), `:772-828`
  (`process_read`), `:830-880` (`process_write`); `fpga_io.cpp:732-760`;
  `spi.cpp:200-210`; `user_io.cpp:3300-3700` (the generic sector loop that
  our hard disks go through, with `mac_sd_service` at `:3456`).
- Ours: `rtl/quadra800.sv:207-260` (cache switches), `rtl/scsi_cache.sv`,
  `rtl/ncr53c96.sv:842-848` (single-buffer fetch), `rtl/iosb.sv:1170-1265`
  (PDMA beat), `configs/cpu_development.tcl:16`.

## Follow-up (same day): transfer primitives, other SCSI cores, DDR3

### `spi_block_*` vs `fpga_spi_fast_block_*`

`spi_block_write/read(buf, wide, sz)` (`spi.cpp:200-210`) is a thin wrapper:

- with `wide` set, it calls `fpga_spi_fast_block_write/read(buf, sz/2)`, one
  16-bit word per strobe;
- otherwise it calls the `_8` variants, one byte per strobe.

`fpga_spi_fast_block_write` (`fpga_io.cpp:732`) is two GPO register writes
per word: data, then data | `SSPI_STROBE`. The read loop is unrolled by 16.

Both `ide_sendbuf` and our `UIO_SECTOR_RD` frame the transfer on the IO
channel (`EnableIO()`), then run the same loop. The only difference is the
header: `UIO_DMA_WRITE` + register address versus `UIO_SECTOR_RD | ack`. The
Atari ST's `memory_write` is slower: it calls `spi_w()` once per word, not
the fast loop.

### Other (non-Mac) cores with SCSI-class disks

- **Atari ST (ACSI)**, `support/st/st_tos.cpp:152`: the SCSI command set
  (READ/WRITE 6/10, INQUIRY, sense, capacity) runs entirely on the ARM. For a
  READ(10) the ARM loops over the whole transfer:
  1. `FileReadAdv` up to 128 sectors (64 KB);
  2. `memory_write`s the chunk straight into ST RAM through the core's DMA
     port;
  3. repeats until the transfer is done;
  4. sends one `dma_ack`.

  One ARM visit covers one command, and the core sees no sector
  handshakes at all.
- **NeXT** (`support/next`, the fork only): Ethernet via a DDR3 window;
  nothing disk-specific was found.
- No SCSI in Minimig, ao486, PCXT or Archie; all of these use `ide.cpp`.

### Cores that use DDR3 for disk or media data

- **C64 G64 (`71c4946`, `support/c64/c64.cpp:421-436`, `:568`)**: at mount,
  the ARM `shmem_map`s `0x30000000` (+2 MB per drive) and `FileLoad`s the
  **whole image** into DDR3. D64 images are expanded to a G64 there. The 1541
  then fetches tracks from DDR3 itself, without hps_io. Writes are flushed
  back through hps_io in the background. The comment lists the gains:
  non-blocking reads and writes, seek timing, and no C64/drive desync.
- **N64DD** (`n64.cpp:1700/2568`): the whole disk is loaded into DDR3.
- **Saturn CD** (`saturncdd.cpp:1275`) and **MD+** (`mdplus.cpp:342`): data
  buffers in a shared DDR3 window.
- **Mac fork already**: `mac_eth.cpp:846` maps `ETH_DDR_BASE` 0x1FF00000, and
  `MacQuadra800.sv:905-1010` already has a DDRAM port (ROM, Ethernet window;
  `DDR_ETH_BASE`, `DDR_ROM_BASE`, `DDR_RAM_BASE`). Main-side mmap and
  core-side DDR arbitration both exist.

### What DDR3 could do for our disks

Two shapes, in increasing ambition:

1. **A DDR3 sector window instead of GPO transfers.** The ARM memcpys each
   request's sectors into a DDR3 ring with `mmap`, and the doorbell/ack
   stays on hps_io. This removes the bit-bang cost: two GPO writes per 16-bit
   word, not yet measured, so check `sdprof.main_to_fpga_ns` first. It
   **does not remove the Main-loop latency**, which with the cache off is
   likely the bigger term. Only worth it if the profile shows SPI time
   dominating.
2. **The image resident in DDR3, C64-style.** Load or `mmap` the `.hda` at
   mount. `scsi_cache` (or the engine) then reads sectors straight from DDR3,
   at microseconds per sector with no ARM on the read path. Writes go to DDR3
   *and* are written back through hps_io behind the guest, which is the same
   write-behind contract `scsi_cache` already has.
   - Constraint: the FPGA-visible DDR3 region is ~512 MB
     (0x20000000-0x3FFFFFFF), already shared with the scaler framebuffer, our
     ROM/RAM/Ethernet windows and so on. A 60-500 MB image may fit; multi-GB
     images will not, so this needs a fallback to today's path.
   - Risks: mount time (loading hundreds of MB from SD), and dirty data in
     DDR3 at power-off. That risk is the same class as today's cache, but the
     window is much larger, so the flush has to be prompt and ordered.
   - Area: a DDR3 client plus a writeback queue, in place of most of
     `scsi_cache`'s 40 M10Ks. It is probably area-neutral or better, but that
     needs a `--check` to confirm.

Either one should wait for the measurement in step 0 above.
