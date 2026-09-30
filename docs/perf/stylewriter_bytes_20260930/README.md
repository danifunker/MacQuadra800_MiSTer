# StyleWriter driver bytes reach the printer daemon (2026-09-30)

The question was whether any bytes from Apple's StyleWriter driver reach
`mister_printerd` over the modem port. The quality of the emulation did not
matter for this test.

**Yes, the bytes arrive.** The Color SW 2500 driver (version 2.2.1) on the
Mac OS 8.1 disposable disk sent **24 bytes** at 57600 baud. The StyleWriter
build of the daemon parsed every one of them:

- It answered each query. The UART's transmit counter went from 0 to 7 bytes.
- The driver identified the printer: it sent `?`, got `CS\r` back, and then
  queried the sub-model (`p`).

**The driver then sent nothing more.** It went silent after a `B` status
query and an `x` byte. The Desktop Printer Spooler held the CPU for more than
10 minutes, so the Finder clock stopped. Force Quit freed the Mac.

**No image band ever arrived.** The daemon logged "Job was empty, discarding"
and wrote no PDF.

## Setup

**Box:** `10.3.164.251`, core `48a23a786f69d40790b011f0fe28691b` (the trial
build with the inverted CTS bit). Main is the tight-loop build. The `.92` box
was not touched.

**Guest:** slot 0 was the disposable `QuadSquad8-pipeline-test-20260919.hda`.
The master `QuadSquad8.hda` was not touched. CFG byte 0 was `0x40` (32 MB,
Ethernet on).

**Daemon build:**

