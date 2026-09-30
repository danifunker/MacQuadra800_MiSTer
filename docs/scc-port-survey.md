# SCC port survey — MacLC -> wombat33 (Quadra 800)

Survey date 2026-08-31, branch `scc-ppp-midi-mt32`. Source core:
`../MacLC_MiSTer` @ `e7da76f`.

## Status (2026-08-31, branch `scc-ppp-midi-mt32`)

| phase | state |
|---|---|
| 0 — `scc.v` + `txuart.v`/`rxuart.v` in, `files.qip` updated | **done** |
| 1 — `sel_scc` decode, beat-bus adapter, IRQ to `iosb`/`quadra800` | **done** |
| 2 — top-level serial, CONF_STR `UART` token (**PPP**) | **done** |
| 3 — baud constants re-timed for 33 MHz, gates re-run | **done** |
| 4 — MT32-pi instance, OSD page, I2S mix, info popup | **done** |
| 5 — LCD overlay composited into `VGA_R/G/B` | **done** |
| Quartus full compile | **successful**, timing met at **+0.062 ns** |
| hardware boot on `.143` | **PASS** — clean boot to the Finder with the SCC live |
| PPP / MIDI / MT32-pi end to end | **not yet** — needs guest-side setup |

Fitted cost of the whole feature set: **82 % -> 85 % ALMs** (+1,213), registers
28,980 -> 29,886, DSP 47 -> 51. Worst slack fell from +0.243 ns to **+0.062 ns**
— it met, but that is the number to watch on the next netlist change.

The hardware boot is the result that mattered. The SCC space used to decode as
present-but-inert (reads 0, writes discarded, always acked), so the ROM's
`InitSCC` and loopback selftest now get real answers for the first time. That
is not a quiet failure mode when it goes wrong — the sibling `lbmactwo` core
hit it and the ROM dropped into the Test Manager (`lbmactwo/docs/new-scc.md`).
This core walks straight through to the desktop, and the Serial Driver loads
without the freeze that had to be fixed on the LC.

What is left is guest-side, not RTL: a PPP client plus MacTCP/OT to exercise
PPP, a MIDI application for MIDI, and a physical Pi on the user port for
MT32-pi. The "Browse the Internet" and "Mail" icons already on the test image
are the obvious PPP targets.

Simulation gates, all green:

| gate | result |
|---|---|
| `verilator/tb_scc_midi.v` | PASS — unchanged, still at its 32.5 MHz default |
| `verilator/tb_scc_baud.v` | PASS — 57600 -> 564 clk/bit |
| `verilator/tb_iosb_scc.v` | PASS — **new**, covers the adapter |

`tb_iosb_scc.v` is the one to keep green for anything touching the bus side: it
exercises the address decode, channel independence, the back-to-back access
case (the too-early-ack trap), and measures 1056 clk/bit on `scc_txd_a` end to
end — i.e. 31250 baud at 33 MHz, proving the clock parameter reached the
instance inside `iosb` and not just the module default.

## Status check (2026-09-27)

- **Modem port (channel A)** is the only port wired out: `UART_TXD/RXD/RTS`
  (OSD UART modes PPP / Console / MIDI / Modem-MidiLink; 57600/115200 and MIDI
  31250), TX also to the MT32-pi.  Handshake is not modelled: RR0 CTS and DCD
  read constant 0 (`rr0_cts_a`/`rr0_dcd_a` in `scc.v`), `UART_CTS` is ignored,
  and `UART_DTR` is looped from `UART_DSR`.
- **Printer port (channel B)** has its UART inside `scc.v`, but `txd_b` ends
  at `serialOutB` (unconnected) and `rxd_b` is tied idle.  No LocalTalk.
- PPP, MIDI and MT32-pi are still untested end to end on this core.
- Main's new "Printer" UART mode (`mister_printerd`, branch
  `mac-printer-writebuffer`) drives the MiSTer UART, i.e. this core's modem
  port; Main reports the mode to the core as `uart_mode == 7`.  Routing
  channel B to the UART in that mode would give the Mac a real printer port.
  **Decision (user, 2026-09-27): leave the UART on the modem port for now so
  PPP cannot break.**  An ImageWriter set to the modem port may work with the
  Printer mode as is (untested; the baud rates must match).
