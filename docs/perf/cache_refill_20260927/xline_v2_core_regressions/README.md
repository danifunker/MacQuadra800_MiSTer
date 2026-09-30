# Cache-v2 core regressions and smoke evidence

This archive records a completed paired CPU-model regression gate for the reviewed cache-v2 (`9e8c0582…`) against the prior cache (`7cba7f73…`), with the exact same frozen 6c FPU (`6c157b3b…`) on both sides. The five existing program tests—FPU, FPU frames, prepared FPSP resume, MMU, and exceptions—passed on both variants. The supplementary `t_cache` run also passed on both. This is one paired regression run, not a performance benchmark or a hardware result.

The five program tests produced identical baseline/candidate bus phase cycle counts for every target (30 phase observations total); their per-target logs are byte-identical. Full enabled CPU feature macros were used, with `CACHE_CD_OFF=1`, `CACHE_SMALL=1` (8+8), and `SIMULATION=1`. The frozen 101-input manifest SHA-256 is `9462419b0f13e9cdf173caef70f12abd5b24865af0bfcbe08aecfbc6563a9d81`. Result, exact flags, tools, simulation/program image hashes, and run times are in `program_result.json`; launch/preflight and process-observation details are in the adjacent metadata files. The launcher completed with exit 0 in 117.95 seconds, with no retry. Its host PID was not captured by the exec wrapper and no process remained after completion; the execution metadata says so explicitly.

The supplementary `t_cache` test reused those already-built, hash-pinned VVPs and the same assembler. Both passed with cycles `2294 / 3382 / 3382` for bus phases 0 / 1 / 2. Its independent start/end timestamps are `06:17:00.941708–06:17:01.482461 -0400` (about 0.541 seconds). Its commands, per-command exit statuses, VVP hashes, phase counts, and logs are in `t_cache/metadata.json` and `t_cache/{baseline,candidate}/`.

`source/` contains the exact program assembly sources, `t_cache.s`, program testbench, image converter, and paired-run scripts. `candidate_cache.diff`, `source_comparison.json`, `command_plan.json`, and the frozen input manifest preserve the source delta and recipe. The manifests identify the complete original scratch inputs; this compact archive intentionally omits the full RTL tree, compiler outputs, VVP executables, generated `.bin`/`.hex` images, and unrelated fixture files. The source copy map explains each archived item and its scratch provenance.

## Separate generated-host build and disk-free smoke

`build_smoke/` records a successful Verilator 5.050 generated-host build and a short disk-free smoke from the separate full-machine setup. `make fastboot` and `make -j2 V=/home/alans/verilator5/bin/verilator` exited 0; the smoke exited 0 and both report checks passed. The source manifest was revalidated after build and after smoke. This smoke used `+ram_line_model +ram_first_latency=4 +ram_line_publish_delay=2`, had a 200,000-cycle cap, and sampled 100,002 cycles, but it is setup validation only: it is not an FPU workload, benchmark, or evidence of candidate guard coverage. It must not be combined with the CPU-model regression claims above. The guest ROM and compiled executable are omitted; their hashes and exact invocation are retained in metadata.

Run the offline archive checker with:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 check_archive.py
```

`SHA256SUMS.txt` covers the complete compact archive except itself. The checker verifies those hashes, the recorded result/log identities and phase counts, smoke status and provenance, and rejects generated binaries or caches. No simulation or Quartus command is part of the checker.
