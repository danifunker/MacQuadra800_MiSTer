# Printing through the modem port: 57600 (StyleWriter) and 9600 (ImageWriter)

2026-09-29. Simulation and source reading only; the MiSTer was in use and
nothing here has been run on hardware.

**The problem.** Mac OS 8.1 prints through the core's modem port (SCC channel A,
the only channel wired to the HPS UART, `docs/scc-port-survey.md`) to Main's
"Printer" UART mode (`mister_printerd` on `/dev/ttyS1`). An ImageWriter at 9600
prints correctly. A StyleWriter does not, and the failure looks like a baud-rate
problem. The StyleWriter I/II driver runs the port at 57600 with DTR/CTS
hardware handshake, and the printer has only a small buffer.

## Verdict

**The core's serial path is not the cause.** Channel A sends and receives
57600 8N1 and 9600 8N1 cleanly. The bit period is within 0.015 % of nominal in
both directions, and the receiver tolerates a ±5 % rate error.

**The StyleWriter fails on the Main side.** `mister_printerd` has no StyleWriter
model: no parser for its raster stream and no way to answer the driver's status
queries. The only models are ImageWriter, Epson, Epson-TPS, Adam and MPS-803.
The daemon also has a single speed, with no rate tied to the printer model.

Two outcomes are possible:

- **The daemon runs at 9600** (the rate that makes the ImageWriter work).
  Every 57600 frame then reaches the 9600 receiver as a framing error.
  `cfmakeraw` leaves `INPCK` clear, so Linux passes those bytes through as
  data, and the ImageWriter parser draws random characters. This is the
  "baud-rate problem".
- **The daemon runs at 57600.** The bytes arrive intact, but they are StyleWriter
  protocol that the ImageWriter parser cannot read. Nothing on the tty answers
  the driver's status queries, so the driver stalls or reports that the printer
  is not responding.

**Fix: mainly in Main.**

1. Add a StyleWriter model to `mister_printerd`. It needs a parser for the raster
   stream and a responder that writes status replies back to `/dev/ttyS1`.
2. Give each printer model its own port speed: StyleWriter 57600, ImageWriter
   9600. The speed should be forced by the model, not taken from the shared
   OSD Baud setting.

**A core change is probably needed too.** RR0 CTS should follow `UART_CTS`, so
that the driver's hardware handshake sees the daemon's flow control. Today
RR0 CTS reads a constant 0 (section 1.3). Any StyleWriter emulation that
throttles the Mac depends on this.

---

## 1. Core, 57600 (StyleWriter)

