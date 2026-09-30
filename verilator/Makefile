# wombat33 — Verilator GUI simulation (same setup as the other cores'
# verilator directories: ImGui + SDL2, FST tracing, `make && ./obj_dir/Vemu`).
V = verilator

TOP = --top-module emu
RTL = ../rtl
AP  = ../rtl/ap68040/rtl
V_INC = +incdir+$(RTL) +incdir+$(AP) -I$(AP)

# mirror of ../Main_MiSTer/support/mac (scripts/sync_main_mac.sh): the CD
# response builders and playhead the sims serve the CD slot's windows with
MAINMAC = sim/mac
V_DEFINE = +define+SIMULATION=1 \
	-CFLAGS "-I../sim/imgui -I../sim/ -I../sim/mac -g" \
	--timescale-override 1ps/1ps -Wno-TIMESCALEMOD \
	-I$(RTL)
V_DEFINE += -Wno-fatal -Wno-WIDTH -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-IMPLICIT \
	-Wno-PINMISSING -Wno-UNUSEDSIGNAL -Wno-UNOPTFLAT -Wno-CASEINCOMPLETE \
	-Wno-UNSIGNED -Wno-CMPCONST -Wno-LATCH -Wno-UNDRIVEN -Wno-MISINDENT \
	-Wno-COMBDLY -Wno-INITIALDLY -Wno-SYNCASYNCNET -Wno-BLKLOOPINIT \
	-Wno-MULTIDRIVEN -Wno-GENUNNAMED
V_DEFINE += --trace-fst --timing

UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S), Linux)
	LIBS += -lGL -ldl `sdl2-config --libs`
	CXXFLAGS += `sdl2-config --cflags` -Iimgui
	CFLAGS = $(CXXFLAGS)
endif
ifeq ($(UNAME_S), Darwin)
	# homebrew: SDL2, plus lz4/zstd/zlib for verilator >=5.05x FST writer
	LIBS += -framework OpenGL `sdl2-config --libs` -L/opt/homebrew/lib -llz4 -lzstd -lz
	CXXFLAGS += `sdl2-config --cflags` -I/opt/homebrew/include -Iimgui -DGL_SILENCE_DEPRECATION
	CFLAGS = $(CXXFLAGS)
endif

CFLAGS += -Iimgui
LDFLAGS = $(LIBS)
EXE = ./obj_dir/Vemu
# --unroll-count: ap040_mmu.v clears the 128 ATC valid flops with a for loop of
# delayed assignments (PFLUSHA, reset); above Verilator's default of 64 the loop
# is not unrolled and the assignment is silently dropped (BLKLOOPINIT, which the
# warning list above hides), so PFLUSHA was a no-op in the sim.  Found by Dani
# Sarfati in the NeXT-Color core (6d2e1a5, 2026-09-26).
V_OPT = --x-assign fast --x-initial fast --noassert --unroll-count 256

# Core RTL under simulation: the quadra800 machine (AP68040 submodule +
# wombat glue) plus the template pattern core, which still paces frames
# and paints the VGA window until DAFB lands.
V_SRC = \
	sim.v \
	$(RTL)/mycore.v \
	$(RTL)/cos.sv \
	sim_lfsr.v \
	$(RTL)/quadra800.sv \
	$(RTL)/wombat_cpu.sv \
	$(RTL)/wombat_store_buffer.sv \
	$(RTL)/wombat_bus32.sv \
	$(RTL)/iosb.sv \
	$(RTL)/via6522.sv \
	$(RTL)/dafb.sv \
	$(RTL)/rtc3430042.sv \
	$(RTL)/easc.sv \
	$(RTL)/ncr53c96.sv \
	$(RTL)/sonic_mbx.sv \
	$(RTL)/cd_audio.sv \
	$(RTL)/scsi_cache.sv \
	$(RTL)/adb.sv \
	$(RTL)/scc.v \
	$(RTL)/uart/txuart.v \
	$(RTL)/uart/rxuart.v \
	$(AP)/ap040_core.v \
	$(RTL)/ap68040/experimental/ap040_pipeline_integer.sv \
	$(AP)/ap040_bus_timeout.v \
	$(AP)/ap040_regfile.v \
	$(AP)/ap040_alu.v \
	$(AP)/ap040_muldiv.v \
	$(AP)/ap040_mmu.v \
	$(AP)/ap040_cache.v \
	$(AP)/ap040_fpu.v \
	$(RTL)/dpram.v

