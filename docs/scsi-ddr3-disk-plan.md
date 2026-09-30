# Hard-disk data over a DDR3 mailbox (plan, not built)

Written 2026-09-24 as a read-only planning pass. It follows
`docs/disk-speed-vs-minimig-ao486.md`. Its step 0 (measure first, with the
block cache back in) still comes before any of this.

The problem, in one line: the whole image does not fit in the FPGA-visible
DDR3. DDR3 therefore has to be a **transport plus a cache**, with a
request/completion mechanism like the Ethernet mailbox's.

## 1. What the Ethernet mailbox teaches (`rtl/sonic_mbx.sv`, `support/mac/mac_eth*.cpp`)

- **The guest waits for DDR3, never for software.** A register write is done
  once its doorbell entry is *in DDR3*. The ARM consumes the ring later.
- **The ARM publishes, and the FPGA reads what it needs when it needs it**
  (the shadow block, the PROM).
- **Applied index.** The ARM stamps what it publishes with the ring index it
  had consumed at that moment. The FPGA uses that stamp to decide whether the
  published data can already reflect a given entry (CR overlay, ISR seq). The
  same trick solves the disk's write/read-ahead race below.
- **MAGIC-gated presence.** On an old Main the feature is inert, and the core
  falls back to what it did before.
- **Latency is set by how often the ARM looks.** `mac_eth_q8.cpp` spins
  1.5 ms (`SPIN_US`), then `usleep(50)`, which "costs ~1 ms". The unexplained
  44 KB/s FTP (`RESUME-ethernet-20260918c.md` §4) smells of Main-loop
  pacing. **A disk service must not live in Main's poll coroutine.**
  `offload.cpp` shows the pattern: a pthread pinned to core 0, while Main
  runs on core 1.

## 2. Two designs; recommending A

### A. The ARM owns the cache; DDR3 is the data path (recommended)

This is the `ide.cpp` / Atari ST ACSI model: one request per **SCSI
command**, not per sector. It runs on a DDR3 ring instead of hps_io, and a
dedicated ARM thread serves it.

- **The cache is Linux's page cache.** The DE10-Nano's Linux side has
  ~512 MB, mostly idle under this core. A `FileReadAdv` that hits the page
  cache is a memcpy. It holds hundreds of MB of the image with no tags in the
  FPGA and no replacement policy of our own. A cold miss costs one SD read, on
  the ARM thread and never on the guest's bus.
- **Coherency is trivial.** One ARM thread processes one ordered ring, so a
  READ after a WRITE always sees the written data (page cache or file).
- The FPGA keeps what it has today: the 53C96 model, the target state,
  `sbuf`. It gains a DDR3 burst client, the ring, and one read-ahead
  descriptor per disk (§4).

### B. The FPGA owns a tag-mapped DDR3 cache; the ARM fills misses

This is what "a cache in DDR3" suggests first. Hits would never touch the ARM.
It loses to A for four reasons:

1. **Tag storage.** 128 MB of 4 KB lines is 32 K tags. That does not fit in
   M10K next to the CPU (the chip is at 93-95 %). Put the tags in DDR3 and
   every lookup becomes a DDR3 round trip anyway.
2. **Write coherency across two owners.** Guest write hits patch lines in
   the FPGA while the ARM fills and read-aheads lines from the file. Every
   ordering needs its own rule: write during fill, fill completing after a
   write to the same line, write-miss allocate. That is the class of bug
   `scsi_cache` took a random bench to close (`9754dac`), only now with
   software on the other side.
3. **Duplicates the page cache.** B re-implements in RTL a cache Linux already
   provides for free.
4. **Not much faster.** A's per-command cost is one ring round trip. On a
   streaming read, the read-ahead descriptor (§4) removes even that.

## 3. The mechanism (design A)

### DDR3 window

The base must be free in both the ARM's and the FPGA's maps:

- ascal uses `0x20000000`;
- Ethernet uses `0x1FF00000`;
- the ROM image is at `0x38000000`;
- `DDR_RAM_BASE` = `0x30000000` is declared in `MacQuadra800.sv:919`, but
  nothing addresses it.

