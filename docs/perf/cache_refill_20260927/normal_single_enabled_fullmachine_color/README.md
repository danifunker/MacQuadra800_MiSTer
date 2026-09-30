# Enabled normal-single FMOVE candidate — OS Color8 regression

Candidate6c completed with “The tests are done!”, Eightbit9.878seconds, rating1.072, iteration1. Root reviewed setup4277 (onlyEightbit selected, iteration1) and final5525; both PNGs are byte-exact the original baseline. The displayed result also matches the prior73bc result. Other color iterations are zero. No Color regression was observed.

The standard524,160,000-cycle profile is byte-exact baseline after removing newly added passive `FPU_GUARD_` rows. Observer273 raw branch events contained no normal single input or eligible6c event; postROUND mismatches were zero. Fixed-window totals are capture reconciliation, not measured Color duration or speed.

Actual child2462108 exited0 at2026-09-28T08:27:53UTC. Supervisor recorded successful postrun source validation and refill/v2allow-empty report checks; independent rechecks passed and the child was absent. The binary remained2f16b5..., source manifest6ce6d469... (223inputs), FPU candidate6c157b.... Original supervisor metadata deliberately retains PENDING_SCREENSHOT_REVIEW; the later root finding is preserved in separate `candidate/manual_review.json` without rewriting terminal metadata.

Matched original recipe: all10 releaseCPU flags plusSCSI_CACHE_OFF, cache8+8KB, Verilator5.050/unroll256, calibrated opt-in RAM first4/publication2, controlfae07029..., ROMhex045c027..., fresh90,224,128-byte golden disk80d84794.... Fullguest RAM modeling is not the production SDRAM/controller fixture or FPGA timing qualification. Frozen source/build and supervision manifests document actual input identities; mutated completed disk, ROM image, executable/generated model and full raw log are excluded from this compact archive. Full artifacts remain in `scratch/fpu_normal_single_enabled_color8_20260928` and its pinned source project. Absolute scratch paths in provenance manifests are historical identities, not archive-local replay instructions. `inputs.json` retains its prelaunch preparation-stage label; terminal evidence is `candidate/run.meta.json`.

Baseline recipe/outputs are copied from the previously qualified original-baseline archive. Candidate `run_profile.py` is a frozen recipe reference; do not launch it inside this archive. A fresh replay needs the complete pinned source/model and build, original assets, a fresh golden disk, distinct output directory and child supervision.

Verify the archive from any working directory:

```
python3 docs/perf/cache_refill_20260927/normal_single_enabled_fullmachine_color/check_archive.py
```

The archive-relative checksum covers all included artifacts. FPU and Mix are separate gates and remained live when this archive was prepared. No numerical FPU or hardware qualification follows from this graphics result.
