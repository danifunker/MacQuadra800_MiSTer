# Normal-single FMOVE candidate: full OS Color8 regression

Candidate completed with “The tests are done!”, Eightbit9.878seconds/rating1.072/iteration1, exactly the baseline displayed result. Setup shows only8bits/pixel checked and iteration1. Both setup and final images are byteexact baseline. Full fixed-window TSV is also byteexact:524,160,000 samples. These window totals reconcile the capture and are **not** measured Color test duration or speed. Guest times/screens are the measurement gate.

Only FPU2d53→73bc differs in RTL; all10 release CPU macros plusSCSI_CACHE_OFF, cache8+8KB geometry, unroll256, original host model/sim_main and control remain matched. Original calibrated opt-in RAM service is4-clock firstword/2-clock retained publication; this fullguest model is not the production SDRAM controller/chip fixture or FPGA timing qualification. Fresh90,224,128-byte golden disk SHA80d8479430a66edae161c2bac6a9563dbb4f6bd0f564ee7849a555c447df8888, ROMhex045c027..., controlfae07029... and exact build/input identities are preserved in metadata/preflight/manifests. Completed guest disk is mutable output and excluded. No edits/rebuilds occurred during the run; source_manifest verified unchanged afterward.

Actual child2282523 exited0 at04:10:52UTC; independent refill checker exited0 and child was absent afterward. Candidate binary3b4fd308..., build identityf0af69..., input source manifestc528f7.... Run metadata intentionally retains PENDING_SCREENSHOT_REVIEW status emitted by the frozen supervisor; comparison.json records subsequent manual source/screen qualification instead of rewriting live outputs. Original baseline recipe is baseline_RUN_MANIFEST.txt plus baseline/run_color8.sh. Candidate uses the exact pinned recipe via run_profile.py --kind color8 in its full isolated source project; archive copies document it and should not be launched inside this text archive.

Archive includes standard setup/final PNGs, exact baseline/candidate controls and TSVs, supervisor/recipe/source identities, compact terminal milestones and portable reconciliation checker. Full binaries/ROM/disks/source trees and125MB raw trace remain in completed scratch projects. Source manifests retain actual scratch absolute paths; archive_manifest.sha256 checks archive-relative artifacts. FPU and matched Mix results are separate gates and remained active when this Color evidence was finalized. No new numerical FPU oracle or hardware claim follows from this graphics regression.

From repo root:

    python3 docs/perf/cache_refill_20260927/normal_single_move_fullmachine_color/check_archive.py

A fresh replay requires the original complete model/build recipe, exact pinned source overlay and fresh golden input disk, its own output directory, and child supervision. Never overwrite completed/live inputs. No additional screenshots were requested during the measurement; preserved images came from frozen control.
