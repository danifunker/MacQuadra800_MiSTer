# baseline FPU full-machine run

Started UTC: 2026-09-27T20:38:10Z. Completed with exit status 0 (see `fpu_run.meta`).

- Binary SHA256: `fa4f49fb89ab14932dd4dbd3d957396435d86cac2031c6da406a8f4f1c32ed76`
- Command: `./Vemu --headless --no-cpu-trace --disk run.hda +rom=quadra800-fastboot.rom.hex +ram=0 --control fpu_control_full.txt --cpu-profile fpu_refill.tsv --max-cycles 20000000000 +ram_line_model +ram_first_latency=4 +ram_line_publish_delay=2`
- Profile: 1,304,100,000 cycles, 194,699,885 opcode dispatches, 6.698 clocks/dispatch
- Profile start cycle: 3,592,624,051
- Final screenshot: `screenshot_f7382.png`, SHA256 `c66734da35be5eb0e04b114f765700996988f846dd0b7da3afdd9e0a7ea67fea`
- Refill report checker: passed.

The exact control stream, TSV, command wrapper, metadata, selected screenshots, and compact log milestones are preserved alongside this file. The source tree and full log remain in `scratch/fpu_refill_model_baseline_20260927/verilator`.
