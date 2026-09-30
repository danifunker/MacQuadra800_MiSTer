# Combined 6c + WQ-available handoff: seed-33 timing failure

This archive records one seed-33 full FPGA compile of the same 6c FPU plus queue-availability bridge candidate documented for seed 31 in `../seed31_timing_failed/`. Seed 33 differs from its seed-32 base only in `MacQuadra800.qsf` (`SEED 32` → `SEED 33`). The 1,892-entry base and candidate manifests, both QSFs, and exact QSF diff preserve this provenance; source postrun verification passed all 1,892 entries.

Quartus analysis, synthesis, placement, fitting, and artifact generation succeeded, but the timing gate failed. CPU setup slack is +0.099 ns (TNS 0); HDMI is −0.198 ns (TNS −0.378); RAM rising-to-falling is −0.292 ns (TNS −0.579). Minimum hold slack is +0.201 ns. The RBF is recorded by hash and size only and is excluded from this archive; it must not be deployed. No hardware programming was performed.

The serialized cross-domain report has all 12 listed paths positive: system→RAM worst +0.035 ns (`wq_wp[1]` to the duplicated `wq_available_handoff`), and RAM→system worst +0.099 ns (`line_done_handoff` to `line_tag[15]~DUPLICATE`). The same-RAM-clock report has two negative rising-to-falling paths from `wq_rp[1]` to `wq_available_handoff` (−0.287 ns direct and −0.292 ns duplicated). The raw detailed report identifies a normal launch clock and an inverted latch clock; report payloads remain unchanged. The direct `wq_wp[1]` to availability path is +0.040 ns. Availability to `d_ram[31]` is +0.355 ns. These are report endpoints and slack values, not attribution to a broader architectural cause.

Run metadata records 38,622 ALMs, 24,631 registers, and 468 RAM blocks. The RBF is 4,447,936 bytes, SHA-256 `bcd6a403d51fad66b2b4dba6f76f251ee762c36f7c4aa9c06bb68fd7bdaacf11`; the SOF is 6,690,368 bytes, SHA-256 `9f36df6183209b252d2e5662bdb9d88d50c18982d0b5539b06b665f064fa1b4d`. Neither payload nor any Quartus database is included.

Validate from this directory with:

    PYTHONDONTWRITEBYTECODE=1 python3 check_archive.py .

The checker validates archive hashes, source-manifest identity and seed-only QSF delta, recorded source-postrun verification, report values, terminal exits, and omitted payload/database claims. It does not run Quartus or certify hardware behavior.
