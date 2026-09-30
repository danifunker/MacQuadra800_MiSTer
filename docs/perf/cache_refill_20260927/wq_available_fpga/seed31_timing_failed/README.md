# Combined 6c + WQ-available handoff: seed31 timing failure

This archive records one isolated seed31 full FPGA compile for the qualified 6c FPU plus the `wq_available_handoff` bridge change. Quartus completed its flow with zero flow errors, but the build wrapper returned 1 because CPU and HDMI setup timing failed. The artifact hashes are metadata only: the RBF and SOF are omitted and neither was deployed.

The fit used 38,741/41,910 ALMs, 24,624 registers, 468/553 RAM blocks, 3,389,411 memory bits, 36 DSPs and 4 PLLs. Setup slack was CPU −0.033 ns (TNS −0.033), HDMI −0.119 ns (TNS −0.119), and RAM falling-to-rising +0.528 ns; worst hold was +0.213 ns. Thus the queue output path itself meets the half-cycle check, while the overall candidate is not timing-clean.

The separate cross-domain reports passed all 12 paths: system→RAM worst +1.739 ns and RAM→system worst +0.899 ns. The intra-RAM-clock report also has all 12 paths positive; the queue output path from `wq_available_handoff` to `a_ram[26]/[24]` is +0.528 ns with 3.903 ns data delay and −0.460 ns skew. These checks do not override the failed CPU/HDMI setup gates. CPU TimeQuest reports 12 summary paths, with the first two negative at the same `rf_written[9]` → `epf_data[4][3]` prefetch-queue endpoint; TNS is −0.033 ns. RAM path details are preserved separately.

The source manifest covers 1,892 inputs. Comparing base and candidate manifests shows the sole RTL change is `rtl/sdram_beat32.sv`; the archived diff and candidate source make that change reviewable. The source postrun check passed all 1,892 entries. The modified bridge is the 6c FPU source plus one queue-availability bridge change, not a standalone bridge-only candidate.

The RBF is 4,456,988 bytes, SHA-256 `8f875a50d9d03b4cc40eeab0a7a857ab3038d625d4232c2d0dc1a33d70837a30`; the SOF is 6,690,368 bytes, SHA-256 `07343ae95a79cd909826b42825eae03bf493d0fefea387777252a9e59621aa27`. Both payloads and all Quartus databases are excluded. Process identities and tool logs are retained in `run/` and `logs/`.

Validate the archive from this directory with:

    python3 check_archive.py .

The checker validates archive hashes, source-manifest identity and sole-bridge delta, terminal build and source-postrun statuses, fit/STA/cross/RAM/CPU reports, and omitted artifact metadata. It does not run Quartus or certify hardware behavior.
