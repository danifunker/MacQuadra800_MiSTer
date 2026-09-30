# The Quadra 800 disk path through Main, 2026-09-28

Step 0 (ARM side) of `docs/disk-speed-vs-minimig-ao486.md`, plus a prepared
step 3.  Read-only on the repos: nothing was committed, nothing was run on
the MiSTer.  Main is `../Mac_Main_MiSTer` at `b4192cd` (branch
`mac-printer-fujinet`; its `bin/MiSTer` is md5 `ff404af9`, the binary on the
box).  Line numbers below are in that tree unless a path says otherwise.
Core at `ae0ce07`.

## 1. The request path today

### What the core asks for (release recipe, `SCSI_CACHE_OFF=1`)

- `MacQuadra800.qsf:558` sets `SCSI_CACHE_OFF=1`, so `rtl/quadra800.sv:233-246`
  wires the 53C96 engine straight to hps_io, with no block cache.
- **The block count for a disk is always 1.** `rtl/quadra800.sv:241` passes a
  count only for a CD-slot read (`e_io_rd[2]`). `rtl/ncr53c96.sv:258` gives a
  count only for the CD-audio engine's frame fetch (`eng_owns`); every
  nexus request has count 0. `MacQuadra800.sv:224` hands that count to
  slots 0, 1 and 4. With `BLKSZ=2` (`MacQuadra800.sv:192`), Main decodes
  `blks=1`, `sz=512` (`user_io.cpp:3587-3596`). `sd_blk_cnt` is never above 0
  for slots 0/1 in this configuration.
- **The engine serializes each sector with the guest:**
  - Read: `ncr53c96.sv:842-850` raises the next `io_rd` only when `!io_busy`
    and the guest has drained the 512-byte `sbuf`. `io_busy` lasts until the
    cycle after the ack falls (`:297`).
  - Write: `:1014-1025` raises `io_wr` only once `sbuf` is full. While
    `flush_pending` is set, the FIFO does not drain into `sbuf` (`:452`), and
    DRQ drops once the FIFO is full (`:345`). So the guest stalls until the
    ARM has read the sector.
  - There is no overlap between the SPI transfer and the guest's PDMA.

### What Main does with a request

The main loop is the scheduler. `scheduler.h:4` defines `USE_SCHEDULER`, and
`main.cpp:75-77` runs it. `scheduler.cpp:26-40` (`co_poll`) runs
`user_io_poll()`, `frame_timer()`, `input_poll(0)` and `video_poll()`, then
yields. `co_ui` then runs `HandleUI()` and `OsdUpdate()` (`:44-55`), and the
scheduler alternates the two for ever.

**Nothing in a pass sleeps:** `input_poll`'s `poll()` has timeout 0 outside
the menu core (`input.cpp:5597-5618`). So the poll cadence is simply the
length of one round of both coroutines. It has not been measured; that is
what sdprof's `pass_avg_us` is for.

One pass of `user_io_poll()` (`user_io.cpp:3472`) that serves a disk sector
goes like this:

1. **`mac_poll()`** (`:3491` → `support/mac/mac.cpp:72-108`): Toolbox
   announce, `cdchanger_poll`, `mac_cdrom_poll`, then `mac_eth_poll()`
   (`mac_eth.cpp:602`).
   - With the Ethernet card off (the OSD default), `mac_eth_poll` returns
     after a 1 ms pace check (`:621-624`).
   - With the Q8 card up, it runs every pass: `drain_ring`, the SONIC model,
     TX (`:650-657`) and up to 1 ms of RX. A DMA RPC spins up to 1.5 ms and
     then `usleep(50)`s, with a 250 ms timeout (`mac_eth.cpp:136,178`,
     `mac_eth_q8.cpp:49,89`).
   - This all runs **before** the disk loop in the same coroutine.
2. **`mwb_poll()`** (`:3562`): write-buffer runs idle for 20 ms are flushed
   (O_SYNC `write()`).
