# RESUME — PRAM persistence through an `.nvr` image (MacLC-style, minimum)

Paste the section below as the prompt for the session that does the work.

---

## Prompt

Add the smallest possible PRAM persistence to the Quadra 800 core, the same
way `../MacLC_MiSTer` does it: a 512-byte `.nvr` save image mounted on hps_io
virtual-drive slot 2. It should load at core start and save back when the
PRAM changes. Read `CLAUDE.md` and `HANDOFF-20260928.md` first; the build,
seed-walk and hardware rules there apply.

### Why

`rtl/rtc3430042.sv` holds the 256-byte XPRAM in one M10K
(`pram [0:255]`, line ~79). Nothing loads or saves it, so it powers up zeroed
at every core load. The ROM sees a bad checksum and writes its defaults, like
a Mac with a dead battery. The known symptom is in the 20260930 release notes
(`releases/README.md:119`, `HANDOFF-20260928.md:130`): the Chooser's port
choice goes back to the Printer port after every load. The array has no
reset, so PRAM already survives an OSD reset. Only core loads lose it.

### The reference: MacLC_MiSTer

`../MacLC_MiSTer/MacLC.sv`:
- CONF_STR `"SC2,NVR,Mount PRAM;"` (line 88). `SC` makes Main remember the
  image in `config/<core>.s2` and re-mount it at every core start.
- The PRAM FSM is at lines ~299-516. It has these parts:
  - a mount latch (`img_mounted[2]` with `img_size != 0` means load; size 0
    means no image);
  - a load: `sd_rd` at LBA 0 → capture 256 bytes from `sd_buff_dout` while
    `sd_ack[2] && sd_buff_wr` → copy into PRAM;
  - a save: fill `sd_buff_din[2]` → `sd_wr` → wait for the ack to fall;
  - a `pram_dirty` flag set by every guest PRAM write;
  - flush triggers: the OSD opening (`OSD_STATUS` rising) and a ~2 s
    settle timer restarted by each guest write ("eager flush", user
    directive 2026-08-19, so a change reaches the SD card without an OSD
    open);
  - a load watchdog with retries, and a "ready" backstop so that a missing
    or slow image never hangs the boot.
- The request handshake follows the SCSI one: drop rd/wr when `sd_ack`
  rises; the sector is done when `sd_ack` falls.
- `releases/MacLC.nvr` is a shipped default image, 512 bytes.

### Leave out what the Quadra does not need

The LC's Egret keeps its own copy of PRAM and copies it into the 68k's
working PRAM at boot, which is why the LC has `pram_ready`,
`pram_restart_after_load`, the `P_LD_CPY` copy loop and a 256-byte `pram_buf`
staging array. On the Quadra the ROM reads the RTC chip directly, and
`rtc3430042`'s array is the only copy. Leave out, at least in this pass:
- the staging buffer (see "RTL shape" below);
- the "WIPE PRAM" R6 option (deleting or zeroing the `.nvr` does the same);
- the MT32/Egret-specific parts.

Keep:
- the load before the CPU reads PRAM;
- the dirty flag;
- both flush triggers (OSD open and settle timer);
- the load watchdog and backstop.

### RTL shape (proposal; confirm it against the RAM Summary)

1. **`rtc3430042.sv`: give the array a host port.** Split `pram` into two
   128x8 banks, even and odd bytes, each a true dual-port M10K:
   - port A is the existing RTC access; `addr[0]` picks the bank and
     `addr[7:1]` the row;
   - port B is a host port that reads or writes one 16-bit word
     (`{odd, even}`) at a 7-bit word index in one cycle.

   This matches the hps_io WIDE word layout directly, so no staging buffer
   and no two-cycle byte sequencer are needed. Also add a `pram_wr_stb`
   output: a one-cycle pulse on any guest PRAM write, i.e. `pram_we`.

   Expected cost: +1 M10K (468/553 today) and a few dozen ALMs. Check the
   `.map.rpt` RAM Summary: both banks must stay M10K, not registers. Also
   check that the host port does not break the `no_rw_check` inference.
