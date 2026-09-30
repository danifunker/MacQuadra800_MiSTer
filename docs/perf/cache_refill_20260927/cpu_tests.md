# AP68040 cache A/B self-tests

Both runs use isolated copies of `rtl/ap68040` taken from checkout HEAD `6456c62b4f2ef076929ce19c2c3ceee1fa7278a3`. The candidate differs only in `rtl/ap68040/rtl/ap040_cache.v`, copied from `scratch/fpu_bulk_line_candidate_20260927/ap040_cache.v`.

The runner is `rtl/ap68040/tb/run_tests.sh`. Both variants passed all 31 named run legs, including the required negative controls, with these same settings:

```text
VASM=/home/alans/mister/MacQuadra800_fixtures/wombat-vasm/vasmm68k_mot
CPU_TEST_XSTORE=1
CPU_TEST_LEA=1
CPU_TEST_WORK=build_results
```

The VASM binary reports version 2.0f. Reproduce each run by changing to that copy's `rtl/ap68040/tb` and running:

```sh
VASM=/home/alans/mister/MacQuadra800_fixtures/wombat-vasm/vasmm68k_mot \
  CPU_TEST_XSTORE=1 CPU_TEST_LEA=1 CPU_TEST_WORK=build_results \
  bash run_tests.sh > run_tests.log 2>&1
```

Full logs and individual bench outputs are kept in each copy's `tb/` directory. `SHA256SUMS.txt` records both cache sources and run logs; `SOURCE_SHA256SUMS.txt` records all shared AP68040 source inputs. The two `run_tests.log` files are byte-identical (SHA256 `191d880594b567d4285620cad6d1b935e43a08153e33535301efe7ae638d60dd`).

This self-test script covers the AP68040's directed and programmed core benches with only the two requested compile options. It is not a full release-pipeline build or a full-machine simulation.
