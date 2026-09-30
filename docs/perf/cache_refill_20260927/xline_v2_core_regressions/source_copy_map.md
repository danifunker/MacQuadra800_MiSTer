# Source and evidence copy map

The source of truth was `scratch/cache_v2_core_regressions_20260928/` plus `scratch/cache_v2_t_cache_extra_20260928/` and `scratch/cache_xline_sideband_fullmachine_supervision_20260928/`.

- `source/programs/t_{fpu,fpu_frames,fpu_resume,mmu,exceptions}.s`: exact five assembler inputs from `cache_v2_core_regressions_20260928/inputs/tb/asm/`.
- `source/programs/t_cache.s`: exact supplemental program from `cache_v2_t_cache_extra_20260928/`.
- `source/harness/tb_ap040_program.v`, `bin2hex.py`, and the two `run*.py` files: exact harness, conversion helper, and paired-run recipes from their respective scratch packages.
- `candidate_cache.diff`, `command_plan.json`, `source_comparison.json`, `profile.json`, `prepared_identity.json`, `input_manifest.sha256`: recipe and identity records from the five-test package. The manifest has 101 original inputs; their full RTL inputs are not duplicated here.
- `program_result.json`, `program_preflight_identity.json`, `program_execution_metadata.json`, and `program_runs/{baseline,candidate}/*.log`: terminal result, tool/preflight identities, candid process metadata, and exact ten simulation logs. Assembly/HEX/compile logs are omitted; their command details and generated image hashes remain in the result/command plan.
- `t_cache/metadata.json` and six adjacent logs: supplemental two-variant `t_cache` evidence. The generated `.bin` and `.hex` images are deliberately excluded.
- `build_smoke/` files are copied from the separate generated-host build/smoke package. `baseline6c_source_manifest.sha256` identifies the 223-file build source snapshot; `preparation_manifest.sha256` is the project preparation identity; `build.meta.json` and `completed_build_identity.json` hold build provenance; `smoke/meta.json`, `smoke/refill.tsv`, `smoke/run.log`, check logs, and control files capture the disk-free smoke. `build.py`, `smoke.py`, and their diffs preserve the runner changes. The large full RTL snapshot, ROM payload, executable, object files, and ccache are omitted.

The file manifests record source identities rather than asserting that omitted RTL bytes are embedded in this archive. Paths inside original command/metadata records may refer to the original scratch workspace; `source_copy_map.md` maps the compact archived material.
