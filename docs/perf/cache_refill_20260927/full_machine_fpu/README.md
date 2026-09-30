# Full-machine FPU cache refill comparison

This is one matched baseline/candidate pair using the opt-in retained-RAM-line model. Both ran the saved FPU control stream with the same benchmark selection (Whetstone, MatrixMultiply, FastFourier, one iteration), independent writable copies of the same Speedometer 4.02 fixture, identical release CPU defines, and identical model parameters. Both completed with exit status 0. This is simulator evidence, not hardware validation.

Root visually verified the final screenshots and read the displayed tests:

| Test | Baseline | Candidate |
|---|---:|---:|
| Whetstones | 3,849.262 KWhetstones/sec; rating 0.739 | 3,848.418 KWhetstones/sec; rating 0.739 |
| MatrixMultiply | 0.991 sec; rating 0.713 | 0.990 sec; rating 0.714 |
| FastFourier | 0.447 sec; rating 0.642 | 0.447 sec; rating 0.642 |
| Aggregate rating | 0.698 | 0.698 |

These tiny single-run differences do not establish a repeatable gain and show no meaningful FPU improvement. Do not advance to Quartus based on this result.

The CPU profiler bracket was exactly 1,304,100,000 cycles in each run. Baseline logged 194,699,885 opcode dispatches and 6.698 clocks/dispatch; candidate logged 202,036,213 and 6.455 clocks/dispatch. Both started at simulator cycle 3,592,624,051. These fixed-window counters include all activity within the bracket and are secondary to the guest benchmark results; raw occupancy is not a test-only stall measure.

Refill region means (baseline → candidate, clocks per completed fill) were RAM data 10.980 → 8.969, RAM instruction 11.198 → 9.194, ROM data 10.256 → 10.254, and ROM instruction 11.225 → 11.227. Partial-fill start/end/abort counters were baseline 0/1/0 and candidate 1/0/0. Refill report checks passed for both runs. Different fixed-window fill totals reflect activity mix, not same-work speedup.

Both variants used `+ram_line_model +ram_first_latency=4 +ram_line_publish_delay=2`, Verilator 5.050, `--unroll-count 256`, and release defines `AP040_EXPERIMENTAL_XSTORE AP040_EXPERIMENTAL_LEA AP040_EXPERIMENTAL_PIPELINE AP040_EXPERIMENTAL_PIPELINE_LOADS AP040_EXPERIMENTAL_PIPELINE_STORES AP040_EXPERIMENTAL_PIPELINE_PEA AP040_EXPERIMENTAL_PIPELINE_P6 AP040_PIPELINE_MEMORY_ENTRY AP040_PIPELINE_COMPARE AP040_PIPELINE_EARLY_DRAIN SCSI_CACHE_OFF`. Model `sim.v` SHA256: `372f1a1988c55a900d45132bfde6e251e439143c299464081886c39dbf878c36`. Build manifests are included for each variant. Each run folder preserves its exact control stream, command wrapper, report TSV, metadata, selected screenshots, and compact log milestones. Exact file hashes are in `SHA256SUMS.txt`; original large logs and mutable disks remain in scratch.