Take a window at e.g. `0x30000000` (to be verified against ascal's buffer size
and Main's other mappings). It needs only a few MB. Word indices are 64-bit,
as in `sonic_mbx`.

| area | size | direction | contents |
|---|---|---|---|
| MAGIC | 8 B | ARM→FPGA | `"McQ8DSK1"`: the service thread is up |
| REQ ring | 64 × 32 B | FPGA→ARM | `{seq, op, target, lba, count, slot}`; op = READ, WRITE, SYNC, RESET |
| REQ_WPTR | 8 B | FPGA→ARM | monotonic |
| CPL | 8 B per target | ARM→FPGA | `{applied seq, status, bytes_ready}`; `bytes_ready` grows while a READ streams |
| RA desc | 16 B per target | ARM→FPGA | `{lba, count, slot, applied seq}`: the read-ahead the ARM has already staged (§4) |
| data slots | 4 × 64 KB per target | both | READ data from the ARM, WRITE data from the FPGA |
| DEBUG/stats | 64 B | FPGA→ARM | what the FPGA saw; the Ethernet window has the same kind of word |

Mount, image size and write-protect stay on hps_io (`img_mounted`,
`img_size`), as today.

### READ(6/10) of n blocks

1. The engine has the CDB. It posts `READ lba n slot` in the ring. That is one
   DDR3 write, done in well under 1 µs.
2. The ARM thread sees `REQ_WPTR` move. It `FileSeek`s and `FileReadAdv`s
   **straight into the mmapped slot**, 16 KB at a time (C64's `FileLoad` into
   DDR3 does the same). After each piece it bumps `bytes_ready`.
3. The engine streams 512 B at a time from DDR3 into `sbuf` as soon as
   `bytes_ready` covers the next sector. This is Minimig's "fast read": the
   guest drains sector k while the ARM writes k+1..k+31. A 512 B burst is
   64 beats at 33 MHz, about 2-3 µs. No ARM involvement per sector, no hps_io.
4. Commands over 64 KB loop over slots.

### WRITE(6/10)

1. The guest's PDMA bytes go into `sbuf`. Each full sector is burst to the
   command's DDR3 slot.
2. When the last sector is in DDR3, post `WRITE lba n slot` and return
   **GOOD at once** (write-behind, as `scsi_cache` does today).
3. The ARM copies the slot out and writes the file (O_SYNC or not, §6). It
   then posts CPL, which frees the slot.
4. If all slots are busy, the engine holds DATA OUT, and the guest simply
   waits. The data in flight is capped at 4 slots × 64 KB per disk: the same
   risk class as today's write-behind, with a larger bound.
5. SYNCHRONIZE CACHE ($35), a machine reset, and the `nreset` replay all wait
   for every WRITE to complete before reporting status.

### The ARM thread

- A pthread pinned to core 0 (as in `offload.cpp`).
- It owns the two disk `fileTYPE`s while the path is live. Main's mount code
  pauses it around a remount (a mutex plus a generation number).
- **Polling policy:** spin on `REQ_WPTR` (an uncached `/dev/mem` read) while
  requests keep coming and for about 2 ms after the last one, then
  `usleep(100)`. Streaming latency is then a few µs. The first request after
  idle costs about 1 ms, which is no worse than today.
- `sys_top.v:577` has an `f2h_irq`, today carrying the vsync lines. A real
  FPGA→HPS interrupt would remove the idle cost, but it needs a kernel/UIO
  path that Main does not have. Leave that for later.

## 4. Read-ahead without a round trip (the applied-index trick)

After a READ, the ARM thread reads the next 64 KB into a free slot and
publishes `RA = {lba, count, slot, applied seq}`. On the next READ the engine
checks RA itself. If the READ falls entirely inside RA, the engine serves it
at once. It still posts the READ, marked as served from RA, so the ARM moves
the read-ahead forward. A sequential stream then never waits for the ARM.

The race: the ARM reads the file for RA while a guest WRITE into that range
sits unconsumed in the ring. RA would then hold stale data.

The rule: the FPGA uses RA **only if RA's applied seq ≥ the seq of the last
WRITE the FPGA posted for that target.** A write posted after the ARM staged
RA therefore invalidates it, as the Ethernet CR overlay does. The ARM applies
writes in ring order, so the next RA it publishes carries the write.
Conservative, one comparator, no range check.

## 5. What goes away, what gets added

- **Goes:** `scsi_cache` for the disks. 877 ALMs, 40 M10K on the
  2026-09-16 fit. The CD can keep its pass-through, or move to the same
  mailbox later.
- **Added** (estimates, to be confirmed with a `--check`): a DDR3 burst
  client (512 B bursts; see §6 for the ROM), the ring writer, the CPL/RA
  readers, and one or two more sector buffers in `ncr53c96` for overlap. This
  should be well under the cache's ALMs, with M10Ks going *down*.
- **Main:** a new `support/mac/mac_disk_ddr.cpp`, with no Main dependencies in
  the ring logic, so a host test and the Verilator sim can compile the same
  file. `mac_sd_service` is untouched. On an old Main the core sees no MAGIC
  and uses today's hps_io path.

## 6. Hazards

- **The ROM also lives in DDR3** (`MacQuadra800.sv:995-1004`: the arbiter
  serves ROM beats one at a time). A 64-beat disk burst in front of a ROM miss
  adds ~2 µs to that fetch. Give the ROM priority between bursts of 8-16
  beats. Measure with Speedometer; the CPU caches hide most ROM traffic.
- **The full-machine sim does not cover `MacQuadra800.sv`** (CLAUDE.md). Put
  the disk DDR client and its port **inside `quadra800`**, give `sim_main.cpp`
  a DDR3 array, and run the ARM thread's ring code as a C model inside the
  sim. The CD plan does the same with `mac_cdrom_resp.cpp`. The top then only
  multiplexes one more requester into the existing arbiter.
- **O_SYNC.** Write-behind in an ARM thread makes the guest stop waiting for
  it. Keep O_SYNC at first (correctness over speed), and revisit it with
  numbers.
- **Unclean exits.** Dirty data sits in DDR3 or the ARM thread until
  completed. Main must drain the ring before `load_core`, remount or reboot,
  as the rule 1 hygiene already assumes.
- **Thread safety in Main:** `FileReadAdv`/`fileTYPE` are not designed for
  concurrent use. The thread must be the only user of its two files.
- **Area and routing** are the binding constraint right now (P232 routes on
  one seed of seven). This is a win only if it comes out smaller than
  `scsi_cache`, and that has to be measured.

## 7. Order of work

0. **Measure** (the earlier doc's step 0): guest throughput with the cache on
   and off, plus `sdprof`-style counters. If the cache-on build is already
   near the guest-side PDMA limit, stop here.
1. **Main:** the thread, the ring, RA, and a host test driving it with a C
   model of the FPGA side (`support/mac/test/mac_q8_test.cpp` is the
   pattern).
2. **RTL:** the client plus a `tb_disk_ddr` with a DDR3 model and a random
   write/read-ahead interleaving that checks the §4 rule. Model it on
   `tb_scsi_cache` T7, which is what found the last cache's two races.
3. **Full sim:** boot to the Finder with the C model. Then compare
   `--check` area against `scsi_cache`.
4. **Hardware:** the regression gate, plus a disk-throughput number
   before/after in `docs/PERFORMANCE_MEASUREMENTS.md`.

## 8. Optional: where the ROM lives (measure first)

This is not needed for the disk work. It is recorded here because the ROM
shares the DDR3 port with this plan (§6), and because moving it interacts
with the RAM-size option.

### Facts (2026-09-24)

- **The ROM:**
  - `releases/quadra800.rom` is 1,048,576 bytes.
  - It is uploaded as `boot.rom` into DDR3 at `0x38000000` (`DDR_ROM_BASE`).
  - It is served one longword per DDR3 read (`ddram_burstcnt <= 1`,
    `MacQuadra800.sv:1001`).
  - The ROM window is cacheable (`wombat_cpu.sv:408`). The AP040 caches are
    only 4 KB I + 4 KB D with 16-byte lines, so **one ROM line fill is four
    separate DDR3 round trips**.
  - The comment at `MacQuadra800.sv:760` ("read rarely enough that latency is
    free") is an assumption; no one has measured it. The header comment at
    `MacQuadra800.sv:7` still says RAM is in DDR3, which is out of date.
- **SDRAM:**
  - The SDRAM is a 128 MB module, two 64 MB ranks (`sdram.sv:156`).
  - Guest RAM is the only thing in it: VRAM is BRAM, the ROM is DDR3.
  - The OSD offers 32/64/128 MB, so 96/64/0 MB are free.
- **RAM sizes:**
  - Only power-of-two totals boot (`quadra800.sv:478-499`). The decode is one
    flat range. The djMEMC bank registers are stored but ignored.
  - 48 MB hangs the ROM at `$408A0230`, on DDR3 and on SDRAM alike.
  - A real Quadra 800 has 8 MB on board plus four 72-pin SIMM slots
    (4/8/16/32 MB), for a maximum of 136 MB. That never fit in 128 MB of
    SDRAM.
  - Period upgrades such as 24 MB (8+16) and 36 MB (8+4+8+16) need the
    bank decode.

### Step 1: measure

Add a cycle counter on ROM beats: count, total wait cycles, max. Publish it
through the Ethernet DEBUG-word style or a debug status bit, and run it over
a Speedometer Mix and a Finder session. If ROM wait time is a small share of
the run, stop here. Graphics, which is QuickDraw in ROM, and trap-heavy tests
are where it would show.

### Step 2 (if it matters): one DDR3 burst per ROM line

Fetch the whole 16-byte line in one request (`burstcnt = 2`, two 64-bit
beats) and hold it in a one-line ROM buffer. The other three longwords of the
fill become buffer hits: four round trips become one.

- It stays in the existing DDR3 arbiter.
- There is no RAM-size change and no SDRAM change.
- It also shortens how long the ROM holds the port against the §6 disk
  bursts.

**Try this before step 3.**

### Step 3 (only if step 2 is not enough): the ROM in SDRAM

This means dropping the 128 MB option. The ROM goes at a fixed upper region,
e.g. byte 64 MB (rank 1). Changes are on the clk_sys side only, in front of
`sdram_beat32` (`MacQuadra800.sv:780-788`):

- `req` also covers ROM beats, with `addr` = `{1'b1, ROM offset}`;
- ROM writes are still acked and discarded before the bridge (write
  protection, as the DDR3 arbiter does today);
- the `boot.rom` ioctl upload is muxed into the bridge. The select only
  changes under reset. That is one LUT level on a clk_sys input.

Nothing changes in `sdram.sv` or on `clk_ram`. Re-run the clk_sys↔clk_ram
path reports after the fit anyway (CLAUDE.md, `docs/sdram-open-row-crossing.md`).

Two side effects:

- ROM fetches get ordinary SDRAM line reads, **not** the retained-line fast
  paths: those compare physical RAM addresses, so a `$408xxxxx` fetch can
  never match. That is safe, and extending them is a separate job.
- Moving the ROM out of DDR3 also removes the ROM-vs-disk contention of §6.

RAM options after the move:

| options | max guest RAM | SDRAM free | work |
|---|---|---|---|
| 32 / 64 | 64 MB | 64 MB | step 3 only |
| 8 / 16 / 32 / 64 | 64 MB | 64 MB | step 3; 8 and 16 are powers of two, but untested |
| real SIMM totals (24, 36, 40, 72, …) | 120 MB (8 + 32 + 32 + 32 + 16) | ≥ 8 MB | step 3 + the djMEMC bank decode |

### The bank decode (a separate feature, independent of the ROM move)

The bank decode lives in `decode()` in `quadra800.sv`, which is on the CPU's
per-beat address path. That path, not the SDRAM, is where it risks timing.

The cheap way to build it: when the ROM writes a bank register, rebuild a
small registered table ({bank, base, size}). Each beat then compares against
the table and replaces a few upper address bits. There is no adder on the
beat path.

Validate each size with a full boot sim (the sizing stages run on every
boot; `docs/quadra800-ram-test.md`), then on hardware under the regression
gate. The A/UX gate stays at 32 MB.
