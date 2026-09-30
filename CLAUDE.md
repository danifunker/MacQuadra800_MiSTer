# MacQuadra800_MiSTer — working notes for Claude

Start with [HANDOFF-20260928.md](HANDOFF-20260928.md): the current release
state (the 2026-09-28/29 FPU, disk and IOSB work, what is owed for a final
release, what is next). `RESUME-20260927.md` is the historical experiment
journal. `releases/README.md` is the per-build record.

Macintosh Quadra 800 core for the MiSTer FPGA (DE10-Nano). Authentic 33 MHz
68040 bus clock, AP68040 CPU (git submodule), 128 MB SDRAM main memory, DAFB
video, NCR 53C96 SCSI, Z8530 SCC, ASC sound, ADB via VIA. Boots Mac OS 7.x/8.1
and A/UX 3.1. The core was called `wombat33` until 2026-09-02; the internal
`wombat_cpu` / `wombat_bus32` / `wombat_store_buffer` module names are a
separate codename and are deliberately unchanged.

## Layout

| path | what |
|---|---|
| `MacQuadra800.{qpf,qsf,sdc,sv,srf}` | Quartus project. `MacQuadra800.sv` is the MiSTer `emu` top (CONF_STR, SDRAM/DDR3 glue, video out). Fitter seed and its history live as comments in the `.qsf`. |
| `files.qip` | the RTL file list (mirrored in the `.qsf`); add new RTL to **both** |
| `rtl/quadra800.sv` | the machine: address decode, service FSM, ROM overlay, retained-line fast paths |
| `rtl/wombat_cpu.sv` | AP68040 core + MMU + cache + store buffer wrapper |
| `rtl/wombat_bus32.sv`, `rtl/wombat_store_buffer.sv` | transaction→beat adapter; two-entry ordered RAM write queue |
| `rtl/sdram.sv`, `rtl/sdram_beat32.sv` | open-page BL8 SDRAM controller (99 MHz) and the 33↔99 MHz beat bridge with the retained 16-byte line |
| `rtl/iosb.sv`, `rtl/scc.v`, `rtl/via6522.sv`, `rtl/asc*.sv` | I/O |
| `rtl/ncr53c96.sv`, `rtl/cd_audio.sv` | 53C96 with three targets (ID 0/1 disks, ID 3 AppleCD CD-ROM) and the CD TOC/audio engine — `docs/cdrom.md` |
| `rtl/sonic_mbx.sv` | built-in Ethernet: the FPGA half of the DP83932 SONIC (doorbell ring, local ISR/IMR, op-list DMA master); the chip model is in the Main fork — `docs/ethernet.md`. OSD default Off; `ETHERNET_OFF=1` in the `.qsf` builds without it. |
| `rtl/ap68040/` | the AP68040 CPU, **vendored** (was a submodule until 2026-09-17; `rtl/ap68040/UPSTREAM.md` says which upstream commits it came from and how to port patches from `../AP68040`). Edit and commit it like any other RTL. |
| `verilator/` | full-machine Verilator sim (`sim.v`, `sim_main.cpp`) plus directed testbenches (`tb_*.sv`, targets in `verilator/Makefile`) |
| `SingleStepTests/` | CPU corpus benches |
| `scripts/` | build / deploy / hardware test tooling (see below) |
| `tools/misterdeploy/` | the reusable rbf push + `load_core` launcher |
| `releases/` | shipped `.rbf`s + `README.md` (table + one section per release) + `quadra800.rom` |
| `docs/` | design notes (`sdram-fast-path.md`, `PERFORMANCE_MEASUREMENTS.md`, `scsi/`, …) |
| `HANDOFF-20260928.md`, `RESUME-*.md` | current handoff first; dated experiment journals preserve historical state |
| `BUILD.md` | full build/deploy/disk documentation — read it before touching hardware |

## Build

```bash
bash scripts/build_only.sh            # full compile, ~40 min, -> output_files/MacQuadra800.rbf
bash scripts/build_only.sh --check    # Analysis & Synthesis only (~13 min), no rbf
```

- Needs `scripts/local.env` (gitignored; from `scripts/local.env.sample`). It
  holds `QUARTUS_BIN`, the MiSTer host/key, and the seed paths.
