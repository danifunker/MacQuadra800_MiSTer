#!/bin/sh
# Regenerate fpu_latency.s, assemble it, build tb_fpu_latency.sv with
# Verilator 5 (production AP040_* macros) and run it at bus latency 3 and 1.
# Outputs (hex, listing, logs, results_lat*.txt) go to
# scratch/fpu_latency_20260928/; the Verilator obj dir is deleted afterwards.
# Runs as a transient user unit so a closed shell cannot orphan it.
# Extra arguments go to fpu_latency.py, e.g.  --latency 3  or  --keep-obj
set -eu
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
exec systemd-run --user --unit="fpu-latency-$(date +%s)" --collect --pipe --wait \
	--working-directory="$ROOT" \
	python3 docs/perf/fpu_latency_20260928/fpu_latency.py run "$@"
