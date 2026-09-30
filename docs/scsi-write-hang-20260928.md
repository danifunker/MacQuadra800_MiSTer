# The Finder-copy SCSI hang, 2026-09-28: a lost 53C96 interrupt in the IOSB's VIA2

On hardware on 2026-09-28, the third Finder duplicate of a 4 MB file stopped
writing at 62 %. The 53C96 engine raised no more sector requests, while the
guest's interrupt level stayed alive (`docs/perf/disk_tightloop_20260928/README.md`).

I reproduced this in the full-machine Verilator sim with a randomised SD
service model. The same seed reproduces it exactly every time. The cause is
in `rtl/iosb.sv` and has nothing to do with the SD latency itself:

- When the guest writes the pseudo-VIA2 IFR, the whole of `via2_ifr[6:0]` is
  assigned.
- That assignment comes after the edge latch in the same always block.
- So if the write lands in the same clock as the 53C96 INT rising edge, the
  edge is overwritten with the old 0.
- The write that did it here is the ROM's VBL/slot dispatcher writing `$02`.
  That write clears nothing.
- The chip then holds INT (bus service, phase DATA OUT, 218 blocks still to
  go) and waits for the next `$90`. The SCSI Manager waits for a level-2
  interrupt that will never come. VBL interrupts continue, so the pointer
  moves, but the Finder is blocked and its menu-bar clock stops.

Everything below is simulation and directed benches. Nothing was changed in
`rtl/`, the `.qsf` or the tracked sim sources, nothing was committed, and no
hardware was used. The scratch area is `scratch/scsi_hang_20260928/`.

## 1. Harness

- **Tree:**
  - `git archive` of HEAD `b0d7d88` into `scratch/scsi_hang_20260928/tree/`.
  - The Verilator `Makefile` adds every CPU macro of the release `.qsf` plus
    `SCSI_CACHE_OFF=1`, so the engine talks to hps_io directly, as on the
    shipped core.
  - `HANGDBG` enables the scratch taps.