- **2026-09-29, printing:** the ImageWriter at 9600 prints; a StyleWriter
  (57600, DTR/CTS handshake) does not.  `verilator/tb_scc_printer.v` shows
  channel A clean at 57600 and 9600 both ways (573 / 3438 clk/bit, +0.015 %,
  RX tolerant to +-5 %), so the cause is Main-side: `mister_printerd` has no
  StyleWriter model, never answers the driver, and runs at one OSD-chosen
  speed.  Also found: RR0 CTS ignores `UART_CTS` (no flow control towards the
  Mac), and the ROM-selftest BRG catch-all hijacks the Serial Driver's
  **1200 baud** setting (TC=94, WR4=$44/$4C -> 4 clk/bit).  Details and the
  hardware checks: `docs/serial-printer-20260929.md`.

## Decision (2026-08-31): port the LC's `scc.v`, use MAME as an oracle

Considered: port from MacLC, transliterate MAME's `z80scc.cpp` / QEMU's
`escc.c`, or write a full Z85C30 from the datasheet. **Ported from MacLC.**

Evidence that settled it:

- **The file is already proven across machines.** `MacIIvi_MiSTer/rtl/scc.v` is
  byte-identical to MacLC's (line endings only), and the IIvi is a different
  machine with a different ROM, I/O at `$50000000` and SCC at `+$4000` — the
  Quadra's neighbourhood, not the LC's `$F04000`/V8 world. The "it is full of
  LC-specific hacks" worry is mostly wrong.
- **It carries fixes that cost real hardware time.** `MacLCII_MiSTer`'s copy
  looked like a cross-machine variant (257 lines apart) but is just *older*: it
  lacks the `post_loopback` RX-gate removal (without which async channel A is
  permanently dead after the ROM loopback selftest), the RR2B modified vector,
  the deferred FIFO pop, the WR0-pointer race fix, and `wr11_*` (so no MIDI at
  all). Rediscovering those here costs a Quartus fit plus a hardware boot each.
- **MAME/QEMU are not sources.** `z80scc.cpp` is 3050 lines of event-driven
  behavioural C++; `escc.c` is 1123 and *less* complete. Neither is
  synthesizable, and neither models the part that actually bites — bus timing,
  when the pointer is consumed, when the FIFO pops. Both are kept as reference
  oracles for register semantics instead.
- **A datasheet-complete Z85C30 is the most work for the least payoff.** The
  Mac uses a narrow slice (async 8N1, plus SDLC for LocalTalk); WR7' and the
  ESCC extras are unused.

What the choice does **not** buy: the bus adapter. Every prior integration
(LC, LCII, IIvi) hangs off the same minimigmac 16-bit `dataController_top.sv`
with `_cpuLDS`/`_cpuUDS`; the IIvi instance still says `// Mac LC:` in its
comments. wombat33's 32-bit beat bus needed a fresh adapter, and that cost is
identical whatever the SCC came from.

## Summary — read this first

**wombat33 has no SCC.** `find -iname '*scc*'` over this repo returns nothing.
The three requested features are therefore not three independent ports: PPP,
MIDI-over-SCC and MT32-pi all sit on top of one Z8530 (`rtl/scc.v`, 1985 lines)
that does not exist here yet, plus the top-level serial plumbing that connects
it to the MiSTer framework.

Realistic order of work:

1. Port the SCC and its two serializers, wire it into the IOSB decode -> the
   machine has a serial port.
