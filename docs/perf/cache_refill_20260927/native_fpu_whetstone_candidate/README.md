# Native FPU Whetstone candidate runtime replay

Matched native selector1: baseline8,726,508 → candidate8,724,166 loop clocks,2,342 fewer (0.02684%). Runtime return600D/ABI/code/native-FPSP/histogram/chip-bus-IRQ gates PASS both. This is negligible timing change in this fixture, alongside separate native Matrix/FFT improvements around6–7%; it does not establish aggregate10% or OS/FPGA gain. No numerical output oracle or payload capture exists for this Whetstone comparison.

Exact completed baseline fixture image/entry/TB/runner/checker/counters and ROMlat6/releaseflags/unroll256 were reused. Copied tree differs only in FPU2d53→73bc. preflight.json and run/identity.json record actual variant and shared inputs. The unchanged checker still prints “baseline” and measurement.scope still contains “baseline”; these are inherited harness labels, not the consumed candidate identity. comparison.json explicitly identifies candidate73bc. qualification_identity.json carries only the required initial-code hash and scope; original baseline binary/source IDs are recorded separately in preflight rather than copied as candidate labels.

An external supervisor verifies source hashes sequentially, requires fresh outputs, records actual runner/nativePID and exehash, and kills/waits its processgroup on failure/650s outer timeout. Original runner/TB retain300s per phase/40M-cycle bounds. No failure or retry occurred; supervisor.json is QUALIFIED_RUNTIME and original runner/native processes were absent after completion. To supply the unchanged checker's recorded-result consistency input, supervisor executes its existing read-only checks/result construction, writes candidate measurement.json, then runs the complete unchanged checker. No checker gate or RTL/harness instrumentation changed.

This archive contains small text provenance, exact runner/checker/supervisor, measurement/comparison and terminal ABI/code/stack/global captures. Shared TB/entry/image generator is archived at ../native_fpu_whetstone; full RAM/ROM images, copied RTL, generated model and binary remain in scratch/native_fpu_whetstone_candidate_20260928. source_manifest.sha256 records original immutable scratch/external paths, while archive_manifest.sha256 is archive-relative. Prospective PLAN.md preserves its prelaunch wording.

From repository root:

    python3 docs/perf/cache_refill_20260927/native_fpu_whetstone_candidate/check_archive.py

Any replay must use a new scratch directory, exact shared baseline image/TB/entry and pinned candidate RTL from preflight, fresh output and the external supervisor. Never overwrite completed scratch inputs/results. The comparison is runtime-only and does not substitute for the independent arithmetic regressions, native Matrix numerical oracle, FFT baseline equality gate or full OS results.