- **SD service model:** `tree/verilator/sim/sim_blkdevice.cpp`. Before the
  change the model used one fixed `+blkdev_latency` (16,000 clocks) for every
  request, and the ack window was one word per clock. The new plusargs are in
  clocks at 33 MHz:

  | plusarg | meaning |
  |---|---|
  | `+lat_seed=N` | xorshift seed |
  | `+lat_min= +lat_max=` | uniform pre-ack latency per request (Main's loop gap) |
  | `+stall_ppm= +stall_min= +stall_max=` | extra pre-ack stall with probability ppm/10^6 (write-buffer flush, 1-45 ms = 33,000-1,485,000) |
  | `+ack_word=W` | clocks per 16-bit word while `sd_ack` is high (SPI time: 16 ≈ 125 µs per write block, ≈ 250 µs per read block) |
  | `+ackstall_ppm= +ackstall_min= +ackstall_max=` | a stall **inside** the ack window at a random word (Main preempted mid-SPI) |
  | `+arm_cycle=N` | before N the stock fixed model is used, so the boot is identical in every run |

- **Guest:**
  - The disk is `MacQuadra800-Speedometer402-profile.hda` (System 7.5.5)
    with a 3,958,784-byte file, "Big File", added to its Desktop Folder
    with `hcopy`. That is the size of the Photoshop read on hardware
    (`golden.hda`, sha256 in `golden.sha256`).
  - The control stream is `control_dup.txt`:
    1. the p256 boot pacing;
    2. Esc, Tab, Tab, Return to "Exit to Finder" from MacAtrium;
    3. type "Big" to select the file;
    4. Cmd-D;
    5. a screenshot every 2 guest seconds.
  - Cmd-D lands at clock 1,149.5 M; the model arms at 1,140 M.
- **Detectors:**
  - `sim_main.cpp` prints `[LIVE]` every guest second: low-memory `Ticks`
    and `Time`, requests, and the time since the last request.
  - It quits 2.5 guest s after the last request, taking a screenshot first.
  - `iosb.sv` (`HANGDBG`):
    - logs every request and ack edge with the engine and PDMA state
      (`[HST]`);
    - keeps two 512-entry rings of engine and engine+PDMA transitions;
    - dumps them on an SDMA fault and on a stall trip, which fires when the
      engine is mid-transfer with no request for 66 M clocks (2 s);
    - keeps a deduplicated log of 53C96 and VIA2 IFR/IER accesses
      (`[HREG]`).
- **Launch:** each run is one `systemd-run --user` unit (`run_one.sh`).
  `analyze.py` builds the table below from each run's counters.

## 2. Runs (System 7.5.5, 3.96 MB Finder duplicate)

Latencies are in clocks at 33 MHz (3,300 = 100 µs). `rd`/`wr` count requests
after the arm point. The file itself is 7,732 blocks. The gap histogram runs
from an ack falling to the next request being raised, i.e. the guest's drain
or fill time.

| run | model | outcome | copy (guest s) | pre-ack stalls | in-ack stalls | SDMA faults |
|---|---|---|---|---|---|---|
| g1 | lat 3.3-16.5 k | complete | 7.4 | 0 | 0 | 0 |
| g2 | + stall 1 % of 1-45 ms | complete | 11.1 | 150 | 0 | 0 |
| g3 | + stall 1 %, ack_word 16 | complete | 13.0 | 155 | 0 | 0 |
| g4 | + stall 5 %, ack_word 16 | complete | 27.1 | 789 | 0 | 0 |
| g5 | lat 1.65-33 k, stall 2 % | complete | 18.9 | 283 | 0 | 0 |
| g6 | ack_word 16, in-ack 0.2 % of 1-12 ms | complete | 9.5 | 0 | 28 | 4 (reads, recovered) |
| g7 | stall 1 %, ack_word 20 | complete | 13.3 | 149 | 0 | 0 |
| g8 | lat 3.3-66 k, stall 2 % | complete | 27.1 | 264 | 0 | 0 |
| g9 | in-ack 0.5 % of 6-12 ms | complete | 10.1 | 0 | 89 | 24 (reads, recovered) |
| g10 | stall 10 % | complete | 46.3 | 1,593 | 0 | 0 |
| g11 | lat 3.3-33 k, stall 20 % | complete by request count (7,820 / 7,738); the 121 s sim cap was hit 0.1 s later, before the idle screenshot | 86 | 3,121 | 0 | 0 |
| g12 | stall 5 %, ack_word 24 | complete | 28.6 | 798 | 0 | 0 |
| g13 | in-ack 0.5 % of 4.5-7.6 ms (under the watchdog) | complete | 9.7 | 0 | 70 | 0 |
| **g14** | **in-ack 0.5 % of 8.2-12 ms** | **STOPPED after 1,086 reads / 294 writes** | 1.1 | 0 | 5 | **0** |
| g15 | g9's model on the watchdog fix | complete | 11.4 | 0 | 76 | 0 |
| g16 | stall 5 % + in-ack 0.2 % of 1-45 ms, watchdog fix | complete | 27.0 | 735 | 32 | 0 |
| g17 | lat 0.5-2 ms, stall 5 % | complete | 42.8 | 798 | 0 | 0 |
| g18 | lat 3-100 µs, ack_word 4 (a tight-loop Main) | complete | 3.8 | 0 | 0 | 0 |
| g14r | g14 rerun, same seed, register + CPU trace | stopped at the same clock | | | | |
| g14t | g14 rerun, exact-cycle IFR trace | stopped at the same clock | | | | |
| **g14f** | **g14's seed on the IFR fix (section 4)** | **complete, copy byte-identical** | 10.2 | 0 | 82 | 35 (reads, recovered) |

- **Request statistics** (g1, no stalls): 7,820 reads and 7,738 writes;
  17,848 53C96 interrupts during the copy; mean pre-ack latency 201 µs.
- **Gap histogram** (g1): <50 µs 0, 50-100 µs 6,677, 100-200 µs 8,224,
  200-500 µs 562, 0.5-2 ms 32, 2-100 ms 62, ≥100 ms 1.
- **Comparison with hardware:** sdprof on hardware had 0 below 50 µs and the
  bulk between 50 and 500 µs. The sim's guest drain/fill time therefore
  matches.
- **Stalls:** stalls of up to 45 ms before the ack, even 20 % of requests
  (g11), only stretch the copy.

**The hang does not need a slow Main.** g14's stop came about 150 sectors
and 98 ms after its last in-ack stall. That stall was on a write, and a
System 7.5.5 write never has a PDMA beat waiting during the ack (section 5).
The run had no pre-ack stalls at all. So neither kind of stall caused it. The
random latencies only move the phase of each sector's interrupt relative to
the guest's VBL handler, and one of those phases is fatal.

## 3. The hang, g14 / g14r / g14t

**Engine side.** The last transitions of the engine ring
(`runs/g14r/run.log.gz`, dumped at the trip, 66 M clocks later):

```
[HRA 1185193588] ph=0 xo=1 fp=1 wr=1 cia=1 tz=1 irq=0 | ff=0 sp=0 tc=0 bl=218 lba=93222   <- flush of the sector requested
[HRA 1185202145] ph=0 xo=1 fp=1 wr=1 ack=1 ...                                            <- Main (the model) acks
[HRA 1185202146] ph=0 xo=1 fp=1 wr=0 ack=1 ...
[HRA 1185206227] ph=0 xo=1 fp=1 ack=0 ...                                                 <- ack falls: sector is on the card
[HRA 1185206228] ph=0 xo=1 fp=0 ...
[HRA 1185206229] ph=0 xo=0 cia=0 tz=1 irq=1 ist=10 bl=218                                 <- chunk complete: INT, bus service
(nothing for 66,000,001 clocks)
[HTRIP 1251193589] engine busy with no block request for 66000001 clocks (last request at 1185193588)
[HST ...] POST-TRIP ph=0 xi=0 xo=0 fp=0 bv=0 rd=0 wr=0 ack=0 irq=1 ist=10 bl=218 sp=0 ff=0 tc=0 drq=0 as=0 ifr=00 ier=1a
```

- **The engine** has done everything it should. The TI's 510 bytes plus 2
  FIFO bytes are flushed, TC is 0, and the FIFO is empty. INT has been up
  with `istatus=$10` since clock 1,185,206,229. It waits for the ISR read
  and the next `$90`. No request is due, so none is raised.
- **The PDMA side** is idle (`astate=0`, no beat).
- **The VIA2** shows `ifr=00` with `ier=1a`. IER bit 3, the SCSI IRQ, is
  enabled, and the chip's INT is high, but IFR bit 3 is 0. So `via2_active`
  is 0 and no level-2 interrupt is presented.

**Guest side.** The per-sector protocol of the System 7.5.5 SCSI Manager
(`[HREG]`, g14r), one interrupt per sector:

```
[NCR 1185188569] INT+ ist=10 ph=0              chunk complete (previous sector)
[HREG 1185188712] rd via2.d=88                 level-2 dispatcher: IFR (bit 3 + summary)
[HREG 1185188726] rd via2.e=1a                 IER
[HREG ...       ] rd ncr.4=90                  STATUS: INT, DATA OUT
[HREG 1185189036] wr via2.d=88                 clear IFR bit 3 (before the ISR read: correct order)
[HREG 1185189105] rd ncr.5=10                  ISR -> INT drops
[HREG 1185189217] wr via2.e=08 / 88 / 08       SCSI IRQ disabled while it works
[HREG 1185190726] wr ncr.2=83, 8b              2 bytes through the FIFO
[HREG 1185190822] wr ncr.0=fe, ncr.1=01        TC = 510
[NCR 1185190833] cmd=90                         DMA transfer info, then 510 bytes of PDMA
[HST 1185193588] REQ-WR ... bl=218 lba=93223    flush
[HREG 1185193882] wr via2.e=88                 SCSI IRQ enabled again, return, wait
[HREG 1185204148] rd via2.d=82                 a VBL (slot) interrupt: IFR bit 1
[HREG 1185204162] rd via2.e=1a
[HREG 1185204230] wr via2.d=02  x2             the slot handler writes IFR=$02 twice
[NCR 1185206205] INT+ ist=10 ph=0              the next chunk complete ...
[HREG 1185624148] rd via2.d=82                 ... but every later IFR read is $82: VBLs only, for ever
```

**The CPU trace** (g14r, `--trace-after`, main_time is in half clocks)
shows where the two `$02` writes come from:

```
40809BE6: C029  and.b   ($1a03,A1), D0          @2370408283   VIA2 dispatcher: IFR
40809BEE: C029  and.b   ($1c13,A1), D0          @2370408313   & IER
40809BF8: 4ED0  jmp     (A0)                    @2370408353
4088BC56: 137C  move.b  #$2, ($1a00,A1)         @2370408359   slot handler: IFR = $02 (first)
   ... slot VBL tasks run ...
40806EE8: 4ED0  jmp     (A0)                    @2370412311
4088BC56: 137C  move.b  #$2, ($1a00,A1)         @2370412317   IFR = $02 again
4088BC5C: 7080  moveq   #-$80, D0               @2370412465   (the store took 74 clocks)
```

- In the trace's clock (main_time / 2), the second `move.b #$2` issues at
  ~1,185,206,158 and the next instruction at ~1,185,206,232.
- The 53C96 INT rises inside that window: 1,185,206,205 by the engine's
  counter, 1,185,206,229 by the iosb tap's. The counters differ by a few
  clocks of reset offset.
- g14t (`tree4`, exact-cycle tap) shows the collision:

  ```
  [HIFR 1185188593] 53C96 INT RISES (edge latch: via2_ifr[3] <= 1)       <- a normal sector:
  [HIFR 1185188712] CPU reads VIA2 IFR -> 88
  [HIFR 1185189036] CPU writes VIA2 IFR=88 (via2_ifr before=08, INT=1, same-cycle INT edge=0)
  [HIFR 1185189106] 53C96 INT falls (edge latch: via2_ifr[3] <= 0)
  ...
  [HIFR 1185204148] CPU reads VIA2 IFR -> 82                              <- VBL
  [HIFR 1185204230] CPU writes VIA2 IFR=02 (via2_ifr before=02, INT=0, same-cycle INT edge=0)
  [HIFR 1185206229] 53C96 INT RISES (edge latch: via2_ifr[3] <= 1)
  [HIFR 1185206229] CPU writes VIA2 IFR=02 (via2_ifr before=00, INT=1, same-cycle INT edge=1)
  [HIFR 1185206272] via2_ifr=00 ier=1a INT=1 ipl_n=111                    <- and so it stays
  [HIFR 1185207296] via2_ifr=00 ier=1a INT=1 ipl_n=111
  ```

**The RTL.** `rtl/iosb.sv` in the `ce` block:

```systemverilog
if (scsi_irq_i != scsi_d) via2_ifr[3] <= scsi_irq_i;     // edge latch (line ~1094)
...
A_IDLE: ... if (sel_via2) if (write) case (rsel)
    4'd13: via2_ifr[6:0] <= (via2_ifr[6:0] & ~(wbyte[6:0] & 7'h19) & 7'h7D)
                            | {5'd0, slot_any, 1'b0};        // (line ~1124) assigns bit 3 too
```

- `$02 & $19` is 0, so this write keeps every bit.
- But it assigns bit 3 from the **old** `via2_ifr[3]` (0), and as the later
  non-blocking assignment it wins over the edge latch in the same clock.
- The edge is gone, and `scsi_d` has already followed, so nothing re-latches
  it.
- The only way out would be a change of the chip's INT, which needs an ISR
  read, which needs the interrupt.
- ASC (bit 4, `if (asc_irq_i && !asc_d) via2_ifr[4] <= 1`) has the same
  window: a sound interrupt can be lost the same way.

**Which side is waiting, and which handshake was missed.**

| side | waiting for | state |
|---|---|---|
| 53C96 engine | the ISR read and the next `$90` TI | phase DATA OUT, INT up, `istatus=$10`, 218 blocks to go |
| guest | a level-2 SCSI interrupt | VIA2 IFR bit 3 = 0 while the chip's INT = 1 |

The missed handshake is the chip's INT edge into VIA2 IFR bit 3. It was
latched and overwritten in the same clock by an unrelated IFR write.

**Why it is rare, and why it fits the hardware.**

- The window is one clock per IFR write.
- The slot/VBL handler writes the IFR twice per VBL: about 160 writes/s at
  the sim's VBL rate, about 130 at the hardware's 67 Hz.
- A 4 MB copy raises about 17,800 SCSI interrupts.
- Expected losses per copy: 17,800 × 160 / 33 M ≈ 0.09 in the sim and about
  0.07 on hardware.
- Observed: 1 stop in 18 distinct-seed copies in the sim; on hardware, 1
  hang in 8 duplicates (5 on `ff404af9` and 3 on `sdprof`).
- The sdprof Main was not the cause. Any change in Main's per-request time
  shifts the interrupt phases and reshuffles which copy is unlucky.
- The disks' interrupt handler is the same ROM on Mac OS 8.1 (the dispatcher
  at `$40809BE0` and the slot handler at `$4088BC56` are ROM code).
