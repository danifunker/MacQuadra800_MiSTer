# Built-in Ethernet (DP83932 SONIC) — plan

**Status 2026-09-18: PLAN, awaiting the user's go. Nothing built.**
Goal: the Quadra 800's onboard Ethernet, as small and as fast as possible,
MAC address derived from the MiSTer's own, a runtime (OSD) switch and a build
switch.

## 1. Verdict

- **Emulate the real onboard SONIC at `$5000A000`, not a NuBus card.** The ROM
  and both guests already carry its driver (the Quad Squad disk has "Apple
  Built-In Ethernet"; A/UX 3.1 has its own), so there is no declaration ROM, no
  slot decode and no driver install. This core has no NuBus slot space at all
  (`decode()` bus-errors `$Fs`/`$s0`), and on the MacIIvi the NB card
  enumerates but no driver has bound yet (`MacIIvi docs/resume_enet_hw_ftp.md`).
- **Keep the SONIC chip model on the ARM** (`../Main_MiSTer/support/mac/
  mac_sonic.cpp`, a MAME `dp83932c` port, already in the fork and
  HW-validated on the MacLC). A full SONIC in RTL (register file, 16x48 CAM,
  descriptor walkers, CRC, packet buffers) is an estimated 2,500-3,500 ALMs
  plus M10K and would still need a packet transport to Linux.
- **The donor RTL is `../MacLC_MiSTer/rtl/pds/pds_enet.sv`, not
  `../MacIIvi_MiSTer/rtl/nubus/nubus_enetnbtp.sv`.** The NB card's SONIC only
  masters 128 K of on-card RAM (a DDR3 window). The Quadra's SONIC is a true
  bus master into main RAM — the LC card's problem, solved there by the
  guest-RAM "DMA-RPC" engine. We take that architecture and slim it.
- **New code is needed**, but little: one new RTL module (~450 lines), ~60
  lines of glue in three existing files, and a third "personality" in Main's
  `mac_eth.cpp`. `mac_sonic.cpp` and `mac_eth_iface.cpp` are reused unchanged
  or nearly so.

## 2. Ground truth (MAME `macquadra800.cpp`/`dp83932c.cpp`/`iosb.cpp` vs QEMU `q800.c`/`dp8393x.c`/`q800-glue.c`)

| item | value | MAME / QEMU |
|---|---|---|
| registers | `$5000A000-$5000A0FF`, 64 x 16-bit, **4-byte stride**, data on **D15-D0 = bytes +2/+3** of the longword | agree (`umask32 0x0000ffff` / `it_shift=2`); QEMU also answers at +0, MAME does not |
| mirror | every `$40000` through `$50FFFFFF` — the ROM uses `$50F0A000` | agree; iosb already decodes on the low bits |
| MAC PROM | `$50008000` (`$50F08000`), 8 bytes: `[0..5]` = MAC, **each byte fully bit-reversed**, `[6]`=0, `[7]` = `~XOR([0..5])` | layout/checksum agree. Bit transform differs: QEMU `revbit8` (true reversal) vs MAME's nibble "swizzle". Main's `swizzle()` is in fact a true reversal and is HW-proven with Apple's driver on the LC: **use revbit8** |
| OUI | forced **08:00:07**; only octets 3-5 come from the host NIC config | agree — exactly the MAC policy asked for (§7) |
| IRQ | SONIC INT -> VIA2 port A **bit 0** (slot $9, active low) -> "any slot" IFR bit 1 -> IPL 2 | agree in classic mode. `iosb.sv:443 nubus_irqs` already has the bit, tied idle. QEMU's A/UX mode (GLUE) puts SONIC on IPL 3 — this core has no A/UX interrupt mode today (§9) |
| DMA | physical addresses, big-endian. With `DCR.DW=1` (what the Mac driver sets) every 16-bit descriptor field is one **longword**, value in the low half, upper half written 0 | agree |
| DMA ops | LCAM 4 rd/entry +1; RRA 4 rd; TX: 4 hdr rd + 3 rd/fragment + data + 1 status wr + 1 link rd; RX: data + 4 wr + link rd + in_use wr + status wr (+ EOL link re-read) | agree; QEMU pads RX data to 4 with FCS, MAME does not |
| reset | CR=`$0094`, EOBC=`$02F8`, TCR\|=NCRS\|PTX; SR = 6 (MAME) / 4 (QEMU) | both SR values work for Mac OS |
| QEMU only | `RCR.CRS` set at reset ("cable connected"); WT0/WT1 watchdog -> ISR.TC; DCR writable only in reset | `mac_sonic.cpp` already has the watchdog; add CRS |

## 3. Architecture

```
 guest CPU --beat--> quadra800 svc FSM --S_IOSB--> iosb --sonic_sel--> sonic_mbx
                         ^   (third master, like the MMU walker)          |
                         +------------- DMA longword beats <--------------+
                                         + snoop_stb -> D-cache invalidate
 sonic_mbx <--64-bit single beats--> DDRAM arbiter (MacQuadra800.sv) <--> DDR3 window
                                                                            ^
 Main: mac_eth.cpp (Q800 personality) + mac_sonic.cpp + mac_eth_iface.cpp --+--> eth0/tap0
```

What the FPGA does (module `rtl/sonic_mbx.sv`, all `clk_sys`, `DDRAM_CLK` is
already `clk_sys`):

1. **Register writes -> doorbell ring** in DDR3 (256 x u64, monotonic wptr,
   rptr backpressure with a ~2 ms escape, ~4 ms bus watchdog). Verbatim from
   `pds_enet.sv`; the guest never waits on host software.
2. **Register reads -> one on-demand DDR3 read of the shadow block** (~0.3 us).
   This is the big area lever: `pds_enet`/`nubus_enetnbtp` keep all 64
   registers in 1,024 flip-flops behind a 64:1 mux (most of their 892 ALMs /
   1,500-1,640 registers) and poll 16 shadow words per round. On demand is
   *fresher* (as of Main's last push), costs no storage, and shrinks the poll
   walk from 21 words to 4 (MAGIC, ISR_SET, RPTR/APTR, DMA_CMD), so interrupt
   and DMA pickup are ~5x faster at the same cadence.
3. **ISR and IMR live in the FPGA** (30 flops). Guest write-1-to-clear takes
   effect in its own bus cycle and `irq = |(isr & imr)` is exact. Main raises
   bits through a sequenced `ISR_SET` word; every doorbell entry carries the
   last `ISR_SET` seq the FPGA had consumed (the ring entry's reserved seq
   field), so Main applies an ack only to bits the guest could have seen —
   exact causality. This *replaces* the three hardest-won hacks of the LC
   card (timed ISR clear-mask, 1.85 ms irq-suppression timer, Main's 20 ms
   redelivery guard), which exist only because the LC's ISR is remote, and
   which cap it at a few hundred interrupts per second.
4. **CR command overlay** (10 flops): command bits the guest has written read
   back set until Main's applied-index passes that doorbell. Apple's driver
   spin-polls `CR.TXP` (`mac_eth.cpp:735`), and a stale 0 means "done".
5. **MAC PROM**: on-demand DDR3 read of the 8 cooked bytes. Zero flops.
6. **Guest-RAM DMA engine**: Main posts an ordered **op list** (up to 8 x
   {dir, addr32, len16}) instead of the LC's single op; the engine moves
   longwords between the XFER window and guest RAM *through the machine's
   own service FSM* as a third master beside the CPU and the MMU walker
   (`quadra800.sv` S_IDLE, alternating with CPU beats so neither starves).
   Going through the ordinary beat port buys coherence for free:
   - `sdram_beat32` invalidates the retained BL8 line on any write;
   - the store buffer keeps I/O writes behind older RAM stores, so the
     descriptors are in SDRAM before the CR doorbell exists;
   - each DMA write beat pulses `wombat_cpu.snoop_stb/snoop_addr` — the port
     was left in for this ("SONIC later") and invalidates the D-cache set,
     the 68040's own bus-snoop behaviour;
   - `decode()` must say RAM, else the op ends with the error bit (never ROM,
     VRAM or I/O).
   Op lists cut the ARM round trips per frame from 5-8 to 2-3 (RX: {data,
   descriptor body, link read} then {in_use, status-last}; the LC doc's
   ORDERING LAW — publish word last, nothing touched after — is preserved
   because ops execute in list order).

What Main does: everything else — the SONIC model, CAM filter, CRC,
descriptor walks, the AF_PACKET/TAP bridge, the MAC policy.

Rejected: (a) straight `pds_enet` port with flop shadows, ~900-950 ALMs and
LC-class speed (60-110 KB/s measured); (b) NB card in a NuBus slot, ~900 ALMs
plus slot decode, a declaration ROM asset, and an unproven driver bind;
(c) SONIC in RTL, 2,500-3,500 ALMs.

## 4. DDR3 window v4 (contract; ARM phys `0x1FF00000`, the a2065/LC/NB area — one core at a time, version-stamped MAGIC)

```
+0x0000  16 KiB  XFER     op k's bytes start at the next 8-byte boundary
+0x4000  u64[]   control block
   w0  MAGIC     ARM->FPGA  "McQ8ETH4"; presence gate, sampled in guest reset
   w1  WPTR      FPGA->ARM  doorbell write index (monotonic)
   w2..w17 SHAD  ARM->FPGA  64 regs, reg 4n+k at bits [16k+15:16k] (read on demand)
   w18 ISR_SET   ARM->FPGA  [7:0] seq | [30:16] bits to OR into ISR
   w19 ISR_ACK   FPGA->ARM  [7:0] seq consumed
   w20 MACPROM   ARM->FPGA  8 cooked bytes (read on demand)
   w21 GEO       ARM only   4
   w22 PTRS      ARM->FPGA  [31:0] RPTR (slurped) | [63:32] APTR (applied+pushed)
   w23 DMA_CMD   ARM->FPGA  [7:0] seq | [11:8] op count
   w24 DMA_STAT  FPGA->ARM  [7:0] seq echo | [8] error | [15:12] failing op
   w32..w39 OPS  ARM->FPGA  [0] dir | [31:16] byte count | [63:32] guest address
+0x4800  2 KiB   RING     256 x u64: [0] valid | [3:1] tag | [9:4] reg | [31:16] data | [39:32] ISR_SET seq seen
```

## 5. Core changes

| file | change |
|---|---|
| `rtl/sonic_mbx.sv` (new) | §3. Parameters for the window base. |
| `rtl/iosb.sv` | decode `$A000` regs / `$8000` PROM to a `sonic_*` device port when `sonic_present`, else today's inert read-0 (so Off == today's machine, bit for bit); `nubus_irqs[0] = ~sonic_irq`. |
| `rtl/quadra800.sv` | `parameter SONIC` (like `CDROM`); instantiate `sonic_mbx`; DMA master arm in the service FSM; `snoop_stb/addr`; export the 64-bit `eth_mem_*` port. |
| `MacQuadra800.sv` | third requester on the DDRAM arbiter (ROM beat > ioctl > eth); `O[6],Ethernet (on reset),On,Off;` `O[8:7],Net interface,eth0,tap0,macvlan,eth1;` (bits 35-43 are MT32's, so the LC's `o45`/`o03` positions are taken). |
| `MacQuadra800.qsf`, `files.qip` | the new file in both; `ETHERNET_OFF=1` macro (commented) -> `SONIC=0`: module, master arm and arbiter port generate away. |
| `verilator/` | `tb_sonic_mbx` (port of MacLC `tb_pds_enet.v` + `sim_ddr3.v`), and a `tb_memory_path` case: DMA write then CPU read through the cache must see the new data; DMA interleaved with CPU traffic. Full-machine sim runs `SONIC=0` unless a DDR3 model is attached. |

## 6. Main changes (fork branch `mac-ethernet-pr-with-SCSI-Optimizations`)

- `mac_eth.h`: layout v4. `mac_eth.cpp`: `CARD_Q800` personality on an exact
  `macquadra800` name match (today the core would fall into the **LC**
  personality if `ethernet.rom` existed — wrong window, wrong MAGIC); no
  declaration ROM requirement; 32-bit addresses; op-list RPC backend behind
  the same `sonic_host_ops`; per-personality OSD bit positions; poll on every
  Main loop pass for this personality instead of the 1 ms pace timer; apply ->
  push -> publish APTR ordering.
- `mac_sonic.cpp`: ISR ownership hook (raise-through-`ISR_SET`, seq-qualified
  acks) selected per personality so MacLC/MacIIvi behaviour is untouched;
  `RCR.CRS` at reset. `mac_sonic_test`: DW=1 descriptor cases, op-list
  backend, ack-causality cases.
- `mac_eth_iface.cpp`: add `SIOCGIFHWADDR`.

## 7. MAC address

`08:00:07:xx:yy:zz`, `xx:yy:zz` = the last three octets of the MiSTer's
`eth0` hardware address (of the chosen interface for `eth1`; `eth0`'s for
tap/macvlan; the old fixed scheme only if no interface has an address).
Stable per box, no OSD nibble, never equal to the host's own MAC (different
OUI), and the forced Apple OUI is what both emulators do and what Linux's
`macsonic` requires. `eth.cfg mac=` stays as the override. Wi-Fi-only boxes:
raw bridging with a foreign source MAC does not work on most access points —
that is what the `tap0` option is for.