C_SRC = \
	sim_main.cpp \
	sim/sim_console.cpp sim/sim_video.cpp sim/sim_input.cpp sim/sim_clock.cpp \
	sim/sim_audio.cpp sim/sim_blkdevice.cpp \
	sim/cd_window.cpp $(MAINMAC)/mac_cdrom_resp.cpp $(MAINMAC)/mac_cdrom_play.cpp \
	sim/m68kdasm.c sim/m68k_dasm_stubs.cpp \
	sim/imgui/imgui_impl_sdl.cpp sim/imgui/imgui_impl_opengl2.cpp \
	sim/imgui/imgui_draw.cpp sim/imgui/imgui_widgets.cpp \
	sim/imgui/imgui_tables.cpp sim/imgui/imgui.cpp \
	sim/imgui/ImGuiFileDialog.cpp sim/imgui/implot.cpp sim/imgui/implot_items.cpp

VOUT = obj_dir/Vemu.cpp

all: $(EXE) quadra800.rom.hex

# ROM image as $readmemh words (big-endian: file order = byte order)
quadra800.rom.hex: ../releases/quadra800.rom
	xxd -p -c4 $< > $@

# sim-only fast-boot ROM: NOP the RAM-test warm gate at file offset
# $47344 (docs/quadra800-ram-test.md) so the ~1.5G-cycle pattern test
# is skipped; run with +rom=quadra800-fastboot.rom.hex
fastboot: quadra800-fastboot.rom.hex
quadra800-fastboot.rom.hex: ../releases/quadra800.rom ../docs/tools/make-fastboot-rom.sh
	sh ../docs/tools/make-fastboot-rom.sh $< .fastboot.tmp.rom
	xxd -p -c4 .fastboot.tmp.rom > $@
	rm .fastboot.tmp.rom

SIM_HEADERS = sim_control.h cpu_dispatch_observer.h sim_refill_profile.h sim_ram_snapshot.h ../scripts/fixtures/speedometer_timing_observer/adapter.inc ../scripts/fixtures/speedometer_timing_observer/speedometer_observer.h
$(VOUT): $(V_SRC) $(C_SRC) $(SIM_HEADERS) Makefile
	$V -cc $(V_OPT) -LDFLAGS "$(LDFLAGS)" -exe --trace --Mdir ./obj_dir \
		$(V_DEFINE) $(V_INC) $(TOP) -CFLAGS "$(CFLAGS)" $(V_SRC) $(C_SRC)
	@touch $(VOUT)

$(EXE): $(VOUT) $(SIM_HEADERS)
	@# verilator's Vemu.mk has no dep tracking for our C sources: evict
	@# any object older than its source before the inner make.
	@for f in $(C_SRC); do o=obj_dir/$$(basename $${f%.*}).o; \
		[ -e $$o ] && [ $$f -nt $$o ] && rm -f $$o obj_dir/Vemu || true; done
	@for f in $(SIM_HEADERS); do \
		[ -e obj_dir/sim_main.o ] && [ $$f -nt obj_dir/sim_main.o ] && rm -f obj_dir/sim_main.o || true; done
	$(MAKE) -C obj_dir -f Vemu.mk

# Directed benches (each `make <name>` builds and runs one; none needs a ROM or
# a disk): tb_easc tb_sonic_mbx tb_sdram tb_scsi_cache tb_scsi_cache_mbcd
# tb_ncr53c96 tb_wombat_bus32 tb_store_buffer tb_memory_path*
# tb_line_dma tb_scsi_irq_ack_race tb_sdma_ack_watchdog tb_iosb_scc