- **Since 2026-09-13 the work runs on a 16-core Linux box**, not the Windows
  machine the next two bullets describe: Quartus is
  `/home/alans/intelFPGA_lite/quartus/bin` (in `scripts/local.env`), Verilator 5
  is `/home/alans/verilator5/bin`, and the ARM toolchain for Main is under
  `/opt/gcc-arm-10.2-2020.11-x86_64-arm-none-linux-gnueabihf/bin`.  A seed walk
  or variant is a **scratch project**: a copy of the project in
  `scratch/<name>` with the changed files and `SEED` edited, launched with
  `systemd-run --user ... bash scripts/build_only.sh`. Separate scratch
  databases isolate inputs, but **only one Quartus flow may run globally**.
  Keep the normal wait gate and verify host processes before launching.
- **Historical Windows instructions only:** run from Git bash, not WSL.
  On the former Windows host `bash.exe` on PATH resolves to
  WSL's `C:\Windows\System32\bash.exe`; the build needs
  `C:\Program Files\Git\bin\bash.exe`. From PowerShell, launch it detached with
  `Start-Process` so a tool timeout cannot kill Quartus mid-fit.
- **No git worktrees** (user, 2026-09-18: they are confusing). Build in this
  checkout: commit what is to be built, launch `build_only.sh`, and do not
  touch RTL, the `.qsf`, `files.qip` or the `.sdc` until the flow ends (docs
  and `scratch/` are fine meanwhile). A variant or older RTL is a commit you
  check out between builds. On the current Linux host use isolated scratch
  copies with pinned manifests and durable user units; the older
  `scripts/sim_tree_wsl.sh` recipe was for WSL. After each fit, before
  the next build overwrites the db:
  `quartus_sta -t scripts/cpu/timequest_cross_domain.tcl <tag>`.
- **Never run two builds of this project at once** — they share `db/` and
  corrupt each other. **And never two Quartus flows on this box at all,
  worktrees included** (user, 2026-09-16): a seed walk runs one seed after
  another; check host `ps`/`pgrep` for every `quartus_*` process first. Other cores are built on this box by other sessions
  (sgiindy, MacLC…): `build_only.sh`'s wait-gate blocks on *any* `quartus_*`,
  so launch with `--no-wait` only after checking that no Quartus flow is
  running, and never kill a `quartus_*` process without matching its command
  line and working directory to this project. Prefer the normal wait gate.
- Timing met (positive worst slack in `output_files/*.sta.summary`) is the
  **release** bar, not a precondition for trying a build. The design sits at
  ~92 % ALMs with tenths of a nanosecond of slack and the fits are a seed
  lottery (2026-09-15: five seeds, one placement failure, misses on the
  framework's own `sys_top` HDMI register by 0.1-0.8 ns). **Try the build
  on hardware instead of waiting for more seeds** (user, 2026-09-16 -- the
  hard rule was inherited from the LC core): deploy a marginal build with
  `ALLOW_TIMING_VIOLATION=1 bash scripts/deploy_screenshot.sh` and let the
  gate (boot, Speedometer, shutdown, A/UX) judge it. A miss on the 33 MHz
  CPU clock (`emu|pll ... general[0]`) is the one that can corrupt memory
  silently, so note it in the release entry and prefer a clean seed for the
  shipped rbf when one exists; a miss on the HDMI domain is a video-output
  register and is worth trying at once. Record every seed's result in the
  `.qsf` comment block.
- After any array change, check the RAM Summary in the `.map.rpt` (see BUILD.md):
  an array falling out to registers costs tens of thousands of ALMs.
- The other direction bites too: a small array read combinationally across
  clocks can be *inferred* as an M10K with a register from the other domain
  retimed into it (`sdram.sv` `open_row`, 2026-09-02). Anything read every
  cycle from a cross-domain index gets `(* ramstyle = "logic" *)`, and after
  a re-placement (area change, seed walk) re-run the clk_ram / clk_sys↔clk_ram
  path reports (`docs/sdram-open-row-crossing.md`) before trusting the build.
- `SCSI_TRACE` in the `.qsf` makes a **debug** build that hijacks the serial
  port. It must stay commented out for anything released.
- **The qsf's default settings ARE the release recipe** (updated 2026-09-29;
  the seed and every seed tried is in the `.qsf` comment block, with
  `PLACEMENT_EFFORT_MULTIPLIER 2.0` and `ROUTER_TIMING_OPTIMIZATION_LEVEL
  MAXIMUM` since 2026-09-28, without which no seed met the CPU clock at
  94 %).  On top of the 2026-09-08 recipe below it sets: all the
  `AP040_*PIPELINE*` / `XSTORE` / `LEA` CPU macros (the second integer
  pipeline, back since `31b6e99`), `SCSI_CACHE_OFF` (the core's SCSI block
  cache off -- it no longer fits, `docs/perf/disk_cacheon_builds_20260928/`;
  the 53C96 engine's two-half sector buffer, P260, does the overlap instead
  -- **needs the write-buffer Main**, below, or every disk write waits ~4 ms
  on the SD card), and the release-lite framework trims
  `MISTER_BYPASS_AUDIO_FILTER`, `MISTER_DISABLE_VIDEO_CALC`,
  `MISTER_DISABLE_SHADOWMASK` (`VIDEO_512_OFF` was dropped on 2026-09-29: the
  512x384 monitor option is in the release); CPU caches are 8+8 KB (`SETW =
  7` in `ap040_cache.v`; 16+16 KB fits the M10K budget but misses the CPU
  clock).  The build sits at 94 % ALMs, 468 of 553 M10K, and every RTL
  change re-rolls the placement: expect a 2-4 seed walk per change
  (`docs/perf/*_fpga_*`); `docs/AREA_BUDGET_20260924.md` has the per-feature
  costs.
  The 2026-09-08 recipe:
  balanced synthesis, register duplication off, and the switches
  `CACHE_CD_OFF` (the CD passes through the block cache), `CACHE_SMALL`
  (32/32/16-sector cache), `MISTER_DISABLE_ALSA`, `MISTER_DOWNSCALE_NN`,
  `MISTER_DISABLE_ADAPTIVE`. Alan's 2026-09 AP68040 is +20 % logic and the
  chip sits at 98 %; speed synthesis does not fit, all-area synthesis fits
  but fails HDMI-domain timing. Composite Y/C stays in (the user uses it);
  `VIDEO_512_OFF` and the two switches above are the spare levers. The
  per-block sizes and what each switch saves are in `RESUME-cdrom-fix.md`
  and the `area-levers` memory.
