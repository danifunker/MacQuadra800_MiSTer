#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
MCQ_VERILATOR5=${MCQ_VERILATOR5:-/home/alans/verilator5/bin/verilator}
MCQ_JOBS=${MCQ_JOBS:-8}
CCACHE_DIR=${CCACHE_DIR:-/tmp/mcq800_ccache}
export CCACHE_DIR
mkdir -p "$CCACHE_DIR"
"$MCQ_VERILATOR5" --version | rg '^Verilator 5\.' >/dev/null

if [[ ${1:-} == --calibrate ]]; then
    test_top=tb_sim_ram_calibrate
else
    test_top=tb_sim_ram_line
fi

sources=(
    "tests/$test_top.sv" sim.v
    ../rtl/mycore.v ../rtl/cos.sv sim_lfsr.v
    ../rtl/quadra800.sv ../rtl/wombat_cpu.sv ../rtl/wombat_store_buffer.sv
    ../rtl/wombat_bus32.sv ../rtl/iosb.sv ../rtl/via6522.sv ../rtl/dafb.sv
    ../rtl/rtc3430042.sv ../rtl/easc.sv ../rtl/ncr53c96.sv
    ../rtl/sonic_mbx.sv ../rtl/cd_audio.sv ../rtl/scsi_cache.sv
    ../rtl/adb.sv ../rtl/scc.v ../rtl/uart/txuart.v ../rtl/uart/rxuart.v
    ../rtl/ap68040/rtl/ap040_core.v
    ../rtl/ap68040/experimental/ap040_pipeline_integer.sv
    ../rtl/ap68040/rtl/ap040_bus_timeout.v
    ../rtl/ap68040/rtl/ap040_regfile.v ../rtl/ap68040/rtl/ap040_alu.v
    ../rtl/ap68040/rtl/ap040_muldiv.v ../rtl/ap68040/rtl/ap040_mmu.v
    ../rtl/ap68040/rtl/ap040_cache.v ../rtl/ap68040/rtl/ap040_fpu.v
    ../rtl/dpram.v
)
"$MCQ_VERILATOR5" --binary --timing --top-module "$test_top" \
    -j "$MCQ_JOBS" --unroll-count 256 \
    -Wno-fatal -Wno-WIDTH -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC \
    -Wno-PINMISSING -Wno-UNUSEDSIGNAL -Wno-UNOPTFLAT \
    -Wno-BLKLOOPINIT -Wno-MULTIDRIVEN -Wno-GENUNNAMED \
    +define+SIMULATION=1 +incdir+../rtl +incdir+../rtl/ap68040/rtl \
    -I../rtl/ap68040/rtl --Mdir "./obj_dir_$test_top" "${sources[@]}"

if [[ $test_top == tb_sim_ram_calibrate ]]; then
    "./obj_dir_$test_top/V$test_top" \
        +ram_line_model +ram_first_latency=4 +ram_line_publish_delay=2
else
    "./obj_dir_$test_top/V$test_top"
    "./obj_dir_$test_top/V$test_top" \
        +ram_line_model +ram_first_latency=3 +ram_line_publish_delay=2
fi