# Directed unit test for the EASC (rtl/easc.sv). Runs in seconds and does not
# need a ROM or a disk, which is the point: the machine only touches the sound
# chip's FIFO billions of cycles into a boot.
#   make tb_easc && ./obj_dir_tb/tb_easc
tb_easc:
	$V --binary --timing -Wno-fatal -Wno-WIDTH -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-UNSIGNED -Wno-CMPCONST -Wno-DECLFILENAME +define+SIMULATION=1 --top-module tb_easc --Mdir ./obj_dir_tb -o tb_easc tb_easc.sv $(RTL)/easc.sv
	./obj_dir_tb/tb_easc

# Built-in Ethernet front-end (rtl/sonic_mbx.sv): doorbell ring, on-demand
# register reads, local ISR/IMR, CR overlay, the op-list DMA engine, reset
# replay protection, bus watchdog, OSD-off inertness.
#   make tb_sonic_mbx
tb_sonic_mbx:
	$V --binary --timing -Wno-fatal -Wno-WIDTH -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-UNSIGNED -Wno-CMPCONST -Wno-DECLFILENAME +define+SIMULATION=1 --top-module tb_sonic_mbx --Mdir ./obj_dir_tb -o tb_sonic_mbx tb_sonic_mbx.sv $(RTL)/sonic_mbx.sv
	./obj_dir_tb/tb_sonic_mbx

# sim.v builds the machine with SONIC=0 (no DDR3 window model), so the front-end's
# wiring into quadra800.sv gets its own elaboration check:
#   make lint_sonic
lint_sonic:
	$V --lint-only $(V_DEFINE) $(V_INC) --top-module quadra800 $(filter-out sim.v,$(V_SRC))

# Directed unit test for the SDRAM beat bridge (rtl/sdram_beat32.sv) and the
# controller under it, driven against a behavioural chip model. The GUI sim
# backs RAM with a plain array, so this is the only place the burst capture,
# the posted write, the two clock crossings and the chip protocol are checked.
#   make tb_sdram
tb_sdram:
	$V --binary --timing -Wno-fatal -Wno-WIDTH -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-UNSIGNED -Wno-CMPCONST -Wno-DECLFILENAME +define+SIMULATION=1 --top-module tb_sdram --Mdir ./obj_dir_tb -o tb_sdram tb_sdram.sv $(RTL)/sdram_beat32.sv $(RTL)/sdram.sv altddio_out_stub.v
	./obj_dir_tb/tb_sdram

# Directed unit test for the 53C96 SCSI target (rtl/ncr53c96.sv), driven in
# BOTH driver dialects: the Quadra 800 ROM's DMA-form selects and a Unix
# ncr53c9x-class driver's FIFO-preloaded $41/$42/$43/$46.  A/UX's own c94
# driver is the second kind, so this is where widening the model for it is
# checked against the ROM path that already boots Mac OS.
#   make tb_ncr53c96
tb_scsi_cache:
	$V --binary --timing -Wno-fatal -Wno-WIDTH -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-UNSIGNED -Wno-CMPCONST -Wno-DECLFILENAME -Wno-CASEINCOMPLETE -Wno-BLKSEQ +define+SIMULATION=1 +define+VERILATOR=1 -Wno-MULTIDRIVEN -Wno-SYNCASYNCNET -Wno-COMBDLY +incdir+$(RTL) --top-module tb_scsi_cache --Mdir ./obj_dir_tbc -o tb_scsi_cache tb_scsi_cache.sv $(RTL)/scsi_cache.sv
	./obj_dir_tbc/tb_scsi_cache

