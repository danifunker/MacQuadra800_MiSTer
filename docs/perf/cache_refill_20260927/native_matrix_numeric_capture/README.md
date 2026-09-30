# Native FPMm Matrix numeric capture

This archive records two isolated native Speedometer `tEsT12000` selector 3 (`FPMm`) runs through the SDRAM platform fixture. The candidate changes only the consumed `ap040_fpu.v` RTL relative to the baseline; the capture testbench, image, oracle, and other consumed RTL are the same. These are native Matrix-kernel results, not a SANE Whetstone workload, the FPU test-suite callbacks, a full live Mac run, or a hardware test.

At the first validated free call (`PC=0x600260`), the testbench required an empty CPU store buffer and bridge write FIFO, no pending write push, and no active write. It failed immediately if those natural-drain guards were false. It did not wait, freeze a clock, or require the SDRAM controller to be idle. It captured all 123 heap allocations, 164 bytes each. The archive checker compares the 40×40 active cells of A, B, and C byte-for-byte against the independent oracle; allocated row zero and column zero are skipped.

| Capture | Loop clocks | Returned clocks | Active Matrix cells | Result |
| --- | ---: | ---: | ---: | --- |
| Baseline | 31,634,431 | 31,635,207 | 4,800/4,800 exact | PASS |
| Candidate FPU | 29,640,994 | 29,641,770 | 4,800/4,800 exact | PASS |

Both runs produced the same C row-major binary32 hash: `95b611a1ef946a97c8940e5d5723666d3cf7fe3ab5180df6f2e3565ce752a45f`. The exact oracle and its provenance are in `reference/fppm_oracle.py` and `reference/FPMM_ORACLE_README.md`. Each capture directory contains its raw 123 payload files, run log, generated flattened chip-model source, compile log, run identity, and validated measurement. The run identity records consumed RTL/model/image/ROM hashes and release flags; its separate oracle/checker hash fields identify the numerical check inputs. The prepared and original artifact manifests preserve the scratch-run hashes; `archive_artifact_manifest.sha256` checks the self-contained archive files.

The final post-run checker sources are named `reference/baseline_postcheck.py` and `reference/candidate_postcheck.py`. The candidate checker’s expected clock count and report wording were corrected after the simulation output was produced; baseline and candidate postchecks were rerun offline, and the measurement JSON was generated or recomputed from the already captured logs and payloads. No simulation was repeated for those label/checker changes. The output-side qualification label in the run logs is preserved as captured.

Run `python3 check_archive.py` from this directory to validate manifests, both run identities, the 123 payload files per capture, all 9,600 numeric cell comparisons, equal oracle hashes, and the known run gates. Run `python3 reference/test_payload_checker.py` for the synthetic valid-payload and corrupted-cell host checks. No FPGA fit, hardware measurement, or performance claim is included here.