- Repo `/home/alans/mister/printeremulation`, local branch `stylewriter`
  tracking `origin/stylewriter`, at `6496ead` ("Add a review of the Quadra 800
  core's Z8530 SCC"). That commit sits on `4f2aa3e` ("Map Apple's Color SW 2500
  driver") and `c70981d` ("Add Apple StyleWriter emulation").
- Build command:

  ```
  cd /home/alans/mister/printeremulation
  PATH=/opt/gcc-arm-10.2-2020.11-x86_64-arm-none-linux-gnueabihf/bin:$PATH make arm
  ```

  `make arm` runs `arm-none-linux-gnueabihf-gcc -O2 -Wall -Wextra -Wno-format -Isrc src/*.c -lm`
  and then strips the binary. It built with no warnings.
- Output: `build/mister_printerd.arm`, md5 **`54a71d0047cc5fb6a4426f63b3ab7173`**.
  It was installed as `/media/fat/mister_printerd_stylewriter`, which is left on the box.
- The stock daemon, `/media/fat/mister_printerd` (md5 `24cfa37e6315b6a334dabd77a0dea7a2`),
  was not modified.

**Model option:** `-m auto` does not detect a StyleWriter, so the model has to
be given. The README gives `-m stylewriter`, which is the Color SW 2500. For
StyleWriter models the daemon opens the tty **without** `crtscts` on purpose:
the printer has no flow control, and the replies must go out regardless of
CTS. So `stty` shows `speed 57600` and **`-crtscts`**, not `crtscts`.

## Commands (on the box)

**Stop the stock daemon.** `/sbin/uartmode 7` runs the daemon inside a respawn
loop, so the loop's `bash` pid has to be killed first, then the daemon's pid.
Killing only the daemon brings it back a second later.

```
kill <uartmode-7 loop pid>; kill <mister_printerd pid>
```

**Start the StyleWriter build.** The raw capture goes to `/tmp/printer_stream.bin` (`-D`).

```
cd /media/fat; setsid nohup stdbuf -oL -eL /media/fat/mister_printerd_stylewriter \
  -d /dev/ttyS1 -b 57600 -m stylewriter -c MacQuadra800 -o /media/fat/printers -v -D \
  >> /media/fat/printers/stylewriter_test.log 2>&1 < /dev/null &
```

**Clear RTS** (the inverted-CTS core needs this to read "ready"):

```
python3 /tmp/rts.py off
```

**Load the core.** The guest was at the safe screen first (screenshot checked).

```
echo load_core /media/fat/_Unstable/MacQuadra800.rbf > /dev/MiSTer_cmd
```

**What the core load did.** Main's `uartmode 7` started the stock daemon at
57600 **alongside** the StyleWriter one, because busybox `killall` did not
catch `mister_printerd_stylewriter`.

- Both daemons had ttyS1 open at once.
- Both loops and daemons were killed, and the StyleWriter build was restarted
  as above (pid 16266).
- The checks after the restart:
  - `ls -l /proc/16266/fd`: fd 3 is `/dev/ttyS1`, and no other printerd was running;
  - `stty`: 57600, `-crtscts`;
  - after `rts.py off`: `/proc/tty/driver/serial` shows `CTS|DTR|DSR|CD|RI` (no RTS);
  - baseline `rchar` 13504, ttyS1 `rx:25018 tx:0`.

## Guest side

The Chooser showed these drivers (`chooser_open.png`):

- AppleShare
- **Color SW 1500**
- **Color SW 2500**
- **Color SW Pro**
- ImageWriter
- PSPrinter

AppleTalk was **Inactive**. There is no StyleWriter II driver on the disk.

Changes to the disposable disk:

- **Color SW 2500** was selected in the Chooser. Its port was switched from
  **Printer Port** to **Modem Port** (`chooser_modem.png`).
- This made the Color SW 2500 the default printer. The ImageWriter stays on
  the Modem port, as the last session left it.
- Background Printing stayed **On**: a click meant to turn it off missed.

The print:

- Finder: File → Print Desktop…. The **Color StyleWriter 2500** dialog (2.2.1)
  opened with Normal quality, Plain paper and Color image (`print_dialog3.png`).
- Print was pressed at 03:23:01 UTC.

## Result

**On the wire.** The job capture is `stylewriter_job_20260930_0323.bin`, and
`stylewriter_sampler.txt` samples the port once a second.

| UTC | daemon rchar | ttyS1 rx / tx | bytes |
|---|---|---|---|
| 03:23:01 | 13504 | 25018 / 0 | (Print pressed) |
| 03:23:13 | 13509 | 25023 / 0 | `00 FF FF FF 49`: reset `I` |
| 03:23:16 | 13523 | 25037 / 6 | query `1` → `00`, query `2` → `00`, `?` → `CS\r`, query `p` → `05` |
| 03:23:19 | 13528 | 25042 / 7 | `D`, query `B` → `80`, `x` |
| until 03:35 | 13528 | 25042 / 7 (8 after a test byte) | nothing more |

- **24 bytes in, 7 replies out.**
- The complete stream is
  `00 FF FF FF 49 FF FF FF 31 FF FF FF 32 3F FF FF FF 70 44 FF FF FF 42 78`.
- There was no framing error: the `fe:2` count predates the run.
- The replies went out while the tty ran without `crtscts`.
- The driver's use of `CS\r`: it sent `p` only after `?`, so it read the
  identify reply.
- **Not seen:** the cartridge query `H`, the mode byte `m`, and any `R`/`c`
  rect or `G` band.

**Daemon log** (`stylewriter_test.log`):

```
[printerd] Started new print job: /media/fat/printers/Print_2026-09-30_03-23-12.pdf
[stylewriter] query '1' (0x31) -> 0x00
[stylewriter] query '2' (0x32) -> 0x00
[stylewriter] identify -> CS
[stylewriter] query 'p' (0x70) -> 0x05
[stylewriter] query 'B' (0x42) -> 0x80
[printerd] Inactivity timeout reached (12s), finalizing job...
[printerd] Job was empty, discarding.
```

**No PDF was written** for the job.

### What the Mac showed

**While the spooler held the CPU:**

- No "not responding" dialog and no error alert appeared.
- The desktop printer icon carried a document (the job in progress, `dp_icon_zoom.png`).
- The menu-bar clock **stopped at 3:23**, and stayed there for more than 10 minutes (`print_80s.png`).
- The pointer still moved, so the Mac was not frozen.
- Cmd-. did nothing.

**Tried with no effect:**

- clearing RTS again at 03:26:37 (the next section explains why it was set);
- sending one `00` byte to the Mac at 03:30.

**Force Quit:**

- Cmd-Option-Esc named **"Desktop Printer Spooler"** (`after_forcequit_keys.png`).
- After Force Quit, the clock ran again. A new spooler instance then reported
  "**The serial port is currently in use by another application. Please quit
  that application and print again.**" (`after_fq_click.png`). The
  force-quit spooler had left the modem port driver open.

**What the silence means is not settled.** Two readings fit:

1. **A pre-flight check, then a render that never yields.** Identify, `D`,
   status, `x` (which the driver map lists on the close path). The spooler
   would then be rasterising the 360 dpi colour page without yielding. It
   might have finished eventually; it was given 10.5 minutes.
2. **A wait on something the emulation does not provide.** The expected next
   step after identify is `H` (cartridge). Instead the driver sends `D`, which
   the driver map places at job end. That may mean the driver decided to stop.

CTS is **not** the cause:

- The silence began at 03:23:19, before RTS came back at 03:23:28.
- The driver opens the port with handshaking off (driver map, `SerHShake` all zero).
- Clearing RTS later did not resume the job.

### Operational finding: opening ttyS1 re-asserts RTS

RTS came back twice without `rts.py`: at 03:23:28, and between 03:15 and
03:21. Both times match a `stty -F /dev/ttyS1 -a` check. A Python open of the
tty at 03:30 did the same. Any `open()` of ttyS1 raises RTS again.

On the current inverted-CTS core, that silently turns the Mac's CTS to "busy".
So **any `stty -F` check must be followed by `rts.py off`** until the fixed core
is built.

### Side capture: the core-load glitch

**The bytes are a walking bit, not random noise.** During `load_core`, ttyS1
received 16 bytes, split between the two daemons that had the port open. The
StyleWriter build's 8 are `80 40 20 10 08 04 02 01` (`stylewriter_coreload_glitch.bin`).

The stock daemon took the other 8 and wrote the usual near-blank
`Print_2026-09-30_03-14-39.pdf` (92,770 B, left on the box).

This fits a deliberate output such as a self-test more than a floating line.
That is an inference and was not investigated.

## Restore

- **Guest:** Special → Shut Down via the vmouse recipe reached "It is now safe
  to switch off your Macintosh" at 03:35 UTC. The glyphs were intact (`halt.png`).
- **Daemon:** the StyleWriter build (pid 16266) was killed. Then
  `/sbin/uartmode 0; /sbin/uartmode 7` restarted the stock daemon, as the box does:
  - it runs as `/media/fat/mister_printerd -d /dev/ttyS1 -b 57600 -m auto -c MacQuadra800 -o /media/fat/printers`;
  - `stty` shows 57600 with `crtscts`, and RTS is asserted (the stock behaviour).
- **Speed is 57600, not 9600.** The core load reset `/tmp/UART_SPEED` to the
  saved 57600, and the restart kept it. Before this test the daemon ran at the
  session's OSD value, 9600. The ImageWriter on this core wants 9600: set it
  from the OSD if needed.
- **Left on the box:**
  - `/media/fat/mister_printerd_stylewriter`;
  - in `/media/fat/printers`: `stylewriter_test.log`, `stylewriter_sampler.txt`,
    `stylewriter_job_20260930_0323.bin` and `stylewriter_coreload_glitch.bin`.
- **Disposable disk:**
  - the Color SW 2500 is the default printer, on the Modem port;
  - the job may still be queued in the desktop printer. Its spooler may try
    it again on the next boot, and hold the CPU the same way.

**Not done:** no commit, and no `rtl/` or `.qsf` edit.

## Next steps

- **Emulation side:** find what the driver does after `B` → `80` and `x`.
  - Check whether `D` means "abort" and whether a buffer reply of `0x80` is
    read as "not ready".
  - Then retry with Background Printing **Off**, so that any error dialog
    comes up in the foreground.
- **Core side:** build the corrected CTS polarity, so that RTS no longer needs
  clearing by hand.

## Files here

- `stylewriter_test.log`: the daemon log.
- `stylewriter_sampler.txt`: once-a-second daemon `/proc/PID/io` and ttyS1 counters.
- `stylewriter_job_20260930_0323.bin`: the raw 24-byte job.
- `stylewriter_coreload_glitch.bin`: the core-load bytes.
- Screenshots:
  - `chooser_open.png`, `chooser_modem.png`: the Chooser;
  - `print_dialog3.png`: the print dialog;
  - `print_80s.png`, `dp_icon_zoom.png`: the spooler holding the CPU;
  - `after_forcequit_keys.png`, `after_fq_click.png`: Force Quit and the port-in-use alert;
  - `halt.png`: the halt screen.
- Every capture from the run is in `scratch/stylewriter_bytes_20260930/`.
