# releases/

Dated core builds, named `wombat33_YYYYMMDD.rbf` (the convention the sibling
Mac cores use). The date is the **work date** the build belongs to, not
necessarily the wall-clock minute Quartus finished — an overnight session that
starts on the 29th is stamped `20260829` even if the fitter returned after
midnight.

Each entry records the md5 so a core on a MiSTer can be identified without
guessing, and the timing margin, because a build that fits but violates timing
must never be flashed (`scripts/deploy_screenshot.sh` refuses one).

| build | md5 | timing | notes |
|---|---|---|---|
| `MacQuadra800_20260930.rbf` | `49951492d3576add9470bc1d1ef28e5d` | met, **+0.310 ns setup (HDMI) / +0.219 ns hold worst** (`clk_sys` +0.507, `clk_ram` +0.834; crossings +1.201 / +0.507) | **Release polish: the three `Dbg` OSD lines are gone, an OSD Scale option (Normal / V-Integer / Narrower and Wider HV-Integer) through the framework's `video_freak`, the 12in 512x384 monitor option is back, and the SCC's CTS bit reads the way the Mac serial driver wants, so printing over the Modem port works with the daemon's RTS asserted and a printer that drops RTS gets "not responding".** Room made by keeping the FPU state frame once (P263, -159 ALMs / -595 registers); the CPU and disk paths are otherwise 20260929_2's: PR 1.267, Disk 2.488, FPU 0.961-0.968 warm, Mix 1.808, 4 MB duplicate 5.24 s median, 0 hangs in 10; all four Scale modes and 512x384 through OSD resets; ImageWriter prints at 9600; idle and Shut Down clean. Known: PRAM starts zeroed at every core load, so the Chooser's port choice must be made again after a load. **Use with `MiSTer_20260928`.** A/UX and CD audio still not run. Seed 24; 39,300 ALMs (94 %). |
| `MacQuadra800_20260929_2.rbf` | `f769b9e1ef496428be071d4ded9e90ae` | met, **+0.299 ns setup (CPU and HDMI) / +0.207 ns hold worst** (`clk_ram` +0.678; crossings +0.707 / +0.600) | **Disk 45 % faster: the 53C96 engine's sector buffer is two halves in the same M10K, so the platform transfer of sector n+1 overlaps the guest draining sector n, and a write flushes one half while the guest fills the other.** Speedometer PR Disk 1.70 -> **2.46** (72 % of a real Quadra 800), a 4 MB Finder duplicate 6.68 -> 4.95 s, read phase 1.65 -> 2.1-2.4 MiB/s, write 1.0 -> 1.4-1.5 MiB/s; CPU, FPU (0.976), Mix (1.807) and Graphics unchanged; 30 duplicates with no hang; idle and Shut Down clean. Everything else as 20260929. **Use with `MiSTer_20260928`.** A/UX and CD audio still not run. Seed 27; 39,246 ALMs (94 %). |
| `MacQuadra800_20260929.rbf` | `dc281d649d54f1cbbddd4650423e204b` | met, **+0.110 ns setup (HDMI) / +0.250 ns hold worst** (`clk_sys` +0.864, `clk_ram` +0.409; crossings +1.128 / +0.867) | **20260928 plus the IOSB interrupt fix: a Finder copy could hang mid-write** when the ROM's VBL dispatcher wrote the VIA2 IFR in the clock the 53C96 raised its interrupt (the edge was lost; about one copy in ten to twenty). Also the PDMA watchdog no longer ages through a slow acknowledge. Found by reproducing the hang in the full-machine sim with randomised sector latency; directed benches in `verilator/`. Hardware: 30 Finder duplicates over two boots with no hang, PR Disk 1.70 with the tight-loop Main, FPU 0.96-0.98, idle and shutdown clean. **Use with `MiSTer_20260928`** (the tight disk service loop, PR Disk 1.62 -> 1.74). A/UX and CD audio still not run. Seed 31; 39,102 ALMs (93 %). |
| `MacQuadra800_20260928.rbf` | `b7e88b8163679a607680e2e80669f396` | met, **+0.006 ns setup (HDMI) / +0.220 ns hold worst** (`clk_sys` +0.103, `clk_ram` +0.612; crossings +1.432 / +0.586) | **The FPU catches the real Quadra 800: Speedometer 4.02 FPU Benchmarks 0.973 on hardware (0.684 on the 2026-09-27 build; a real Quadra 800 scores 1.011), Benchmark Mix 1.803 (1.781), Color 8-bit unchanged.** Nine CPU commits (P250..P258): FP decode and operand fetch overlap the running FP op, FADD/FMUL in 4 clocks, results written back in the rounding clock, S/D operands unpacked and packed at dispatch, d16 and indexed FP operands resolved in the decode clock, exception prefetch in longwords, FSAVE/FRESTORE loops tightened. Mac OS 8.1 gate passed (24 valid benchmark runs, idle clock, clean shutdowns). **A/UX 3.1 and CD audio NOT run on this bitstream** (the images are no longer on the test box). Needs a Main with the Quadra support and the Mac write buffer (`45182b73` or the FujiNet/printer `ff404af9` it was tested with). Seed 31 with `PLACEMENT_EFFORT_MULTIPLIER 2.0` and `ROUTER_TIMING_OPTIMIZATION_LEVEL MAXIMUM`; 39,191 ALMs (94 %), 468 M10K, 36 DSP. |
| `MacQuadra800_20260919.rbf` | `933b421a0880177be1b5fb2861dcea15` | met, **+0.107 ns setup / +0.190 ns hold worst** (HDMI +0.107, `clk_ram` +0.415, `clk_sys` +0.622) | **Built-in Ethernet.** The Quadra 800's onboard DP83932 SONIC at its real addresses, so Apple's own driver binds to it: DHCP, ping, FTP both ways byte-exact, on Mac OS 8.1 with Open Transport. OSD **Ethernet (on reset)**, default Off; needs the Main binary `releases/MiSTer`. With it Off the machine is the 20260918 one. Carries three `Dbg ...` bring-up lines in the OSD: leave them at On. |
| `MacQuadra800_20260918.rbf` | `fde49a3cf474d5c07aff26c592200125` | met, **+0.204 ns hold / +0.527 ns setup worst** (HDMI +0.527, `clk_ram` +0.668, `clk_sys` +0.772) | **The CPU pipeline increments: Speedometer 4.02 Benchmark Mix 0.9285 (0.855 on 20260916_2, +8.6 %), Color QuickDraw 0.670, on a core 1,055 ALMs smaller.** A one-clock data-cache hit on a dedicated hint bus, redirects that hint and issue their target from the retire that pops them (BRA/BSR/JSR/JMP, DBcc, short Bcc), pops/pushes/MOVEM issued in place, a one-clock posted store with a write-side MMU verdict, and a read that may pass one queued store to another line. Mac OS 8.1 and A/UX 3.1 (32 MB) pass the gate; eight Mix runs + CQD + FPU with zero anomalous values. **The CD-audio item of the gate was NOT run on this bitstream** (the CD/SCSI RTL is unchanged from 20260916_2). Seed 21; 86 % ALMs. |
| `MacQuadra800_20260916_2.rbf` | `8552a4094e151bf7b853916a9099e2c2` | met, **+0.244 ns setup** (HDMI +0.255, `clk_sys` +0.442, `clk_ram` +0.851) | **The AP68040 vendored into the repo with Adam Polkosnik's September fixes** (replaces the 2026-09-17 00:42 file `ab1da889`, same SCSI/CD RTL, whose CPU clock missed by 0.231 ns): memory bitfield reads sized by span, FPSP BUSY-frame FRESTORE resume (the Quadra ROM uses it), MOVEM saved-EA/SSW.CM continuation, nonresident ATC entries, our memind reserved-encoding fix, shared ALU adders and FPU normalizer, the integer register file in MLABs. Cycle-identical to the 20260915 CPU on the sim gates; Speedometer 4.02 Benchmark Mix **0.855** (0.858 on 20260915), Color QuickDraw 0.641 over four depths (8-bit 0.629 vs 0.605), Performance Rating 0.810. Mac OS 8.1 boots with a second disk and a CD mounted; A/UX and CD audio not re-run on this file (unchanged RTL outside the CPU, gated on `ab1da889`). Ships with `releases/MiSTer_20260916` (`431da61a`). Seed 21; 37,144 ALMs (89 %). |
| `MacQuadra800_20260916.rbf` | `1eae0fb7ed8de620751af3efb94047fb` | met, **+0.247 ns setup** (HDMI +0.442, `clk_sys` +0.729, `clk_ram` +0.732) | **The CD-ROM target's responses come from the ARM (SCSI offload phase 1): -510 ALMs, timing met.** INQUIRY, MODE SENSE, READ TOC and the Apple status commands are served by the Main fork through window reads of the CD slot; MODE SELECT, eject and the resets are forwarded through a command block with STATUS held until the ARM acks. **Requires the Main fork `ae708d3` or later for any CD image.** Mac OS 8.1: Finder in 126 s with the retail ISO, idle clock in step over 4 min, keyboard, the CD's window, both guest volumes of the retail disc put away from the Finder, the OT ISO hot-mounted from the OSD and put away, the retail disc re-mounted, `mac_shutdown.sh` to the halt screen in 61 s; Speedometer not re-measured (the restored Quad Squad image lacks it; the CPU/SDRAM path is unchanged from 20260915). A/UX 3.1 at **32 MB**: desktop in 120 s, `uname -a` = `A/UX localhos 3.1 SVR2 mc68040`, `shutdown -h now` to the halt screen in 131 s. **Known: A/UX 3.1 hangs its shutdown when the RAM option is 128 MB, on this build and on 20260915 / 20260908_3 alike (six runs); run A/UX at 32 MB.** Seed 21; 38,128 ALMs (91 %). |
| `MacQuadra800_20260915.rbf` | `4c80a3be96cb46992d00002484f9f67a` | **VIOLATED by 0.095 ns on the HDMI domain** (one `sys_top` `hdmi_dv_hs -> hs` register); `clk_sys` +0.712 ns, `clk_ram` positive | **Alan Steremberg's checkpoint-15 AP68040 (`167c5e8`) with the multi-site sequencer tasks hoisted (R1..R4, `8778213`), and the 53C96 fix for the Mac OS 8.1 boot hang it exposed.** Speedometer 4.02 Benchmark Mix **0.858** (0.462 on the 2026-09-12 store head, 0.360 on 20260908_3), CQD 0.605, FPU 0.449. Mac OS 8.1 Finder in 106 s, clean shutdown; A/UX 3.1: multiuser desktop in 148 s, `uname -a` = `A/UX localhos 3.1 SVR2 mc68040`, `shutdown -h now` to the halt screen in 127 s. Shipped as a marginal build by decision (2026-09-16): the miss is on the framework's video output register, not on the CPU clock. Seed 22; 38,711 ALMs (92 %). |
| `MacQuadra800_20260908_3.rbf` | `71102b391b375ebc9614d80432136611` | met, **+0.444 ns setup** (clk_sys +0.797, clk_ram +0.927) | **The CD-ROM refuses MODE SELECT block-length changes like QEMU; ships with the rebased Main fork binary (`MiSTer_20260908`, upstream 20260907 + Mac SCSI family + multi-block CD fill).** Same CPU, CD and multi-block cache as 20260908_2. Both OSes pass the gate. The retail CD shows twice on the Quad Squad desktop: traced to that system folder (QEMU reproduces it from the same disk image; a fresh 8.1 install shows one icon), not the core. Seed 21; 98 % ALMs, 476 RAM blocks. |
| `MacQuadra800_20260908_2.rbf` | `61da22443a3a66ac385eaa3ddc53e3de` | met, **+0.171 ns setup** (clk_sys +0.358, clk_ram +1.008, hold +0.243) | **The same CPU and CD, plus the multi-block SCSI cache, with composite Y/C back in.** Every hps_io transaction moves an aligned 8-sector group instead of one sector; the cache's tag bitmaps are sized to the slot (32/32/16 sectors here); the framework's ALSA path and two scaler refinements are compiled out, Y/C stays. Mac OS 8.1 desktop in 136 s (151), ROM CD boot in 107 s (146). Both OSes and the CD boot pass the gate. Seed 19; 98 % ALMs, 476 RAM blocks. |
| `MacQuadra800_20260908.rbf` | `b882d3fce60b63fac4ab1284755031d6` | met, **+0.343 ns setup** (clk_sys +0.415, clk_ram +0.609, hold +0.158) | **Alan Steremberg's next AP68040 (`5aa596f`) with the CD-ROM still in.** Speedometer 4.02 Benchmark Mix 0.360 (Q605 = 1.0; 0.231 on 20260901), Color QuickDraw 0.317, FPU 0.250. Fits at 98 % with balanced synthesis, the framework's trimmed PLL reconfig core for 512x384, the CD passed through the block cache, and composite Y/C + ALSA compiled out. Both OSes and a CD boot pass the gate. Known cosmetic: the CD can appear twice on the Mac OS 8.1 desktop (the Main's 60 s re-insert; fixed in source after this build). Seed 19. |
| `MacQuadra800_20260907.rbf` | `03f83c62d92d997e5cdf89efbb99c42f` | met, **+0.250 ns setup** (clk_ram +0.721, clk_sys +0.850) | **Mac OS 8.1 installs from the retail CD end to end; SCSI block cache.** Fixes the installer deadlock (a write flush's ack followed cur_tgt across a target switch), adds a per-target read-ahead / write-behind block cache in front of hps_io (32/24/8 KB), ROM CD boot, 512-byte CD block mode, CD audio in the mix, Drive Setup's MODE SENSE page, the 12" 512x384 monitor option. Verified on hardware against BOTH Mac OS 8.1 and A/UX 3.1. Tracer off; seed 19; 91 % ALMs, 502 RAM blocks. |
| `MacQuadra800_20260902.rbf` | `91cf5d727920e387c5cefdf18dc695f4` | met, **+0.420 ns setup / +0.195 ns hold** | **First MacQuadra800 release; Alan Steremberg's CPU/SDRAM speed-ups merged.** BL8 open-page SDRAM, related-clock handoff, retained 16-byte line into the AP040 cache, two-entry store buffer, store-hit cache update. Speedometer 3.23 CPU PR 2.66 → 3.88 on Alan's runs. Verified on hardware against BOTH A/UX 3.1 and Mac OS 8.1. Seed 19; 85 % ALMs. |
| `wombat33_20260902.rbf` | `70716e92871448d1ff81ebb430902f4a` | met, **+0.130 ns** | **A/UX 3.1 boots to multiuser.** Both NCR53C96 SCSI bugs fixed (control-path phase flip + write-path chunk-flush). First build verified on hardware against BOTH A/UX 3.1 and Mac OS 8.1. Tracer off; seed 13; 85 % ALMs. |
| `wombat33_20260901_2.rbf` | `d1d785de28439d132333a1c9e3aab5c5` | met, **+0.270 ns setup / +0.241 ns hold** | Related-clock SDRAM handoff: 151 ns reads, 22.0 MB/s simulated sequential RAM, Speedometer 3.23 CPU PR 2.917. |
| `wombat33_20260831_2.rbf` | `4414e7b3294b3d554a9e43faa16682bd` | met, **+0.062 ns** | **The machine has a serial port.** Ports the Z8530 SCC from MacLC onto the beat bus, plus MIDI-over-SCC and MT32-pi. 85 % ALMs — watch the slack. |
| `wombat33_20260831_1.rbf` | `3901ef5705f58dba3279c0417412f5f8` | met, +0.243 ns | **Sound works.** Fixes the watch-cursor wedge (ASC FIFOSTAT reported an empty FIFO as full) and hooks up the $806 volume slider. |
| `wombat33_20260830.rbf` | `64c79dfb93ceefb549200c78671cdc31` | met, +0.248 ns | **ADB actually works** — the mouse button reaches the guest and motion stops inventing input. |
| `wombat33_20260829.rbf` | `4c46a65c3a48b44ddb6f4fd6808d0422` | met, +0.245 ns | First build that boots Mac OS unattended. |


## `MiSTer` — the Main binary that goes with the Ethernet core

md5 `fbb540c8a51134cfdc960a8b5115807b`. The Main fork
(`danifunker/Main_MiSTer`, branch
`mac-ethernet-pr-with-SCSI-Optimizations-with-q800-eth`, commit `6919c21`),
built from a clean object tree on 2026-09-19 with
`scripts/build_main_wsl.sh` (no object older than the day in the link). On top
of what `MiSTer_20260916` carries (the Mac SCSI family support, CUE/CHD discs,
the BlueSCSI Toolbox, CD audio) it has the Quadra 800 onboard SONIC Ethernet
service (`support/mac/mac_eth*`, `mac_sonic*`, `docs/ethernet.md`) including
Alan's guard that never posts a DMA op list over one the engine has not
finished. It is named plain `MiSTer` so it can be copied to `/media/fat/` as it
is: keep the old binary (`mv MiSTer MiSTer.prev_<md5>`), copy this one in,
`sync` and reboot — never `cp` over the running binary, and never judge it
after a hand relaunch over ssh.

Installed on the `.143` box that way on 2026-09-19; the user confirmed the
menu and the display working. It is meant for the Ethernet core built from
`add-ethernet` (`b2e5377` and later), released as `MacQuadra800_20260919.rbf`
(below); the older released cores run under it with Ethernet simply absent.

### `MiSTer_20260928` — Main with the tight disk service loop

md5 `75e00b65d443e17c288c3297e5e93caf`. `alanswx/Main_MiSTer` branch
`mac-printer-fujinet-tightloop`, commit `be6604e` (one commit on the
FujiNet/printer/write-buffer build `b4192cd`, md5 `ff404af9`), clean build
2026-09-28; passes both CLAUDE.md greps. After serving a Quadra 800
hard-disk request on slot 0/1 it spins on the SD status for up to 250 us
and keeps serving while requests keep coming, for at most 2 ms per pass,
instead of waiting a whole Main pass for every 512-byte sector
(`MAC_SD_SPIN_US` / `MAC_SD_BUDGET_US` environment overrides, spin 0 = the
old behaviour). On `MacQuadra800_20260928.rbf`: Speedometer PR Disk
1.704 / 1.745 / 1.741 (1.52 for the instrumented spin-0 control, 1.62 on
`ff404af9`), 4 MB Photoshop duplicate 6.68 / 6.69 / 6.94 s (7.34 for the
control, about 7.2 on `ff404af9`), mouse and guest Ethernet unaffected
(`docs/perf/disk_tightloop_20260928/production.md`). Install as for the
binary above; no inittab change is needed.

## `MacQuadra800_20260930.rbf`

md5 `49951492d3576add9470bc1d1ef28e5d`, sha256
`2627bf94d547200cfc5d2151b9487b21e379f145e3e0bb2945246f188cf7ccf0`, seed 24,
the 20260928 recipe with `VIDEO_512_OFF` dropped. **Timing met on every
clock**: `clk_sys` +0.507 ns, `clk_ram` +0.834 ns, HDMI +0.310 ns, worst hold
+0.219 ns, crossings +1.201 / +0.507 ns. 39,300 ALMs (94 %), 24,668
registers, 468 M10K, 36 DSP. Built 2026-09-30 from `6ce38c8` on
`add-ethernet` (the `.qsf` at `b89ab9e`). Seed walk:
`docs/perf/p263_fpga_20260930` (seeds 27 and 28 failed routing, 31 missed the
CPU clock, 23 missed HDMI only and was hardware-trialled first,
`docs/perf/p263_hw_20260930`).

**What is new: the release polish.** The three `Dbg ...` bring-up lines are
gone from the OSD (the store buffer, SDRAM line and DMA snoop fast paths are
simply on, as in every release since 20260919). The OSD has a **Scale**
option (Normal, V-Integer, Narrower HV-Integer, Wider HV-Integer) through
the framework's `video_freak`, and the **12in 512x384** monitor option is
back (`pll_cfg`, about 360 ALMs). The SCC's RR0 CTS bit now reads the way
the Mac serial driver expects, so printing over the Modem port with the
daemon's RTS asserted works again and a printer that drops RTS gets "The
printer is not responding" instead of a stalled queue. To make room, the
FPU's state frame is kept once (P263: the core's FRESTORE staging and the
FPU's duplicate copies are gone, -159 ALMs / -595 registers,
`docs/cpu-fsave-compaction-20260929.md`); the CPU is otherwise the
20260929_2 one, so every FPU/disk figure is unchanged within boot-to-boot
spread.

**Hardware** (`docs/perf/p263_release_hw_20260930`, disposable Quad Squad copy,
32 MB, `MiSTer_20260928`; the seed-23 trial of the same RTL in
`docs/perf/p263_hw_20260930`): Performance Rating five runs, PR 1.267, CPU
0.896, Disk **2.488** median (20260929_2: 1.266 / 0.896 / 2.462); FPU 0.953
cold, 0.961 and 0.968 warm (0.976; the difference is the Matrix Multiply
subtest's boot-to-boot spread, 0.68-0.75 s over five runs on this RTL);
Benchmark Mix 1.808 (1.807); ten Photoshop duplicates, median 5.24 s
(4.98-5.27; 20260929_2 4.95 s, whose two write modes both recur), 0 hangs;
Scale Normal 960x720, the three integer modes 640x480, back to Normal; 12in
512x384 desktop through an OSD reset and 13in 640x480 through another, halt
screens intact; Print Desktop to the ImageWriter on the Modem port at 9600
with RTS asserted, 19,146 bytes at line rate and a two-page PDF, no alert
(at seed 23 the same job with RTS dropped by hand gave "The printer is not
responding" and resumed when RTS returned); four minutes idle with the
clock in step; three clean Shut Downs.

**Known on this build:** PRAM powers up zeroed at every core load
(`rtl/rtc3430042.sv`), so the Chooser's serial-port choice for the printer
reverts to the Printer port after a load and must be set to Modem Port
again; after an OSD reset the guest clock re-seeds to the core-load time.

**Main:** `MiSTer_20260928` (the tight disk service loop). **Gate status:**
Mac OS 8.1 passed on the shipped bitstream; A/UX 3.1 at 32 MB and CD audio
still not run (the images are not on the test box).

## `MacQuadra800_20260929_2.rbf`

md5 `f769b9e1ef496428be071d4ded9e90ae`, sha256
`28c40b4b3999ca2f64d783892c13da760d17fadebb6fff3cfae5f2b2d38bdfa9`, seed 27,
the 20260928 recipe. **Timing met on every clock**: `clk_sys` +0.299 ns,
`clk_ram` +0.678 ns, HDMI +0.299 ns, worst hold +0.207 ns, crossings +0.707 /
+0.600 ns. 39,246 ALMs (94 %), 468 M10K, 36 DSP. Built 2026-09-29 from
`2b30d64` on `add-ethernet` (the `.qsf` at `d2a9207`).

**What is new: the ping-pong sector buffer (P260).** The 53C96 target's
sector buffer is 512 x 16 in the same single M10K, two 256-word halves. A
READ prefetches the next sector into the idle half as soon as the platform
channel and that half are free, while the guest is still draining the active
one; the halves swap when the active one is spent. A WRITE flushes a full
half and hands the other to the guest at once; intermediate chunks complete
with the flush in flight, the command's last chunk still waits for its flush
so STATUS GOOD means the data was accepted. Before this the engine raised the
next request only after the guest had drained or filled its single buffer,
so every sector cost the SPI transfer plus the guest's drain in series.
Qualified in the full-machine sim with randomised sector-service latency (18
of 18 copies byte-identical, 18-34 % faster) and by two new directed tests in
`tb_ncr53c96` (T21 the ROM boot shape, T22 random-timing 8-block READ/WRITE),
`docs/perf/p260_pingpong_sim_20260929`.

**Hardware** (`docs/perf/p260_hw_20260929`, disposable Quad Squad copy, 32 MB,
`MiSTer_20260928`): Performance Rating five runs, **Disk 2.462 median**
(20260929: 1.699; real Quadra 800 3.443), PR 1.266 (1.211), CPU / Graphics /
Math unchanged; 30 Photoshop duplicates on one boot, median **4.95 s** (6.68),
read phase 2.06-2.36 MiB/s (1.65), write phase 1.37-1.53 MiB/s (0.94-1.01);
FPU 0.951 cold / 0.976 warm, Benchmark Mix 1.807; 0 hangs in 30 copies; four
minutes idle with the clock in step; Shut Down to the halt screen.

**Main:** `MiSTer_20260928` (the tight disk service loop). **Gate status:**
Mac OS 8.1 passed; A/UX 3.1 at 32 MB and CD audio still not run.

## `MacQuadra800_20260929.rbf`

md5 `dc281d649d54f1cbbddd4650423e204b`, sha256
`c12571b540f0f1c34165f608499c1d759f626b1b33f894f23c3190c64fed1273`, seed 31,
the 20260928 recipe. **Timing met on every clock**: `clk_sys` +0.864 ns,
`clk_ram` +0.409 ns, HDMI +0.110 ns, worst hold +0.250 ns, crossings +1.128 /
+0.867 ns. 39,102 ALMs (93 %), 468 M10K, 36 DSP. Built 2026-09-29 from
`f9f6da6` on `add-ethernet`.

**What is new: two IOSB fixes** (`docs/scsi-write-hang-20260928.md`). While
measuring the disk, Finder copies of a 4 MB file hung in the write phase about
one time in ten to twenty: writes stopped, the 53C96 raised no further sector
request, the pointer still moved, the clock froze. Reproduced deterministically
in the full-machine sim with randomised sector-service latency (seed 14 of 18)
and traced to the VIA2 emulation: the IFR write assigns the whole flag register
after the edge latches in the same always block, so the ROM's VBL dispatcher
writing `$02` in the very clock the 53C96 raised INT erased the just-latched
bit 3, and since the chip holds INT until its ISR is read no further edge ever
came. The IFR write now carries the live INT and DRQ levels (the latch already
follows the level at both edges) and a same-clock ASC edge. Second, the PDMA
beat watchdog aged through the platform acknowledge, so a guest beat waiting
through an acknowledge longer than 7.9 ms (Main preempted mid-transfer) got a
spurious bus error; it now freezes while `io_ack` is up. `make
tb_scsi_irq_ack_race tb_sdma_ack_watchdog` in `verilator/` fail on the old
IOSB and pass now; the sim completes the hanging copy byte-identically.

**Hardware** (`docs/perf/iosbfix_hw_20260929`): 30 Finder duplicates over two
boots on the disposable Quad Squad copy with zero hangs (the old RTL would
have passed that 4-21 % of the time), PR Disk 1.70 / PR 1.21 with
`MiSTer_20260928`, FPU 0.955-0.981, four minutes idle with the clock in step,
type-select alive, Shut Down to the halt screen. Speed unchanged from 20260928.

**Main:** `MiSTer_20260928` (md5 `75e00b65`, branch `mac-printer-fujinet-tightloop`
of alanswx/Main_MiSTer): the Quadra support, the Mac write buffer, and the tight
disk service loop that removes Main's per-sector turnaround (PR Disk 1.62 ->
1.74, 4 MB copies 7.0 -> 6.7 s, input and ping unaffected). `ff404af9` and
`45182b73` also work, more slowly on disk.

**Gate status:** Mac OS 8.1 passed. A/UX 3.1 at 32 MB and the CD audio
transport still not run (no images on the test box).

## `MacQuadra800_20260928.rbf`

md5 `b7e88b8163679a607680e2e80669f396`, sha256
`7f6c835be1ed5bc4944cd697b01237838dbf3b92803a6e2c0ba5ae37787fe79c`, seed 31,
the qsf recipe plus two fitter settings that are now part of it
(`PLACEMENT_EFFORT_MULTIPLIER 2.0`, `ROUTER_TIMING_OPTIMIZATION_LEVEL
MAXIMUM`; with the old settings no seed of this RTL met the CPU clock, see
`docs/perf/fpu_p254_seed_walk` and `docs/perf/fpu_p258_fitter_settings`).
**Timing met on every clock**: `clk_sys` (the 33 MHz CPU clock) +0.103 ns,
`clk_ram` +0.612 ns, HDMI +0.006 ns, worst hold +0.220 ns; the SDRAM bridge
crossings +1.432 / +0.586 ns; no array fell out to registers. **39,191 ALMs
(94 %)**, 24,675 registers, 468 M10K, 36 DSP. Built 2026-09-28 on branch
`add-ethernet` from `ad7a0d4` (the RTL) with the recipe committed as
`868b0e8`.

**What is new: the FPU.** Nine CPU commits in one day, each measured with a
new 10-second per-instruction harness (`docs/perf/fpu_latency_20260928`) and
driven by a timed-window profile of Speedometer's three FPU tests
(`docs/perf/fpu_subtest_breakdown_20260928`):

- P250: an FP instruction's decode, effective address and operand reads
  overlap the FP op still running; only the request waits.
- P251, P252: done in the writeback clock, product registered at dispatch,
  alignment folded into the add, and the common result rounded and written
  back in one clock. FADD and FMUL 4 clocks (68040: 3 and 5), FDIV 27 (37.5).
- P253, P255: single and double memory sources unpacked, and single/double
  register stores packed, in the dispatch clock.
- P256: d16(An), d16(PC) and brief-indexed FP operands resolved in the decode
  clock (the four EA states skipped). Matrix's inner loop 26 -> 15 clocks,
  FFT's butterfly 65 -> 33.
- P257, P258: the exception prefetch fetches the handler window in aligned
  longwords (every exception 9 clocks cheaper), FSAVE frame words back to
  back and FRESTORE reads hinted (the FPSP trap with frame save 167 -> 125).

Register-level results are byte-identical to the previous core on the
native Whetstone, Matrix and FFT kernels and on the corpus; a new 67-check
directed program (`t_fpu_addr`) covers every inline addressing form.

**Hardware** (`docs/perf/hw_p258_seed31_20260928`, disposable Quad Squad
copy, 32 MB): FPU Benchmarks median of five **0.973** (KWhet 4563, Matrix
0.693 s, FFT 0.280 s; the 2026-09-27 build 0.684; a real Quadra 800 1.011,
5457, 0.713 s, 0.288 s: Matrix and FFT beat the real machine, Whetstone is
84 % of it because 58 % of that test runs inside the ROM's FPSP). Benchmark
Mix median of five **1.803** (1.781). Color 8-bit 9.85-9.90 s (unchanged).
24 valid runs, no anomalous timer, the menu-bar clock in step with the
MiSTer's for the whole session, four minutes idle, keyboard alive, Special ->
Shut Down to the halt screen twice. Individual Mix rows move by up to 20 %
between two fits of the same RTL (memory placement per boot), so compare
builds by the whole-Mix median only.

**Gate status:** Mac OS 8.1 passed. **A/UX 3.1 at 32 MB and the CD audio
transport were not run** on this bitstream: neither the A/UX image nor
`ToneTest.cue` is on the test box any more. The SCSI, CD and I/O RTL is
unchanged from 20260919; the CPU's exception and FSAVE/FRESTORE paths did
change (P257, P258), which is what A/UX exercises hardest, so that check is
owed before this is called final.

**Main:** needs a Main with the Quadra 800 support and the Mac write buffer
(`SCSI_CACHE_OFF` recipe): branch `mac-printer-writebuffer` of
`alanswx/Main_MiSTer` (`45182b73`) as documented, or the FujiNet/printer
build `ff404af9` that was on the box for these runs; both pass the two greps
in CLAUDE.md.

## `MacQuadra800_20260919.rbf`

md5 `933b421a0880177be1b5fb2861dcea15`, seed 21, the qsf-default recipe,
**timing met on every clock**: `clk_sys` (the 33 MHz CPU clock) +0.622 ns,
`clk_ram` +0.415 ns, HDMI +0.107 ns, worst hold +0.190 ns; the SDRAM bridge's
33 -> 99 MHz request handoff (`sdram_beat32 req_tgl -> req_handoff`) has
+1.545 ns and the return path (`line_done_handoff -> line_tag`) +0.622 ns;
`open_row` stays in logic (no altsyncram in the map report). **36,914 ALMs
(88 %)**, 25,896 registers: +825 ALMs over 20260918, of which the SONIC
front-end is about 400. Built 2026-09-19 11:19 on branch `add-ethernet` from
`b2e5377` (the merge of Alan Steremberg's fixes, `alanswx/MacQuadra800_MiSTer`
pull request #3).

**What is new: the built-in Ethernet** (`docs/ethernet.md`). The guest sees the
DP83932 SONIC at `$5000A000` with its MAC PROM at `$50008000` and its interrupt
on VIA2 slot $9, so the ROM and Apple's "Apple Built-In Ethernet" driver bind
to it with nothing to install. The FPGA holds the register doorbell, ISR/IMR,
the CR overlay and an op-list DMA engine that is a third bus master in the
machine (`rtl/sonic_mbx.sv`); the chip model and the bridge to Linux run in
Main. OSD: **Ethernet (on reset)** Off/On, default **Off**, and **Net
interface**; both are latched under reset. The guest's MAC is `08:00:07` + the
last three octets of the MiSTer's own. With the option Off the block is held
in reset and the machine is the 20260918 one.

**Needs the Main binary `releases/MiSTer`** (md5
`fbb540c8a51134cfdc960a8b5115807b`, section above). On a stock Main the option
does nothing.

Two machine bugs that only a second bus master could expose were found and
fixed on the way (both by Alan, both in `rtl/quadra800.sv`): a retained-line
ack registered in the clock the service FSM leaves idle for a DMA beat
launched a phantom adapter read, which corrupted Open Transport's CAS/CAS2
list code seconds after receive traffic started (`0533256`); and the DMA
engine starved behind a parked pseudo-DMA beat while the HPS fetched a disk
sector, a deadlock under FTP (`49b8648`). Earlier in the bring-up: the VIA2
any-slot flag is a level (`665a450`), and in Main the SONIC's 32-bit mode keeps
the receive buffer pointer longword-aligned (DHCP failed without it).

**Still in this build on purpose:** three bring-up switches in the OSD,
`Dbg store buffer`, `Dbg SDRAM line`, `Dbg DMA snoop` (status bits 9-11,
latched under reset). They default to On = the normal machine; leave them
there. They come out, with the SAMPLE/DEBUG words, once the Ethernet speed
work is closed.

**Hardware gate, 2026-09-19, on the `.143` DE10-Nano with Main `fbb540c8`**
(operator report `docs/ethernet-regression-20260919.md`), all at the 32 MB
RAM setting:

- Mac OS 8.1, Ethernet On with every fast path on (CFG `40 00`): DHCP lease,
  **506/506 pings, 500 of them 1400 bytes, 0 lost, 3 ms average**, no DMA
  timeout in the statistics, pointer and menus responsive, menu-bar clock
  ticking at idle, Special -> Shut Down to the halt screen.
- CD audio transport (`AudioTest.cue` in slot 4): the disc mounts, the AppleCD
  Audio Player shows the TOC, the counter runs under Play, freezes under
  Pause, resumes from the frozen value, Stop returns to Track 01 00:00, no
  "not responding" dialog. **Whether it is audible was not judged in this run**
  (it needs ears at the display).
- A/UX 3.1 with the SONIC present: multiuser Finder desktop within 186 s, root
  CommandShell `uname -a` = `A/UX localhos 3.1 SVR2 mc68040`, `ls`, `df` sane,
  `shutdown -h now` to "You may now switch off your Macintosh safely" within
  126 s. A/UX has no driver bound to the chip here and never touches it; A/UX
  networking is a later goal.
- Both guests again with Ethernet Off (CFG `00 00`): the guest is unreachable
  by ping, no error dialog, clean shutdowns.

Measured by Alan on his box on the same RTL (build 10, `RESUME-handoff-20260919.md`):
FTP 10 MB both ways with matching md5s (download 62.6 KB/s, upload 227 KB/s —
the speed is the open work), no DMA timeout in 35,920 round trips, Speedometer
4.02 Mix 0.923-0.926 with Ethernet On and idle against 0.922-0.925 Off. Not
re-measured on this rbf: Speedometer, FTP. Known and unchanged: A/UX at the
128 MB setting hangs in `shutdown -h now`.

## `MacQuadra800_20260918.rbf`

md5 `fde49a3cf474d5c07aff26c592200125`, seed 21 with
`FITTER_AGGRESSIVE_ROUTABILITY_OPTIMIZATION ALWAYS` (now part of the
committed recipe), **timing met on every clock**: `clk_sys` (the 33 MHz CPU
clock) +0.772 ns, `clk_ram` +0.668 ns, HDMI +0.527 ns, worst hold +0.204 ns,
TNS 0; the SDRAM bridge's 33 -> 99 MHz request handoff (`sdram_beat32
req_tgl -> req_handoff`) has +0.727 ns and the return path +0.772 ns; no
`open_row` altsyncram in the map report. **36,089 ALMs (86 %)**, 25,140
registers: 1,055 ALMs SMALLER than 20260916_2. Built 2026-09-18 06:55 on
branch `CPU-pipeline` from the detached build tree `4d09389`, whose
synthesizable RTL and qsf settings are identical to the branch head's
(`4abb118` and later; verified by diff, only test benches and comments
differ), with the qsf-default recipe (balanced synthesis, register
duplication off, `CACHE_CD_OFF`, `CACHE_SMALL`, `MISTER_DISABLE_ALSA`,
`MISTER_DOWNSCALE_NN`, `MISTER_DISABLE_ADAPTIVE`; composite Y/C kept; tracer
off). It was "build 13" of the branch; its staging directory is
`scratch/pipeline_b13/`.

**What changed: the CPU, and the store path below it.** Everything outside
`rtl/ap68040/`, `rtl/wombat_cpu.sv` and `rtl/wombat_store_buffer.sv` is the
RTL of 20260916_2 (SCSI offload, CD audio engine, the Main binary contract:
`releases/MiSTer_20260916` or later). The increments, each gated by the AP
suite (25 legs), the directed benches and the corpus-100 silicon comparison
with 0 real diffs, are described one by one in
`docs/cpu-pipeline-increments-20260917.md`:

1. Alan Steremberg's one-clock data-cache hit on a dedicated hint bus (his
   AP68040 `6e65192`, which never closed a seed at 92-93 %; it fits here).
2. The go_pc and DBcc-refill carrier hoists (about -1,100 ALMs).
3. The redirect states hint their target; 4. stack pops and MOVEM transfers
   issue in place and hint themselves; 5. forward taken Bcc.B from the
   lookahead arm; 6. MOVEM loads retire on the acknowledge; 7. pushes issue
   in place; 8. MOVEM stores from the loop, LINK/PEA on the acknowledge.
9. BRA/BSR .W/.L and JSR/JMP abs/d16(PC) redirect from the retire that pops
   them, the target computed from the queue words (no prediction); the early
   fetch shares the one redirect target wire (the rule that gave the CPU
   clock its margin back). 10. DBcc dispatched from the pop.
13. The one-clock posted store: store hints from the core, a write-side MMU
    verdict (no write protection, modified bit already set), the cache's
    store fast lane on registered terms only.
14. A read may pass one queued store to another 16-byte line in
    `wombat_store_buffer` -- **with the line-crossing fix `cf06fe6`**: the
    first fit of this increment did not boot (a fill passed a queued store
    that straddled two lines; `docs/PERFORMANCE_MEASUREMENTS.md` section 21).
15. BRA.B resolved by the lookahead arm from any retire.

Increments 11 and 12 (a loop-top decode record cache) are NOT in: the build
that carried them returned impossible Speedometer times in 2 of 5 runs, this
one none in eight; they were reverted (`4abb118`).

**Performance** (the .143 box, Mac OS 8.1 from `QuadSquad8.hda`, 32 MB,
Speedometer 4.02, Quadra 605 = 1.0; section 22 of
`docs/PERFORMANCE_MEASUREMENTS.md`, `scratch/pipeline_b13/report.md`):

| test | this release | 20260916_2 |
|---|---|---|
| Benchmark Mix, mean of EIGHT valid runs (0.926 / 0.928 / 0.929 x6) | **0.9285** | 0.855 (**+8.6 %**) |
| Color QuickDraw, four depths | **0.670** | 0.643 on the branch's first step (+4.2 %) |
| FPU | 0.466 / 0.468 | 0.464 |

Per test against the branch's previous best (build 8, Mix 0.907): Sieve
+6.0 %, Permutations +3.7 %, Queens +2.9 %, Towers +2.6 %, Bubble Sort
+2.2 %, Dhrystones +1.9 %; Puzzle -0.2 % (inside its spread).

**Hardware gate on this bitstream (2026-09-18):**

- **Mac OS 8.1**: Starting Up splash at +57 s, the Finder at <= 100 s;
  menu-bar clock in step with the box, mouse and Apple menu respond; 59
  minutes of Speedometer (eight Mix runs, CQD, two FPU runs) with **zero
  anomalous values in 11 series**, no artefact, dialog, dropout or system
  error in any captured frame; Special -> Shut Down to "It is now safe to
  switch off your Macintosh" in 47 s.
- **A/UX 3.1** (pristine image restored from the zip, OSD RAM option 32 MB):
  multiuser Finder desktop in under 500 s, no panic or garbled console; a
  root CommandShell, `uname -a` = `A/UX localhos 3.1 SVR2 mc68040`,
  `ls -l /etc | head -20` and `df` sane; `shutdown -h now` to "You may now
  switch off your Macintosh safely." within 127 s, no port-mapper failure.
  (A modal "This disk is unreadable" dialog held the Finder until the disc
  in slot 4, an audio/mixed-mode CUE that A/UX's System 7 environment cannot
  read, was ejected at the display; Mac OS 8.1 ignores the same disc. Not a
  core matter: `scratch/pipeline_b13_aux/report.md`.)
- **CD audio: NOT RUN on this bitstream.** The CD target, the audio engine
  and the 53C96 are the RTL of 20260916_2, on which the user heard CD audio
  in a game; the ToneTest procedure of `CLAUDE.md` (the AppleCD Audio Player
  transport and the check by ear) is owed and should be run before this file
  is relied on for CD audio.
- The full-machine simulation of this tree also boots Mac OS 8.1 to the
  desktop (3.02 G clocks, `scratch/pipeline_b13/sim_prof_f7200.png`).

Known margins to watch: the 33 -> 99 MHz request handoff has +0.727 ns in
this placement (+1.4 to +2.5 ns in the branch's other fits); it is a
same-PLL half-cycle path that TimeQuest times, and it is re-reported for
every fitted tree.

## `MacQuadra800_20260916_2.rbf`

md5 `8552a4094e151bf7b853916a9099e2c2`, seed 21, **timing met, +0.244 ns setup**
(HDMI +0.255 ns, `clk_sys` +0.442 ns, `clk_ram` +0.851 ns; no `open_row`
altsyncram in the map report). 37,144 ALMs (89 %), 24,959 registers. Built
2026-09-17 13:21 from `6de9473` on `add-CPU-fixes` with the qsf-default
recipe (balanced synthesis, register duplication off, `CACHE_CD_OFF`,
`CACHE_SMALL`, `MISTER_DISABLE_ALSA`, `MISTER_DOWNSCALE_NN`,
`MISTER_DISABLE_ADAPTIVE`; composite Y/C kept; tracer off).

**This file replaces the 2026-09-17 00:42 release of the same name** (md5
`ab1da889a28b1b7f3b030e881b7b5390`, built from `2922294`, seed 21, CPU clock
MISSED by 0.231 ns on one path, shipped marginal). Everything outside the CPU
is the same RTL: the SCSI offload phase 2, the CD audio engine, the Main
binary contract. The CPU is new, and the fit is clean.

**The CPU (`docs/cpu-upstream-2026-09.md`, `rtl/ap68040/UPSTREAM.md`):** the
AP68040 is vendored into `rtl/ap68040/` (no submodule) at the 20260915 CPU
(Alan Steremberg's checkpoint 15 + our carrier hoisting R1..R4, `8778213`)
plus, one commit each, from Adam Polkosnik's September work: memory bitfield
reads sized to the bytes the field occupies (a short field at a page end no
longer faults on the unmapped next page; `3458e64`); FRESTORE of an
FPSP-prepared BUSY frame with CU_SAVEPC=$fe executes the prepared command on
the frame's operands -- the Quadra 800 ROM does exactly this at `40890100`
for denormal and unnormalized operands, and the core used to restore the
frame and do nothing (`880b81c`); a MOVEM operand fault stacks its original
EA with SSW.CM and RTE resumes from it (`880b81c`); a failed table search
installs a valid nonresident ATC entry as the 68040 does (`880b81c`); the
reserved full-extension encodings IS=1/I-IS[2]=1 execute as Quadra 800
silicon does (our `docs/ap68040-memind-reserved.patch`, verified 2026-08-30,
finally in); ADD/ADDX and SUB/SUBX/CMP share one adder each and the three
FPU normalizers one shifter (`7431dcb`); D0-D7/A0-A6 live in two mirrored
MLABs with a one-cycle pending-write bypass (`7431dcb`). Adam's seven
directed programs and three unit benches join `run_tests.sh` (23 legs); four
of the programs failed on the 20260915 CPU. Sim gates: AP suite 23/23,
`bench_loop` 94368/95166 and the corpus-100 silicon comparison 33,335,739
cycles / 0 REAL diffs, both identical to the 20260915 CPU.

Hardware on this bitstream (2026-09-17, the .143 box, `.s0` QuadSquad8.hda
with a second disk in `.s1` and a MacLC CD cue in `.s4`, i.e. NOT the bare
gate configuration; `scratch/gate_cpufixes/`):

- **Mac OS 8.1**: Finder desktop complete at T0+136 s (the first capture;
  splash not observed) with both extra volumes mounted and the CD's window
  auto-opened, no video artefacts; menu-bar clock in step with host time over
  four minutes, `write_bytes` flat at idle; mouse, Apple menu, Find File and
  four Finder windows opened and redrawn. This is the first hardware run of
  the MLAB register file, whose failure mode (MLAB read-during-write) shows
  only on silicon; it booted and ran.
- **Speedometer 4.02 (the user, one iteration each; screenshot
  `docs/perf/speedometer402_vendored_cpu_20260917.png`)**: Benchmark Mix
  **0.855** (20260915: 0.857/0.859/0.859), every row within 3 % of the
  20260915 rows and Towers the only one that moved (1.229 s vs 1.196 s);
  Color QuickDraw **0.641** averaged over 1/2/4/8 bits (8-bit 16.847 s =
  0.629 vs 17.497 s = 0.605 on 20260915, the only depth measured then);
  Performance Rating **0.810** (CPU 0.684, Graphics 0.741, Disk 0.859, Math
  8.052), the first PR figure for Speedometer 4.02 on this core. The CPU
  fixes are correctness and area, not speed, and the numbers agree.
- **Not re-run on this file:** A/UX 3.1 and the CD audio path. Nothing
  outside the CPU changed since `ab1da889`, whose gate (below) covered both;
  the user chose to release on the Mac OS 8.1 run.

The rest of this section is the `ab1da889` entry as released, still
accurate for the SCSI/CD side of this file.

**Main binary correction (2026-09-17):** the `898854ef` binary named
below was mis-linked -- the WSL build had rsynced 28-August object files
from the Windows checkout, so `video.cpp.o` / `hardware.cpp.o` read the
config structure at pre-rebase offsets (a black picture at the MiSTer
menu on HDMI, the Mac core mostly unaffected). The correct binary of the
same commit `ae708d3` is md5 `431da61aef440964204a59ce0069bfa2` (built
from nothing; `scripts/build_main_wsl.sh` now discards build objects).
The gates below ran with the mis-linked binary: every Mac-side object in
it was current, so their results stand, but `431da61a` is the one to
install. **Re-verified on `431da61a` 2026-09-17 10:10-10:26**
(`scratch/cdbin/report.md`): this rbf installed under the generic
`_Unstable/MacQuadra800.rbf` name, Mac OS 8.1 Finder with "Audio CD 1"
at T0+139 s on the audible `ToneTest.cue` (`scripts/make_tonedisc.py`,
same layout as `AudioTest.cue`), the AppleCD Audio Player's counter
running (00:17 / 01:25 / track 2 at 01:04 at +16 / +85 / +154 s, the
auto-advance over two track boundaries), Pause frozen 90 s, Resume from
the frozen value, Stop to 00:00, no "not responding" dialog; Main's five
`Mac CD: cmd` lines (47, 4B, 47 FF:FF:FF, 4B, 01) with every `cur`
matching the wall clock to the second. The "not responding" dialog the
user saw on 2026-09-17 09:46 came from the OLD Sep-8 build (`512cd4f8`)
that sat under the generic `_Unstable` name until this run, with the
silent test disc in slot 4; it reproduced on that build at 10:06 and did
not appear on this one. Sound itself the operators could not judge -- they
cannot hear, and the tone disc is on the card for that -- so it was left to
the user, whose listening test is below.

**Ships with a Main binary:** `releases/MiSTer_20260916` (md5
`431da61aef440964204a59ce0069bfa2`) is the Main fork
(`danifunker/Main_MiSTer`, branch `mac-ethernet-pr-with-SCSI-Optimizations`,
commit `ae708d3`, rebased onto upstream `f80abdc`), built from a clean
object tree on 2026-09-17 (`scripts/build_main_wsl.sh`). It carries the
Mac SCSI family support (CUE/CHD discs, the BlueSCSI Toolbox, the CD
changer), the CD-ROM response and command windows of phase 1, and phase
2's next-frame window, the command block's transport arm and the volume
scaling. Required for every CD image on this core; on an older Main the
guest sees no CD-ROM (the capability probe), nothing hangs. Install it as
`/media/fat/MiSTer` (back the old one up first) and reboot. The 20260916
(phase 1) entry named the mis-linked `898854ef` build of the same commit;
use this file instead.

What changed since `20260916` (design note `docs/scsi-hps-offload-plan.md`,
contract `docs/cdrom.md`):

- **`rtl/cd_audio.sv`** (`d5442fe`) -- the command decode, the playhead
  (SEARCH / PLAY / PAUSE / STOP / SCAN, the track and M:S:F bookkeeping and
  its dividers), the blob's track table and its RAM, the volume law and its
  two multipliers are gone; what is left is the blob-header parse after a
  mount, one `$CC` status read after every forwarded transport command
  (how the engine learns play / paused / end / idle), a fetch loop that
  reads the next 2352-byte frame plus a pad (state, frame-present, flush
  generation) from `$7C000000` as one 5-block transaction into the free
  half of the two-frame ping-pong, and the 44.1 kHz cadence with linear
  interpolation as before.
- **`rtl/ncr53c96.sv`** -- the transport CDBs are forwarded with STATUS
  held until the ARM's ack; `$42` / `$C2` / `$CC` come from the response
  window; the page-`$0E` volume ports left the RTL (Main mirrors them from
  the forwarded MODE SELECT). The **channel owner register** `eng_owns`
  (`97ea3eb`): the engine's request is shown to the platform only once
  granted, and `io_lba` / `io_blk_cnt` / the ack mask / the sector
  buffer's platform port follow the owner. **`abort_nexus`** (`3ec22e4`)
  arms `io_discard` only for the old nexus's own read in flight, and the
  engine's transfer no longer holds a data phase open (`2922294`): a poll
  whose last byte drained while a frame fetch was out used to stay in DATA
  IN for ever -- the driver's timeout right after PLAY.
- **`rtl/scsi_cache.sv`** -- honours the engine's block count for
  pass-through reads (`e_blk_cnt`).
- Bench: `tb_ncr53c96` T19 (PLAY forwarded, the poke, two frames, the
  window status forms, PAUSE / RESUME / STOP) and T20 (a forced same-cycle
  collision of a disk flush and of a guest `$CC` read with a frame fetch,
  on a slot-faithful platform model, and the phase at the chunk end with the
  fetch in flight), 477,417 checks; the pre-owner RTL fails T20 the way the
  hardware did (527 failures), the RTL before the completion fix fails the
  phase check.

Hardware (2026-09-16/17, the .143 box, the release gate on this exact
bitstream, `scratch/p2d/report.md`; the same RTL was probed before on the
seed-24 build `a719e24f`, `scratch/p2c/report.md`):

- **Mac OS 8.1** with the retail ISO: Finder at T0+119 s with the CD's window,
  idle clock in step over 135 s with `write_bytes` flat, keyboard, both
  guest volumes put away from the Finder, `mac_shutdown.sh` to the halt
  screen in 44 s on the probe build; on this bitstream: Finder at T0+132 s,
  the idle clock flat over 80 s, both volumes put away, halt at 00:20.
- **AppleCD Audio Player** on the 4-track audio CUE (`AudioTest.cue`): Play
  runs (00:12 / 00:43 / 01:14, track 3 at 3:24 exact), Pause holds and
  resumes from 01:15, Next / Prev, the scan button jumps ~16 s, the
  volume slider, Stop to 00:00; 12 min 32 s of playback without a dialog;
  Main's 25 `Mac CD: cmd` lines match every displayed position to the
  second. On this bitstream (the p2d gate): Play 00:10 / 00:39 / 01:14, Pause
  frozen 60 s and resumed from 00:08, Next / Prev, scan +24 s in 5 s, volume
  down / up, Stop to 00:00; 14 min 20 s active; Main logged 17 transport
  commands (47 incl. the FF:FF:FF resume form, 4B, CD for the scan, 01 for
  Stop), every `cur` matching the display and the wall clock.
- **CD audio by ear (the user, 2026-09-17):** a thorough listening test on
  this bitstream with the Main binary above -- playing a game with CD audio,
  not a test tone -- and the user's verdict is that it works great. The first
  sound ever confirmed from the core's CD-DA path (the engine's 44.1 kHz
  cadence fed by Main's 75 Hz next-frame window), and the only part of the
  gate an operator driving the box over the network cannot judge.
- **A/UX 3.1** with no CD, RAM 32 MB: multiuser desktop at T0+188 s (the image
  restored from the backup zip first), `uname -a` = `A/UX localhos 3.1 SVR2
  mc68040`, `shutdown -h now` to "You may now switch off" in 144 s, no
  streaks, no wedge.

Known: A/UX 3.1 hangs its shutdown when the RAM option is 128 MB (all
builds since at least 20260908_3); run A/UX at 32 MB. The morning's
20260916 (phase 1) carries the discard exposure for a command selected
during the blob-header read after a mount (rare) -- superseded by this
build.

## `MacQuadra800_20260916.rbf`

md5 `1eae0fb7ed8de620751af3efb94047fb`, seed 21, timing met at **+0.247 ns**
(HDMI +0.442 ns, `clk_sys` +0.729 ns, `clk_ram` +0.732 ns). 38,128 ALMs
(91 %, -510 against 20260915), 25,659 registers, 491 of 553 RAM blocks, 59
DSP blocks. Built from `f612084` on `optimize-SCSI` with the qsf-default
recipe (balanced synthesis, register duplication off, `CACHE_CD_OFF`,
`CACHE_SMALL`, `MISTER_DISABLE_ALSA`, `MISTER_DOWNSCALE_NN`,
`MISTER_DISABLE_ADAPTIVE`; composite Y/C kept; tracer off). The commits
after `f612084` on the branch up to this entry are tooling and notes,
except the phase-2 RTL (`d5442fe`, playback on the ARM), which is NOT in
this bitstream.

**Main binary correction (2026-09-17):** the `898854ef` binary named
below was mis-linked -- the WSL build had rsynced 28-August object files
from the Windows checkout, so `video.cpp.o` / `hardware.cpp.o` read the
config structure at pre-rebase offsets (a black picture at the MiSTer
menu on HDMI, the Mac core mostly unaffected). The correct binary of the
same commit `ae708d3` is md5 `431da61aef440964204a59ce0069bfa2` (built
from nothing; `scripts/build_main_wsl.sh` now discards build objects).
The gates below ran with the mis-linked binary: every Mac-side object in
it was current, so their results stand, but `431da61a` is the one to
install.

**Ships with a Main binary:** the Main fork branch
`mac-ethernet-pr-with-SCSI-Optimizations` at `ae708d3` (binary md5
`898854ef18882048b409127f7fb562f8`). It is required for every CD image on
this core: the core reads its CD responses from Main and forwards commands
to it. On an older Main the CD drive does not answer selection (the
capability probe finds no `SONY CDU-8004` identity in the INQUIRY window),
so the guest simply sees no CD-ROM; nothing hangs. The other Mac cores are
byte-identical on this Main (`is_mac_scsi_optimized()` is `macquadra800`
only).

What changed since `20260915` (design note `docs/scsi-hps-offload-plan.md`,
contract `docs/cdrom.md`):

- **`rtl/ncr53c96.sv`** -- the CD-ROM target's DATA IN responses (INQUIRY,
  MODE SENSE pages, READ TOC formats 0/1/2, Apple `$C1` TOC) are one-block
  reads of a response window on the CD slot, served for the CDB's clamped
  allocation; MODE SELECT (after the RTL's own refusal rules), eject
  (`$1B` LoEj / `$C0`), machine reset and SCSI bus reset are forwarded as a
  command-block write (the CDB at bytes 496..507) with STATUS held until
  the ARM acks; forwards serialize behind a reset notice in flight; a
  capability probe after every reset and mount pulse arms the target.
- **`rtl/cd_audio.sv`** -- the response builders and the three table
  planes (12 M10Ks) are gone; the playhead still runs in RTL in this build.
- **`MacQuadra800.sv`** -- the CD slot's `sd_wr` is wired for the command
  block.
- **`scripts/mac_shutdown.sh`** -- the one closed-loop Mac OS 8.1 shutdown
  walker (pointer checked before the press, the lit row before the
  release).
- Bench: `tb_ncr53c96` serves the windows through the Main fork's own
  builders (`verilator/sim/cd_window.cpp`), 476,841 checks; the golden
  test `scripts/cd_resp_golden.sh` proves the builders byte-identical to
  the old RTL tables (6,304 checks).

Hardware (2026-09-16, the .143 box, operator runs, `scratch/p1a/`,
`scratch/p1b/`, `scratch/p2/`): Mac OS 8.1 (QuadSquad8) Finder at 126 s
from `load_core` with the retail ISO in slot 4 (its window auto-opened,
17 items), the menu-bar clock in step with wall time over 4 min with
`write_bytes` flat, Cmd+W / type-select / Cmd+O (a directory read through
the response windows), both guest volumes of the retail disc put away
from the Finder within 9 s each (the eject forward; no dialog, no freeze),
the Open Transport ISO hot-mounted from the OSD (the probe re-armed, the
driver found it, the Finder icon within 30 s, its window 9 items) and put
away, the retail disc re-mounted, `mac_shutdown.sh` to "It is now safe to
switch off" in 61 s. Speedometer was not re-measured: the Quad Squad image
restored from the Aug 31 backup does not carry it, and nothing on the
CPU/SDRAM path changed since 20260915 (0.858). A/UX 3.1 at 32 MB:
multiuser Finder desktop at 120 s, `uname -a` =
`A/UX localhos 3.1 SVR2 mc68040`, `shutdown -h now` to "You may now
switch off your Macintosh safely" in 131 s. Old-core check: the
20260915 rbf on this Main boots 8.1 with the retail ISO (Finder at 130 s)
and shuts down cleanly.

**Known: A/UX 3.1 hangs `shutdown -h now` when the core's RAM option is
128 MB** -- after the port-mapper line the kernel console keeps echoing
(drawn at 1 bpp into the 8-bpp frame, which looks like coloured streaks)
but the shutdown never completes. Six runs today, on this build, on
20260915 and on 20260908_3, with and without a CD, with and without the
slot-1 disk, and with an older Main, all at 128 MB; the one run at 32 MB
halted in 126 s, as did every earlier A/UX gate (all at 32 MB). Not a
change of this release; run A/UX with the RAM option at 32 MB until the
128 MB case is understood (`docs/scsi-hps-offload-plan.md`, W track).

## `MacQuadra800_20260915.rbf`

md5 `4c80a3be96cb46992d00002484f9f67a`, seed 22, **timing NOT met by 0.095 ns
on the HDMI PLL domain** -- a single endpoint, the framework's own
`sys_top` `hdmi_dv_hs -> hs` register pair with -0.58 ns of clock skew from
placement; `clk_sys` (the 33 MHz CPU clock) +0.712 ns, the 99 MHz SDRAM
domain positive. 38,711 ALMs (92 %). Built from `ce78378` on
`alan-perf-20260908` (submodule `rtl/ap68040` at `8778213`) with the
qsf-default recipe (balanced synthesis, register duplication off,
`CACHE_CD_OFF`, `CACHE_SMALL`, `MISTER_DISABLE_ALSA`, `MISTER_DOWNSCALE_NN`,
`MISTER_DISABLE_ADAPTIVE`; composite Y/C kept; tracer off). Shipped as a
marginal build by decision: at 92 % the fit is a seed lottery on that
register (seeds 21/23 missed it by 0.77 ns, 24 and 27 did not place, the
R1..R6 variant missed the CPU clock by 0.6-1.7 ns), and the hardware gate,
not the STA, is the judge (`CLAUDE.md`). Deploy it with
`ALLOW_TIMING_VIOLATION=1 bash scripts/deploy_screenshot.sh`. The store
head's ARM-side captures cannot see the HDMI register; watch a real monitor
for output glitches and report them.

What changed since `20260908_3`:

- **CPU** -- Alan Steremberg's checkpoint 15 (`cpu-regalu-capture-retire-20260909`,
  `167c5e8`): 16 KB instruction and data caches, posted stores, the whole
  instruction line returned to the prefetch queue, line-crossing reads
  served from the cache, operands consumed at decode, memory-destination
  EAs from the pipe start, one-cycle register shifts, short Bcc resolved at
  the producer's retire, folded RTS/LINK/UNLK, the decode record handed
  over at every retire. On top of it, six multi-site sequencer tasks
  (`fetch_next`, `mrd`/`mwr`, `exc`, `immf`) hoisted into single post-`case`
  carrier arms (`docs/cpu-area-consolidation.md`), cycle-identical on the
  AP suite, `bench_loop` and the 100-row corpus, which is what makes the
  checkpoint fit at all (64,723 -> 58,786 ALUTs in synthesis). The wrapper
  gained the line offer, the posted-store handshake and `c_busy`
  (`rtl/wombat_cpu.sv`, `rtl/wombat_store_buffer.sv`).
- **`rtl/ncr53c96.sv`** -- the boot hang that the faster CPU exposed. For a
  CD MODE SELECT the data-out drain raised Bus Service the cycle the FIFO
  emptied while the list verdict moved the phase to STATUS ~12 cycles
  later; the Apple CD-ROM extension's poll read the STATUS register in
  that window (INT set, phase still DATA OUT), cleared the ISR, and waited
  forever for a phase change it had already consumed. The drain now
  withholds the Bus Service when the drained byte completes a judged list;
  the verdict raises it with the phase already STATUS (both PIO and DMA
  paths). Found with a register-level trace in the full-machine sim
  (`scratch/ck15_hang/analysis.md`); `tb_ncr53c96` 476,837 checks, 0
  failures. Sim tooling: `[NCRREG]` trace, `--trace-on-ncr`, `--trace-max`.
- `sys/` untouched; every feature of 20260908_3 (CD-ROM, block cache, Y/C)
  kept. Requires the same Main fork binary as 20260908_3 for CUE/CHD discs.

Hardware (2026-09-15/16, .92 box, operator runs, `scratch/gate_fix/`):
Mac OS 8.1 (QuadSquad8, 32 MB) Finder desktop at 106 s from `load_core`,
clock in step with host time over 4 min, mouse and Apple menu live;
Speedometer 4.02 Benchmark Mix 0.857 / 0.859 / 0.859 (mean **0.858**; the
2026-09-12 store head scored 0.462 and 20260908_3 0.360 on the same disk;
Alan's own board 0.855), Sieve 1.06, KWhetstones 2.19, Dhrystones 0.578;
Color QuickDraw 0.605 (0.414 / 0.337); FPU 0.449 (0.305 / 0.251); a
wall-clock bracket of a fourth Mix (34 +/- 3 s) confirms the seconds are
real. Special -> Shut Down to "It is now safe to switch off" in 48 s.
A/UX 3.1: multiuser Finder desktop at 148 s from `load_core` (no fsck: clean prior halt), CommandShell `uname -a` = `A/UX localhos 3.1 SVR2 mc68040`, About This Macintosh = Quadra 800 / System 7.0.1 / 32 MB, `shutdown -h now` reached "You may now switch off your Macintosh safely" in 127 s with `write_bytes` flat afterwards (the point where the 299cb36 CPU wedged on 2026-09-12). Both gates pass.

## `MacQuadra800_20260908_3.rbf`

md5 `71102b391b375ebc9614d80432136611`, seed 21, timing met at **+0.444 ns**
overall (HDMI PLL domain; `clk_sys` +0.797 ns, the 99 MHz SDRAM domain
+0.927 ns), the widest margin since the release recipe. 41,014 ALMs (98 %),
26,005 registers, 476 of 553 RAM blocks. Built from `4f859b3` on `main`
with the qsf-default recipe (balanced synthesis, register duplication off,
`CACHE_CD_OFF`, `CACHE_SMALL`, `MISTER_DISABLE_ALSA`, `MISTER_DOWNSCALE_NN`,
`MISTER_DISABLE_ADAPTIVE`; composite Y/C kept; tracer off). The qsf now
records seed 21.

**Ships with a Main binary:** `releases/MiSTer_20260908` (md5
`916829ffe37e778ac3e7bf41fb5a8eaa`) is the Main fork
(`danifunker/Main_MiSTer`, branch `mac-ethernet-pr`, commit `4857af1`)
rebased onto upstream's `20260907` release. It carries the Mac SCSI family
support this core needs for CUE/CHD discs, CD audio, the BlueSCSI Toolbox
and the CD changer, plus a new multi-block CD data-window fill (a 4 KB run
per hps_io transaction) that a later core build will use (`MB_CD=1`,
`13d7fea`, not in this bitstream). Install it as `/media/fat/MiSTer`; a
flat `.iso` also works on upstream's own Main.

What changed since `20260908_2`:

- `rtl/ncr53c96.sv` -- **the CD-ROM refuses a MODE SELECT block-length
  change** the way QEMU's `scsi-cd` does: a block descriptor the list does
  not contain (the ROM's boot-scan 8-byte list) or any block length but
  2048 gets CHECK CONDITION 05/26/00; the audio control page (0Eh) of a
  well-formed list is still applied; the block length is 2048 always. STATUS
  is delivered only once the list has been judged, so an initiator can
  never fetch a GOOD the parse is about to overturn (an ICCS that arrives
  early is held one cycle). `tb_ncr53c96` 476,837 checks, 0 failures; the
  bench's new cases read the interrupt register before their next command,
  as a 53C96 driver must.
- `rtl/scsi_cache.sv` -- unchanged from `20260908_2` in this bitstream (the
  CD slot still moves single sectors; the multi-block CD path lands with the
  Main above in the next build).

Hardware (2026-09-08, operator run, screenshots `scratch/op*.png`): Mac OS
8.1 (QuadSquad8) Finder desktop at about 2 min 15 s from `load_core`, the
retail CD's window readable, clock 12:06 -> 12:09 over an idle watch with
`write_bytes` flat, mouse and keyboard live, Special -> Shut Down clean.
A/UX 3.1 multiuser Finder desktop in about 3 min 30 s with the UNIX root
volume mounted, About This Macintosh = Quadra 800 / System 7.0.1 / 32 MB
with CommandShell running, Special -> Shut Down to "You may now switch off
your Macintosh safely". Both gates pass.

Known, and traced to the guest after this build: on the Quad Squad boot the
retail Mac OS 8.1 CD shows up twice on the desktop, two windows of the same
volume. The MODE SELECT change above matched QEMU's behaviour and did not
remove it. A request trace on the box showed the HFS volume mounted twice
at +118 s with a command sequence identical to QEMU's, and QEMU itself,
with its own `scsi-cd`, shows the same two icons when it boots a copy of
the Quad Squad disk, while a fresh Mac OS 8.1 install shows one icon on
QEMU and on the FPGA alike. So it is the Quad Squad system folder's
extension set, not the core: with it both the disc's ROM-loaded driver and
the extension's driver keep a drive-queue entry. Its Apple CD-ROM 5.4.2
copy is excluded (swapping in Mac OS 8.1's own, byte for byte, changed
nothing in QEMU); which item does it is not yet bisected. Cosmetic; the install
from the disc works.

## `MacQuadra800_20260908_2.rbf`

md5 `61da22443a3a66ac385eaa3ddc53e3de`, seed 19, timing met at **+0.171 ns**
overall (HDMI PLL domain; `clk_sys` +0.358 ns, the 99 MHz SDRAM domain
+1.008 ns, hold +0.243 ns). 41,181 ALMs (98 %), 476 of 553 RAM blocks, 49
DSP blocks. Built from `43e5d09` on `main` with the recipe that is now the
qsf default: balanced synthesis, register duplication off, `CACHE_CD_OFF`,
`CACHE_SMALL`, `MISTER_DISABLE_ALSA`, `MISTER_DOWNSCALE_NN`,
`MISTER_DISABLE_ADAPTIVE`; composite Y/C output kept; tracer off.

What changed since `20260908` earlier the same day:

- `rtl/scsi_cache.sv` -- **multi-block platform transactions**: a miss into
  an absent aligned 8-sector group fetches the whole group as one hps_io
  read, the prefetcher brings the next two absent groups the same way, a
  fully dirty group flushes as one 8-block write, and a fetched sector is
  valid the moment its last word lands. Each hps_io transaction costs a
  Main_MiSTer main-loop pass, and the core used to pay it per 512 bytes.
  Partly dirty groups flush singly once the engine has been quiet, a miss
  into a group already on its way waits for it, and the flush scanner
  wraps at the slot's size (a latent index-aliasing bug found by the
  32-sector geometry). Tag bitmaps are sized to the largest slot;
  `CACHE_SMALL=1` selects 32/32/16 sectors. The CD slot still uses single
  sectors until the Main fork's CD path is confirmed to honour the block
  count. Bench `tb_scsi_cache` T1-T9 in three geometries, 279,315 checks
  each; `io_blk_cnt` reaches hps_io's `sd_blk_cnt` for the three real
  slots.
- `rtl/ncr53c96.sv` -- a CD mount pulse that names the disc already present
  (same size, not ejected) is a no-op.
- Framework switches: ALSA (audio from the Linux side into the mix) off;
  the scaler's bilinear downscaling and adaptive scanlines off. Composite
  Y/C is compiled IN again (it was out of `20260908`). MT32-pi is
  unaffected by the ALSA switch: it is the user-port I2S module.
- `scripts/guest/menu.sh`, `menuitem_probe.py`, `mac_shutdown.sh` -- the
  operator menu drivers aim at the title centre, measure the mouse scale,
  and recognise System 7's black highlight; not part of the bitstream.

Hardware (2026-09-08, `scratch/gate_L/`): Mac OS 8.1 (QuadSquad8) Finder
at 136 s with the retail CD mounted and its window readable, clock 6:55 ->
7:00 over the idle watch, mouse and keyboard live, a 5.5 MB Finder
duplicate in about 29 s, Special -> Shut Down clean. A/UX 3.1 multiuser
desktop in under 282 s, `uname -a` = `A/UX localhos 3.1 SUR2 mc68040`,
`shutdown -h now` clean in 188 s. ROM boot from the retail CD to its Finder
desktop in 107 s, clean shutdown.

Known and cosmetic, and now better understood: on the Quad Squad boot the
retail CD shows up twice on the desktop, and Get Info on both icons reports
the identical volume at SCSI ID 3. The CD boot and A/UX show it once. So it
is not the core presenting two targets, and the same-disc mount guard did
not change it; the variable is the Quad Squad disk's own extension set,
which most likely carries a second CD driver that mounts the disc too.

The CD audio engine's 12 % diet (`79d3e9b`, `5f52240`, `3098ee3`) is on
`main` but not in this bitstream.

## `MacQuadra800_20260908.rbf`

md5 `b882d3fce60b63fac4ab1284755031d6`, seed 19, timing met at **+0.343 ns**
overall (HDMI PLL domain; `clk_sys` +0.415 ns, the 99 MHz SDRAM domain
+0.609 ns, hold +0.158 ns). 41,108 ALMs (98 %), 499 of 553 RAM blocks.
Built from `ff7f4b0` on `main` with the release recipe in the qsf notes:
`OPTIMIZATION_MODE BALANCED`, `OPTIMIZATION_TECHNIQUE BALANCED`, register
duplication off, `CACHE_CD_OFF=1`, `MISTER_DISABLE_YC=1`,
`MISTER_DISABLE_ALSA=1`. Tracer off.

**Alan Steremberg's next AP68040 step is in** (`5aa596f`: retained
instruction fetches across branches, memory operands retired on read
acknowledge, DBcc collapse, simple An effective addresses and source-EA
dispatch bypassed, register ADD operands preselected in decode). Against the
20260901 numbers in `docs/PERFORMANCE_MEASUREMENTS.md` the Benchmark Mix
average goes 0.231 -> **0.360** (+56 %), Color QuickDraw 0.219 -> 0.317, FPU
0.161 -> 0.250; Permutations 1.97x, Towers 1.78x, Dhrystones 1.75x. The core
is +20 % logic, which is why this build needed:

- the framework's trimmed PLL reconfiguration core (`pll_cfg_hdmi`) behind
  the 12" 512x384 option instead of the generic IP (715 -> ~300 cells);
- the CD-ROM passed straight through the SCSI block cache (`CACHE_CD_OFF`):
  the disks keep their read-ahead and write-behind, the CD loses its 8 KB
  read-ahead;
- the composite/S-Video encoder and the ALSA (audio-over-HPS) path compiled
  out; HDMI and VGA video and HDMI/analog audio are unaffected;
- balanced rather than speed-directed synthesis. Speed synthesis does not
  fit; area synthesis fits but breaks HDMI-domain timing.

Hardware (2026-09-08, `scratch/gate2_b882d3fc/`): Mac OS 8.1 (QuadSquad8)
Finder at 151 s with the retail CD mounted and its window readable, clock
5:25 -> 5:30 over the idle watch, mouse and keyboard live, Speedometer
average 0.360, Special -> Shut Down clean. A/UX 3.1 multiuser desktop in
under 263 s (the CD readable there too), `uname -a` = `A/UX localhos 3.1
SUR2 mc68040`, `shutdown -h now` clean. ROM boot from the retail CD to its
Finder desktop in under 146 s, clean shutdown.

Known and cosmetic: with the CD in the slot at boot the disc can show up
twice on the Mac OS 8.1 desktop when booting from the Quad Squad disk (once
when booting from the CD or under A/UX). Both icons are the same volume at
SCSI ID 3. A same-disc mount guard (`2631967`) was tried against the Main's
60 s re-insert and did not change it (see `20260908_2`); the likely cause is
a second CD driver in that disk's extension set. The multi-block SCSI cache (`f878a6e`) is not in it
either: with this CPU and the CD it sits a seed's worth of variance over
the device; see the resume doc for the geometry option being built.

## `MacQuadra800_20260907.rbf`

md5 `03f83c62d92d997e5cdf89efbb99c42f`, seed 19, timing met at **+0.250 ns**
overall (HDMI PLL domain; the 33 MHz `clk_sys` domain closes at +0.850 ns and
the 99 MHz SDRAM domain at +0.721 ns; hold positive everywhere). 37,939 ALMs
(91 %), 502 of 553 RAM blocks. Fitter/STA summaries next to it as
`MacQuadra800_20260907.{fit,sta}.summary` (gitignored, local only). Built from
`c805300` on `main`; the serial SCSI tracer is compiled out.

**The retail Mac OS 8.1 CD installs end to end on the hardware** (install #9,
2026-09-07: base system plus every optional package, 177 MB written,
"The installation process has finished"), which is what the whole CD-ROM
line of work was for. What changed since `20260902`:

- `rtl/ncr53c96.sv` -- the installer deadlock (`f349e9e`): the engine reports a
  write's GOOD status when its last block *starts* flushing; when the ROM then
  selected the CD, `cur_tgt` switched and the flush's ack was lost, wedging
  `io_busy`. An outstanding flush now follows its own target (`flush_tgt`).
  Also: the disks accept MODE SELECT / VERIFY / SYNCHRONIZE CACHE / FORMAT
  UNIT / REASSIGN BLOCKS / SEND DIAGNOSTIC, answer MODE SENSE page $30 with
  Apple's firmware-ID page (Drive Setup), the CD-ROM honours a MODE SELECT
  block length of 512, and a CD eject lasts only until the next bus reset, so
  the ROM's two-pass CD boot finds the disc again.
- `rtl/scsi_cache.sv` (new, `docs/scsi-block-cache.md`) -- a per-target
  read-ahead / write-behind block cache between the engine and `hps_io`:
  64/48/16 sectors (32 KB disk 0, 24 KB disk 1, 8 KB CD) in one 64 KB
  altsyncram. Reads hit in RAM and prefetch eight sectors ahead; writes ack
  from RAM in ~25 us and flush in the background, so no platform transfer is
  ever outstanding across a target switch. Install write bursts peak at
  11.7 MB/min versus ~9 without it. Bench `tb_scsi_cache` T1-T8, 237,584
  checks; `tb_ncr53c96` 475,299 checks.
- `MacQuadra800.sv` -- the CD-ROM's audio is mixed into the speakers; the
  CD strobe is on slot 4 (it was on the CD-changer slot 5, which is why the
  first CD builds hung with a disc mounted).
- `rtl/dafb.sv` / video -- the 12" RGB 512x384 monitor as an OSD option
  (`docs/video-modes.md`).
- `rtl/wombat_cpu.sv` -- the core stall watchdog is held while an HPS block
  transfer is outstanding and widened to 0.5 s, so an SD-card pause under a
  pseudo-DMA beat is not a bus error.
- Build switches in the qsf: `SCSI_TRACE=1` (debug tracer on the modem port,
  never in a release) and `CDROM_OFF=1` (drops the CD target and its audio
  engine, about 3,000 ALMs, for CPU-area experiments).

Hardware (2026-09-07, `scratch/gate_03f83c62/`): Mac OS 8.1 (QuadSquad8)
Finder at 150 s, clock ticking 5:47 -> 5:52 over the idle watch, mouse and
keyboard live, Special -> Shut Down to "safe to switch off" in 25 s. A/UX 3.1
multiuser desktop at ~4.5 min, `uname -a` = `A/UX localhos 3.1 SUR2
mc68040`, `shutdown -h now` to "You may now switch off" in 2 min 10 s.

Known and not in this build: Alan Steremberg's next AP68040 step
(`5aa596f`, about 2x CPU) is on `main` but does not fit alongside the CD
path (4221 LABs needed of 4191 even with aggressive-area synthesis); it ships
as a `CDROM_OFF` measurement build for now.

## `MacQuadra800_20260902.rbf`

md5 `91cf5d727920e387c5cefdf18dc695f4`, seed 19, timing met at **+0.420 ns
setup / +0.195 ns hold** overall (worst paths are in the HDMI PLL domain; the
33 MHz `clk_sys` domain closes at +1.138 ns and the 99 MHz SDRAM domain at
+0.916 ns setup). 85 % ALMs, 30,750 registers. Fitter/STA reports next to it as
`MacQuadra800_20260902.{fit,sta}.summary` (gitignored, local only).

**First release under the MacQuadra800 name, and the first with Alan
Steremberg's CPU and memory speed-ups** (merged from
`alanswx/wombat33_MiSTer` branch `cpu-sdram-handoff-seed15` in `e744dde` and
`e8eebe9`, with the `rtl/ap68040` submodule moved to `alanswx/AP68040`
`be0a662`). What changed, platform side then CPU side:

- `rtl/sdram_beat32.sv`: the 33 ↔ 99 MHz request/completion toggles cross on
  the falling edge of `clk_ram` instead of through two-flop synchronisers —
  the clocks are phase-related outputs of one PLL, and `derive_pll_clocks`
  times the half-cycle paths. Isolated read 212 → 151 ns.
- `rtl/sdram.sv`: BL8 open-page controller — rows stay open per {rank, bank}
  with tRAS/tRP tracking, refresh precharges both ranks explicitly. Every
  read captures a full 16-byte line that the bridge retains.
- `rtl/quadra800.sv`: aligned RAM longword reads that hit the retained line
  (or are the first miss of one) complete through registered pulses without
  crossing `wombat_bus32`; everything else keeps the service-FSM cadence.
- `rtl/ap68040` (`ap040_cache`): a line fill takes its remaining three words
  from the retained line instead of issuing three more bus reads; an aligned
  cacheable store now updates the resident data-cache word instead of
  invalidating the whole set.
- `rtl/wombat_store_buffer.sv` (new, below the cache): a two-entry ordered
  queue acknowledges non-faulting physical-RAM stores at capture and drains
  them behind cache hits. Reads, walker cycles and device writes wait for it.
- `ap040_core`: the exception format is carried in the entry state, removing
  a 50-level decode path that had stopped seeds 18–20 closing.

Alan's Speedometer 3.23 PR numbers on Mac OS 7.5.5 (his disk, one iteration
each; see `docs/PERFORMANCE_MEASUREMENTS.md` §8–12): CPU 2.661 → **3.878**,
Graphics 3.487 → **5.130**, Math 15.841 → **29.395**.

**Verification on this tree:**

| check | result |
|---|---|
| `tb_sdram` | 45 checks, 0 failures, 0 chip protocol errors (both ranks modelled), 43.7 MB/s |
| `tb_wombat_bus32`, `tb_store_buffer` | 6/6; all store-buffer ordering/backpressure tests pass |
| `tb_memory_path`, `..._registered_first_miss` | 0 failures, 52 MB/s integrated |
| `tb_ncr53c96`, `tb_easc` | 6556/6556, 18/18 |
| AP68040 `tb_ap040_cache_snoop` | ALL TESTS PASSED (incl. T10 retained-line fill, T11 store-hit update) |
| Full-machine Verilator gate (`gate-emu.hda`, fastboot ROM) | cpu 717 rows: 13,585 groups match, the 2 known memory-indirect diffs; fpu 270, saverestore 8, integration 1328 rows clean; mmu_full 24 rows: 13 diffs that the **pre-merge base `f9767d8` reproduces identically** (pre-existing in this harness, not a regression) |

**Hardware result (192.168.99.143, 2026-09-02):**

| guest | result |
|---|---|
| A/UX 3.1 (`HD60_512-AUX3.1-Installed.hda`) | multiuser Finder desktop 4 min after `load_core`, no fsck; Apple menu → CommandShell; `uname -a`, `ls`, `uptime`, `sum /unix` all answer; sync writes at idle; `shutdown -h now` → "You may now switch off." |
| Mac OS 8.1 (`QuadSquad8.hda`) | Finder 2 min after `load_core`; menu-bar clock ticks at idle (2:35 → 2:41); Cmd-W closes a window, pointer tracks; Special → Shut Down → "It is now safe to switch off." |

## `wombat33_20260902.rbf`

md5 `70716e92871448d1ff81ebb430902f4a`, timing met at **+0.130 ns** (seed 13,
`SCSI_TRACE` off). Fitter/STA reports next to it as
`wombat33_20260902.{fit,sta}.summary` (gitignored, local only).

**A/UX 3.1 now boots to the multiuser Finder desktop.** Two NCR53C96 SCSI bugs
in `rtl/ncr53c96.sv`, both needed:

1. **Control path:** non-DMA `$10` TRANSFER INFO flips phase to STATUS on the
   request's last byte. Killed "Protocol Error Processing SCSI request"; A/UX
   reaches `fsck`.
2. **Write path:** saio splits one WRITE into `$90` TIs of TC=256; the old
   completion arm flushed a part-filled sector buffer at every chunk boundary,
   so each sector got 256 real bytes + stale zeros and fsck saw "BAD SUPER
   BLOCK: MAGIC NUMBER WRONG." Fix: a chunk end is an interrupt only; only
   `sbuf_pos == 512` flushes. (Mac OS writes single-TI and never tripped it,
   which is why every prior build booted Mac OS but corrupted A/UX.)

Pinned in sim by `verilator/tb_ncr53c96.sv` T1–T15 (6556 checks). Full story in
`RESUME-aux-superblock.md`, `docs/scsi/rtl-gap-analysis.md` item 19, and
`docs/scsi/aux-startup-boot-path.md` §9.

**This is the tracer-off release of the seed-13 build.** `SCSI_TRACE` (the
`rtl/iosb.sv` modem-TX debug mux) is commented out in `wombat33.qsf`, so the
SCC reaches the serial pin normally. Removing the tracer logic reroutes the
netlist, so this is a distinct fit from the 09-01 `scratch/seeds` seed-13
backup (`abb5ede4…`, +0.132 ns) — same seed, different bytes.

**Hardware result (192.168.99.143, 2026-09-02):**

| guest | result |
|---|---|
| A/UX 3.1 (`HD60_512-AUX3.1-Installed.hda`) | boots through fsck → multiuser Finder desktop; 16+ min interactive (CommandShell, menus); `shutdown -h now` → "You may now switch off." |
| Mac OS 8.1 (`QuadSquad8.hda`) | boots to Finder; keyboard + mouse responsive; menu-bar clock ticks at idle; clean Shut Down. No regression. |

Both guests were exercised at idle and shut down cleanly. An apparent Mac OS
"foreground wedge" seen mid-session was traced to a test-harness bug (a guest
menu-driver script killed by a timeout left the mouse button held down), not
the bitstream; it did not reproduce with clean input.

## `wombat33_20260901_2.rbf`

MD5 `d1d785de28439d132333a1c9e3aab5c5`, seed 15. Overall timing closes at
**+0.270 ns setup and +0.241 ns hold**; the 99 MHz SDRAM domain is +1.353 ns
setup and +0.431 ns hold. Targeted TimeQuest reports put every new handoff
path above +1.353 ns setup and +3.191 ns hold.

This build replaces the conservative two-flop request and completion
synchronisers in `rtl/sdram_beat32.sv`. The 33 and 99 MHz clocks are
phase-related 1:3 outputs of one PLL, so the handoff is captured on the falling
edge of the 99 MHz clock and checked as a timed half-cycle path.

Measured against the seed-13 SDRAM-fast-path control:

| | seed 13 | seed 15 |
|---|---:|---:|
| isolated RAM read | 212 ns | **151 ns** |
| sequential RAM | 16.4 MB/s | **22.0 MB/s** |
| Speedometer 3.23 CPU PR | 2.661 | **2.917 (+9.6%)** |

Verification: `tb_sdram` 33/33 with zero chip-protocol errors, `tb_easc`
18/18, ten SingleStep rows with 170 matching field groups and zero real
differences, Mac OS boot, full Speedometer 3.23 PR suite, and clean guest
shutdown. The complete measurements and screenshots are in
`docs/PERFORMANCE_MEASUREMENTS.md` §8.

## `wombat33_20260831_2.rbf`

md5 `4414e7b3294b3d554a9e43faa16682bd`, timing met at **+0.062 ns**.

The Quadra 800 gets a serial port for the first time: `rtl/scc.v` (the Zilog
85C30) ported from the MacLC/MacIIvi lineage, hung off the beat bus through a
new adapter in `rtl/iosb.sv` at `$5000C000`, plus MIDI-over-SCC and the
MT32-pi user-port block. Full rationale and the port map in
`docs/scc-port-survey.md`.

**Hardware result (192.168.99.143, 2026-08-31):** boots clean to the Mac OS 8
desktop with the SCC live. This was the real risk — the space previously
decoded as present-but-inert (reads 0, writes discarded, always acked), so the
ROM's `InitSCC` and its loopback selftest now get real answers for the first
time. A wrong answer there does not fail quietly: the sibling `lbmactwo` core
hit exactly this and the ROM dropped into the Test Manager. This one walks
straight through ROM → "Welcome to Mac OS" → extensions → Finder, and the
Serial Driver loads without the freeze that had to be fixed on the LC.

**Utilization moved, and the slack with it.**

| | before | after |
|---|---|---|
| Logic (ALMs) | 34,223 / 41,910 (82 %) | **35,436 / 41,910 (85 %)** |
| Registers | 28,980 | 29,886 |
| DSP blocks | 47 (42 %) | 51 (46 %) |
| RAM blocks | 421 (76 %) | 423 (76 %) |
| Worst slack | +0.243 ns | **+0.062 ns** |

+1,213 ALMs buys the whole feature set (both SCC channels, four UART
serializers, the MT32-pi block). The four extra DSPs are the baud arithmetic
introduced by the `SYS_CLK_HZ` parameterisation — one operand is constant, so
they can be forced into logic if DSPs ever get tight.

**62 ps is the number to watch.** It met, and every other domain is
comfortable (HDMI next at +0.243 ns), but this core is seed-sensitive and the
next netlist change could push `clk_sys` negative. Expect a seed re-roll rather
than a structural problem if it does.

Still unproven on hardware: PPP, MIDI and MT32-pi end to end. Those need
guest-side setup (a PPP client and MacTCP/OT) and, for MT32-pi, a Pi on the
user port. The RTL paths are covered in simulation by
`verilator/tb_iosb_scc.v`, which measures 1056 clk/bit on `scc_txd_a` — 31250
baud at 33 MHz — through the real bus adapter.

## `wombat33_20260831_1.rbf`

md5 `3901ef5705f58dba3279c0417412f5f8`, timing met at +0.243 ns (seed 6).

Two changes, both in `rtl/easc.sv`.

**The watch-cursor wedge is fixed.** `$804` FIFOSTAT bits 1/3 read
`(cap == 0) || (cap >= 1023)`, so an EMPTY FIFO reported itself FULL. A guest
that fills until the full flag sets therefore wrote nothing; with no bytes
queued nothing ever popped, so the half-empty edge never fired and no refill
interrupt was ever raised. The wait never ended. Mac OS sat at a fully drawn
desktop with a watch cursor and a stopped menu-bar clock while ADB kept
tracking the mouse at interrupt level -- interrupts were fine all along, the
foreground was simply blocked forever.

Scored on hardware against `wombat33_20260830.rbf`, every run on a freshly
restored disk:

| build | scanout | ASC IRQ | menu-bar clock |
|---|---|---|---|
| `20260830` (known good) | 33 MHz | n/a | ticks |
| pre-fix | 25.175 MHz | off | FROZEN |
| pre-fix | 33 MHz | off | FROZEN |
| pre-fix | 25.175 MHz | off | FROZEN (2nd sample) |
| this build | 25.175 MHz | **on** | ticks |

Note rows 2-4: the wedge reproduced with the ASC interrupt DISCONNECTED and
with the DAFB scanout forced back off the 25.175 MHz pixel clock. Both of
those were the prime suspects and both are innocent. Do not re-investigate
them; the fault was always the status register.

**The Sound control panel's volume slider works.** `$806` was stored and
ignored (MAME does not apply it either). Bits 7-5 are the eight steps the
panel offers; the gain table is `x*256/7` so step 7 is EXACTLY unity and a
machine at maximum sounds identical to before. `volume` resets to `0xE0`
(max), not 0 -- the boot chime is ROM-generated before Mac OS loads any sound
preference, and a zero reset would silence it.

`make tb_easc` passes 18/18, including `stat after reset = 05`.

## `wombat33_20260830.rbf`

The build where ADB input is correct. Deployed to the MiSTer at
192.168.99.143 and verified against the pristine *Quad Squad* image (md5
`f4287aee9ff9a4413fa1e5fd9f2d63b4`) on two separate boots.

One RTL hunk, in **`rtl/via6522.sv`**: in ACR modes `011`/`111` CB1 is an input
and the internal shift clock IS the pin, but the RTL forced `shift_clock` high
whenever `shift_active` was low. Clearing `shift_active` on an `sr_ext_complete`
therefore drove it 0→1, and that rising edge shifted the byte the completion had
just loaded one place left, with `cb2_i` (tied low) in the LSB — **every byte the
ADB shim delivered, every time**.

An ADB mouse Talk R0 byte 0 is `{~button, dy[6:0]}`, so the button is exactly the
bit a left shift throws away, and what took its place was the old bit 6, the sign
of dy. That is both halves of the fault the previous entry lists as a known
issue: clicks did nothing, and plain motion with dy ≥ 0 read as button-down,
which is why mouse movement alone opened menus and appeared to type.

Scored against a control build differing only in that hunk — same disk, same ROM,
same injected mouse traffic — non-`$00` bytes surviving from the transceiver to
the driver went from **0 / 82** to **670 / 670**. Full derivation and the
measurement method: `docs/adb-via-shift.md`.

Also here: fitter `SEED` 2 → 3. Seed 2 gave −0.283 ns hold on the 99 MHz
`clk_ram` domain, which a `clk_sys`-domain change cannot reach — the placement
swing the qsf comment warns about, not the RTL.

What this build makes possible: `scripts/mac_shutdown.sh` now drives Special →
Shut Down unattended, so a core can be swapped without power-cutting a mounted
HFS volume.

**Known issues.**

- **Boot stalls roughly 1 in 3.** Frozen at "Starting Up…", disk `pos` frozen,
  screen byte-identical for minutes. Present before this build and not caused by
  it; reproduced here on a freshly restored pristine image. See
  `RESUME-adb-and-corruption.md` for the ADB-deadlock hypothesis and the
  detector committed to test it.
- **Host keystrokes never reach the guest.** Host-side, not the core —
  `kbd:osd` does not open the MiSTer OSD either, so nothing is arriving at the
  Main. The core's ADB keyboard path is therefore untested end to end.
- The Mac reads exactly one hour behind the host (minutes dead-on), which looks
  like standard vs daylight time in what the Main sends.

## `wombat33_20260829.rbf`

First core that reaches the Mac OS desktop with no operator intervention:
core load → `SC0` auto-mount of `games/Wombat33/QuadSquad8.hda` → Finder.
Verified on the MiSTer at 192.168.99.143 against the pristine *Quad Squad*
image (md5 `f4287aee9ff9a4413fa1e5fd9f2d63b4`).

Fixes in this build, over the first hardware run:

- **`ncr53c96`** — a non-DMA transfer-info that underflows now ends the data
  phase (`PH_STAT` + `I_BUS`) instead of waiting forever for a byte the target
  will never produce. This was the freeze at "Starting Up…": an INQUIRY with a
  `$24` allocation length delivered all 36 bytes and the chip then sat in
  DATA-IN. Matches QEMU `esp.c:667-671`.
- **`iosb`** — the A_SDMA hold-off got an escape (a wedged pseudo-DMA beat
  releases into a bus error rather than deadlocking the machine), and that
  escape's watchdog is frozen while a platform block transfer is outstanding,
  so SD latency cannot trip it.
- **`iosb`** — the ADB transceiver handshake moved into the `adb_en` domain.
  Driving it at full `clk` dropped command bytes and delivered response bytes
  more than once.
- **`wombat33.sv`** — CONF_STR `S0` → `SC0` so the mount is remembered, plus a
  latch that replays a mount arriving while the machine is held in reset.
- **`wombat33.qsf`** — fitter `SEED` 1 → 2; seed 1 produced a −0.122 ns hold
  violation on the 99 MHz `clk_ram` domain.

**Known issue (RESOLVED in `wombat33_20260830.rbf`, and the guess below was
wrong — it was the VIA shift register, not the heartbeat):** occasional phantom
keystrokes remain. The ADB duplicate-byte
defect is fixed and measured (VIA deliveries per transceiver byte dropped from
~2.3× to ~1.3×), and mrext is ruled out — it sends only `mouseMove`/`mouseBtn`,
never `kbd`. The residue is most likely the idle-autopoll heartbeat
re-delivering a stale `kbd_to_mac`; see `RESUME-first-hardware-run.md`.

The Quadra 800 ROM (`quadra800.rom`) is **not** committed — Apple firmware, see
`.gitignore`. Put your own 1 MB image there; the deploy seeds it to the MiSTer
as `games/Wombat33/boot.rom`.