- The hardware symptoms match the sim: the pointer moves (VBL at IPL 2 is
  still serviced), the menu-bar clock stops, Main sees no more requests, and
  every written byte is already on the card.

## 4. Proposed fix (not applied to `rtl/`)

`scratch/scsi_hang_20260928/tb/iosb_irqfix.diff`:

```diff
--- a/rtl/iosb.sv
+++ b/rtl/iosb.sv
@@ -1120,9 +1120,19 @@
 				if (sel_via2) begin
 					if (write) begin
 						case (rsel)
-						// bit 1 (any slot) is a live level: see above
+						// bit 1 (any slot) is a live level: see above.
+						// This assignment covers all of via2_ifr[6:0] and
+						// comes after the edge latches, so it must carry
+						// what they set this very clock: bit 3 is the
+						// 53C96 INT LEVEL (the chip holds INT until its
+						// ISR is read), bit 4 an ASC edge arriving now.
+						// Without that, the VBL dispatcher's move.b #$02
+						// (which clears nothing) landing in the clock of
+						// a SCSI INT edge erased it: no level-2 interrupt
+						// ever again for that command, the Finder copy
+						// hung mid-write (docs/scsi-write-hang-20260928.md).
 						4'd13:   via2_ifr[6:0] <= (via2_ifr[6:0] & ~(wbyte[6:0] & 7'h19) & 7'h7D)
-						                          | {5'd0, slot_any, 1'b0};
+						                          | {2'd0, asc_irq_i && !asc_d, scsi_irq_i, 1'b0, slot_any, 1'b0};
 						4'd14:   via2_ier[6:0] <= wbyte[7]
 						             ? (via2_ier[6:0] |  (wbyte[6:0] & 7'h1b))
 						             : (via2_ier[6:0] & ~(wbyte[6:0] & 7'h1b));
```

