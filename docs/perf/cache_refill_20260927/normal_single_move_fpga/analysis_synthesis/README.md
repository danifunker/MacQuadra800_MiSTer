# Preserved Analysis & Synthesis evidence

This capture is the completed `build_only.sh --check` phase for the isolated candidate project. Quartus 17.0.2 A&S succeeded with exit 0, zero errors and 179 warnings. The full platform project passed elaboration. No fitter/STA/assembler ran in this phase.

`MacQuadra800.map.summary` reports 24,790 registers, 3,389,411 total block-memory bits, 36 DSPs, and four PLLs. `MacQuadra800.map.rpt` says its logic utilization field is N/A but gives an A&S estimate of 37,598 ALMs needed. This is an estimate, not fitted ALM use or a timing result.

The A&S RAM Summary contains 98 inferred memory instances: 69 AUTO, 17 explicitly M10K block, and 12 MLAB. In the AP040 cache it lists 44 AUTO entries and two 23,040-bit M10K tag memories. The AUTO cache entries comprise 16 cdata arrays (8,192 bits each), 16 idata arrays (4,096 bits each), and 12 pairdata arrays (4,096 bits each). The FPU register file appears as two MLAB instances, 8x80 bits each. AUTO means the A&S report has not resolved final physical block-memory placement. The report also includes synthesized-away RAM node warnings; do not treat the A&S instance table as a fitted M10K/MLAB count.

No byte-matched baseline A&S project was run as part of this task, so these resource figures do not establish a candidate-vs-baseline area delta. They also do not establish timing or physical fit. `launch_identity.json` records systemd invocation and the observed `quartus_map` PID. The source and preparation manifests are beside the project root.
