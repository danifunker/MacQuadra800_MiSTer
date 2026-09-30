# Simulation control and profiling checks

These deterministic host-only tests were recovered from the profiling branch.
They require no ROM, disk, FPGA, or running guest:

```sh
g++ -std=c++17 -Wall -Wextra -Werror \
  verilator/tests/cpu_dispatch_observer_test.cpp -o /tmp/q800-dispatch-test
/tmp/q800-dispatch-test
g++ -std=c++17 -Wall -Wextra -Werror \
  verilator/tests/sim_control_test.cpp -o /tmp/q800-control-test
/tmp/q800-control-test
g++ -std=c++11 -Wall -Wextra -Werror \
  verilator/tests/sim_refill_profile_test.cpp -o /tmp/q800-refill-test
/tmp/q800-refill-test
python3 verilator/tests/check_refill_report_test.py
```

The refill sampler distinguishes data/instruction and RAM/ROM/other, samples
each fill beat's issued/acknowledged state, and records complete fill-through-
tag-write durations. Partial brackets and aborted fills are excluded from
duration histograms. These are post-eval state samples, not bus transactions
or a claim that every fill clock stalls the CPU. Check an actual profile with:

```sh
python3 verilator/tests/check_refill_report.py path/to/profile.tsv
```

The checker requires observed complete refills and reconciles samples,
cache-state totals, state partitions and duration counts. It rejects missing
instrumentation and incomplete or inconsistent report structure. The original
full-machine RAM model omits the retained-line sideband used on hardware;
counter consistency alone does not establish hardware timing fidelity.

The full simulator integration test catches missing model wiring that parser
unit tests cannot see. After building `verilator/obj_dir/Vemu`, run:

```sh
python3 scripts/cpu/test_profile_integration.py
```

It boots a tiny synthetic ROM, injects real key down/up events, checks a
20,002-clock profile bracket, requests `quit` before the cycle limit, and
requires a flushed timing-observer summary. No guest disk is opened.

The dispatch test covers reset, stalls, consecutive opcode loads with identical
PC/state, disabled consumers, and profile start/stop boundaries. It tests
opcode-load observation; it does not claim every folded branch generates an
opcode event. The control test covers bounded parsing, clock-based pacing,
reset/screenshot pauses, FIFO reconnect, and append-only command files.

For the register-pipeline differential experiment, run
`python3 scripts/cpu/pipeline_prototype.py`. For immutable Speedometer wrapper
signatures and timer observations, see
`scripts/fixtures/speedometer_timing_observer/README.md`.