- **Bit 3** becomes the 53C96 INT level whenever the IFR is written:
  - a write in the edge's clock no longer erases it;
  - a write-1-to-clear while INT is still up leaves it set, so an
    interrupt acknowledged late is not lost either;
  - outside IFR writes, the edge-follow behaviour is unchanged.
  - The observed guest clears bit 3 **before** reading the ISR, so the level
    drops with the ISR read and there is no spurious second call.
- **Bit 4** keeps its edge semantics, but an edge in the write's own clock
  now survives.
- **Area** is a few LUTs.
- **Validation after applying it:** `build_only.sh --check`, the gate (8.1
  copy loop, A/UX), and a Finder duplicate loop of at least 20 copies. At
  the estimated 7 % rate the stock core fails roughly 1 in 14.

**Full-machine proof (g14f).** g14's model and seed, run on
`tree3_irqfix` (the bit-3 half of the fix):

- The run is identical up to the same second `move.b #$2`, which again lands
  on the INT edge. The first ack falls at the same 1,185,206,227.
- After that, the dispatcher reads IFR = `$88` at 1,185,206,430 instead of
  `$82`.
- The SCSI handler runs (`rd ncr.4=90`, `wr via2.d=88`, `rd ncr.5=10`,
  ...), and the next request follows at 1,185,211,791.
