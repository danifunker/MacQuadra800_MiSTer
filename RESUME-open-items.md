# Historical open items after the 2026-09-08 release

**Historical snapshot. Current handoff: [HANDOFF-20260928.md](HANDOFF-20260928.md).**
Remote addresses, permissions, release state and open-item status below describe
September8 and must not be used as current operational instructions.

Written 2026-09-08 ~13:40 at the end of the day's session. Everything below
is either on `main` or on the MiSTer as described; nothing is uncommitted.

## State at hand-off

- **Repo:** `main` at `acda90d`, clean. Latest release
  `releases/MacQuadra800_20260908_3.rbf` (md5 `71102b39…`, build M =
  `4f859b3`, seed 21, +0.444 ns, 98 % ALMs; both OS gates passed). The
  release ships `releases/MiSTer_20260908` (md5 `916829ff…`), the Main
  fork at `4857af1`. The qsf defaults ARE the release recipe (seed 21).
  `README.md` is current and has the area/switch table for Alan.
- **Main fork** (`../Main_MiSTer`, branch `mac-ethernet-pr`): rebased onto
  upstream `20260907` (`f8dc68e`), tip `4857af1`, tree clean. **Not
  pushed**: the rebase rewrote published history, so it needs
  `git push --force-with-lease origin mac-ethernet-pr` — the user's call.
  Build recipe: `rsync` the tree to WSL `~/Main_MiSTer`,
  `PATH=/opt/gcc-arm-10.2-2020.11-x86_64-arm-none-linux-gnueabihf/bin:$PATH make -j8`.
- **MiSTer (192.168.99.143):** at the Mac OS halt screen ("It is now safe
  to switch off"), build M loaded from `/media/fat/_Unstable/MacQuadra800.rbf`,
  `.s0` = `QuadSquad8.hda`, `.s1` = `MacQuadra800FreshTest.hda`, `.s4` =
  `MAC_OS_8-1_RETAIL.ISO`. `/media/fat/MiSTer` on disk = the release Main
  `916829ff`; the **running** Main process is the trace build `d92a9304`
  (identical plus one printf) until the next Main restart or reboot.
  Backups: `MiSTer.bak_upstream20260907_74b59a34` (what the user had
  installed via upstream at 05:11). A Main restart auto-loads the last core
  and boots slot 0 at once — expect a guest booting, wait for it.
- **Permissions:** the auto-mode classifier refused `killall MiSTer` +
  replace over ssh until the user added allow rules to
  `.claude/settings.local.json`; ssh/scp to the box now work.
- **Scratch worth keeping:** `scratch/cdio_trace_full.{log,txt}` (hardware
  CD request trace), `scratch/qemu_cd_seq.txt` + `qemu_reads.py` +
  `cdio_seq.py` (QEMU vs hardware renderings), `scratch/qemu_install/A_*`,
  `B_*`, `C4_*.png` (QEMU experiments), `scratch/MiSTer_cdtrace_d92a9304`
  (trace Main), `scratch/MacQuadra800_M_71102b39.rbf`. In WSL
  `~/qemu-work/`: `qs8.hda` (Quad Squad 08-31 backup, unpacked),
  `qs8_swap2.hda` (same with stock Apple CD-ROM swapped in place),
  `hd2.hda` (fresh 8.1 install), `fbshot.py` (`QMON=/tmp/qmonX python3
  fbshot.py NAME` -> `scratch/qemu_install/NAME.png`), QEMU launch lines
  in `RESUME-cdrom-fix.md` (experiments A/B/C). No QEMU VM is running.

## Open items (raw CPU speed excluded)

### SCSI and CD-ROM

1. **CD multi-block on hardware.** `MB_CD=1` is on `main` (`13d7fea`,
   `tb_scsi_cache_mbcd` passes) and the Main with the 4 KB data-window fill
   is installed, but no bitstream has run it. Do: full build of `main`
   (seed 21 first), gate with **a CUE/CHD disc** (the changed path) and the
   flat ISO, then release. Old Main + MB_CD=1 reads CUE/CHD as zeros: the
   README row must say the release needs `MiSTer_20260908` or later.
2. **Disk throughput, second half.** The 8-sector groups were fix 1 of the
   user's analysis (`RESUME-cdrom-fix.md`, "SCSI throughput"). Fix 2 —
   double-buffered hps_io so the ARM's next transaction overlaps the
   current one (ping-pong) — is not designed. No throughput number exists
   with the multi-block cache; measure first (Finder copy timing or the
   Speedometer disk test), same disk, same method as
   `docs/PERFORMANCE_MEASUREMENTS.md` §9.
3. **The double CD icon** (Quad Squad + retail ISO shows the disc twice):
   proven guest-side — QEMU with its own scsi-cd reproduces it from
   `qs8.hda`, a fresh 8.1 install shows one icon on QEMU and FPGA, A/UX's
   7.0.1 shows one. The Apple CD-ROM 5.4.2 copy is excluded (in-place swap,
   `C4_02.png`). Which item of "System Folder 8.1" does it is unbisected.
   If wanted: boot `qs8.hda` in QEMU with Shift held (`sendkey shift 40000`
   on the HMP socket right after the ROM memory test) to prove it is an
   extension, then bisect. NOTE: a full `machfs` `Volume.write` of this
   2 GB volume breaks the Finder ("disk cannot be found"); edits must be
   in place (catalog record offsets: `filRLgLen` 36, `filRPyLen` 40,
   `filExtRec` 74, `filRExtRec` 86 from the record start after the
   even-aligned key). Cosmetic; do not spend core time on it.
4. **BlueSCSI Toolbox and CD changer transports:** hps_io slots 3 and 5 are
   tied off in `MacQuadra800.sv` (`sd_rd[VD_TOOLBOX] = 0`, …). The Main side
   (`support/mac/mac_toolbox.cpp`, `cdchanger_*`) is in the fork and the
   MacLC `scsi.v` has the target-side reference. Open feature.
5. **Flat ISOs get a synthesized single-track TOC** (the generic image path
   cannot serve the TOC window; Main logs "Fail to seek … offset=1099478073344").
   Data discs fine; audio/mixed-mode need CUE/CHD. One line for `docs/cdrom.md`.
6. **AppleCD responses built on the ARM** (TOC/subcode planes and the
   t2/t43/resp builders in `cd_audio.sv`, ~800 LC): precedent is
   `ide_cdrom.cpp` in Main for ao486/Archie/CD32. Architectural; awaiting
   the user's go. It is the largest remaining area lever short of
   `CDROM_OFF`.

### Correctness items owed

7. **First-run timing anomaly:** Speedometer Sieve 0.494 s on the first run
   only, and the earlier −17,482 s Queens: a first-pass timer/cache bug.
   Not chased. Start: reproduce on the current release (first Benchmark
   after a cold boot), then look at the VIA timer / Time Manager path and
   the first-miss cache fill (`docs/PERFORMANCE_MEASUREMENTS.md`).
8. **Benchmark Mix on `MacQuadra800_20260907`** (be0a662 core + cache) to
   isolate what `5aa596f` bought. Owed since the CPU merge; same disk,
   same method.
9. **`open_row` crossing fix** (`docs/sdram-open-row-crossing.md`): argued
   from the netlist, never reproduced. Many builds since with no memory
   fault; re-check the clk_ram path report after any re-placement, as
   CLAUDE.md says. Low.

- **Boot chime is the Mac II sound, not the Quadra's** (user, 2026-09-17,
  heard on the vendored-CPU build). The ROM picks its startup sound by
  machine/ASC detection, so look at the EASC version/identification
  register path in `rtl/easc.sv` / `rtl/asc*.sv` first, with QEMU q800 on
  the same ROM as the reference for the right chime. Not investigated.