2. **Plumb the port up** through `iosb.sv` → `quadra800.sv` → `emu`. It is
   all `clk_sys`, since `quadra800` runs on `clk_sys`, so there is no
   crossing.
3. **`MacQuadra800.sv`:**
   - add `"SC2,NVR,Mount PRAM;"` after `SC1`;
   - replace the slot-2 stubs (`sd_rd[2]`, `sd_wr[2]`, `sd_lba[2]`,
     `sd_buff_din[2]`, lines ~171-184) with the FSM;
   - update the slot comment at line ~142;
   - `sd_blk_cnt` for slot 2 is already `6'd0`, which with `BLKSZ(2)` is
     one 512-byte block.

   hps_io latches `sd_buff_din[sdn_ack]` on the same `'h18` strobe that
   advances `sd_buff_addr` (`sys/hps_io.sv:415`). A registered read from
   port B at `sd_buff_addr[6:0]` therefore has a whole SPI word time to
   settle. Confirm this in `tb` or sim; do not assume it. Words at address
   128 and above are the pad: write 0 on save and ignore them on load.
4. **Load before the ROM reads PRAM.** Hold the machine in `reset` (the
   `wire reset` at `MacQuadra800.sv:374`) until one of these happens:
   - the load finishes;
   - slot 2 reports no image (size 0);
   - a backstop of about 3 s expires.

   Only the *first* load after core start gates reset. A late load, or a
   manual re-mount from the OSD, writes the array and then pulses a
   machine reset, like MacLC's `pram_restart_after_load`. Keep the gate
   outside `reset` itself; the FSM runs on `pll_locked` only, as the mount
   replay does. Watch the interaction with the mount-replay FSM and the ROM
   download hold (`~rom_loaded`). The HPS is busiest at core start (ROM
   download plus every slot mounting), and that is exactly when MacLC's
   load used to stall (its 2026-07-16 black-screen class); copy the
   watchdog.
5. **Default image.** Ship `releases/MacQuadra800.nvr`: 512 bytes captured
   from hardware after a boot with the Chooser set to the Modem port, or
   all zeros if no capture is made. Zeros reproduce today's behaviour, and
   the first flush writes the ROM defaults back. Document it in
   `releases/README.md` and `BUILD.md`, and have the deploy put it in
   `games/MacQuadra800/` and write `config/MacQuadra800.s2`.

### Things to check, not assume

- Does the Main fork (`../Main_MiSTer`, branch `mac-printer-writebuffer`)
  apply its Mac disk write buffer to slot 2 too? If it does, a flush may sit
  in Main's buffer; make sure the buffer is flushed on core unload. Slot 2 is
  not used by `support/mac/mac.cpp`: the Toolbox is 3, CD 4, CD changer 5.
- Is the RTC clock (`seconds[]`) outside the saved image? It must stay
  outside, and keep seeding from `TIMESTAMP`. Saving the clock would bring
  back a stale time.
- Does the write-protect register (`wprot`) stay RTC-only? Host loads must
  bypass it.
- The A/UX 3.1 guest writes PRAM too; the gate covers it.

### Verification

1. **Directed bench:** extend or add a `verilator/tb_rtc_pram` that
   bit-bangs an XPRAM write and read over the VIA protocol. Also drive the
   host port with a load, save and dirty/strobe sequence alongside it.
2. **Full-machine sim:** with a zeroed image loaded, the boot matches
   today's. With a captured image loaded, the ROM does not rewrite the
   defaults: watch the RTC writes in the log.
3. **Synthesis check:** `bash scripts/build_only.sh --check`, then the RAM
   Summary.
4. **Full build:** expect a 2-4 seed walk at 94 % ALMs, and record the seeds
   in the `.qsf`.
5. **Hardware (8.1 gate):**
   1. Set the Chooser to the Modem port and set a desktop pattern.
   2. Shut down cleanly.
   3. `load_core` the same rbf; both settings must survive.
   4. Check that `games/MacQuadra800/*.nvr` changed on the SD card after the
      settle time, without opening the OSD.
   5. Delete the `.nvr` mount: the core must still boot, on defaults, within
      the backstop.
   6. Run the rest of the release gate as usual.