- The copy completes: 7,820 reads and 7,738 writes, 10.2 guest s, and the
  final screenshot shows "Big File copy" on the desktop.
- `hcopy` of both files out of the run's disk and `cmp` show the copy is
  byte-identical to the original.
- This held even though the same run (on the stock watchdog) took 35 PDMA
  bus errors from the in-ack stalls and recovered from each.

**Directed test.** `scratch/scsi_hang_20260928/tb/tb_scsi_irq_ack_race.v`
is an iosb + ncr53c96 bench driven over the beat bus like the CPU, with an
HPS model.

- **Part B, the observed bug:**
  - a WRITE(10) of 24 blocks, one `$90` TC=512 per sector, 128 `move.l`
    PDMA beats each;
  - `IFR=$02` written 0..23 clocks after each flush ack falls, sweeping the
    write across the INT edge.
  - The stock `iosb.sv` loses the interrupt at exactly one offset (1): IFR
    `$00`, IPL 0. With the fix, none of the 24 offsets loses it.
- **Part A, the secondary hazard:**
  - the handler acknowledges IFR bit 3 **after** the next INT has already
    risen;
  - the stock core loses it, the fix keeps it pending.
- **Results:** stock `RESULT: FAIL (errors=2)` (log `tb/irq_stock.log`),
  fixed `RESULT: PASS` (`tb/irq_fix.log`).
