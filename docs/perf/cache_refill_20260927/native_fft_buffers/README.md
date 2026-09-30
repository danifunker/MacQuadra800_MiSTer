# Native FFT matched first-free buffer regression

Both qualified replays passed natural-drain capture at the first free600e00, without clock/CE changes or deferred capture. All5152 bytes matched exactly: input/output complex allocation2056, scratch2056, twiddles1040. Timing remained14,301,941 baseline /13,358,788 candidate clocks. Runtime ABI/code/heap/error/state-sum and20 FFft/1 FExptab/20 N-pointer/20 FP4-scalar gates passed both. Baseline FPU2d53 → candidate73bc is the only RTL change.

This is **baseline/candidate output regression**, not an independent numerical FFT oracle or full OS/hardware qualification. Complete blocks include unused complex slot0; active complex slices separately hash bytes8..2055. Twiddle comparison includes its entire allocation without guessing an active subset. pair_result.json records pointers/sizes/full and active hashes.

The shared common/TB and monitor were copied identically into two fresh scratch projects. monitor.diff/tb.diff show the only capture instrumentation added to the completed profiling fixture. Hook occurs after validated primary A01F/pinned-opcode/pointer/order checks, before free bookkeeping. Guard checks store-buffer count/drain/request/push, direct and machine RAM writes, publication write poison, FIFO raw-pointer equality/used/empty/push, controller active/busy writes and bridge write request. Failure would terminate qualification without waiting or retry. Queue snapshots and marker are preserved in each run.log.

This text-only archive contains exact shared monitor/TB, variant runners/checkers, identities/manifests, terminal logs and small payload/ABI/code/stack/heap captures. Full RAM/ROM images, RTL trees, generated models and binaries remain in scratch/native_fft_buffers_20260928 and are excluded. source_manifest.sha256 records immutable original scratch/external input paths; archive_manifest.sha256 checks this archive. Baseline native source/image generation recipe is archived at ../native_fpu_fft; candidate profile identity/delta is at ../native_fpu_fft_candidate. Generic WHETSTONE and inherited “baseline” checker/measurement scope labels remain unchanged harness text; actual consumed FPU hashes and paired labels distinguish variants.

From repo root:

    python3 docs/perf/cache_refill_20260927/native_fft_buffers/check_archive.py

For reproducibility, use fresh scratch directories, shared common/TB+monitor/checkers, regenerated pinned selector2 image per ../native_fpu_fft, exact baseline/candidate RTL hashes, all10 release flags/cache geometry/ROMlat6/unroll256. Each runner requires fresh run/ and uses40M clock/300s phase caps, two compile jobs, child processgroup timeout/kill/wait. Do not replay into completed inputs. Pair checker requires unchanged loop clocks and byte equality for all3 blocks, and clearly reports the absence of an independent oracle.
