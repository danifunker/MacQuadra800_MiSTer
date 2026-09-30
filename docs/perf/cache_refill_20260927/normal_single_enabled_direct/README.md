# Enabled-exception normal FMOVE.S directed qualification

This archive contains the completed isolated FPU real-port qualification of candidate `6c157b3bc045e74a90416f4764f35cf65024e77577019a100b8aa9b5bdd9ce9b` against production `2d53db3ae4a04310add04eeb7919f0219197a98827ed92e410e6d4a4a90f5465`. The exact source pair and unified delta are under `source/`; frozen test inputs and the build/run scripts are under `test_inputs/`. Logs and invocation outputs are under `logs/`. No compiled simulator binaries are included.

The qualification ran 97,795 fast-path eligible normal FMOVE.S cases. The first 65,024 total cases include both signs, every normal exponent, eight selected fraction patterns, all four precision settings, and all four rounding modes at FPCR exception enable `0x20`. It added 32,768 cases from eight boundary words across all 256 enable masks, precisions, and rounding modes, plus three explicit precision cases. Each case checked the independent binary32-to-extended result, FPSR/FPIAR/shadow behavior, a prior exceptional or unusual destination value, both physical register banks, and a dependent register-source move.

Both variants reported 97,795 normal cases and 97,834 total checks. Production classified 0 fast / 97,830 slow; candidate classified 97,795 fast / 35 slow. All 36 excluded and restore signature lines matched byte-for-byte. Both compile/run sequences passed with exit status 0. Detailed output is retained in `logs/`; run/source identities are in the JSON records at the archive root.

The tests also cover excluded zero, subnormal, infinity, NaN, unsupported formats and opmodes, enabled exceptional source encodings, old destination signaling and quiet NaNs, side-port interactions, CE stalls, request handling, reset during a command, E1 restored-pend enable behavior, and restored resume. The currently unreachable `fstate_resig` state was not fabricated.

This is unit-level FPU evidence. It does not establish CPU-level or full-machine performance, FPGA timing, or hardware behavior. The archived `test_inputs/run.py` records the original runner, whose paths refer to the scratch workspace; use the included checker for portable archive verification, without rerunning simulations:

```sh
python3 docs/perf/cache_refill_20260927/normal_single_enabled_direct/check_archive.py
```

`SHA256SUMS` covers every archived file except itself. The archive contains no `.vvp`, `.rbf`, or `.sof` files.