# the CD slot on multi-block groups as well (MB_CD=1, the shipped setting)
tb_scsi_cache_mbcd:
	$V --binary --timing -Wno-fatal -Wno-WIDTH -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-UNSIGNED -Wno-CMPCONST -Wno-DECLFILENAME -Wno-CASEINCOMPLETE -Wno-BLKSEQ +define+SIMULATION=1 +define+VERILATOR=1 -Wno-MULTIDRIVEN -Wno-SYNCASYNCNET -Wno-COMBDLY +incdir+$(RTL) --top-module tb_scsi_cache +define+MB_CD_TB=1 --Mdir ./obj_dir_tbc_mbcd -o tb_scsi_cache_mbcd tb_scsi_cache.sv $(RTL)/scsi_cache.sv
	./obj_dir_tbc_mbcd/tb_scsi_cache_mbcd

# cd_audio table dump for the golden-bytes test of Main's response builders
# (scripts/cd_resp_golden.sh builds it and runs it once per TOC shape):
#   make tb_cd_audio_dump && ./obj_dir_tb/tb_cd_audio_dump +blob=x.blob.hex +out=x.rtl.bin
# CD_AUDIO_REF is the pre-2026-09-16 cd_audio.sv (the last one that built the
# tables); scripts/cd_resp_golden.sh extracts it from git into scratch/, next
# to the cd_vol_lut.vh it includes (the volume law left the RTL with phase 2).
CD_AUDIO_REF ?= ../scratch/cd_resp_golden/cd_audio_ref.sv
tb_cd_audio_dump:
	$V --binary --timing -Wno-fatal -Wno-WIDTH -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-UNSIGNED -Wno-CMPCONST -Wno-DECLFILENAME -Wno-CASEINCOMPLETE -Wno-BLKSEQ +define+SIMULATION=1 +define+VERILATOR=1 -Wno-MULTIDRIVEN -Wno-SYNCASYNCNET -Wno-COMBDLY -Wno-PINMISSING -Wno-UNUSEDSIGNAL +incdir+$(RTL) +incdir+$(dir $(CD_AUDIO_REF)) --top-module tb_cd_audio_dump --Mdir ./obj_dir_tb -o tb_cd_audio_dump tb_cd_audio_dump.sv $(CD_AUDIO_REF)

tb_ncr53c96:
	$V --binary --timing -Wno-fatal -Wno-WIDTH -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-UNSIGNED -Wno-CMPCONST -Wno-DECLFILENAME -Wno-CASEINCOMPLETE -Wno-BLKSEQ +define+SIMULATION=1 +define+VERILATOR=1 -Wno-MULTIDRIVEN -Wno-SYNCASYNCNET -Wno-COMBDLY +incdir+$(RTL) -CFLAGS "-I$(abspath sim) -I$(abspath sim/mac)" --top-module tb_ncr53c96 --Mdir ./obj_dir_tb -o tb_ncr53c96 tb_ncr53c96.sv $(RTL)/ncr53c96.sv $(RTL)/cd_audio.sv cd_win_dpi.cpp sim/cd_window.cpp $(MAINMAC)/mac_cdrom_resp.cpp $(MAINMAC)/mac_cdrom_play.cpp
	./obj_dir_tb/tb_ncr53c96

# Directed timing/data test for the transaction-to-beat adapter's registered
# one-beat completion and its two-beat misalignment path.
tb_wombat_bus32:
	$V --binary --timing -Wno-fatal -Wno-WIDTH -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-DECLFILENAME --top-module tb_wombat_bus32 --Mdir ./obj_dir_tb_bus32 -o tb_wombat_bus32 tb_wombat_bus32.sv $(RTL)/wombat_bus32.sv
	./obj_dir_tb_bus32/tb_wombat_bus32

# Directed ordering/backpressure test for the AP040's two-entry RAM store queue.
tb_store_buffer:
	$V --binary --timing -Wno-fatal -Wno-WIDTH -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-DECLFILENAME --top-module tb_wombat_store_buffer --Mdir ./obj_dir_tb_store_buffer -o tb_wombat_store_buffer tb_wombat_store_buffer.sv $(RTL)/wombat_store_buffer.sv
	./obj_dir_tb_store_buffer/tb_wombat_store_buffer

