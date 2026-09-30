# Normal-single FMOVE candidate: matched full OS FPU suite

Candidate terminal screen reports “The tests are done!” and all3 iterations1. Aggregate0.698 and ratings0.739/0.713/0.642 are unchanged. Baseline→candidate KWhet/sec3849.262→3850.048, Matrix0.991→0.991sec, FFT0.447→0.447sec. This does **not establish the aggregate10% target**. Earlier native reset-start Matrix/FFT gains did not carry into this OS recipe; their independent scopes remain valid. A possible FPCR/guard environment difference is under read-only investigation, not established explanation.

Setup is byteexact original baseline, all3 FPU tests selected/iteration1. Final screenshots preserve both results. Actual Vemu2265332 exited0 at04:18:31UTC, refillchecker0, child absent; source_manifestc528... verified unchanged. Frozen supervisor metadata retains PENDING_SCREENSHOT_REVIEW; separate comparison.json records subsequent manual qualification. Fixedwindow1,304,100,000 samples includes dialog/idle and is only used for reconciliation; it is not the sum of guest timed execution nor the speed metric. Legacy timed observer is not an acceptance gate here.

Only FPU2d53→73bc is the RTL delta. Same all10 release CPU macros plusSCSI_CACHE_OFF, cache8+8KB geometry/unroll256, original sim.v/sim_main/Makefile/control, fresh golden90,224,128-byte disk80d847..., ROMhex045c027... and original opt-in RAMmodel4-clock criticalword/2-clock retained publication. This calibrated fullguest model is distinct from the actual SDRAM controller/chip native fixture and does not qualify FPGA/hardware timing. Original baseline exact recipe is baseline_RUN_MANIFEST.txt and baseline/run_fpu_profile.sh; candidate uses run_profile.py --kind fpu in the frozen complete isolated source project. Do not launch copied recipe inside this archive.

Archive contains paired setup/final PNGs, controls/TSVs, compact terminal milestones and consumed/build/source identities with portable report checker. Full ROM/disks/binary/RTL/generatedmodels/rawtrace remain in scratch projects. Manifests retain original absolute consumed paths; archive_manifest.sha256 checks this archive. Guest disks are mutable outputs and excluded. Mix comparison remains a separate still-pending gate at archive time; Color already passed unchanged9.878sec. No further optimization or simulation is implied by this outcome.

From repo root:

    python3 docs/perf/cache_refill_20260927/normal_single_move_fullmachine_fpu/check_archive.py

Fresh reproduction needs exact model/build/sourceoverlay/freshgoldendisk and isolated outputs with actual child supervision. Preserved screenshots come only from frozen control; no additional capture was requested during timed execution.