2. Connect channel A to `UART_TXD`/`UART_RXD` -> **PPP works** (PPP is not RTL;
   it is what you get once the guest's TX/RX reach the HPS UART).
3. MIDI is already inside the ported `scc.v` (WR11/TRxC path) -> it works as
   soon as the CONF_STR carries the `UART...,MIDI` token.
4. MT32-pi is top-level only, and `sys/mt32pi.sv` **is already in this repo,
   byte-identical to MacLC's** (verified: differs by line endings alone).

So the expensive, risky part is step 1. Steps 2-4 are mostly transcription.

---

## 1. Inventory — what MacLC actually has

| file | lines | role | port? |
|---|---|---|---|
| `rtl/scc.v` | 1985 | Z8530/85C30. Both channels, 3-byte RX FIFO each, WR0-WR15/RR0-RR15 subset, two-stage pointer state machine, interrupt + RR2B modified vector, BRG, WR11 clock-source select, SDLC/LocalTalk latch bits | **yes** |
| `rtl/uart/txuart.v` | 1138 | TX serializer, instantiated as `txuart_a`/`txuart_b` | **yes** (hard dep) |
| `rtl/uart/rxuart.v` | 467 | RX serializer, instantiated as `rxuart_a`/`rxuart_b` | **yes** (hard dep) |
| `sys/mt32pi.sv` | 283 | framework MT32-pi module (MIDI out, I2S in, I2C detect, LCD overlay) | **no — already present here and identical** |
| `verilator/tb_scc_midi.v` | 449 | the regression gate for any SCC serial/baud/FIFO edit | **yes** |
| `verilator/tb_scc_baud.v` | 88 | BRG divider capture | yes |
| `docs/SCC_gaps.md` | 87 | MAME/SuperMario comparison | reference only, **partly stale** |
| `MacLC.sv` ~L783-900 | ~120 | serial + MT32-pi + overlay top-level plumbing | adapt, do not copy |
| `rtl/dataController_top.sv` L1080-1102 | 23 | the `scc s(...)` instance | re-derive for the beat bus |

`docs/SCC_gaps.md` is worth reading but is behind the code: it says `scc.v` is
955 lines (it is 1985) and lists "only one serial channel exposed" as an open
gap, but `rxd_b`/`txd_b_out` are ports today. Treat its **Gap 3 (byte lane)**
and **Gap 5 (RTxC clocks)** as still-live — they are exactly the two things the
Quadra port has to re-decide anyway.

### The commit trail worth reading

```
6c33401  scc: MIDI over SCC — WR11 capture + TRxC 31250-baud path; mt32pi + MIDI uart token
7c743eb  scc: lift post_loopback 'no cable' RR0/RX gates — async ch A was permanently dead after ROM selftest
49786ad  scc: RR2B modified vector in Status-Low mode — the cozyMIDI/Serial Driver freeze
eed94b3  scc: fix 57600 baud collision with the uninitialized-BRG catch-all
759b128  working serial port for console and ppp (#6)
```

`7c743eb` and `49786ad` are hard-won bug fixes found on real hardware; they are
in `scc.v` and come across for free, which is the main argument for porting the
file wholesale rather than writing a fresh SCC.

---

## 2. What wombat33 has today

Good news — the hooks are already cut:

| here | state |
|---|---|
| `rtl/iosb.sv` | has `input scc_irq` (port exists), and the IPL encode `scc_irq ? 3'b011` = **level 4**, already correct |
| `rtl/iosb.sv` header | documents SCC space as "present-but-inert: reads 0, writes discarded, always acked" |
| `rtl/quadra800.sv:225` | `.scc_irq(1'b0)` — tied off |
| `sys/hps_io.sv:170` | already exports `uart_mode` — identical to MacLC, **no framework change needed** |
| `sys/mt32pi.sv` | already the full LCD-overlay-capable version |
| `wombat33.sv:35` | `assign USER_OUT = '1;` — user port tied off |
| `wombat33.sv:36` | `assign {UART_RTS, UART_TXD, UART_DTR} = 0;` — UART tied off |
| `wombat33.sv:61` CONF_STR | no `UART...` token, no MT32-pi page |

So no framework surgery is required. Every change is in `rtl/` plus the top
level plus the CONF_STR.

---

## 3. The three features, precisely

### PPP

There is no PPP in the RTL and never was. PPP is host-side (`pppd` or `tcpser`
behind MidiLink on the HPS). The RTL contract is exactly four lines:

```verilog
assign UART_TXD = serialOut;
assign serialIn = UART_RXD & userport_midi_in;   // see the gate below
assign UART_RTS = serialRTS;
assign UART_DTR = UART_DSR;
```

plus the CONF_STR UART token (`"...;UART57600:115200,MIDI;"`), which is what
makes the Main offer UART modes and report `uart_mode` back.

**The one lesson that must survive the port** (MacLC.sv L800-811): an earlier
`mt32_available ? mt32_midi_rx : UART_RXD` mux repointed guest RX at the Pi's
MIDI-return line whenever a Pi was detected, killing *every* guest-receive path
while TX kept working. PPP was what exposed it — LCP hung because the guest
never saw pppd's ConfAck. The fix, and the shape to copy:

```verilog
wire userport_midi_in = (uart_mode == 8'd3) ? mt32_midi_rx : 1'b1;
assign serialIn = UART_RXD & userport_midi_in;
```

Outside OSD UART-mode = MIDI, `serialIn` is `UART_RXD` alone and the user port
can never hijack guest receive. Both lines idle high, so the AND-merge is inert
until something actually transmits.

MacLC status: **HW-validated 2026-08-13**, LCP + IPCP on System 7.5.5 including
guest FTP.

### MIDI over SCC

Entirely inside `scc.v`; nothing extra at the top level beyond the CONF_STR
token and the RX merge above.

- WR11 capture: `wr11_a`/`wr11_b`, `scc.v` L723-750. Hardware reset leaves them
  0 (RTxC for both) so the TRxC clause stays inert until a guest selects it —
  pre-MIDI boot behaviour is bit-identical.
- TRxC baud clause: `scc.v` L1587-1600. Mac MIDI interfaces feed **1 MHz** into
  the serial port's HSKi pin (wired to the SCC's TRxC input); drivers program
  `WR11=$28` (RX+TX clock from TRxC) + `WR4=$84` (x32) for 31,250 baud with the
  BRG **disabled**. `scc.v` models a permanently-attached 1 MHz TRxC source:
  `clocks_per_baud = 32.5 * mult` (x32 -> 1040 exactly at 32.5 MHz).