# Whole post-cache memory transport (transaction adapter + production RAM
# service handshake + SDRAM bridge/controller/chip model), including the
# held-request/one-pulse-per-beat contract used by ap040_cache's refill port.
tb_memory_path:
	$V --binary --timing -Wno-fatal -Wno-WIDTH -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-UNSIGNED -Wno-CMPCONST -Wno-DECLFILENAME +define+SIMULATION=1 --top-module tb_memory_path --Mdir ./obj_dir_tb_mempath -o tb_memory_path tb_memory_path.sv tb_sdram.sv $(RTL)/wombat_bus32.sv $(RTL)/sdram_beat32.sv $(RTL)/sdram.sv altddio_out_stub.v
	./obj_dir_tb_mempath/tb_memory_path

# Same production path with quadra800's experimental pre-adapter line bypass
# disabled.  Hits still come from sdram_beat32's retained BL8 line, but every
# CPU request keeps the established wombat_bus32/service-FSM ordering.
tb_memory_path_safe:
	$V --binary --timing -Wno-fatal -Wno-WIDTH -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-UNSIGNED -Wno-CMPCONST -Wno-DECLFILENAME +define+SIMULATION=1 --top-module tb_memory_path -GFAST_BYPASS=0 --Mdir ./obj_dir_tb_mempath_safe -o tb_memory_path_safe tb_memory_path.sv tb_sdram.sv $(RTL)/wombat_bus32.sv $(RTL)/sdram_beat32.sv $(RTL)/sdram.sv altddio_out_stub.v
	./obj_dir_tb_mempath_safe/tb_memory_path_safe

# Intermediate architecture: retain the generic transaction adapter but let
# its aligned platform beats consume the completed BL8 line directly.
tb_memory_path_ordered_line:
	$V --binary --timing -Wno-fatal -Wno-WIDTH -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-UNSIGNED -Wno-CMPCONST -Wno-DECLFILENAME +define+SIMULATION=1 --top-module tb_memory_path -GFAST_BYPASS=0 -GADAPTER_LINE_HIT=1 --Mdir ./obj_dir_tb_mempath_ordered_line -o tb_memory_path_ordered_line tb_memory_path.sv tb_sdram.sv $(RTL)/wombat_bus32.sv $(RTL)/sdram_beat32.sv $(RTL)/sdram.sv altddio_out_stub.v
	./obj_dir_tb_mempath_ordered_line/tb_memory_path_ordered_line

# Exact established quadra800 completion cadence: SDRAM completion is
# registered by the machine service FSM before wombat_bus32 sees it.
tb_memory_path_stock_machine:
	$V --binary --timing -Wno-fatal -Wno-WIDTH -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-UNSIGNED -Wno-CMPCONST -Wno-DECLFILENAME +define+SIMULATION=1 --top-module tb_memory_path -GFAST_BYPASS=0 -GADAPTER_LINE_HIT=0 -GDIRECT_MEM_ACK=0 --Mdir ./obj_dir_tb_mempath_stock_machine -o tb_memory_path_stock_machine tb_memory_path.sv tb_sdram.sv $(RTL)/wombat_bus32.sv $(RTL)/sdram_beat32.sv $(RTL)/sdram.sv altddio_out_stub.v
	./obj_dir_tb_mempath_stock_machine/tb_memory_path_stock_machine

# Serve retained BL8 words inside the machine service FSM while preserving its
# registered acknowledgement cadence for every transaction-adapter beat.
tb_memory_path_registered_line:
	$V --binary --timing -Wno-fatal -Wno-WIDTH -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-UNSIGNED -Wno-CMPCONST -Wno-DECLFILENAME +define+SIMULATION=1 --top-module tb_memory_path -GFAST_BYPASS=0 -GADAPTER_LINE_HIT=1 -GDIRECT_MEM_ACK=0 -GREGISTERED_LINE_HIT=1 --Mdir ./obj_dir_tb_mempath_registered_line -o tb_memory_path_registered_line tb_memory_path.sv tb_sdram.sv $(RTL)/wombat_bus32.sv $(RTL)/sdram_beat32.sv $(RTL)/sdram.sv altddio_out_stub.v
	./obj_dir_tb_mempath_registered_line/tb_memory_path_registered_line

