# Combined 6c + WQ-available handoff: seed-32 fitter failure

This archive records one authorized seed-32 full FPGA compile of the same 6c FPU plus `wq_available_handoff` candidate evaluated at seed 31. The seed-32 source input set contains 1,892 manifest entries and differs from the seed-31 candidate only in `MacQuadra800.qsf`, where the fitter seed changed from 31 to 32. The archived QSF copies, unified diff, source manifests, preparation identity, and source-postrun check preserve this provenance.

Quartus analysis and synthesis completed successfully. Placement also reports success. The fitter then failed in routing: the build log reports estimated average interconnect use of 46%, a peak of 75% in region X45_Y11 through X55_Y22, a warning that the router was resolving exceedingly high congestion, and termination of the routing phase due to congestion. Critical warning 188026 says the design did not route successfully; Error 170143 records the unsuccessful final fitting attempt, followed by Error 11802. The fit report lists 38,652 ALMs needed of 41,910 (92%), 24,226 registers, and 468 RAM blocks. Those utilization figures do not identify a specific resource shortage; the captured failure context points to routing congestion after placement.

No fresh RBF or SOF was generated, and no final STA summary exists. Cross-domain and same-RAM-clock STA were not run because the fitter did not produce a successfully routed design. This archive contains no bitstream, generated database, or Quartus work directory, and it does not claim a timing result or hardware behavior.

Validate the compact archive from this directory with:

    PYTHONDONTWRITEBYTECODE=1 python3 check_archive.py .

The checker validates archive hashes, both 1,892-entry source-manifest inventories and their sole seed-setting delta, the recorded source-postrun status, failure-log context, and absent artifact/STA claims. The complete RTL source tree is omitted; root independently verified the actual 1,892 scratch inputs. The checker does not run Quartus.