3. **The generic sector loop**, `for (i < 4)` (`:3563`):
   1. **Status read.** `spi_uio_cmd_cont(UIO_GET_SDSTAT)` plus 3 words
      (`:3578-3584`). This is hps_io `'h16` (`sys/hps_io.sv:335,400-406`);
      bit 15 is always set, and the op bits are 0 when nothing is pending.
   2. **Dispatch.** `mac_sd_service()` (`:3663` → `mac.cpp:116-185`) only
      takes the Toolbox slots (3, 5) and the CD window/translated CD slot. It
      **returns 0 for slots 0/1**, so the hard disks fall through to the
      generic code.
   3. **Write** (`:3684-3733`):
      - `UIO_SECTOR_WR|ack` plus `spi_block_read` of 512 B (`:3693-3696`).
        That is 256 16-bit GPO words (`spi.cpp:200-210`,
        `fpga_io.cpp:749`). hps_io holds `sd_ack` from the command word
        until `DisableIO` (`hps_io.sv:321,337`), so **the ack ends before
        any file work**.
      - `mwb_write()` (`:3721`) then memcpys the sector into a 64 KB run
        (`:3397-3445`). The run reaches the card as one O_SYNC `write()`:
        - when it fills (`:3428`);
        - when all 8 runs are in use;
        - before an overlapping read (`mwb_before_read`, `:3754`);
        - after 20 ms idle;
        - on remount / core load (`fpga_io.cpp:623`).
      - The image itself is opened `O_RDWR|O_SYNC` (`:2262`), on a `sync`
        mount.
   4. **Read** (`:3735-3869`):
      - `mwb_before_read` runs first.
      - Then the 16 KB per-slot buffer is checked (`:3756`). On a miss it
        does `FileSeek` + `FileReadAdv` of 16 KB **before** the transfer
        (`:3778`).
      - `UIO_SECTOR_RD|ack` plus `spi_block_write` of 512 B (`:3836-3839`)
        is the ack.
      - If this request used the buffer's last block, the next 16 KB is read
        synchronously after the ack (`:3845-3866`).
   5. The next iteration reads the status again. The engine cannot have
      raised the next sector yet: the guest must first drain or fill 512 B
      through PDMA, which takes tens of µs or more. So the op bits are 0 and
      the loop hits `else break` (`:3871`).

### Per-request cost

- **One 512-byte request costs one Main-loop pass.** It takes one status
  read (4 SPI words) and one data command (1 + 256 words). A second request
  is served in the same pass only when post-ack file work (a 16 KB prefetch,
  or a run flush) takes long enough for the guest to finish the next sector
  meanwhile.
- **The 2026-09-25 measurements** (`docs/DISK_TRACE_20260925.md`) were:
  - SPI: ~110 µs per 512 B read (837 µs per 4 KB) and ~150 µs per write;
  - ~100-200 µs from one request to the next, which is guest drain plus
    Main-loop lag;
  - about 250-350 µs per sector end to end, i.e. **~1.5-2 MB/s** at best.
- **The pieces are serial:** SPI, then guest drain, then waiting for the
  next pass.

| 64 KB, cache off, write-buffer Main | read (sequential) | write (sequential) |
|---|---|---|
| requests / Main passes | 128 / ~128 | 128 / ~128 |
| SPI data commands | 128 × 512 B `SECTOR_RD` | 128 × 512 B `SECTOR_WR` |
| file operations | 1 demand `FileReadAdv` 16 KB (first sector) + 4 read-ahead 16 KB after the ack (the 4th is the next 16 KB); 127 buffer hits | 128 memcpys into the run |
| O_SYNC `write()` | 0 (unless the read overlaps a buffered run, which flushes it) | **1** 64 KB (run fills), or 2 (a partial run plus the rest after 20 ms idle), ~4-5 ms each, **after** the ack |
| same, with a Main without the write buffer | — | **128** O_SYNC writes of 512 B, ~4 ms each (~0.5 s, ~130 KB/s), each before the next request |

For contrast, `ide.cpp` (Minimig/ao486) does the same 64 KB in about one pass,
8 KB per `FileReadAdv`, inside one `process_read` call.

## 2. sdprof for the Mac fork

The build lives in `scratch/mac_main_sdprof_20260928/`, which is gitignored:

