# Enabled normal-single FMOVE — matched OS FPU result

Candidate6c completed all three FPU tests, one iteration each. Root reviewed the all-three-selected setup4277 and “The tests are done!” final7382. Displayed aggregate rose from0.698 to0.729 (+4.441%, below the10% aggregate target). Whetstone was3850.048 KWhetstones/sec versus original3849.262 (the same displayed value as55ff); Matrix0.928sec versus0.991; FFT0.418sec versus0.447. From rounded displayed times, Matrix throughput increased0.991/0.928−1=6.789% and FFT0.447/0.418−1=6.938%. These are guest benchmark results, not measured FPGA gains.

Previous55ff used the same calibrated recipe and scored0.698, with Matrix0.991/FFT0.447. Its artifacts are retained alongside original-baseline outputs for comparison. Candidate6c removes the exception-enable-byte exclusion from the normal-single conversion shortcut while preserving ROUND/WB exception handling; the exact delta against55ff and architectural review are included. No production RTL or original completed inputs were changed.

The passive observer reconciles1,304,100,000 full-window edges and11,666,052 raw new-command branch events. It observed5,347,864 normal-single6c eligible events, all followed by actual ROUND, zero mismatch; historical73bc and55ff predicates accepted930 each. Precision00/enable0x20 accounted for5,346,934 normal events; precision00/enables00 accounted for930. Restore/pending/unexpected-class counts were zero. Context diagnostics are bounded at64 rows, with5,347,800 contexts dropped; aggregate buckets remain complete. Raw events are not proven unique architectural instructions, and the full control window does not attribute them to individual timed subtests.

Actual child2446609 exited0 at2026-09-28T08:35:18UTC and was absent afterward. Frozen source223-input manifest6ce6d469... and binary2f16b5... validated unchanged; supervisor and independent refill/v2 nonempty checkers passed. Supervisor metadata retains its PENDING_SCREENSHOT_REVIEW label; subsequent root review is separately recorded in `candidate/manual_review.json`. Refill362,657,816samples/35,823,263completed entries are reconciliation counts, not guest execution duration or a speed claim.

Matched original recipe: all10 releaseCPU flags plusSCSI_CACHE_OFF, cache8+8KB, Verilator5.050/unroll256, calibrated opt-in RAM first4/publication2, original control33108d..., ROMhex045c027..., fresh90,224,128-byte golden HDA80d84794.... Fullguest uses a calibrated host RAM model rather than the production SDRAM/controller/chip fixture. Hardware timing and functionality remain separate gates; this evidence does not establish them. Mix remains a separate pending result at archive preparation; Color9.878sec was separately qualified unchanged.

This compact archive includes exact controls/TSVs, scheduled setup/final PNGs, terminal/checker/manual-review evidence, source/build identities, frozen supervisor recipe, observer code and candidate delta. Absolute paths in source and launch provenance are historical scratch identities. Complete sources, executable/generated model, ROM, mutated outputdisk and huge rawlog remain in the frozen scratch project; they are not duplicated here. Do not launch the copied supervisor within this archive. Reproduction requires the complete pinned source/model/assets, fresh disk, separate outputs and bounded child supervision.

Archive-relative verification:

```
python3 docs/perf/cache_refill_20260927/normal_single_enabled_fullmachine_fpu/check_archive.py
```

The checksum verifies the included artifacts; checkers validate candidate capture reconciliation and eligibility/actualROUND consistency. Displayed timer interpretation rests on root's recorded image review, not automatic OCR or an independent numerical FPU oracle.
