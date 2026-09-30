# Production tight-loop Main on the box, 2026-09-28 22:50-23:10 EDT

The tight service loop measured in `README.md` (variant (c), spin 250 µs /
budget 2000 µs), rebuilt without the sdprof counters and installed as the
box's Main.

## The binary

| | |
|---|---|
| source | `alanswx/Main_MiSTer` branch `mac-printer-fujinet-tightloop`, commit `be6604e`, one commit on `b4192cd` (the `ff404af9` FujiNet/printer/write-buffer build) |
| change | `user_io.cpp` only, +58 / -1: `mac_tl_disk()`, `mac_tl_wait()`, the armed re-entry in the SD loop of `user_io_poll()`, env read in `user_io_init()` |
| defaults | spin 250 µs, budget 2000 µs, compiled in; `MAC_SD_SPIN_US` / `MAC_SD_BUDGET_US` override them (read at core load, printed only when set); `MAC_SD_SPIN_US=0` is the old loop |
| clock reads | the spin's own `clock_gettime` per status poll, plus one per pass when the first disk request is served, and one per re-entry for the budget; nothing else |
| build | clean `make` with gcc-arm-10.2, `bin/MiSTer` |
| md5 | `75e00b65d443e17c288c3297e5e93caf` (1,248,332 B) |
| greps | `macquadra800` 1, `Mac write buffer` 1 |
| copy | `releases/MiSTer_20260928` (note in `releases/README.md`) |

Behaviour is identical to `tightloop.diff` (the budget test moved into
`mac_tl_wait()`); the only difference is the absence of the sdprof counters,
which cost about ten `clock_gettime` calls per request.

Note for anyone reusing the variant scripts: this Main (like `ff404af9`) has
**no SIGUSR2 handler**, so `tl_pr.sh` / `tl_dup.sh` / `feel.sh` (which send
USR2 to reset sdprof) would kill it. The runs below used `p_pr.sh`,
`p_dup.sh`, `p_feel.sh` in `scratch/disk_tightloop_20260928/`, which judge
copy completion from Main's `wchar` in the `armfine.sh` sampler instead.

## Install

- `/media/fat/MiSTer.ff404af9` (the previous Main) was already there; the
  new binary was copied as `/media/fat/MiSTer.tightloop_75e00b65`, then
  `cp` to `MiSTer.new` and `mv` over `MiSTer`, `sync`, reboot.
- `/etc/inittab` left original (`cmp` with `/etc/inittab.orig-20260928`
  clean: line 21 `::sysinit:/media/fat/MiSTer &`); no `main_env.txt`.
- After the reboot: `/proc/$(pidof MiSTer)/exe` md5 `75e00b65`, no `MAC_SD_*`
  in its environment (the defaults apply).
- **Wi-Fi: wlan0 is still down.** There is no `wlan0` in `/sys/class/net`
  (only `eth0`, `lo`), and `lsusb` lists only the three root hubs: no USB
  device at all enumerates, so the Wi-Fi dongle (and anything else on USB) is
  not seen by the kernel. Not investigated further. The box answers on
  `eth0` 10.3.164.251.

## Validation on the release core

Core `MacQuadra800_20260928.rbf` md5 `b7e88b81`, pushed and launched by
`scripts/deploy_screenshot.sh` (timing OK +0.006 ns; `.s0` already present,
left intact). Slot 0 the disposable `QuadSquad8-pipeline-test-20260919.hda`,
slot 4 `Marathon CD.iso` (idle), CFG byte 0 `0x40` (Ethernet On, 32 MB). The
master `QuadSquad8.hda` was not touched.

| check | result |
|---|---|
| boot | Finder desktop at 105 s, first try, no bomb |
| PR 1 (CPU / Graphics / Disk / Math / PR) | 0.895 / 1.165 / **1.704** / 21.428 / 1.210 |
| PR 2 | 2.972 / 1.168 / **1.745** / 21.441 / 1.958 (CPU is the intermittent Speedometer timer anomaly, like (c)'s Math 41.778; Disk unaffected) |
| PR 3 | 0.895 / 1.166 / **1.741** / 21.476 / 1.214 |
| PR Disk median | **1.741** (instrumented (c) 1.695, spin-0 control 1.521, `ff404af9` 1.623) |
| duplicate 1 (cold source) | **6.94 s**, 571 kB/s; read 3.27 s (1.40 MiB/s, best window 2.65), write 3.99 s (0.95 MiB/s) |
| duplicate 2 | **6.68 s**, 592 kB/s; read 2.51 s (1.65 MiB/s, best 2.73), write 4.01 s (0.94) |
| duplicate 3 | **6.69 s**, 592 kB/s; read 2.77 s (1.51 MiB/s, best 2.71), write 3.74 s (1.01) |
| duplicate median | **6.69 s** (instrumented (c) 6.80, control 7.34; -8.9 %) |
| mouse during a copy | pointer moved ~(120,65) to ~(283,195) by a vmouse move while the copy dialog was up (`prod/feel2_during.png`) |
| ping build host -> guest, 0.2 s, during a copy | median 1.99 / 1.93 ms, p90 6.4 / 5.9, max 52 / 42, 0 % loss (idle: median 1.79, max 4.7) |
| two untimed feel copies | both complete (33 items at the end) |
| Shut Down (vmouse Special menu) | "It is now safe to switch off your Macintosh" |
| **hangs** | **0** of 5 copies (3 timed + 2 feel) and 3 PRs |

Timing method as in `README.md`: Cmd-D to the middle of the sampler window
holding the copy's last write (`analyze.py`). The PR Disk figures sit about
3 % above the instrumented (c) runs, consistent with the removed counters.

The screenshot during a copy still blocks Main for a few seconds (grab.sh
takes ~3.8 s at idle), so the ping maxima are the screenshots, as before.

## Box state at the end

- Running Main `75e00b65` (`/media/fat/MiSTer`), original inittab, no env file.
- Guest at the "safe to switch off" screen with the core `MacQuadra800`
  (`b7e88b81`) loaded; disposable disk cleanly shut down (it now holds five
  more Photoshop copies).
- On the box: `MiSTer.ff404af9` (previous Main, restore by `mv` + reboot),
  `MiSTer.tightloop_75e00b65`, and the earlier `MiSTer_sdprof*` binaries.
- wlan0 absent (no USB devices enumerate); reachable on `eth0` 10.3.164.251.

Files: `scratch/disk_tightloop_20260928/prod/` (screenshots, samplers,
pings, `log.txt`).