- Priority is correct-by-construction: WR11 source selection wins over
  `WR14[0]`, as on real silicon.

One baud divider serves both directions, so RX at 31250 comes free — that is
what made MIDI **IN** work (2026-08-14) on top of MIDI **OUT** (2026-08-12,
cozyMIDI -> MidiLink/MT32-pi).

### MT32-pi

Top-level only. `sys/mt32pi.sv` is already here, so this is `MacLC.sv` L816-900
plus the OSD page:

- instance: `.midi_tx(serialOut | mt32_mute)`, `.midi_rx(mt32_midi_rx)`, I2S
  return `mt32_i2s_l/r`, `.mt32_available`.
- audio: I2S joins the mix at **unity gain**, gated by
  `mt32_use = mt32_available & ~status[24]`; exact zeros otherwise.
- OSD page `P1`: Use MT32-pi `status[24]`, Synth `status[26]`, Munt ROM
  `status[28:27]`, SoundFont `status[31:29]`, Show Info `status[23:22]`.
- Show Info = Yes: `mt32_info_req` / `mt32_info_disp` on `clk_sys` -> hps_io
  `info_req`/`info` -> the CONF_STR `"I,"` string list.
- Show Info = LCD-On/LCD-Auto: `mt32_lcd_en/pix/update` from the module, an
  `mt32_lcd_on` timeout on the video clock, and an overlay composited into the
  final `VGA_R/G/B` with ao486's dim-and-OR:
  `mt32_lcd ? {{2{mt32_lcd_pix}}, r[7:2]} : r`.

`docs/mt32pi_onscreen_display_resume.md` in MacLC is the step-by-step for the
overlay half and is worth reading before attempting it.

---

## 4. Quadra 800 deltas — do NOT copy MacLC verbatim

This is where the port will actually go wrong. Each row is a real difference:

| | MacLC | wombat33 (Quadra 800) | action |
|---|---|---|---|
| **address** | `$F04000-$F05FFF` via V8 / `addrDecoder.v` | `$5000C000-$5000DFFF` (`MacQuadra800_HardwareConfig.md` L231); in this core all of `$5xxxxxxx` routes to `iosb` | add `wire sel_scc = in_low && (addr[19:13] == 7'b0000110);` beside `sel_via2`/`sel_djmemc`, plus its rdata/ack path |
| **bus** | 68020-ish 16-bit, `cs = selectSCC && (LDS or UDS asserted)`, `wdata = cpuDataIn[7:0]` (a TG68K-specific choice, see SCC_gaps Gap 3) | 32-bit AP68040 beat bus with `be[3:0]`, single-cycle ack | **re-derive; highest-risk item.** MAME wraps the 8-bit core in a 16-bit shim (`macquadra800.cpp:163`) |
| **reg select** | `rs = cpuAddrRegLo = cpuAddr[2:1]` | same A2:A1 -> `addr[2:1]` | confirm against MAME `dc_ab` (bit0 = A/B, bit1 = D/C) *through* the Quadra wrapper |
| **clock** | `clk_sys` = **32.5 MHz**, `cep`/`cen` = 8 MHz enables | `clk_sys` = **33.000 MHz** (`wombat33.sv:177`), iosb `ce` tied high | see the baud warning below |
| **IRQ** | `._irq(_sccIrq)` (active low) -> `!_sccIrq ? 3'b011` | iosb wants **active high**: `scc_irq ? 3'b011` | connect `.scc_irq(~_sccIrq)` at `quadra800.sv:225` |
| **DCD** | tied `1'b1` (ADB mouse, not SCC quadrature) | Quadra 800 is also ADB | tie `1'b1` the same way |
| **`wreq`** | connected to `sccWReq`, which then goes nowhere | n/a | leave dangling, or drop the net |
| **chip** | 85C30 modelled as a simplified 8530, no WR7' | Quadra 800 is also 85C30 | same limitation, no new risk |