## 8. Area and speed

Measured donors (Fitter, by entity): `pds_enet` 892 ALMs / 1,293 ALUTs /
1,640 regs / 0 M10K; `nubus_enetnbtp` 892 ALMs / 986 ALUTs / 1,508 regs /
0 M10K. Of those, 1,088 regs + ~340 ALUTs are the shadow file, its mux and
the PROM latch, ~80 ALUTs the LC's V8 address translation, ~40 regs debug
witnesses — none of which we carry.

| block | regs | ALMs (est.) |
|---|---|---|
| bus handshake, watchdog, doorbell, ring pointers | ~190 | 130-160 |
| DDR3 port registers and muxes | ~100 | 80-110 |
| local ISR/IMR, ISR_SET, CR overlay | ~50 | 35-45 |
| DMA engine with op list | ~180 | 130-170 |
| service-FSM master arm + snoop | ~10 | 40-60 |
| DDRAM arbiter port, iosb decode/IRQ | ~10 | 50-70 |
| **total** | **~540** | **~470-620, 0 M10K, 0 DSP** |

Budget **650 ALMs (1.6 %)**. The 20260918 release is 36,089 ALMs (86 %), so
~36,700 (87.6 %) with Ethernet; RAM blocks (490/553) are untouched. It is one
more `clk_sys` block beside a CPU with tenths of a nanosecond of slack, so
expect a seed walk; all new paths are registered at the module boundary.

