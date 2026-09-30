# 55ff all-precision FPU, seed-27 fit

This archive records the single authorized Quartus 17.0.2 full compile and cross-domain STA for the 55ff FPU candidate, based on commit `708c12542a74c0b92872910d330a6e989b6a2181`. It is evidence for an isolated analysis build; no bitstream was deployed and no hardware was accessed. The RBF, SOF, Quartus databases, and incremental database are intentionally omitted.

The frozen project manifest has 1,892 tracked inputs. Compared with the successful 73bc seed-27 project, only `rtl/ap68040/rtl/ap040_fpu.v` changed: `73bc156d147e4f8b1c7ee08f0bb03c7f1cd720d4e78293d8252f63bf992f0b1f` → `55ff9b3cd1d59069ec0b94ca17e4dc3a8c87ac031317902285444d92643724a2`. QSF is unchanged at seed 27 (`9b6fa7c352dd7667339e6e6ec4f03a00d1894b7e7fce14908f8b57b99c059ec4`); SDC SHA-256 is `b2f5bd18b52d7897f711b7b1c465c6a5bd1fffa344275557761aba8f40929062`. All 1,891 non-FPU inputs matched the prior candidate. The exact candidate FPU, QSF, and SDC are in `source/`; full source identity is in `tracked_source_manifest.sha256`.

The compile completed with exit 0 under `codex-fpu-normal-single-allprecision-quartus-20260928-seed27.service` (invocation `bc05612be0014d6880a51cb94c7e282a`, tool session 33157). Quartus used device 5CSEBA6U23I7. Fit used 38,732/41,910 ALMs, 24,636 registers, 468/553 M10Ks, 3,389,411 block-memory bits, 36 DSPs, and 4 PLLs. Worst setup slack was +0.036 ns and worst hold slack +0.205 ns; reported TNS was zero. The generated RBF was 4,487,180 bytes, SHA-256 `41a7058eb0031e179be6f6e86c5b8769b3ce596d6137f321d1746daa320af77a` (hash recorded for identity; binary omitted).

Cross-domain STA completed with exit 0 under `codex-fpu-normal-single-allprecision-quartus-20260928-seed27-cross.service` (invocation `8f2853501ec74e27a7b0931f5ed27c0b`, session 36351; 8 warnings, 0 errors). Worst reported sys→RAM slack was +0.726 ns and RAM→sys was +0.036 ns; six analyzed paths in each direction were positive. Compact summaries and tagged reports are in `reports/`; original build and supervisor logs are in `runlogs/`. Process/executable provenance is in `full_quartus_processes.json`, `full_compile_identity.json`, and `cross_domain_identity.json`.

This fit alone does not establish OS-level performance or hardware behavior. The source-matched original-FPU (2d53) baseline had HDMI setup slack −0.025 ns; that remains a diagnostic comparison and any hardware action remains gated by the project handoff's availability, safe-screen, Main, and disk checks. No such action is included here.

Run the portable archive verifier from any directory:

```sh
python3 docs/perf/cache_refill_20260927/normal_single_allprecision_fpga/seed27_successful_fit/check_archive.py
```

To additionally check the frozen project inputs against an available source tree, pass `--source-tree PATH`. The archive checksum list is `SHA256SUMS`.
