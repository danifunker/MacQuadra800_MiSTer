The combined 6c FPU + cache-v2 guest trial **failed qualification**. All three original runs exited0 and passed source/refill/observer checks, but FPU and Mix display impossible negative or zero timings. Those automated checks reconcile capture/guard behavior; they do not validate the guest's timing results. Cause is unproven. Do not treat this as a harmless timer artifact, a speed gain or release evidence.

| Run | Completed 6c comparator | Cache-v2 final display | Verdict |
|---|---|---|---|
| FPU | Average0.729; Whet3850.048; Matrix0.928s; FFT0.418s | Average−96.774; Whet11460.135; Matrix0.007s; FFT−738.000s | Invalid guest timing |
| Mix | Average1.798 | Average330.532; Bubble−4548s, Queens−293s, Puzzle0.000s, Sieve−19808s | Invalid guest timing |
| Color8 | 9.878s | 9.856s, rating1.075, iteration1; other iterations0 | Isolated visible result only; does not qualify the combined trial |

Primary reviewed setup/final images; independent final viewing agrees. All three setup4277 PNGs and controls are byte-exact completed6c. Final PNGs differ. The Mix dialog obscures some rating/iteration cells; no hidden values are inferred. `guest_results.json` and separate candidate `manual_review.json` files record interpretation without rewriting original terminal metadata, whose PENDING_SCREENSHOT_REVIEW label remains historical.

FPU finished12:25:28.397UTC, Mix12:28:08.927UTC, Color12:01:32.217UTC on2026-09-28. Original children2612657/2615097/2615113 and supervisors2612651/2615087/2615095 were absent at the final check. All223 source hashes remain unchanged; shared executable SHA `727eb1298eaab8189b4b9f472008b3b47aa6b0b88afc343a9ab9ec3318b9a600` matches each recorded /proc executable. Source manifest `8c70ed5a…` contains the sole source/RTL delta against completed6c: cache7cba7f73→9e8c0582, FPU6c157b3b unchanged.

Recipe is the same full-release10CPU flags+SCSI_CACHE_OFF, prefetch fix,8+8KB, Verilator5.050/unroll256 and calibrated host RAM first4/publication2. Each run started with its own90,224,128-byte golden80d847 disk, ROM045c and original FPU33108d/Mixeafdd1b9/Colorfae07029 controls. The host RAM model is not production SDRAM/FPGA timing. Full-window counters are not per-subtest unique instruction counts or guest elapsed times. The earlier native2.139% throughput gain and successful fit remain scoped evidence; they do not override this failed guest trial.

This compact archive preserves exact setup/final PNGs, controls, profiles, original metadata/checker logs, separate reviews, completed6c comparison artifacts, source/build/launch identities, cache delta and frozen recipes. `source_copy_map.json` pins original paths and copied bytes. Full RTL, generated model, binary, ROM, completed mutable disks and huge runtime/build logs remain in scratch and are excluded. Historical source-manifest absolute paths identify original inputs; they are not archive-local replay paths. Do not execute copied launch recipes in this archive.

Verify saved evidence (no simulation):

```sh
python3 docs/perf/cache_refill_20260927/cache_v2_fullmachine_guest_results/check_archive.py
```

The checker validates integrity, terminal identities, setup equality and saved report checks while requiring FPU/Mix to remain classified invalid. It cannot prove a numerical/timer oracle or establish the cause of the anomalies.

The goal is **paused**. No retries, new simulations/tests, RTL edits, builds, hardware access or deployment occurred after completion. The user chooses subsequent work. A proposed next diagnosis, not authorization, is to review existing cross-line replay/coherence and guest timer read/write paths, then consider a narrowly instrumented matched baseline/candidate replay with an independent byte/timestamp oracle if approved. Preserve this failure before changing any checker or candidate. No commit was made by the archival agent.