- `CDROM_OFF=1` as a `VERILOG_MACRO` in the `.qsf` drops the CD-ROM target and
  its audio engine (measured 3,036 ALMs: 36,830 -> 33,794 at seed 19, 2026-09-03)
  for CPU work that needs the area; the gate
  is the `CDROM` parameter on `ncr53c96` (plumbed through `iosb` and
  `quadra800`). Default on; a release build never sets it.

## Simulation

Verilator 5 is `/home/alans/verilator5/bin` on this box (put it first on
PATH; the system verilator is too old), vasm is
`/home/alans/mister/MacQuadra800_fixtures/wombat-vasm/vasmm68k_mot`
(`VASM=... sh rtl/ap68040/tb/run_tests.sh`, also with `CPU_TEST_LEA=1
CPU_TEST_XSTORE=1`; keep `CPU_TEST_WORK` a short path). The WSL notes below
are the pre-2026-09-13 Windows setup. Long runs go under `systemd-run --user
--collect`; never `pkill -f` (it kills the shell). The full-machine guest
recipe the 2026-09-28/29 qualifications used (golden disk copy, control
stream, model 4/2, screenshots) is under `docs/perf/p252_p256_fpu_qual/` and
`docs/perf/p260_pingpong_sim_20260929/` (which also has the randomised
sector-latency harness that found the IOSB hang).

```bash
# directed testbenches, from verilator/
make tb_sdram tb_wombat_bus32 tb_store_buffer tb_memory_path tb_memory_path_registered_first_miss tb_ncr53c96 tb_easc tb_scsi_irq_ack_race tb_sdma_ack_watchdog tb_iosb_scc
# full machine sim: sync sources to ~/MacQuadra800 (ext4), build Vemu + ROM hexes
bash scripts/sim_wsl.sh build
bash scripts/sim_wsl.sh disk <image.hda>      # writable copy
bash scripts/sim_wsl.sh run [args] ; bash scripts/sim_wsl.sh log [pattern]
# CPU self-tests (iverilog + vasm), in the vendored CPU tree
sh rtl/ap68040/tb/run_tests.sh
```

Verilator is lenient where Quartus is not: an out-of-range bit-select on a
too-narrow vector (`mounted[2]` on a 2-bit reg, 2026-09-07) simulated as 0
without a word and failed synthesis in a minute. After new RTL passes its
bench, run `build_only.sh --check` before trusting it; it is cheap.