# Bypass wombat_bus32 only for later aligned longwords already retained from
# the BL8 fetch.  The first miss and all other transaction shapes keep the
# established adapter/service-FSM path, and line-hit completion stays registered.
tb_memory_path_registered_bus_line:
	$V --binary --timing -Wno-fatal -Wno-WIDTH -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-UNSIGNED -Wno-CMPCONST -Wno-DECLFILENAME +define+SIMULATION=1 --top-module tb_memory_path -GFAST_BYPASS=1 -GDIRECT_FIRST_MISS=0 -GADAPTER_LINE_HIT=1 -GDIRECT_MEM_ACK=0 -GREGISTERED_LINE_HIT=1 --Mdir ./obj_dir_tb_mempath_registered_bus_line -o tb_memory_path_registered_bus_line tb_memory_path.sv tb_sdram.sv $(RTL)/wombat_bus32.sv $(RTL)/sdram_beat32.sv $(RTL)/sdram.sv altddio_out_stub.v
	./obj_dir_tb_mempath_registered_bus_line/tb_memory_path_registered_bus_line

# Aligned RAM first misses enter the memory service directly, but completion is
# captured into dedicated registers before reaching the CPU. Retained tail
# words use the hardware-validated registered pre-adapter line path.
# The retained-line read shortcut against a second bus master (the SONIC's DMA
# arm): a line ack registered in the clock the FSM leaves S_IDLE must not let
# bus_req_adapter rise under it.  -GFIX=0 shows the 2026-09-18 hardware failure.
#   make tb_line_dma
tb_line_dma:
	$V --binary --timing -Wno-fatal -Wno-WIDTH -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-UNSIGNED -Wno-CMPCONST -Wno-DECLFILENAME +define+SIMULATION=1 --top-module tb_line_dma --Mdir ./obj_dir_tb_line_dma -o tb_line_dma tb_line_dma.sv tb_sdram.sv $(RTL)/wombat_bus32.sv $(RTL)/sdram_beat32.sv $(RTL)/sdram.sv altddio_out_stub.v
	./obj_dir_tb_line_dma/tb_line_dma

tb_memory_path_registered_first_miss:
	$V --binary --timing -Wno-fatal -Wno-WIDTH -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-UNSIGNED -Wno-CMPCONST -Wno-DECLFILENAME +define+SIMULATION=1 --top-module tb_memory_path -GFAST_BYPASS=1 -GDIRECT_FIRST_MISS=1 -GREGISTERED_FIRST_MISS=1 -GADAPTER_LINE_HIT=1 -GDIRECT_MEM_ACK=0 -GREGISTERED_LINE_HIT=1 --Mdir ./obj_dir_tb_mempath_registered_first_miss -o tb_memory_path_registered_first_miss tb_memory_path.sv tb_sdram.sv $(RTL)/wombat_bus32.sv $(RTL)/sdram_beat32.sv $(RTL)/sdram.sv altddio_out_stub.v
	./obj_dir_tb_mempath_registered_first_miss/tb_memory_path_registered_first_miss

# iosb.sv benches: the whole IOSB (pseudo-VIA2, 53C96 + CD engine, SCC, EASC,
# ADB, RTC, pseudo-DMA) driven from the beat bus, with the HPS block interface
# modelled in the bench.  They share one dependency list.
IOSB_TB_W = -Wno-fatal -Wno-WIDTH -Wno-UNUSED -Wno-PINMISSING -Wno-DECLFILENAME -Wno-MISINDENT \
	-Wno-CASEINCOMPLETE -Wno-SYNCASYNCNET -Wno-BLKANDNBLK -Wno-PINCONNECTEMPTY -Wno-MULTIDRIVEN \
	-Wno-COMBDLY -Wno-BLKSEQ -Wno-UNSIGNED -Wno-CMPCONST -Wno-IMPLICIT -Wno-LATCH -Wno-UNOPTFLAT
