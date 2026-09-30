# Speedometer timer observation on the current CPU

Recovered from `profile-speedometer402-20260909`, then adapted for the
vendored CPU's MLAB register file. The observer recognizes the **Queens
and Sieve** timer wrappers only. It is a passive, bounded simulator tool;
it neither changes timer behavior nor diagnoses every invalid Mix result.

Build the normal full-machine simulator, then add:

```
--speedometer-observe timer.log --speedometer-limit 512
```

Run only against a disposable copy of a guest disk. Output contains raw
Microseconds pairs, simulated rising-edge timestamps, elapsed-time reads,
and accumulation checks when those wrapper signatures are observed. The
final summary distinguishes a capture with no recognized wrappers from
an actual timing observation. A record cap or missing identity is not a
clean timer result. The simulator does not model the physical SDRAM clock
crossing, so a clean simulation does not clear that hardware hypothesis.

The adapter samples successful logical memory requests before evaluation,
and dispatches after evaluation. `sim.v` ties machine CE high. Register
snapshots resolve the RF written mask, MLAB pending write, and newer CPU
pending write in that order, plus the active stack-pointer bank.

Reproduce the observer tests with the original Speedometer resource fork:

```sh
python3 scripts/fixtures/speedometer_timing_observer/run_tests.py \
  --resource '/home/alans/mister/MacQuadra800_fixtures/Speedometer 4.02.rsrc'
```

The test checks the immutable resource hash, both wrapper signatures, all
40 expected instruction words, and synthetic traces with carry/backwards
times, MMU changes, partial reads, pending writes and bounded capture.