`tb_memory_path_registered_first_miss` is the variant that matches the shipped
quadra800 architecture. **The full-machine sim instantiates `quadra800`
directly, not `emu`:** nothing in `MacQuadra800.sv` (hps_io slot wiring, the
mount replay FSM, the VRAM mapper, the video PLL) is covered by it. A bug
that shows on hardware but not in sim lives there first (the CD strobe on
the wrong slot, 2026-09-03). `tb_sdram` models both SDRAM ranks and reports chip
protocol errors; any change to `rtl/sdram*.sv` must keep it at zero.

QEMU (`qemu-system-m68k -M q800`, built from `../qemu` in WSL) boots the exact
ROM + A/UX disk and is the golden reference for SCSI/ESP behaviour.

## Hardware (the MiSTer)

Target is the DE10-Nano at the address in `scripts/local.env`
(`192.168.99.143`, ssh key `~/.ssh/mister_only`, mrext remote on `:8182`).
**Since 2026-09-18 the box is `10.3.89.233` (`MiSTer.local`) over Wi-Fi, key
`~/.ssh/id_rsa`; since 2026-09-29 its USB (and so the Wi-Fi dongle) is dead
and it is reached on wired eth0 `10.3.164.251`** -- `scripts/local.env` has
the current address; the addresses in this section are the old LAN's. This
box's mrext ignores mouse commands: `mac_shutdown.sh` cannot press Shut
Down, use the `vmouse.py` recipe below (the 2026-09-28/29 hardware READMEs
under `docs/perf/` have the exact scripts). Main on the box since 2026-09-29
is `releases/MiSTer_20260928` (the tight disk service loop).  The box is shared with other cores' sessions (FM-7, Apple
IIgs, ...): look at the screen before loading anything, and the user says when
it is free.  The mouse is driven with
`ssh ... python3 /media/fat/Scripts/q800tools/vmouse.py` (Finder Shut Down:
`home m:111,-10 0.5 down 0.8 m:13,66 6 up`).
**Main:** the core needs a Main with the Quadra 800 support and, for the
`SCSI_CACHE_OFF` release recipe, the Mac disk write buffer: branch
`mac-printer-writebuffer` of `alanswx/Main_MiSTer` (MiSTer-devel master +
printer + write buffer; binary md5 `45182b73`, installed 2026-09-27).  A Main
without Quadra support makes every build come up black; check
`grep -a -c macquadra800 /media/fat/MiSTer` and
`grep -a -c "Mac write buffer" /media/fat/MiSTer` before debugging a core.
**Use only this box** (user, 2026-09-16): the second MiSTer at `.92` belongs
to another session and is not to be touched, not even read-only.

```bash
bash scripts/deploy_screenshot.sh       # md5-verified scp + load_core (refuses a timing-failed build)
bash scripts/grab.sh out.png            # screenshot (grab_fresh.sh fails loudly on a stale frame)
python scripts/mister_ws.py raw:<kc> …  # keyboard/mouse injection (see its docstring)
bash scripts/mac_shutdown.sh            # Mac OS 8.1 Finder: Special -> Shut Down; exit 0 = halt screen seen
bash scripts/mac_shutdown.sh --release  # free a held mouse button after a killed walker
```

`mac_shutdown.sh` is the one menu walker (`guest/shutdown_finder.sh` and
`guest/shutdown.sh` run it): it checks the pointer against a screenshot before
pressing and the lit row before releasing, and refuses A/UX's Finder (its
Special menu ends in Logout; shut A/UX down with `shutdown -h now`). Guest
Command is keycode **56** (Left Alt, `rtl/adb.sv:530`); 125 is Option, so cmd-W
is `down:56 raw:17 up:56`. A bare `mister_ws.py` call needs `MISTER_HOST` in
its environment (`. scripts/local.env`).

Disks live in `/media/fat/games/MacQuadra800/`: `QuadSquad8.hda` (Mac OS 8.1),
`HD60_512-AUX3.1-Installed.hda` (A/UX 3.1), `boot.rom`, and `backup/`.
Slot 0 is chosen by `/media/fat/config/MacQuadra800.s0` (rewrite it to switch
guests before a `load_core`); slot 1 is the second disk (`.s1`), slot 4 the
CD-ROM (`.s4`). CUE/CHD discs and the Toolbox need the Main fork
(`../Main_MiSTer`, `support/mac/`), which must list `macquadra800`.

### Binding rules — these have cost real data and whole sessions

