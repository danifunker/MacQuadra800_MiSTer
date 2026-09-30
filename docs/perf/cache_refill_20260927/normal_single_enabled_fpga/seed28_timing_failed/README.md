# 6c seed28 FPGA timing failure

This archive records the seed28 compile and follow-up TimeQuest reports for the 6c candidate. Quartus analysis/synthesis, fitter, assembler and timing analysis completed with no Quartus errors; `quartus_full_flow_exit_status` is 0. The repository `build_only.sh` timing guard returned 1 because CPU and HDMI setup timing failed. No RBF or SOF payload is included or deployed.

The CPU clock setup slack is **−1.225 ns** (TNS −49.875 ns); HDMI setup is **−0.710 ns** (TNS −3.828 ns); RAM clock setup is +0.422 ns. Fit used 38,650/41,910 ALMs, 24,667 registers, 468/553 RAM blocks, 3,389,411 memory bits, 36 DSPs and 4 PLLs. The RBF is 4,448,892 bytes (SHA-256 `366a7633d6737a47cca1a60f4a0aa6494792050fbcae52c7e062dd3f36d4e333`); SOF is 6,690,368 bytes (SHA-256 `6c201428341a86f6bb8d84960b2aaff34fdd84eab55382490081583b9707be91`). These hashes identify omitted build artifacts, not deployable outputs.

The cross-domain TimeQuest command exited 0 and produced both reports, but **the crossing result is not clean**: system-to-RAM has +0.731 ns slack with no violated paths; RAM-to-system has −0.203 ns slack and one violated path. Do not label cross-domain STA as passed.

The worst CPU setup path starts at `ap040_regfile|rf_written[6]` and ends at `ap040_mmu|hq_ptag[19]`: 24 logic levels, 30.871 ns data delay, −0.507 ns clock skew, approximately 74% interconnect. This path has no FPU cell. It differs from seed27's worst endpoint, and does not establish that the FPU change caused the miss.

The durable seed28 Quartus unit reached its actual terminal state at 07:43:20 UTC. The observing exec session 99758 ended with status 143 while the durable flow continued; that observer status is not the Quartus flow status. The original compile identity separately records Quartus flow exit 0 and wrapper/systemd exit 1. Cross-domain STA and worst-path report identities and terminal reports are included.

The frozen seed28 manifest covers 1,892 inputs. Compared with seed27, only `MacQuadra800.qsf` changed, setting SEED 27 to SEED 28; the FPU, SDC, cache source and remaining 1,891 inputs are identical. Source postrun verification passed. The archive includes both manifests, the QSF diff, source comparison and candidate FPU source. It excludes RBF/SOF payloads, Quartus databases, private environment files and the generated project tree.

Run `python3 check_archive.py .` from this directory. The portable checker verifies the archive inventory, source manifests and sole-QSF delta, terminal statuses, timing/crossing results, worst-path identity and omitted-artifact metadata. It does not run Quartus.
