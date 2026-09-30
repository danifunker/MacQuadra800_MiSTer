# Matched full-machine refill runs: four-report comparison

This summarizes one baseline/candidate pair for FPU and one for Color 8-bit. All four runs used the same retained-line model and release CPU defines. Full run inputs, results, screenshots, hashes, and exact commands are preserved in [`full_machine_fpu`](full_machine_fpu/README.md) and [`full_machine_color`](full_machine_color/README.md). Report validation passed for all four TSVs.

| Workload | Guest result, baseline → candidate | CPU profile bracket, baseline → candidate | Interpretation |
|---|---|---|---|
| Color 8-bit | 9.878s / rating 1.072 → 9.807s / rating 1.080, one iteration | 524,160,000 cycles each; 5.578 → 5.488 clocks/dispatch | Candidate elapsed time is 0.71877% lower in this one pair. Preliminary; repeat to establish stability. |
| FPU selected tests | Aggregate rating 0.698 → 0.698; Whetstones 3849.262 → 3848.418 KWhetstones/sec; MatrixMultiply 0.991 → 0.990s; FastFourier 0.447 → 0.447s | 1,304,100,000 cycles each; 6.698 → 6.455 clocks/dispatch | No meaningful guest benchmark gain; do not proceed to Quartus based on these results. |

Region means, baseline → candidate, in refill clocks per completed fill:

| Workload | RAM data | RAM instruction | ROM data | ROM instruction |
|---|---:|---:|---:|---:|
| Color 8-bit | 11.010 → 8.993 | 11.165 → 9.175 | 10.503 → 10.495 | 11.146 → 11.147 |
| FPU | 10.980 → 8.969 | 11.198 → 9.194 | 10.256 → 10.254 | 11.225 → 11.227 |

The profiler brackets have equal cycle lengths per workload. Dispatch and fill totals can differ because the fixed windows contain different activity mixes; they are not same-work speedup measures. The guest benchmark scores and times are the workload-level comparison. Each result is a single paired simulation, and the opt-in retained-RAM-line model is not hardware validation.