1. **Never `load_core` / deploy / reset while a guest is booting or running.**
   It yanks a mounted, writable HFS volume. Only deploy when the screen shows
   "You may now switch off your Macintosh safely" or the MiSTer menu. If the
   state is unknown, look first (`grab.sh`) and ask.
2. **Judge guest liveness by `/proc/$(pidof MiSTer)/io` `write_bytes` deltas
   and the menu-bar clock, never by the `.hda` mtime** (main holds the image
   open; mtime is the last close).
3. **Never restart the mrext remote service under a running core** — main does
   not hot-plug input; remote keyboard/mouse goes dead until the next
   `load_core`. Silence then says nothing about the guest.
4. **Always send an explicit `mousebtn:left_up` after any guest-menu
   operation**, and never let `menu.sh` / `click.sh` / `mac_shutdown.sh` be
   killed by a timeout with the button down — a held button wedges the Finder
   in a menu track and looks exactly like a hung CPU. (`mac_shutdown.sh`
   releases on every trappable exit; a SIGKILL or tree-kill needs `--release`.)
5. **Hash or back up a disk image only after a clean guest shutdown** and
   after the core has released the file. A mounted image's md5 means nothing.
6. Do not `push_disk.sh` from the NAS to "refresh" — the MiSTer's image is the
   authoritative base.

### Regression gate before any release

Both guests must boot to a responsive desktop and shut down cleanly on the
candidate bitstream, and the CD audio path must still play:

- **Mac OS 8.1** (`QuadSquad8.hda`): Finder desktop, keyboard + mouse respond,
  menu-bar clock ticks at idle for several minutes, Special → Shut Down reaches
  the "safe to switch off" screen.
- **A/UX 3.1** (`HD60_512-AUX3.1-Installed.hda`), **with the OSD RAM option
  at 32 MB** (at 128 MB A/UX 3.1 hangs `shutdown -h now` after the
  port-mapper line on every build tested, 2026-09-16; the cause is a
  follow-up): boots through to the multiuser Finder desktop (after an
  unclean halt do not wait for the ~6 min fsck: load the menu core and
  `unzip -o backup/HD60_512-AUX3.1-Installed.zip` in `games/MacQuadra800/`
  instead, user rule 2026-09-16),
  CommandShell responds, `shutdown -h now` reaches "You may now switch off".
- **CD audio** (`games/MacQuadra800/ToneTest.cue` in slot 4 via
  `config/MacQuadra800.s4`; needs the shipped Main fork binary,
  `releases/MiSTer_20260916` or later — an older Main and the guest sees no
  CD-ROM at all): the disc mounts on the 8.1 desktop as "Audio CD 1", the
  AppleCD Audio Player's counter runs in step with the menu-bar clock under
  Play, Pause freezes it and Resume picks up from the frozen value, Stop
  returns to Track 01 00:00, and no "The Apple CD-ROM drive is not
  responding" dialog appears at any point. Main's `Mac CD: cmd` lines are the
  proof the transport reached the ARM, so relaunch Main with its stdout in a
  file before the run (`killall MiSTer`, then `nohup stdbuf -oL
  /media/fat/MiSTer /media/fat/menu.rbf >> /media/fat/nohup_video.log 2>&1
  </dev/null &` from `/media/fat`; on 2026-09-18 a hand relaunch like this
  left the user's HDMI output BLACK while the same binary was fine once init
  started it, and screenshots cannot see that, so warn the user first and
  reboot afterwards; to CHANGE the Main binary, rename the old one, rename
  the new one to `MiSTer`, `sync` and `reboot`). **Whether it actually makes a sound has
  to be judged by ear at the display** — an operator driving the box over the
  network cannot hear it, so that half of the check belongs to the user and
  the gate is not complete without them.

Then: copy the rbf to `releases/MacQuadra800_YYYYMMDD.rbf`, add a table row and
a section to `releases/README.md` (md5, seed, slack, what changed, hardware
results), and commit.

## Conventions

- Commit messages: `area: what changed and why` in plain prose, like the
  existing history. Commit as work lands; don't batch a day into one commit.
- Documentation is part of the work: design notes go in `docs/`, hand-off
  state in a `RESUME-*.md`, measurements in `docs/PERFORMANCE_MEASUREMENTS.md`.
- `scratch/` is the gitignored working area for screenshots and logs.
- Git bash mangles absolute `/media/fat/...` arguments — export
  `MSYS_NO_PATHCONV=1` (the scripts already do). `ssh` without `-n` eats a
  piped script.