Speed: a 1,500-byte frame is 375 longword beats (~90 us of SDRAM time) plus
188 DDR3 words (~60 us); hot pickup of a posted command is ~4 x 32 clk =
~4 us. Per-frame cost ~0.3-0.4 ms against 1.2 ms of 10BASE-T wire time, so
the FPGA path is not the limit; the interrupt path (local ISR) and Main's
poll rate are, and both are addressed above. Target: FTP >= 500 KB/s both
ways, stretch = line rate (~1 MB/s). Later levers if needed: DMA reads served
from the retained BL8 line, DDR3 bursts.

## 9. Risks / open questions

1. **Local ISR + on-demand reads + op lists are new**; the LC design they
   replace is HW-proven but slow. Fallback is always available: flop shadows
   and single-op RPC are a superset in the mailbox layout.
2. **A/UX**: QEMU routes SONIC to IPL 3 in A/UX mode; this core has only the
   classic 4/2/1 scheme and A/UX runs on it. Trace QEMU first (does A/UX set
   VIA1 PB6 auxmode; which registers does its driver poll). A/UX networking
   is a second milestone, not part of the first release gate.
3. **Coherence**: the snoop invalidates a D-cache *set* per write beat; verify
   against `ap040_cache` that a fill in flight for the same line is squashed
   (`snoop_fill_row`), in the directed bench, before hardware.
