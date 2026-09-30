# Current-core platform Whetstone A/B, 2026-09-27

This run uses the platform fixture's real quadra800 CPU/MMU/cache/store
buffer, service FSM, sdram_beat32 bridge, sdram controller and two SDRAM
chip models. The ROM bridge is represented by a six-clock latency stand-in;
boot overlay is forced off. The fixed fixture image starts at SSP 0x640000.
There are no interrupts, display scanout, SCSI, Ethernet or ADB transfers.
This screen does not model Mac OS's CPUSHA frequency or the full FPU
benchmark.

Two read-only RTL trees under baseline/rtl and candidate/rtl were copied
from scratch/fpu_refill_baseline_20260927/rtl. A recursive comparison found
only rtl/ap68040/rtl/ap040_cache.v different; the candidate is the exact
scratch bulk-line candidate. The runner copies the tracked platform fixture
into this scratch directory, then applies runner.patch: repository-root
discovery for this location, --unroll-count 256 to match the current MMU
build, and a check that active QSF AP040/cache macros match fixture flags.
The Verilator version is 5.050. Both builds use identical image, ROM,
source files outside the cache, macros and romlat=6. Their identities list
SHA256 for all inputs.

To reproduce from the repository root:

    CCACHE_DISABLE=1 TREE=scratch/fpu_refill_platform_workload_20260927/baseline \
      python3 scratch/fpu_refill_platform_workload_20260927/run_platform_whet.py \
      --out scratch/fpu_refill_platform_workload_20260927/baseline_run
    CCACHE_DISABLE=1 TREE=scratch/fpu_refill_platform_workload_20260927/candidate \
      python3 scratch/fpu_refill_platform_workload_20260927/run_platform_whet.py \
      --out scratch/fpu_refill_platform_workload_20260927/candidate_run
    python3 scratch/fpu_refill_platform_workload_20260927/compare_runs.py

The comparison script requires an exact match to the existing latency
fixture oracle for globals, CODE3 and stack; exact equality between both
platform captures; the $600D guest marker; zero SDRAM protocol errors;
identical image/ROM/macros/romlat; and only the cache source differing.
The loop clock count is measured at the fixture's external writes to
0xF108. See comparison.json and the two stdout/run logs for results.

| Source | Loop clocks | First RAM read misses | Return/protocol/oracle |
| --- | ---: | ---: | --- |
| Production cache | 17,641,650 | 1,984 | $600D / 0 errors / all three match |
| Bulk-line candidate | 17,637,468 | 1,984 | $600D / 0 errors / all three match |

The candidate saves 4,182 loop clocks (0.0237%) in this fixture. This
CPU Mix Whetstone run exercises only 1,984 first RAM read misses during
17.6 million loop clocks, so it is a useful whole-CPU correctness screen
but does not predict the OS-driven FPU workload's performance or establish
the 10% target. No interrupts or DMA occur, and the ROM is a latency model.
All three memory captures match the existing fixture oracle byte for byte
and match each other. Both runs report zero bus errors, zero asserted IPL
cycles and zero SDRAM protocol errors.

The archived stdout, run logs, identity JSON files and comparison JSON are
small text evidence. The full scratch output trees retain the Verilator
build and memory captures; neither is copied into docs.
