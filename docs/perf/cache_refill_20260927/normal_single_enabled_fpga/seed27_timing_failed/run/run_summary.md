# 6c seed-27 Quartus run result

The full compile completed in 19m36s. Analysis/synthesis, fitter, assembler, and TimeQuest ran successfully, but the build script returned 1 because timing was not met. The RBF and SOF exist as analysis artifacts only; neither was deployed. The worst setup result is CPU `emu|pll...general[0]` at -0.449 ns / TNS -3.294 ns; HDMI is +0.267 ns and the RAM clock is +0.443 ns. Worst hold is +0.240 ns, all hold TNS zero.

Fit: 38,590/41,910 ALMs; 24,632 registers; 468/553 RAM blocks; 3,389,411 block-memory bits; 36 DSPs; 4 PLLs. RBF: 4,441,088 bytes, SHA256 `5c0c19e72e7af9332e96dd58c73dd6075949b74b202d36967ad46eb17f9c106c`. SOF SHA256 `d0a3951971a08fc2dcb7b5f5fc935c929c0d4714bbd9a9e4fb3c76c334b56db6`.

Cross-domain STA passed with sys-to-RAM +0.706 ns and RAM-to-sys +0.112 ns, six paths each and no violations. The worst CPU path starts at `wombat_cpu|pres_instr` and ends at `ap040_core|epf_data[2][10]`; 29 logic levels, -0.519 ns clock skew, 30.083 ns data delay. It follows MMU/cache/store-buffer/integer-pipeline/BRF logic and contains no FPU cell. This is not evidence that the new FPU logic caused the CPU path; placement sensitivity remains possible.

Complete compile provenance is in `full_compile_identity.json`, child executable records in `full_quartus_processes.json`, cross STA in `cross_domain_identity.json`, detailed CPU endpoint data in `cpu_worst_paths_identity.json`, and source-tree integrity in `source_postrun_check.json`.