4. **DMA vs a stalled register write**: a doorbell write parked on a full ring
   holds the service FSM in S_IOSB and blocks DMA; Main must keep slurping the
   ring inside its RPC wait (it does) and the 2 ms escape bounds it.
5. **CPU speed with Ethernet idle**: the engine is dormant and the FSM arm is
   one extra term; gate with Speedometer On-idle vs Off vs the 20260918
   numbers.
6. Main hand-relaunch leaves HDMI black on this box: swap Main by rename +
   reboot only (CLAUDE.md).

## 10. Phases (one commit per step; one Quartus flow at a time)

0. **Ground truth traces** — QEMU 8.1 and A/UX with `-trace 'dp8393x_*'`:
   register read/write mix, DCR value, CR/ISR polling, auxmode.
1. **Main** — v4 personality, op-list backend, ISR causality, MAC policy;
   `mac_sonic_test` green in WSL. No hardware needed.
2. **RTL** — `sonic_mbx.sv` + `tb_sonic_mbx`; `build_only.sh --check`.
3. **Integration** — iosb / quadra800 / top / qsf switch; memory-path
   coherence bench; `--check`; RAM Summary unchanged.
4. **Fit + hardware** — seed walk as needed, STA cross-domain script; 8.1:
   DHCP, ping, FTP both ways with `/tmp/mac_eth_stats`; full regression gate
   (8.1, A/UX, CD audio) with Ethernet On and Off; Speedometer.
5. **Speed pass**, then **A/UX networking**, then release with the matching
   Main binary in `releases/`.
