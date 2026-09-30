# Building the MacQuadra800 core

There are two ways to build the FPGA core: the Quartus GUI, or the scripted CLI flow
in `scripts/`. This document covers the **CLI flow** — repeatable, headless-friendly,
and core-agnostic (the same `build_only.sh` works in other MiSTer core repos with no
edits). For the GUI, just open `MacQuadra800.qpf` in Quartus and run a full compilation.

The build **never touches the MiSTer** — deploying is a separate step (see
[Deploy](#deploy-separate-step)).

## Prerequisites

- **Intel Quartus Prime 17.0.2 Lite Edition** installed. Typical `bin` locations:
  - Linux: `/home/<you>/intelFPGA_lite/17.0/quartus/bin` (or `/opt/intelFPGA_lite/17.0/quartus/bin`)
  - Windows (git-bash): `/c/intelFPGA_lite/17.0/quartus/bin64`
  - macOS: `/Applications/intelFPGA_lite/17.0/quartus/bin`
- **Bash** — Linux, macOS, or Windows git-bash.
- For deploy: `ssh`/`scp` on `PATH`, plus the `websockets` Python package.

## First-time setup (once per machine)

The scripts read machine/core settings from `scripts/local.env`, which is **gitignored**
(it holds your Quartus path and — for deploy — the MiSTer host/ssh key). Generate it from
the committed template:

```bash
bash scripts/setup_env.sh
```

Then edit `scripts/local.env` and set at least your Quartus bin dir:

```
QUARTUS_BIN=/c/intelFPGA_lite/17.0/quartus/bin64
```

That is all that is required **to build**. (Deploy additionally needs `MISTER_HOST` and
`MISTER_SSH_KEY` — see the comments in `scripts/local.env.sample`.)

## Build

```bash
bash scripts/build_only.sh
```

Compile time depends on host, candidate and seed. Earlier builds took 35–40
minutes at about 81% ALMs; the 2026-09-28 experimental seed31 fit took about
18 minutes at 92% ALMs, with positive timing on every clock. See the
[current handoff](HANDOFF-20260928.md) for its exact identity. On the current
Linux host use a durable supervised process with captured exit status/logs,
and preserve its inputs until completion. Only one Quartus flow may run globally.

| command | what it does |
|---|---|
| `bash scripts/build_only.sh` | full compile, `.sof` + `.rbf` |
| `bash scripts/build_only.sh --check` | Analysis & Synthesis only (~13 min); **no `.rbf`** — a syntax / multi-driver / RAM-inference sanity check |
| `bash scripts/build_only.sh --no-wait` | don't wait for another in-progress Quartus (see [Multiple builds](#running-multiple-builds-on-one-host)) |
| `bash scripts/build_only.sh -h` | help |

### Reading the status summary

At the end `build_only.sh` prints a summary, for example:

```
BUILD STATUS  (MacQuadra800, 38m12s)
  Analysis & Synthesis   Analysis & Synthesis Status : Successful - ...
  Fitter                 Fitter Status : Successful - ...
  Timing (STA)           met — worst slack +0.441 ns
  Artifact               output_files/MacQuadra800.rbf  (4256376 bytes, ...)
  Quartus flow           exit=0
```

- **Timing (STA)** should read `met` (positive worst-case slack) for a release.
  `VIOLATED` means a marginal `.rbf`: try it on hardware anyway
  (`ALLOW_TIMING_VIOLATION=1 bash scripts/deploy_screenshot.sh`) and let the
  gate judge it, but note which domain missed. The critical domain is
  the 33.000 MHz `clk_sys` out of `emu|pll` — the exact real-Quadra rate that every
  time-anchored divider (RTC `SEC_DIV`, the 60.15 Hz tick, VIA `E_HALF`, ASC
  `SAMPLE_DIV`) assumes.
- **Artifact** must be present. The script's exit code is nonzero on any failure.
- The full Quartus log is written to `output_files/build_<timestamp>.log`.

### Area / RAM-inference gotchas

This design sits close to the device ceiling, so two checks are worth doing after any
A&S run that changes an array:

- `MacQuadra800.srf` suppresses RAM-inference messages wholesale (IDs `276020` / `276027`
  with a `*` wildcard). **Never trust the absence of an inference warning** — read the
  RAM Summary table instead:

  ```bash
  i=$(grep -n "^; Analysis & Synthesis RAM Summary" output_files/MacQuadra800.map.rpt | cut -d: -f1); sed -n "${i},$((i+45))p" output_files/MacQuadra800.map.rpt
  ```

  Every array must show `Type = M10K block` (or `AUTO`). An array that fell out to
  registers costs tens of thousands of ALMs — `Total registers` jumping back toward
  60 k is the tell (a healthy build is ~28-29 k).
- `quartus_map` standalone skips the pre-flow script (`sys/sys.tcl`) that regenerates
  `build_id.v`, which `MacQuadra800.sv` includes. `--check` therefore builds against
  whatever `build_id.v` is on disk; the full flow regenerates it.

## Deploy (separate step)

Building produces `output_files/MacQuadra800.rbf` but does not push it anywhere. To push the
build to a MiSTer, reboot it, and select the core over the OSD:

```bash
bash scripts/deploy_screenshot.sh
```

It refuses to deploy if `MacQuadra800.fit.summary` does not say `Successful`, then hands off
to `tools/misterdeploy/launch_unstable_core.py`: scp (md5-verified) into `_Unstable`,
reboot for a clean menu, and blind-OSD navigation generated from the live menu listing.

Alongside the `.rbf` it seeds two things, both **create-only-if-missing** so real user
data is never clobbered:

| what | where | from |
|---|---|---|
| pristine 1 MB Quadra 800 ROM | `/media/fat/games/MacQuadra800/boot.rom` | `releases/quadra800.rom` |
| SD slot 0 mount memory | `/media/fat/config/MacQuadra800.s0` | points at `games/MacQuadra800/QuadSquad8.hda` |

See `tools/misterdeploy/README.md` for the launcher's full flag set.

> **The slot-0 seed does nothing today.** `MacQuadra800.sv`'s CONF_STR declares the disk
> as `"S0,HDAVHD,Mount SCSI disk;"`. In MiSTer's option parser the letter after `S`
> is a flag: `SC0` sets `store_name`, which is what makes the Main write and later
> restore `config/<core>.s<N>`. A plain `S0` mounts identically when you pick a file
> in the OSD, but the mount is never remembered — so `MacQuadra800.s0` is written by the
> deploy and then ignored, and the disk must be mounted by hand every boot. Every
> sibling core (`MacLC`, `MacLCII`, `MacIIvi`, `MacPlus`, `LBMacTwo`) uses `SC0`.
> Changing `S0` → `SC0` needs a full rebuild; until then, mount from the OSD.
>
> MGL is not a workaround: a `<file type="s" index="0" .../>` entry pointing at the
> image is parsed by the Main (`type=S index=0 path=…`) but comes back `valid=F`
> and no mount happens.

### Main SCSI disk

The disk image is multi-gigabyte, so it lives outside the repo and is pushed **once**;
`deploy_screenshot.sh` only writes the mount memory that points slot 0 at it.
`push_disk.sh` is that one-time step:

```bash
bash scripts/push_disk.sh "/path/to/HD00 512 Quad Squad with 8.hda" QuadSquad8.hda
```

It scps the image into the core's games folder, md5-verifies both ends, and then takes
a gzip backup under `games/MacQuadra800/backup/`. The order is deliberate: verify **before**
backing up (a corrupt transfer must not become the backup), and back up **before the
first boot** — once the core mounts the image read-write there is no pristine copy left.
It refuses to overwrite an image already on the MiSTer, since that one may hold a booted
system's writes.

Roll back on the MiSTer with:

```bash
gzip -dc /media/fat/games/MacQuadra800/backup/QuadSquad8.hda.gz > /media/fat/games/MacQuadra800/QuadSquad8.hda
```

The image was originally pushed from `HD00 512 Quad Squad with 8.hda` in
`\\daninas.local\Software\BlueSCSI Images\Quadra800\` as `QuadSquad8.hda`:
2,146,461,696 bytes, md5 `f4287aee9ff9a4413fa1e5fd9f2d63b4`, verified on both ends
2026-08-29.

**That is no longer the base image.** On 2026-08-31 it was updated in place on the
MiSTer -- new test software was installed into the running system -- and re-blessed.
The live base is now:

| | |
|---|---|
| path | `/media/fat/games/MacQuadra800/QuadSquad8.hda` |
| size | 2,146,461,696 bytes (unchanged -- same geometry, same partition map) |
| md5 | `1a40aa8a77af35cabfe76d4dea9ccf13` — measured after a clean shutdown, see below |
| pristine backup | `backup/QuadSquad8.hda.gz`, 342,339,344 bytes, taken 2026-08-31 17:27 from the quiesced image. **Restore-verified**: `gzip -t` passes and it decompresses to the same `1a40aa8a...` |

> **Hashing a mounted image gives a number that means nothing.** That is
> measured here, not assumed — the same image produced three different md5s on
> 2026-08-31:
>
> | when | md5 |
> |---|---|
> | as pushed from the NAS, 2026-08-29 | `f4287aee9ff9a4413fa1e5fd9f2d63b4` |
> | mid-session: core loaded, volume mounted, guest idle | `a70189d3fbea5f60a5da6be4a22a2e04` |
> | **after Special -> Shut Down, volume unmounted** | **`1a40aa8a77af35cabfe76d4dea9ccf13`** |
>
> Only the last is a base-image hash. The middle one was stable across two
> back-to-back md5 runs with the guest idle, so "I measured it twice and it
> agreed" does **not** mean the volume was quiesced. Two consequences:
>
> - `mtime` is not a freshness signal. The Main holds the image open for the
>   whole core session, so the stamp is the last *close*, not the last write —
>   it sat at 13:17 through all of the above.
> - A backup taken with the volume mounted is not pristine. The 16:04 one is a
>   complete, valid archive (`gzip -t` passes, full 2,146,461,696 bytes) that
>   restores to `93738964c24e06e49b0d90d8baefac01` — a state the machine was
>   never actually in. It is kept as
>   `backup/QuadSquad8_20260831_mounted_snapshot.hda.gz` rather than deleted,
>   but it is not a restore point.
>
> So `push_disk.sh`'s existing rule — back up *before* the first boot —
> generalises to: shut the guest down (`bash scripts/mac_shutdown.sh`) and let
> the core release the file before hashing or archiving anything.

The copy on `\\daninas.local` is **still the old `f4287aee...`** and was not
touched. Do not re-run `push_disk.sh` from the share to "refresh" the disk: that would
roll the machine back and lose the newly installed software. The MiSTer's own image is
the authoritative base from here on.

If you point the mount at a different filename, change `SEED_MOUNT_REL` in
`scripts/local.env` to match — or just remount from the OSD (`Mount SCSI disk`), which
rewrites `config/MacQuadra800.s0` itself.

## Testing on hardware

| command | what it does |
|---|---|
| `bash scripts/grab_fresh.sh out.png` | trigger a MiSTer screenshot and download it, **failing loudly** if no new frame appears (dead video serves a stale frame otherwise) |
| `bash scripts/grab.sh out.png` | the stock grab — newest stored screenshot, stale or not |
| `python scripts/mister_ws.py up down confirm` | send OSD keystrokes over the MiSTer Remote websocket |

Put session screenshots and scratch captures in `scratch/` (gitignored).

The pre-hardware gate is the Verilator testbench in `verilator/` — see
`QUADRA800_TESTBENCH.md` and `RESUME-disk-gate.md`. Sim runs from inside `verilator/`
(the ROM hex path is cwd-relative).

## Running multiple builds on one host

- **The same core twice at once — don't.** Both compiles share `db/`, `incremental_db/`,
  and `output_files/`, so they would corrupt each other. `build_only.sh` prevents this:
  the second invocation waits (30 s poll) until the first Quartus finishes.
- **Different cores or isolated copies:** the current project policy still allows
  only one Quartus flow globally. Keep the host-global wait gate enabled; do
  not use `--no-wait` to bypass it. Check for any running `quartus_*` process
  before launching, including flows owned by other work.

## Portability to other cores

`build_only.sh` and `deploy_screenshot.sh` need **no per-core edits**. Both auto-detect
the Quartus revision from the single `*.qsf` in the repo root (override with
`QUARTUS_REVISION`) and derive the `.rbf` name from it. To reuse this toolchain in
another MiSTer core repo, copy `scripts/` and `tools/misterdeploy/` into that repo, run
`bash scripts/setup_env.sh`, set `QUARTUS_BIN`, and adjust only the CORE section of
`scripts/local.env`.
