#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
cd "$here/baseline_sim/verilator"
./obj_dir/Vemu --headless --no-cpu-trace --max-cycles 100000 --speedometer-observe smoke_observer.log --fpu-timed-profile smoke_timed.tsv +rom=quadra800-fastboot.rom.hex > smoke_run.log 2>&1
SPEEDOMETER_FIXTURE_CHECK=1 ./obj_dir/Vemu --headless --max-cycles 100000 --speedometer-observe fixture_observer.log --fpu-timed-profile fixture_timed.tsv +rom=../../fixture.rom.hex > fixture_run.log 2>&1
cp cpu_trace.log fixture_cpu_trace.log
SPEEDOMETER_FIXTURE_CHECK=1 SPEEDOMETER_FIXTURE_D0=2 ./obj_dir/Vemu --headless --max-cycles 100000 --speedometer-observe fixture_earlybranch_observer.log --fpu-timed-profile fixture_earlybranch_timed.tsv +rom=../../fixture_earlybranch.rom.hex > fixture_earlybranch_run.log 2>&1
cp cpu_trace.log fixture_earlybranch_cpu_trace.log
python3 "$here/check_fixture.py"