- **Build:** `tb/run_tb.sh` builds and runs both benches against the stock
  `rtl/iosb.sv` and the two fixed copies. Each bench is `verilator --binary`
  over the bench, an `iosb.sv` and the iosb dependencies, and runs in 0.1 s.
  `verilator/tb_iosb_scc.v` also still passes on both fixed copies.
- **Where it could live:** it would fit next to `verilator/tb_iosb_scc.v` as
  a `make` target.

## 5. Secondary finding: the PDMA watchdog ages during the platform ack

This is a real bug, but not this hang.

- **The code:** `iosb.sv:1300` freezes the A_SDMA watchdog only while
  `io_rd`/`io_wr` are up:

  ```systemverilog
  else if (io_rd == 3'b000 && io_wr == 3'b000) sdma_watch <= sdma_watch + 1'b1;
  ```

- **Why it fails:** `ncr53c96` drops those strobes the clock `io_ack`
  **rises**. hps_io holds `sd_ack` for Main's whole SPI command
  (`EnableIO; spi_w(UIO_SECTOR_WR|ack); spi_block_read; DisableIO`,
  `Mac_Main_MiSTer/user_io.cpp:3743-3746`). The comment above that line
  describes the intent correctly ("while a platform block transfer is in
  flight"), but the code does not implement it.
- **When it fires:** a guest PDMA beat that waits across the ack window
  (reads: FIFO empty until the sector arrives) is bus-errored once the ack
  lasts more than 2^18 clocks (7.94 ms). The normal window is the SPI time,
  110-150 µs; it takes Main being descheduled inside the transfer.
- **In the sim:**
  - g6 and g9 (stalls inside the ack) took 4 and 24 such faults, all on
    reads.
  - System 7.5.5's handler recovered from every one of them: after the
    fault the guest alternates `rd via2.d` (DREQ) and `rd ncr.4` until data
    arrives, then retries.
  - Writes never faulted. The 7.5.5 write path is one `$90` per sector,
    waiting for the interrupt, so no beat waits on a full FIFO during a
    flush.
- **The fix:** freeze the watchdog on `io_ack` too
  (`tb/iosb_watchdog_fix.diff`):

  ```diff
  -		else if (io_rd == 3'b000 && io_wr == 3'b000) sdma_watch <= sdma_watch + 1'b1;
  +		else if (io_rd == 3'b000 && io_wr == 3'b000 && io_ack == 3'b000) sdma_watch <= sdma_watch + 1'b1;
  ```

  - g15 (g9's model on the fix) had 76 in-ack stalls of up to 45 ms and
    0 faults, and completed.
  - g16 (stalls plus in-ack stalls on the fix) completed.
- **Directed test:** `tb/tb_sdma_ack_watchdog.v` runs a blind WRITE(10) and
  READ(10) of 2 blocks with `SDMA_TIMEOUT_BITS=12`.
  - With `ACK_LEN=6000` the stock core faults 3 beats (write beat 132, read
    beats 0 and 128).
  - The fix: 0 faults.
  - Controls on the stock core: `ACK_LEN=500` passes, and so does
    `LAT=20000` with `ACK_LEN=500` (pre-ack latency is already frozen).
- **On hardware:** it plausibly explains the one-off "bus error" at
  "Welcome to Mac OS" on the first boot after a Main install
  (`RESUME-20260927.md`, open issues). That boot is when Linux is busiest
  and Main most likely to be preempted mid-SPI.
- **Related gap:** the ROM's PDMA bus-error handler reads `$50F18300`/`$400`,
  which are not modelled (`docs/scsi/rtl-gap-analysis.md` item 7). That is a
  separate job.

## 6. What the sim does not model

- **Mac OS 8.1.**
  - The duplicate here is System 7.5.5.
  - `QuadSquad8.hda` boots in the harness: desktop at 60 guest s,
    `qs8_desktop_60s.png`, with SimCity2000 and a Photoshop alias on the
    desktop and the Speedometer window open.
  - The three 8.1 runs were stopped before the copy. At about 1/70 real
    time with 16 other runs, each would have needed 4-5 more hours, and at
    about 7 % per copy three runs were unlikely to hit the one-clock window.
  - The dispatcher and slot handler that write the IFR are ROM code, shared
    with 8.1. Whether 8.1's SCSI Manager also takes one interrupt per sector
    (and so as many chances per copy) is not measured.
- **Main.**
  - Main's loop: the model draws each request's latency independently.
    Real gaps are correlated: bursts of fast service, then a 20-45 ms flush.
  - The SPI transfer is modelled only as `+ack_word` pacing. Main being
    preempted inside it (the watchdog case) is an explicit
    `+ackstall` knob, not a measured distribution.
  - Main's reads overlapping the guest's PDMA: there is no overlap in the
    core. The engine serialises each sector, which the sim reproduces
    exactly.
- **Rates.** The VBL rate: the sim's DAFB frame is about 420 k clocks
  (~79 Hz), against about 67 Hz on hardware. It only scales the collision
  probability.
- **Other traffic.** Ethernet (`SONIC(0)` in the sim) and the CD slot are
  off, so there are no other level-2 sources. They would add more IFR
  writes, i.e. more windows.

## 7. Files

`scratch/scsi_hang_20260928/` (gitignored):

| path | what |
|---|---|
| `tree/` | HEAD `b0d7d88` export, release macros, `HANGDBG` taps (`rtl/iosb.sv`), randomised model (`verilator/sim/sim_blkdevice.cpp`), detectors (`verilator/sim_main.cpp`) |
| `tree_fix/` | the same plus the watchdog fix, for g15/g16 |
| `tree2/`, `tree2_fix/` | the tap with its trip armed after boot, and the direction of faulted beats |
| `tree3_irqfix/` | tree2 plus the IFR bit-3 fix, for g14f |
| `tree4/` | tree2 plus the exact-cycle IFR trace, for g14t |
| `golden.hda`, `golden.sha256`, `control_dup.txt`, `control_qs8.txt` | guest disk and control streams |
| `run_one.sh`, `analyze.py`, `runs_summary.txt` | launcher (one `systemd-run --user` unit per run), summary script and its output |
| `runs/gN/` | per-run `run.log.gz`, `run.meta.txt` (plusargs, Vemu sha256), screenshots; `g14r/cpu_trace.log.gz` (400 k instructions around the hang) |
| `tb/` | `tb_scsi_irq_ack_race.v`, `tb_sdma_ack_watchdog.v`, `run_tb.sh`, `iosb_irqfix.{sv,diff}`, `iosb_watchdogfix.sv` + `iosb_watchdog_fix.diff` (both diffs `git apply --check` clean on HEAD), stock and fixed logs |

The `obj_dir` trees and every `run.hda` copy were deleted after the runs.
`golden.hda` (90 MB) is kept as the reproduction input.

**To reproduce g14:**

1. `make -j8 all fastboot` in `tree2/verilator` (with Verilator 5 on the
   PATH).
2. Launch it:

   ```bash
   VTREE=tree2 bash run_one.sh <name> +arm_cycle=1140000000 +lat_min=3300 \
     +lat_max=16500 +lat_seed=14 +ack_word=16 +ackstall_ppm=5000 \
     +ackstall_min=270000 +ackstall_max=400000 +hang_arm=1140000000
   ```

About 45 minutes on this host; the lost interrupt comes at clock
1,185,206,229.
