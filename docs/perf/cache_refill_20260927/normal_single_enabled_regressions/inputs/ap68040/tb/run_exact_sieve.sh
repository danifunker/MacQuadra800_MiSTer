#!/bin/sh
# One exact-kernel fixture; does not run the general regression suite.
# Usage: sh run_exact_sieve.sh RESOURCE RTL_DIR OUTPUT_DIR [simulation plusargs]
set -eu
cd "$(dirname "$0")"
resource=$1
rtl=$(realpath "$2")
output=$(realpath -m "$3")
shift 3
mkdir -p build "$output"
python3 prepare_exact_sieve.py "$resource" build/exact_sieve.bin
"${VASM:-vasmm68k_mot}" -Fbin -m68040 -no-opt \
    -o build/bench_exact_sieve.bin asm/bench_exact_sieve.s
python3 bin2hex.py build/bench_exact_sieve.bin build/bench_exact_sieve.hex
# Assert placement as well as source identity; assembler changes cannot
# silently change the measured bytes or the exit instruction.
python3 - <<'PY'
from pathlib import Path
image = Path("build/bench_exact_sieve.bin").read_bytes()
kernel = Path("build/exact_sieve.bin").read_bytes()
assert image[0x2000:0x2050] == kernel
assert image[0x2050:0x2054] == bytes.fromhex("4e714e75")
PY
sha256sum "$rtl/ap040_core.v" build/bench_exact_sieve.bin build/exact_sieve.bin
"${VERILATOR:-verilator}" --binary --timing -Wno-fatal -j "${JOBS:-4}" \
    --top-module tb_ap040_program --Mdir "$output/obj" \
    -DAP040_EXACT_SIEVE_MONITOR -DAP040_TB_CACHE=1 -I"$rtl" \
    tb_ap040_program.v exact_sieve_monitor.sv \
    "$rtl/ap040_tg68k_compat.v" "$rtl/ap040_core.v" \
    "$rtl/ap040_bus16_adapter.v" "$rtl/ap040_bus_timeout.v" \
    "$rtl/ap040_regfile.v" "$rtl/ap040_alu.v" "$rtl/ap040_muldiv.v" \
    "$rtl/ap040_mmu.v" "$rtl/ap040_cache.v" "$rtl/ap040_fpu.v" \
    "$rtl/ap040_walker_cdc.v" "$rtl/primitives/dpram.v" \
    >"$output/compile.log" 2>&1
"$output/obj/Vtb_ap040_program" +prog=build/bench_exact_sieve.hex \
    +maxcycles=400000000 +sieveprof "$@" >"$output/run.log" 2>&1
grep '^EXACT_SIEVE\|^phase\|ALL TESTS PASSED\|SIEVE_ORACLE\|FAIL' "$output/run.log"
# The inherited bench uses $finish on timeout; do not mistake exit 0 for PASS.
grep -q 'ALL TESTS PASSED' "$output/run.log"
if grep -q 'FAIL' "$output/run.log"; then exit 1; fi
# Catch an early guest success even if the inherited driver reaches $finish
# before the observer's final delayed sample can run.
awk '
    /^EXACT_SIEVE / { kernels++ }
    /^phase [0-2] passed/ { phases++ }
    END { if (phases == 0 || kernels != 2*phases) exit 1 }
' "$output/run.log"
