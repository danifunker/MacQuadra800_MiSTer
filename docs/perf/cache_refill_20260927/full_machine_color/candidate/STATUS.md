# Matched Color 8-bit regression

Started 2026-09-27 20:50:23 UTC in a separate working directory, using the already built matched full-machine binaries; no build or FPU input mutation was performed. Each run has its own control stream, fresh writable `run.hda`, log, CPU profile, screenshots, and exit metadata. Both runner logs confirm `+ram_line_model +ram_first_latency=4 +ram_line_publish_delay=2`, fixture mount, and start of the saved control stream's 700,000,000-edge wait.

| Variant | Durable tool session | runner namespace PID | binary SHA256 |
|---|---:|---:|---|
| Baseline | 39656 (observer session later returned 143; Vemu continued) | 2 (host PID 1833590) | `fa4f49fb89ab14932dd4dbd3d957396435d86cac2031c6da406a8f4f1c32ed76` |
| Candidate | 23603 | 2 (host PID 1833592) | `20eb94c5a8fc223e0eb8eb5559087b0b473b37f5940092bce4941a9e647edb9a` |

Session handles are authoritative; namespace PIDs are not globally unique. Wrapper `run_color8.sh` records start and final simulator status in `color8_run.meta`. It invokes:

```sh
./Vemu --headless --no-cpu-trace --disk run.hda +rom=quadra800-fastboot.rom.hex +ram=0 --control color8_control_full.txt --cpu-profile color8_refill.tsv --max-cycles 20000000000 +ram_line_model +ram_first_latency=4 +ram_line_publish_delay=2
```

Release CPU defines in the matched binaries: `AP040_EXPERIMENTAL_XSTORE AP040_EXPERIMENTAL_LEA AP040_EXPERIMENTAL_PIPELINE AP040_EXPERIMENTAL_PIPELINE_LOADS AP040_EXPERIMENTAL_PIPELINE_STORES AP040_EXPERIMENTAL_PIPELINE_PEA AP040_EXPERIMENTAL_PIPELINE_P6 AP040_PIPELINE_MEMORY_ENTRY AP040_PIPELINE_COMPARE AP040_PIPELINE_EARLY_DRAIN SCSI_CACHE_OFF`; Verilator 5.050 with `--unroll-count 256`. Both share model RTL SHA256 `372f1a1988c55a900d45132bfde6e251e439143c299464081886c39dbf878c36`.

The source control is `docs/perf/graphics_profile_20260926/color8_control.txt` (SHA256 `998e9b98487a6541978adb579925c7fe30036a4b979b76a7a10adde08798e61a`). It was copied byte-for-byte and only `quit\n` appended after the final one-million-edge wait; expanded control SHA256 is `fae07029b5f17ecc0e7471fa90499d09b29bd08a50c433eb058f603d24a15ecc`. This retains the benchmark commands and bracket. Fixture `run.hda` in both run directories is an independent copy of `/home/alans/mister/MacQuadra800_fixtures/MacQuadra800-Speedometer402-profile.hda`, SHA256 `80d8479430a66edae161c2bac6a9563dbb4f6bd0f564ee7849a555c447df8888`; fastboot ROM SHA256 `045c02746b5f15f83132d33c5414f806e7b049f3bfe53a7bd0ecacb8e072d673`.

Outputs are isolated per variant in `color8_run/`; screenshots are named `screenshot_f<frame>.png`. At completion inspect visible results/scores and run the refill report checker on each TSV. The fixed clock bracket may include post-result idle time; displayed benchmark results are primary.

Parent verified exact `/proc` working-directory mapping: this tree Vemu host PID 1833592; wrapper parent runs `run_color8.sh`. Observer session 23603 remains non-authoritative for process liveness.

Approximate remaining time at the 2026-09-27 21:19 UTC status check: current 200M-edge wait had about 15M edges remaining by matching its logged start cycle to the latest heartbeat; future explicit waits before profile start total about 889M edges, and the profile bracket has 524.96M edges. Observed throughput is ~60M simulator main_time units/minute, about 2 units per requested rising edge, implying ~30 minutes to profile start plus ~18 minutes for the bracket. This excludes shot/frame-boundary overhead and is approximate.

## Completion

Completed 2026-09-27 22:08:11 UTC with `exit_status=0`. Profile stop report: `524160000 cycles, 95514940 opcode dispatches, 5.488 clocks/dispatch`. Checker passed: `refill report reconciles: fill=76596153 tagwrite=8758839 completed=8758838`. Result screenshot `screenshot_f5525.png` SHA256 `9da8a37e09a707693ad25538ebdee388248bda19c6f24945a302f2324dd48357`.