### Missing hardware

10. **Built-in Ethernet (SONIC).** Nothing in `rtl/` for it. The Main fork
    carries `mac_sonic.cpp` / `mac_eth*.cpp` (SONIC + PDS Ethernet from the
    other Mac cores); the Quad Squad disk has "Apple Built-In Ethernet"
    installed. Needs the SONIC register model in the core and the slot
    wiring in `MacQuadra800.sv`. Area: unknown; the chip is at 98 %.

### Build and area

11. **98 % full.** Any netlist change is a seed walk; the recipe and the
    per-block table are in `README.md`; item 6 and `CDROM_OFF` (measurement
    builds only) are the headroom. ALSA stays out (no USB/BT audio; MT32-pi
    unaffected).
12. **Dead code:** `cd_blk512` and its read paths in `rtl/ncr53c96.sv`
    (never set since `4f859b3`); synthesis already removes it. Cleanup only;
    keep `tb_ncr53c96` green (it references `dut.cd_blk512` three times).

### Repository and tooling

13. **Fork push** (see State). **Old branches** `work/all`, `work/all2`,
    `work/side` are superseded by `main`; delete when the user confirms.
14. **Coverage gap:** the full-machine Verilator sim instantiates
    `quadra800`, not `emu`; slot wiring, the mount replay FSM and the video
    PLL are hardware-only (CLAUDE.md). A `tb_emu`-level smoke test would
    have caught the CD-strobe-on-the-wrong-slot class of bug.
15. **A/UX operator driving is fragile:** `menuitem_probe.py` latches onto a
    grey window behind the menu panel (`panel_bottom` wrong); the operator
    walked menus by hand at 0.05 s. CommandShell typing was not exercised
    today (Special -> Shut Down used instead). `mister_ws.py`: Cmd is not
    keycode 125 (Cmd+W did a type-select).
16. **Docs:** `docs/cdrom.md` line 5 still says the Toolbox/changer are
    unwired (true) but its status date is 09-02; `RESUME-cdrom-fix.md` is
    the long log of the CD work and is superseded by this file for pickup.

## Suggested pickup order

1. Item 1 (build `main` with MB_CD=1, gate with a CUE/CHD disc, release
   `20260908_4` or the next date) — it is what the installed Main is for.
2. Item 2 measurement, then decide on the ping-pong design.
3. Item 7 (the first-run anomaly) — the one correctness bug on the list.
4. Item 6 if area is needed for Alan's CPU work; item 10 when there is room.