| file | what |
|---|---|
| `sdprof.diff` | against `Mac_Main_MiSTer` `b4192cd`, `user_io.cpp` only |
| `MiSTer_sdprof` | the binary, md5 `1603be2ff179e3f4d00d8cf386a1ad48`; `grep -a -c` finds `macquadra800` 1 and `Mac write buffer` 1 |
| `src/` | patched tree |
| `orig/` | pristine copy |
| `build_*.log` | build logs |

A control build of `orig/` is byte-identical to the box binary except for
the 6-byte `VDATE` string. The scratch copy is therefore the box's source.

**Build recipe** (the fork's Makefile, no `build.sh`, which pushes over FTP):

```bash
rsync -a --exclude=.git --exclude=bin ../Mac_Main_MiSTer/ scratch/mac_main_sdprof_20260928/src/
cd scratch/mac_main_sdprof_20260928/src && patch -p1 < ../sdprof.diff
PATH=/opt/gcc-arm-10.2-2020.11-x86_64-arm-none-linux-gnueabihf/bin:$PATH make -j16
# -> bin/MiSTer (stripped); bin/MiSTer.elf has symbols
```

**Use** (not done; the box rules in CLAUDE.md apply):

- Launch Main with `SDPROF=1` in its environment. `app_restart` execs itself
  on core load, so the variable survives into the Quadra core.
- Install the binary under the name `MiSTer` (e.g. `/media/fat/sdprof/MiSTer`,
  started from `/media/fat`). That way `pidof MiSTer` and the liveness checks
  still work.
- `kill -USR2 $(pidof MiSTer)` resets the counters just before the workload.
- One line every 10 s goes to `/tmp/sdprof.log`.
- Overhead: about 10 `clock_gettime` calls per request against a ~300 µs
  request, plus 3 per pass. With `SDPROF` unset, each hook is a single test
  of a flag.

The upstream fields (same names as `../Main_MiSTer`'s uncommitted sdprof)
count every slot. A CD playing audio adds 2352-byte reads on slot 4, so keep
the CD idle for disk runs.

| field | meaning |
|---|---|
| `polls`, `poll_avg_us`, `poll_max_us` | status reads (one per loop iteration) and the gap between consecutive ones. The gap includes the previous iteration's service. |
| `status_us` | total time spent in status reads |
| `read_req`/`write_req`, `*_blocks`, `*_bytes` | requests with op set, any slot |
| `read_hist`/`write_hist` | blocks per request: 1, 2-3, 4-7, 8-15, 16-31, 32+. **Cache off: disks are all in the first bucket.** |
| `cache_hit`/`cache_miss` | Main's 16 KB per-slot read buffer |
| `file_read_us` | demand 16 KB read on a miss. **Before** the ack, so the guest waits. |
| `prefetch_us` | the synchronous 16 KB read-ahead **after** the ack. It delays the next request. |
| `file_write_us` | after the ack in the write branch: the `mwb_write` memcpy plus any flush it forced |
| `to_fpga_us` / `from_fpga_us` | SPI time of `SECTOR_RD` / `SECTOR_WR` |
| `service_us` | status read to end of iteration, for iterations that served a request |

Mac additions, appended to the same line:

| field | meaning |
|---|---|
| `passes`, `pass_avg_us`, `pass_max_us` | `user_io_poll` entry to entry: **the poll cadence**, i.e. one full round of `co_poll` + `co_ui`. `pass_max` is the worst input/OSD latency proxy. |
| `macpoll_us`, `macpoll_max_us` | time in `mac_poll()`: Ethernet, CD, Toolbox. This is what sits in front of the disk loop every pass. |
| `mwb_flushes`, `mwb_flush_bytes`, `mwb_flush_us`, `mwb_flush_max_us` | real O_SYNC card writes from the write buffer, whatever triggered them |
| `gap_n`, `gap_avg_us`, `gap_hist` | from the ack of one served request to the status read that finds the next one. Buckets: <50, <100, <200, <500, <1000, <2000, ≥2000 µs; the last bucket also collects idle time between commands. This is the guest's drain/fill time **plus** Main's lag. |
| `tl_waits`, `tl_hits`, `tl_wait_us`, `tl_budget_exits` | the tight loop (§3). Always 0 in `MiSTer_sdprof`. |

**Reading it:**

- Main's share per sector: `service_us / (read_req + write_req)`.
- Main-loop lag: `gap_avg_us` minus the guest's drain time. The tight-loop
  build measures the drain time directly (below).
- If `to_fpga_us`/`from_fpga_us` dominate `service_us`, the GPO bit-bang is
  the limit. That is the DDR3 mailbox case (`docs/scsi-ddr3-disk-plan.md`).

## 3. Tight service loop (proposal, `tightloop.diff`)

The files are `scratch/mac_main_sdprof_20260928/tightloop.diff`, which
applies **on top of** `sdprof.diff` (`user_io.cpp` only, ~60 lines), and
`MiSTer_sdprof_tightloop`, md5 `9be9c37b71c42c839934709aca248002`. The
binary is built but untested and not installed.

- **Arming:** after the generic loop has served an op on slot 0 or 1 of the
  Quadra 800 (`is_mac_scsi_optimized()`, not a CD/Toolbox slot), the next
  iteration starts with `mac_tl_wait()`. This repeats a **one-word**
  `UIO_GET_SDSTAT` for up to `MAC_SD_SPIN_US` (default 250 µs) until any
  slot shows a request.
  - The one-word read is side-effect free in hps_io: the round-robin
    advances on word 2 (`hps_io.sv:402`).
  - On a hit, the normal full status read and service follow. On a timeout,
    the pass ends as today.
- **Budget:** the loop keeps going past its usual 4 iterations while hits
  continue, up to `MAC_SD_BUDGET_US` (default 2000 µs) from the first disk
  service of the pass. It then returns, so `frame_timer`, `input_poll`,
  `video_poll`, `co_ui` (OSD) and, at the top of the next pass, `mac_poll`
  (Ethernet) run at least every ~2.25 ms while the disk streams.
- **Tuning:** `MAC_SD_SPIN_US=0` restores today's behaviour exactly. Both
  variables are read in `user_io_init`, and the values are printed as
  `Mac SD tight loop: ...`.

**Trade-off:**

- **Gain.** Each sector's gap drops from (drain + wait for the next pass) to
  (drain + ~1-2 µs). Nothing changes in the core, the file I/O or the data
  path, so correctness is the same code run sooner.
- **Cost:**
  - Main is single-threaded. For up to 2 ms at a time it serves only the
    disk:
    - keyboard/mouse/OSD latency grows by at most the budget per pass
      (a frame is 16.7 ms);
    - with the Q8 Ethernet card up, `mac_eth_poll` runs at most once per
      budget during disk streams;
    - the write buffer's 20 ms idle flush is unaffected.
  - A timed-out spin wastes up to `spin_us` of ARM time once per burst: at
    the end of every SCSI command, and for every 1-block command. It costs
    the FPGA nothing.
  - The spin must be longer than the guest's per-sector drain/fill, or it
    never hits. The `gap_hist` of the plain sdprof build shows where that
    drain sits before choosing a value.
- **Scope.** This attacks only Main-loop lag. SPI time and the engine's
  single `sbuf` (no overlap) stay. Those are steps 2 and 4 of the first doc
  (command-sized requests, ping-pong `sbuf`), or the DDR3 plan.

**How to measure** (same core, same disk, same workload, CD idle, Ethernet
off and then on):

1. `MiSTer_sdprof`: baseline `gap_hist`, `gap_avg_us`, `pass_avg_us`,
   requests/s.
2. `MiSTer_sdprof_tightloop` with `MAC_SD_SPIN_US=0`: this must match (1).
   It is the control for the loop restructure.
3. The defaults, then spin 100 / 500 and budget 1000 / 4000. Compare:
   - `tl_hits / tl_waits`: near 1 during streams; misses ≈ number of
     commands;
   - `gap_avg_us`: in the tight build it **is** the guest drain time, so
     (1) minus (3) is Main's lag;
   - requests/s and `service_us` per request;
   - `tl_budget_exits`, `pass_max_us`;
   - and, guest side, Speedometer PR Disk and a timed Finder copy.
4. Check that the mouse and menu-bar clock stay responsive during a copy, and
   that FTP throughput with the card on does not drop.

If (3) leaves `gap_avg_us` about equal to (1), Main's lag was never the
problem. The guest drain and the SPI time then set the rate, and the next
lever is command-sized requests (with the cache in) or the DDR3 path.