IOSB_TB_DEPS = $(RTL)/iosb.sv $(RTL)/scc.v $(RTL)/uart/txuart.v $(RTL)/uart/rxuart.v \
	$(RTL)/via6522.sv $(RTL)/easc.sv $(RTL)/ncr53c96.sv $(RTL)/cd_audio.sv $(RTL)/adb.sv \
	$(RTL)/rtc3430042.sv $(RTL)/dpram.v altsyncram_stub.v
IOSB_TB = $V --binary -j 8 $(IOSB_TB_W) --timescale 1ns/1ps -I$(RTL) +define+SIMULATION=1

# The lost 53C96 interrupt (docs/scsi-write-hang-20260928.md): a VIA2 IFR
# bit 3 acknowledge swept across the chip's next INT edge must not drop it.
# FAILS on the iosb.sv of f9f6da6~1.
#   make tb_scsi_irq_ack_race
tb_scsi_irq_ack_race:
	$(IOSB_TB) --top-module tb_scsi_irq_ack_race --Mdir ./obj_dir_tb_irq_race -o tb_scsi_irq_ack_race tb_scsi_irq_ack_race.v $(IOSB_TB_DEPS)
	./obj_dir_tb_irq_race/tb_scsi_irq_ack_race

# The pseudo-DMA watchdog must stay frozen while the platform holds io_ack
# (the HPS SPI transfer), not only while io_rd/io_wr are up
# (docs/scsi-write-hang-20260928.md).  FAILS on the iosb.sv of f9f6da6~1.
#   make tb_sdma_ack_watchdog
tb_sdma_ack_watchdog:
	$(IOSB_TB) --top-module tb_sdma_ack_watchdog --Mdir ./obj_dir_tb_sdma_wd -o tb_sdma_ack_watchdog tb_sdma_ack_watchdog.v $(IOSB_TB_DEPS)
	./obj_dir_tb_sdma_wd/tb_sdma_ack_watchdog

# The SCC's beat-bus adapter inside iosb.sv: decode, channel select, the CS
# window across back-to-back accesses, and 31250 baud at 33 MHz.
#   make tb_iosb_scc
tb_iosb_scc:
	$(IOSB_TB) --top-module tb_iosb_scc --Mdir ./obj_dir_tb_iosb_scc -o tb_iosb_scc tb_iosb_scc.v $(IOSB_TB_DEPS)
	./obj_dir_tb_iosb_scc/tb_iosb_scc

# The modem port as a serial printer sees it (docs/serial-printer-20260929.md):
# 57600 and 9600 8N1 TX clk/bit, RX at nominal / HPS / +-3 % and a sweep,
# RR0 CTS/DCD and the rts pin, and the BRG catch-alls per driver setting.
#   make tb_scc_printer
tb_scc_printer:
	$(IOSB_TB) --top-module tb_scc_printer --Mdir ./obj_dir_tb_scc_printer -o tb_scc_printer tb_scc_printer.v $(IOSB_TB_DEPS)
	./obj_dir_tb_scc_printer/tb_scc_printer > obj_dir_tb_scc_printer/run.log 2>&1; rc=$$?; grep "^TB" obj_dir_tb_scc_printer/run.log; exit $$rc

clean:
	rm -rf obj_dir obj_dir_tb obj_dir_tb_bus32 obj_dir_tb_store_buffer obj_dir_tb_mempath obj_dir_tb_mempath_safe obj_dir_tb_mempath_ordered_line obj_dir_tb_mempath_stock_machine obj_dir_tb_mempath_registered_line obj_dir_tb_mempath_registered_bus_line obj_dir_tb_mempath_registered_first_miss obj_dir_tb_line_dma obj_dir_tbc obj_dir_tbc_mbcd obj_dir_tb_irq_race obj_dir_tb_sdma_wd obj_dir_tb_iosb_scc obj_dir_tb_scc_printer
