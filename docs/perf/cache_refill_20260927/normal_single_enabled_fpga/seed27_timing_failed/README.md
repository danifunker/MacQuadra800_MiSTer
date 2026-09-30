# 6c seed27 FPGA timing failure

This archive records the full seed27 Quartus compile for the 6c enabled normal-single-move candidate. Analysis/synthesis, fit, assembler and TimeQuest completed and emitted an RBF, but `scripts/build_only.sh` returned 1 because its timing guard found CPU setup slack **−0.449 ns** (TNS −3.294 ns). The Quartus flow succeeded; the candidate does not meet timing and was not deployed. The RBF and SOF are intentionally omitted; their sizes and SHA-256 hashes are retained in `run/artifact_hashes.json`.

Cross-domain STA completed successfully: system-to-RAM +0.706 ns and RAM-to-system +0.112 ns. Fit used 38,590/41,910 ALMs, 24,632 registers, 468/553 RAM blocks, 3,389,411 memory bits, 36 DSPs and 4 PLLs. Worst CPU path starts at `wombat_cpu|pres_instr` and ends at `ap040_core|epf_data[2][10]`, with 29 logic levels and 30.083 ns data delay. The reported path traverses MMU/cache/store-buffer/integer-pipeline/BRF logic and contains no FPU cell; this does not attribute the timing failure to the FPU change.

The candidate source manifest records 1,892 inputs. Its comparison against the matched 55ff seed27 project reports one changed input (`rtl/ap68040/rtl/ap040_fpu.v`); the archive includes both FPU files and their diff, both source manifests, and the source comparison. The postrun source integrity check passed. Run and STA process identities, prelaunch collision checks, original terminal statuses, raw map/fit/STA summaries and reports, cross-domain reports and worst-path reports are included.

The archive excludes RBF/SOF payloads, Quartus databases, private environment files and the complete project tree. The reports and hashes describe an analysis artifact, not a deployable or timing-clean core.

Run `python3 check_archive.py .` from this directory. The portable checker verifies SHA256SUMS, source-manifest equality except for the single FPU input, candidate/base FPU hashes, source postrun status, Quartus exit and report status, timing values, cross-domain identities, and omitted artifact metadata. It does not run Quartus.
