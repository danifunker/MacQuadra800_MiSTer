# 6c enabled-move simulator build and disk-free smoke

This archive records a successful Verilator build and a short disk-free integration smoke for the 6c normal-single-move candidate. The full candidate FPU source and enabled observer source are included, with the observer, simulator-main, and Makefile diffs needed to review the instrumented build. Frozen project/source manifests and terminal metadata retain original run identities. The archive omits the compiled simulator, ROM contents, guest disks, ccache, generated C++ and private environment files. The ROM is identified by SHA-256 only.

The build used Verilator 5.050, the ten AP040 release flags plus `SCSI_CACHE_OFF`, unroll 256, the 8+8 cache profile, and RAM model 4/2. `make fastboot` and `make -j2 V=.../verilator` both exited 0. The frozen candidate FPU SHA-256 is `6c157b3bc045e74a90416f4764f35cf65024e77577019a100b8aa9b5bdd9ce9b`; the built simulator SHA-256 is `2f16b5f63372788b8dc1b63ae8d657cdaad67c3e5232524e9be1edb0d14e6ebf` (binary intentionally omitted). The observer and sim-main hashes are recorded in `build/completed_build_identity.json`.

The disk-free smoke child exited 0 after 100,002 profile edges. Both the refill and v2 enabled-observer checkers passed. The observer report contains **zero raw FP command-branch events** and zero eligible normal-single events. This is a short generated-model/ROM/control/profile integration smoke with an empty observer window; it is not guest workload coverage, a speed measurement, or evidence of FPU performance.

`build/source_manifest.sha256` is copied byte-for-byte from the frozen project and retains its original absolute-path identity records. The included changed source files and diffs are independently hash-checked by the archive checker. The recorded ROM hash is `045c02746b5f15f83132d33c5414f806e7b049f3bfe53a7bd0ecacb8e072d673`; ROM data is not included.

Run `python3 check_archive.py .` from this directory. The portable standard-library checker verifies the archive manifest, copied source identities, build and smoke terminal metadata, checker logs, and empty observer result. It does not run a build or simulation.
