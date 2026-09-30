# Native Whetstone baseline source-format admissions

One fresh baseline-only selector1 run passed all original runtime/ABI/code/FPSP/state-sum/error gates at the unchanged8,726,508 clocks. No RTL/kernel/fixture/entry change; simulation-only monitor samples first in the existing main preedge block, before in_loop markers change. Source and exact monitor insertion are retained in monitor.inc/tb.diff. Original baseline image recipe/shared provenance is at ../native_fpu_whetstone; source_manifest.sha256 and run/identity.json record consumed frozen scratch/external inputs.

318,069 normal-command branch edges =318,069 first branches per continuous enabled request episode; held reexecution, restore-priority, pending-frame, conflicting-sideport and unknown-context samples all0. These are branch/request-episode counts, not architectural retirement counts. Raw branch predicates mirror F_IDLE req dispatch and its priority exclusions. Independent sideports remain raw commands but reject opportunity guards. ia_we is allowed. Context is current source-instruction PC only at validated GO160/IR-F2 first admission, via ia_wdata=pc_i; it is not source operand address or later busy-state PC attribution.

| Memory-source MOVE format | First request episodes | Resource PC | ROM PC |
| --- | ---: | ---: | ---: |
| Long integer |1860|0|1860|
| Single |930|0|930|
| Extended |29061|22141|6920|
| Word integer |4200|4200|0|
| Double |5764|6|5758|

Class010/opmode00 only. General shape/context output retains class and raw field_fmt: class000 field is an FP register index, class011 field is output format, so neither is pooled as memory reads. Dynamic resource extended22141/double6/word4200 agrees with earlier static native code counts; ROM operations were absent from that static-only inventory.

Exact existing normal-single candidate guard counted930 unique/raw opportunities. Prospective extended MOVE guard counted29058 unique/raw opportunities of29061 total X MOVE commands: class010/op00/fmt2/J-bit1/exponent1..32766/FPCRprecision00/enables0/no conflicting ports. Single guard usesfmt1/exponent1..254 with the same policy. The three rejected extended requests have no separately captured rejection reasons; do not guess which condition failed. Guard counts are opportunities only: no bypass, saved-cycle measurement or end-to-end speed estimate was implemented. No independent numerical oracle or output buffer capture.

This archive is text-only: exact monitor/TB/diff, runner/supervisor/checkers, source identities, result JSON and small terminal ABI/code/stack/global captures. RAM/ROM images, copied RTL tree, binary and generated models remain in scratch/native_whet_sourceformat_20260928. Original source manifest uses consumed scratch paths; archive_manifest.sha256 is archive-relative. PLAN.md preserves its prospective prelaunch wording. Existing40M/300s phase bounds and650s outer processgroup supervisor were retained; terminal QUALIFIED_RUNTIME and no retry. Actual runner/native children were absent afterward.

From repo root:

    python3 docs/perf/cache_refill_20260927/native_whet_source_formats/check_archive.py

Fresh reproduction uses the original pinned selector1 image/entry plus archived monitor/TB, all10 release flags/cache geometry/ROMlat6/unroll256 and baseline FPU2d53/cache7cba. Supervisor requires fresh output and validates frozen source hashes. Do not rerun inside completed input directories. Context/opportunity checks supplement, rather than replace, the original runtime gates.