### The baud-constant warning

`scc.v` has **32.5 MHz baked into it numerically**, not parameterised:

- `baud_divid_speed_a = 24'd3385` — the 9600-baud default
- the TRxC/MIDI expression `(mult << 5) + (mult >> 1)` = `32.5 * mult` -> 1040
- `cpb = base * (32.5 / 3.672)` in the BRG path
- the fast-path catch-alls (`24'd4`, `24'd100`)

At 33.000 MHz every one of these is **~1.5% low**. That is inside async 8N1
tolerance (a 10-bit frame tolerates roughly 2-3%), so it will most likely just
work — but it should be re-derived rather than inherited, and, more
importantly, **`tb_scc_midi.v`'s expected values are asserted tight** (1040 +/-
2 clk, and 3387 for the BRG regression). Ported unchanged onto a 33 MHz
testbench clock those assertions fail for the wrong reason. Re-time the
constants and the testbench together, in one commit, or the gate is useless.

---

## 5. Suggested port order

| phase | work | done when |
|---|---|---|
| 0 | copy `rtl/scc.v`, `rtl/uart/txuart.v`, `rtl/uart/rxuart.v`; add the three `VERILOG_FILE` lines to `files.qip` | it elaborates |
| 1 | `sel_scc` in `iosb.sv`, byte-lane/rs mapping, `~_sccIrq` to `quadra800.sv` | ROM SCC selftest passes; no boot regression |
| 2 | top-level: `serialIn/serialOut/serialCTS/serialRTS`, UART pins, CONF_STR UART token | **PPP** |
| 3 | re-time baud constants for 33 MHz; port + re-time `tb_scc_midi.v` | gate green |
| 4 | `mt32pi` instance, audio mix, OSD `P1` page, `"I,"` strings | **MT32-pi audio + MIDI** |
| 5 | LCD overlay into `VGA_R/G/B` | Show Info = LCD-Auto |

Phases 2 and 4 are the two that deliver user-visible features; 1 and 3 are the
ones that will eat the time.

## 6. Gates

- `verilator/tb_scc_midi.v` is **the** regression gate for any SCC
  serial/baud/FIFO edit (build command in its header; section 3 is MIDI-in RX at
  31250; keep the ROM-style loopback prelude). Port it in phase 3, re-timed.
- This repo's existing law still applies: any netlist change re-rolls placement,
  so the per-fit hardware video gate is mandatory before calling a build good.

## 7. Open questions — worth settling before phase 1

1. **Byte lane through the Quadra's 16-bit SCC wrapper.** Needs a read of
   `macquadra800.cpp:163` + the `dc_ab` decode. Getting this wrong makes every
   register write garbage while still "working" enough to look alive.
2. **Does the Quadra ROM's SCC selftest differ from the LC's?** Commit
   `7c743eb` lifted `post_loopback` "no cable" gates that were tuned to the LC
   ROM's selftest. If the Quadra ROM probes differently, that area is the first
   place to look.
3. **Channel B / printer port.** MacLC v1 is channel A only — `txd_b_out`
   dangles at the dataController. Do we want full B here (it is the LocalTalk
   port), or match MacLC and defer?
4. **Does the Quadra 800 even want the modem path?** This machine has built-in
   SONIC ethernet (`MacQuadra800_HardwareConfig.md` recommends MacTCP/OT over
   ethernet instead). PPP here is for the period dial-up experience and for
   parity with MacLC, not because it is the fast path.