Bench: `verilator/tb_scc_printer.v` (`make tb_scc_printer` from `verilator/`;
the bench's lines start with `TB`; about 3 minutes). It drives the real
`iosb.sv` beat-bus adapter and `scc.v` at `SYS_CLK_HZ = 33_000_000`, as
the machine does.

**Programming.** The bench opens channel A the way a Mac async driver does. The
sequence is reconstructed from Inside Macintosh's SerReset constants
(baud57600 = 0, baud19200 = 4, baud9600 = 10, baud1200 = 94; stop1 + noParity
+ data8 = WR4 $44, x16 clock) and the Z8530 async recipe. It is **not** a
trace of the ROM's own table, but the registers that set the rate are the
ones every Mac async driver writes:

- once: WR9 $C0 (the ROM's hardware reset)
- per open:
  - WR9 $80
  - WR4 $44
  - WR3 $C0
  - WR5 $E2
  - WR11 $50 (Rx and Tx clocks from the BRG)
  - WR12 TC, WR13 $00
  - WR14 $01 (BRG on, source RTxC)
  - WR3 $C1
  - WR5 $EA (DTR + RTS, 8 bits, Tx on)
  - WR15 $08
  - WR0 $10 twice
  - WR1 $00 (the bench polls; the real driver is interrupt-driven)

### 1.1 TX: 64 ASCII bytes, polled on RR0 bit 2

| | 57600 | 9600 |
|---|---|---|
| divider `baud_divid_speed_a` | 573 | 3438 |
| nominal clk/bit (33 MHz / baud) | 572.92 | 3437.50 |
| measured clk/bit (64 start-to-stop-edge spans, 9 bits each) | 573.000 (min = max) | 3438.000 (min = max) |
| error | +0.015 % (57592 baud) | +0.015 % (9599 baud) |
| frames decoded right / bad stop bits | 64/64, 0 | 64/64, 0 |
| idle gap between frames | 2 clk | 6 clk |
| throughput | 5758 of 5760 chars/s | 960 of 960 chars/s |

At 57600 x16, WR12 = WR13 = $00 is the same register image as the
"uninitialised BRG" catch-all. The catch-all only matches x1 clock mode
(WR4[7:6] = 00; fixed in `eed94b3`), so the StyleWriter setting takes the
normal BRG path. Section 1.4 has every setting's divider.

### 1.2 RX: 64 bytes back to back into `rxd_a`, read through RR0 bit 0 and the data register

The 64 bytes are 00, FF, 55, AA, 00, 00, 1B, 11, 13, 0D, then a pseudo-random
fill. They are sent with 1 stop bit and no idle time between frames. The
fractional bit time is accumulated exactly (at 9600, 3437.5 clk/bit alternates
3437 and 3438).

| sender rate | 57600 receiver | 9600 receiver |
|---|---|---|
| nominal | 64/64, 0 wrong, 0 overrun, 0 framing errors | 64/64, clean |
| real HPS UART rate (100 MHz / 16 / divisor: 57339.4 = −0.45 %; 9600.6) | 64/64, clean | 64/64, clean |
| −3 % | 64/64, clean | 64/64, clean |
| +3 % | 64/64, clean | 64/64, clean |
| ±4 %, ±5 % (sweep) | 64/64, clean | — |
| ±6 %, ±7 %, ±8 % (sweep) | **1 byte read**, then nothing | — |
| 57600 sender into a 9600 receiver | — | 1 byte, framing error, then nothing |

The 100 MHz `l4_sp_clk` behind the HPS UART figures is an assumption. It is not
read from the box.

Two properties of the `rxuart` (wbuart32) receiver behind these numbers:

- **It is all-or-nothing on a continuous stream.** After reset, and after any
  framing error, it waits for the line to idle for 16 bit times (`line_synch`)
  before it accepts another start bit. In the bench, one frame sent with a 0
  stop bit at byte 20 of a back-to-back 57600 stream lost all 43 bytes after
  it. Short replies with idle time between them are unaffected. A long reply
  stream with one bad bit loses its tail.
- **The Mac cannot see receive errors.** RR1 reports overrun and framing errors
  as constant 0, and the Rx FIFO is 3 bytes deep. A channel reset (WR9 $80)
  does not empty that FIFO; only the WR9 $C0 hardware reset does.

### 1.3 Handshake lines

| signal | what the core does |
|---|---|
| RR0 bit 5 (CTS) | **constant 0**, whatever the pin does: $04 with the CTS pin at 1 and at 0 (`rr0_cts_a = 1'b0`, `scc.v`) |
| RR0 bit 3 (DCD) | constant 0 |
| `UART_CTS` (the HPS UART's RTS) | ignored: `serialCTS = 1'b1` in `MacQuadra800.sv`, and txuart's `i_cts_n` is tied 0 |
| WR5 DTR / RTS bits | stored, but no pin: `scc.v` has no DTR output |
| core `rts` pin → `UART_RTS` → HPS UART CTS | `rx_queue_pos_a > 0`, i.e. **0 while the Rx FIFO is empty, 1 while a byte waits** (measured) |
| `UART_DTR` | looped from `UART_DSR` |

The framework's UART handshake lines are active low. The Apple III core wires
`UART_CTS`/`UART_RTS` straight to its 6551's `cts_n`/`rts_n`. So the core's
`rts` works as a sensible active-low "ready" for the HPS transmitter: Linux,
with `CRTSCTS`, may send while the Mac's FIFO is empty and holds off while a
byte is unread.

In the other direction there is no flow control. The Mac never sees Linux's
RTS, so it can neither be throttled nor told that a printer is ready.

**Would a driver waiting for CTS stall?** The ImageWriter prints with RR0 CTS
stuck at 0. So whatever handshake the ImageWriter driver sets up, it does not
hold output on CTS = 0.

The polarity the Mac Serial Driver treats as "clear to send" is not settled
here:

- **MAME's model** (`z80scc.cpp` `cts_w`): a ready device (pin low) sets RR0
  bit 5 to 1.
- **The Mac's HSKi line receiver** sits between the connector and the pin. Its
  polarity was not checked in this investigation.

If the StyleWriter driver enables CTS handshake and reads RR0 CTS = 0 as
"busy", it never sends a byte. On hardware that shows as an **empty** capture
on ttyS1 (section 4), not as garbage.

**Would a driver that ignores CTS overrun the receiver?** Not at the line
level: 57600 into a 57600 receiver is clean. The receiving side is the Linux
tty, which buffers up to 64 KB before dropping, so the daemon is not the
bottleneck. What is missing is a real printer's "buffer full" signal, and no
emulation that decodes more slowly than 5.7 KB/s can provide one without the
CTS change above.

### 1.4 BRG catch-alls (`scc.v` around lines 1640-1690) for every Serial Driver rate

The bench programs each setting and reads the divider back:

| WR4 | TC | rate | divider | result |
|---|---|---|---|---|
| $44 / $4C | 0 | 57600 8N1 / 8N2 | 573 | ok (57592) |
| $44 | 4 | 19200 | 1719 | ok (19197) |
| $44 / $4C | 10 | 9600 8N1 / 8N2 | 3438 | ok (9599) |
| $44 | 22 | 4800 | 6876 | ok |
| $44 | 46 | 2400 | 13752 | ok |
| $44 / $4C | **94** ($5E) | **1200** | **4** | **CATCH-ALL: 8.25 Mbaud** |
| $44 | 189 | 600 | 54721 | ok |
| $4C | 190 ($BE) | 600 8N2 | 100 | CATCH-ALL |
| $04 (x1) | 0 | — | 4 | CATCH-ALL (by design) |

Neither printer rate (9600, 57600) nor 19200 falls into a catch-all.

**1200 baud does.** The ROM selftest special case (WR12 = $5E, WR13 = 0,
WR4 = $44 or $4C) is exactly the Serial Driver's baud1200 setting. So any
application that opens the modem port at 1200 8N1 or 8N2 gets 4 clk/bit, which
is garbage. That is a separate bug, not a printing one. The fix is to qualify
the special case on the selftest's own state (for example, loopback enabled)
rather than on the register image alone.

## 2. Core, 9600 (ImageWriter baseline)

The 9600 columns in 1.1 and 1.2 are the baseline: 3438 clk/bit (+0.015 %),
64/64 TX frames correct, and RX clean at nominal, at the HPS rate and at ±3 %.
This agrees with the user's report that the ImageWriter prints.

## 3. Main side (`../Mac_Main_MiSTer`, branch `mac-printer-fujinet-tightloop`)

### 3.1 How the daemon's port speed is chosen

- **The mode.** Printer is UART mode 7. `SetUARTMode(7)`
  (`user_io.cpp`) sends mode and baud to the core over SPI; the core ignores
  `uart_speed`. It writes `/tmp/UART_SPEED`, then runs `uartmode 7`.
  `/sbin/uartmode` is on the box's Linux image and is **not in any repo here**.
  The comment in `menu.cpp` MENU_BAUD2 says "Printer and FujiNet are
  restarted by /sbin/uartmode at the new speed", so the script presumably
  passes `/tmp/UART_SPEED` to `mister_printerd -b`. Without `-b` the daemon
  uses `DEFAULT_BAUD` 9600 (`printer.h`).
- **The OSD Baud value for mode 7.** `GetUARTbaud(7)` is
  `mlink_speeds[mlink_speed_idx]`, the MidiLink list 110 … 115200. Modem,
  UDP, SNI, Printer and FujiNet all share it. At core load it is set by
  `ValidateUARTbaud(4, speeds[2] ? speeds[2] : uart_speeds[0])`, and
  `uart_speeds[0]` is the CONF_STR token's first value.
- **So the CONF_STR's 57600 does leak into the printer speed.** With no saved
  `uartspeed.MacQuadra800`, Printer mode would start at **57600**, not 9600. That
  the ImageWriter prints means the saved Modem/Printer baud is 9600, or that
  the script ignores `UART_SPEED`. Either way the ImageWriter setup puts the
  daemon at 9600, and the StyleWriter then transmits at 57600 into it.
- **The printer model does not change the speed.** `GetPrinterModel` and
  `SetPrinterModel` only write `/tmp/PRINTER_MODEL`. The OSD models are
  Auto, ImageWriter II, Epson FX-80, Coleco Adam and Commodore 803. "Epson
  FX-80" writes `epson-tps`, and "Auto" writes `auto`, which the daemon's
  `-m` parser treats as ImageWriter. **There is no StyleWriter model or
  parser.**
- **termios** (`open_serial_port`): `cfmakeraw`, the chosen speed, CS8,
  `CLOCAL | CREAD`, `CRTSCTS`, `VMIN = VTIME = 0`. `INPCK` is off, so
  characters with framing errors are delivered as data. Under a rate mismatch
  that is how garbage reaches the parser instead of being dropped.

### 3.2 The daemon's read loop

`poll(500 ms)`, then `read(fd, buf, 512)`, then each byte goes to the parser.
There are no sleeps. PDF output happens at form feed or page overflow
(`job_commit_page`) and at the 4 s inactivity timeout (`job_finalize`), both
inside the loop.

While those run, input piles up in the kernel: n_tty's 4 KB plus flip buffers
up to 64 KB. That is about 11 s at 57600 and over a minute at 9600. Losing
bytes to the daemon's pace is therefore unlikely at either rate.

The daemon **never writes** to the tty. That is fine for the ImageWriter
(one-way). It rules out any printer whose driver waits for answers.

### 3.3 The ImageWriter parser (`parser_imagewriter.c`)

- CR resets the head to the left margin; LF advances a line; FF commits the
  page. Printable 32-126 are drawn with a 5x7 font.
- It handles:
  - `ESC T nn` (line pitch)
  - `ESC K c` (colour)
  - `ESC G`/`S`/`g` + 4-digit length + graphics bytes
  - the pitch letters `n N E e q Q p P`
  - `ESC A` / `ESC B`
  - `ESC c` / `ESC ?`, both treated as reset. On a real ImageWriter II,
    `ESC ?` asks for the ID string; no reply is sent.
- Other ESC pairs are skipped.

StyleWriter data run through this parser gives scattered characters or blank
pages.

## 4. Most likely cause, and what to try when the box is free

**Most likely cause:** there is no StyleWriter emulation on the Main side, and
the daemon's speed is whatever the shared OSD baud says (9600 for the
ImageWriter). The StyleWriter's 57600 stream therefore reaches a 9600
ImageWriter parser as garbage. Even at 57600 there is no parser, and nothing
answers the driver's status queries. On the core side, the only open item is
the CTS polarity question in section 1.3.

**The change that fixes it:**

- **Main:**
  - a `stylewriter` model in `mister_printerd`: a raster decoder plus a status
    responder that writes back to the tty (the open-source `lpstyl` driver
    documents the protocol);
  - a per-model speed override (StyleWriter → 57600, ImageWriter → 9600);
  - a "StyleWriter" entry in `config_printer_models`.
- **Core:** drive RR0 CTS (and optionally DCD) from `UART_CTS`, with the
  polarity the Mac driver expects, so the daemon can hold the Mac off the way
  the printer's small buffer does. After that, a CTS change interrupt
  (WR15 bit 5) becomes meaningful too.

**Hardware checks** (all read-only until the last). Do not disturb a running
guest (CLAUDE.md binding rules).

1. `cat /sbin/uartmode` shows how mode 7 starts the daemon and whether it
   passes `-b "$(cat /tmp/UART_SPEED)"` and `-m "$(cat /tmp/PRINTER_MODEL)"`.
2. Check the live settings:
   - `ps w | grep printerd` shows the actual arguments.
   - `cat /tmp/UART_SPEED /tmp/PRINTER_MODEL` shows what Main set.
   - `stty -F /dev/ttyS1 -a` shows the real speed and `crtscts`; it works
     while the daemon holds the port.
3. Capture the raw StyleWriter stream. In the OSD, set UART mode Printer and
   Baud 57600. Stop the daemon (`killall mister_printerd`), then run
   `stty -F /dev/ttyS1 57600 raw -echo crtscts; cat /dev/ttyS1 > /media/fat/printers/stylewriter.raw &`.
   In the guest Chooser, select StyleWriter on the Modem Port (AppleTalk
   inactive), then print one page. Read the result with `xxd stylewriter.raw | head -40`:
   - Clean ESC-led records mean the line is right, and what is missing is the
     parser and responder.
   - An **empty** file means the driver is holding on CTS (section 1.3) or
     waiting for a reply before it sends any data.
   - Repeat at 9600 to see the garbage the current setup produces.
4. Loopback sanity check at 57600, independent of any printer driver. Set the
   OSD UART mode to None, run `stty -F /dev/ttyS1 57600 raw -echo`, then
   `cat /dev/ttyS1` in one shell and `printf 'hello\r' > /dev/ttyS1` in
   another. Use a guest terminal program (ZTerm or similar, Modem Port,
   57600 8N1, handshake off) to type and receive.
5. Confirm the 1200-baud catch-all bug (optional): with the same terminal
   program at 1200 baud, the host sees nothing sensible.


## Addendum, same evening: what changed in the core, and the daemon branch

The user reports that with a new StyleWriter branch of the printer emulation
(the daemon trying 57600) **no data reached the daemon at all**. That is the
handshake signature rather than a rate one: the StyleWriter driver waits for
the printer's DTR, which is the SCC's /CTS, and RR0's CTS bit was a constant
"not ready" in this core, so the driver never transmitted. Two core changes
landed (`rtl/scc.v`, `MacQuadra800.sv`):

1. **RR0 CTS is now the real pin.** `serialCTS` is `UART_CTS` (the HPS UART's
   RTS as the framework presents it, active low like /CTS), synchronised with
   two flops, and RR0 bit 5 reads its inverse as on the Z8530: a daemon or
   pppd opened with RTS/CTS flow control reads as "clear to send". DCD stays 0.
   `tb_scc_printer` now shows RR0 $24 with the pin low and $04 with it high.
   A daemon that does not assert RTS will still hold a handshake-honouring
   driver off, which is the correct behaviour and the same as before.
2. **The 1200-baud bug (review finding 3):** the ROM-selftest shortcut
   (WR12 $5E, WR4 $44/$4C -> 4 clocks per bit) is gated on local loopback,
   which is how the ROM runs the test, and the diagnostic-disk 600-baud
   shortcut is simulation-only. Real 1200 and 600 baud ports now run at their
   rates. `tb_scc_midi`'s ROM-style loopback prelude still passes.

Not changed: RR1 still reports no receive errors, the receiver still waits 16
idle bit times after a framing error, Tx Empty still asserts at end of
character (review findings 5 and 6 and the framing note above).

**For the daemon branch:** open the tty at 57600 8N1 with `crtscts` (so Linux
asserts RTS and the Mac sees CTS), answer the driver's status queries, and
check `stty -F /dev/ttyS1 -a` on the box shows 57600 with `crtscts` while a
job is pending. With RR0 CTS live, the first thing to look at if the Mac
still sends nothing is the polarity: RR0 must read $2x while the daemon has
the port open.


## Hardware result, 2026-09-29 late (trial build 48a23a78, `docs/perf/p262_trial_hw_20260929`)

The first CTS draft had the polarity backwards for the Mac. With the printer
daemon holding RTS the Mac reported "The Printer is not responding"; with RTS
cleared by hand it sent 24,978 bytes at full 9600 speed and the daemon produced
a correct two-page PDF. So the Mac's drivers read RR0 bit 5 = 0 as clear to
send, which is what the old constant 0 gave them and why the ImageWriter always
printed. The core now passes the framework's active-low `UART_CTS` through
UNinverted: a daemon with the port open (RTS low) reads as ready, no daemon
or a dropped RTS holds the Mac off. This is now real flow control in the Mac
-> daemon direction, which is what a StyleWriter's small buffer needs.

Consequence for the StyleWriter: with the corrected polarity an open daemon
reads exactly as before the change, so the fact that no data reached the
StyleWriter daemon is not the CTS bit; the missing piece is the daemon's
status replies (the driver queries the printer before sending) and 57600
with `crtscts` on the tty. Also seen on the box, unrelated to the core's SCC:
a near-blank PDF appears in `/media/fat/printers` at every core load (line
noise during the load, Main-side); the guest's ImageWriter on the disposable
disk is now set to the Modem port.
