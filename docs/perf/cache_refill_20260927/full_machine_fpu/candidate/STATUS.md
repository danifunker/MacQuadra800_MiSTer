# candidate FPU full-machine run

Started UTC: 2026-09-27T20:38:36Z. Completed with exit status 0 (see `fpu_run.meta`).

- Binary SHA256: `20eb94c5a8fc223e0eb8eb5559087b0b473b37f5940092bce4941a9e647edb9a`
- Command: `./Vemu --headless --no-cpu-trace --disk run.hda +rom=quadra800-fastboot.rom.hex +ram=0 --control fpu_control_full.txt --cpu-profile fpu_refill.tsv --max-cycles 20000000000 +ram_line_model +ram_first_latency=4 +ram_line_publish_delay=2`
- Profile: 1,304,100,000 cycles, 202,036,213 opcode dispatches, 6.455 clocks/dispatch
- Profile start cycle: 3,592,624,051
- Final screenshot: `screenshot_f7382.png`, SHA256 `2b36908fee420dd552247c5b9cc4e171de9e8d45c2e1bde16300c89dab8347e4`
- Refill report checker: passed.

The exact control stream, TSV, command wrapper, metadata, selected screenshots, and compact log milestones are preserved alongside this file. The source tree and full log remain in `scratch/fpu_refill_model_candidate_20260927/verilator`.
