`timescale 1ns / 1ps
//============================================================================
//  wombat33 — Verilator simulation wrapper
//
//  `emu` here is the SIMULATION top — the sim-friendly port surface the
//  framework's sim_main.cpp drives.  Stage 1 of the machine bring-up: the
//  quadra800 machine (AP68040 + overlay + decode) with RAM/ROM/VRAM as
//  plain arrays behind the platform beat port.  The ROM image loads from
//  +rom=<hexfile> (default quadra800.rom.hex, built by the Makefile from
//  releases/quadra800.rom).  The template pattern core still paints the
//  VGA window and paces frames until DAFB lands in stage 2.
//============================================================================

module emu
(
	input         clk_sys,
	input         reset,

	// Template option bits (stand-ins for the MiSTer status word):
	//   sim_status[2]   TV mode (0 NTSC, 1 PAL)
	//   sim_status[4:3] Noise colour (0 white, 1 red, 2 green, 3 blue)
	input  [31:0] sim_status,

	// PS2 keyboard/mouse (unused by the template; wired for the machine)
	input  [10:0] ps2_key,
	input  [24:0] ps2_mouse,

	// VGA output
	output [7:0]  VGA_R,
	output [7:0]  VGA_G,
	output [7:0]  VGA_B,
	output        VGA_HS,
	output        VGA_VS,
	output        VGA_HB,
	output        VGA_VB,
	output        CE_PIXEL,

	// Audio output
	output [15:0] AUDIO_L,
	output [15:0] AUDIO_R,

	// ROM/disk loading interface (ioctl) — the MiSTer quadra800.rom path;
	// the sim loads the ROM by $readmemh instead
	input         ioctl_download,
	input         ioctl_wr,
	input  [24:0] ioctl_addr,
	input  [15:0] ioctl_dout,
	input  [7:0]  ioctl_index,
	output reg    ioctl_wait = 1'b0,

	// SCSI targets: MiSTer block-device surface for sim_blkdevice.cpp.
	// Bit 0 = SCSI ID 0 disk, bit 1 = ID 1 disk, bit 2 = ID 3 CD-ROM; one
	// lba / data bus is shared (one nexus at a time).
	output [31:0] sd_lba0,
	output  [2:0] sd_rd,
	output  [2:0] sd_wr,
	output  [5:0] sd_blk_cnt,   // hps_io sd_blk_cnt: sectors - 1 in this transaction (the block cache moves 8-sector groups)
	input   [2:0] sd_ack,
	input  [12:0] sd_buff_addr,  // 13 bits like hps_io: a group is 2048 words
	input  [15:0] sd_buff_dout,
	output [15:0] sd_buff_din0,
	input         sd_buff_wr,
	input   [2:0] img_mounted,
	input         img_readonly,
	input  [63:0] img_size,

	// CPU debug taps
	output [31:0] debug_pc,        // fetch pointer (debug_status pc)
	output [15:0] debug_opcode,    // current IR
	output        debug_fetch_valid,
	output [31:0] debug_data_addr, // last bus-error address
	output        debug_berr,      // machine bus-error pulse
	output        debug_overlay,
	output        debug_cpu_fault,
	output        debug_cpu_halted,
	output [15:0] debug_sr,
	output [31:0] debug_a7
);


//----------------------------------------------------------------------------
// The machine
//----------------------------------------------------------------------------
localparam RAM_ADDR_BITS = 27;                 // ceiling: 128 MB
// +ram=0|1|2 selects 32/64/128 MB, matching the OSD option on hardware
reg [1:0] ram_cfg = 2'd0;
initial if (!$value$plusargs("ram=%d", ram_cfg)) ram_cfg = 2'd0;
localparam RAM_WORDS  = 1 << (RAM_ADDR_BITS-2);
localparam ROM_WORDS  = 262144;                // 1 MB
// VRAM mirrors MacQuadra800.sv exactly: 308 KB backed, with the 204 KB fold
// that makes the unbacked 308K..512K window alias downward.  It used to be
// a flat 1 MB with no fold, so the fold had NEVER executed in sim and
// hardware-only video corruption was invisible here (RESUME-disk-gate.md
// carried this as a standing warning).
localparam VRAM_WORDS = 82016;                 // 320.4 KB: 512*160 + 96 tail
localparam [16:0] VRAM_FOLD = 17'd52224;       // 204 KB, in words
localparam [16:0] VRAM_TAIL = 17'd81920;       // 512 rows * 160 words

wire        mem_req, mem_write;
wire [31:2] mem_addr;
wire  [3:0] mem_be;
wire [31:0] mem_wdata;
wire  [1:0] mem_memsel;
wire        mem_wp_valid;
wire [31:2] mem_wp_addr;
wire  [3:0] mem_wp_be;
wire [31:0] mem_wp_data;
wire        mem_vram_wp;
reg [127:0] rom_line;                        // the ROM's retained line
reg  [19:4] rom_line_tag;
reg         rom_line_valid = 1'b0;
// Optional abstract SDRAM-line timing model. Off retains the original
// one-clock beat-port behavior. Delays count clk_sys rising edges and are
// intended for calibration against the integrated cache/SDRAM bench.
reg ram_line_model = 1'b0;
integer ram_first_latency = 1;
integer ram_line_publish_delay = 0;
initial begin
	if ($test$plusargs("ram_line_model")) ram_line_model = 1'b1;
	if ($value$plusargs("ram_first_latency=%d", ram_first_latency)) begin end
	if ($value$plusargs("ram_line_publish_delay=%d", ram_line_publish_delay)) begin end
	if (ram_first_latency < 1) ram_first_latency = 1;
	if (ram_line_publish_delay < 0) ram_line_publish_delay = 0;
	if (ram_line_model)
		$display("[RAM-LINE-MODEL] abstract first_latency=%0d publish_delay=%0d clk_sys edges",
		         ram_first_latency, ram_line_publish_delay);
end
reg [127:0] ram_line;
reg  [26:4] ram_line_tag;
reg         ram_line_valid = 1'b0;
reg         ram_line_pending = 1'b0;
reg         ram_line_publish_armed = 1'b0;
integer     ram_line_publish_count = 0;
reg         ram_model_busy = 1'b0;
reg         ram_model_ack_sent = 1'b0;
reg         ram_model_poisoned = 1'b0;
integer     ram_model_wait_count = 0;
reg  [31:2] ram_model_addr;
reg         ram_model_write;
reg   [3:0] ram_model_be;
reg  [31:0] ram_model_wdata;
wire [31:0] mem_rdata;
wire        mem_ack;
reg  [31:0] mem_rdata_r;
reg         mem_ack_r;

wire [21:2] vid_addr;
wire [13:0] vid_stride;
wire        vram_compact = (vid_stride == 14'd1024);
reg  [31:0] vid_rdata;

wire [255:0] m_debug_status;
wire [127:0] m_debug_status2;

// The sim runs the scanout on clk_sys, as MacLC's does: the dedicated pixel
// clock only matters to the HDMI scaler on real hardware, and using it here
// would change every frame count in the existing sim regressions for no
// benefit. Frame rate in sim is therefore 78.6 Hz, not the hardware's 59.94.
// SONIC=0: the Ethernet front-end talks to the ARM through a DDR3 window this top
// does not model; its own bench is tb_sonic_mbx.
quadra800 #(.RAM_ADDR_BITS(RAM_ADDR_BITS), .SONIC(0)) machine (
	.clk(clk_sys),
	.clk_vid(clk_sys),
	.nreset_vid(~reset),
	.ram_cfg(ram_cfg),
	.mon_12in(1'b0),                     // sim scans out the 13" 640x480 shape
	.nreset(~reset),
	.ce(1'b1),

	.mem_req(mem_req),
	.mem_write(mem_write),
	.mem_addr(mem_addr),
	.mem_be(mem_be),
	.mem_wdata(mem_wdata),
	.mem_memsel(mem_memsel),
	.mem_rdata(mem_rdata),
	.mem_ack(mem_ack),
	.mem_wp_valid(mem_wp_valid),
	.mem_wp_addr(mem_wp_addr),
	.mem_wp_be(mem_wp_be),
	.mem_wp_data(mem_wp_data),
	.mem_wq_room(1'b1),
	.mem_line_valid(ram_line_model && ram_line_valid),
	.mem_line_tag(ram_line_tag),
	.mem_line_data(ram_line),
	.mem_line_pending(ram_line_model && ram_line_pending),
	.mem_line_pending_tag(ram_line_tag),
	.mem_rom_line_valid(rom_line_valid),
	.mem_rom_line_tag(rom_line_tag),
	.mem_rom_line_data(rom_line),
	.mem_vram_wp(mem_vram_wp),

	.vid_addr(vid_addr),
	.vid_stride(vid_stride),
	.vid_rdata(vid_rdata),
	.VGA_R(VGA_R),
	.VGA_G(VGA_G),
	.VGA_B(VGA_B),
	.VGA_HS(VGA_HS),
	.VGA_VS(VGA_VS),
	.VGA_HB(VGA_HB),
	.VGA_VB(VGA_VB),
	.CE_PIXEL(CE_PIXEL),

	.AUDIO_L(AUDIO_L),
	.AUDIO_R(AUDIO_R),

	.ps2_key(ps2_key),
	.ps2_mouse(ps2_mouse),

	.img_mounted(img_mounted),
	.img_size(img_size),
	.io_lba(sd_lba0),
	.io_rd(sd_rd),
	.io_wr(sd_wr),
	.io_ack(sd_ack),
	.io_blk_cnt(sd_blk_cnt),
	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din(sd_buff_din0),
	.sd_buff_wr(sd_buff_wr),

	// SCC serial.  Both RX lines idle high (nothing attached); TX is left
	// open — the boot path only needs the chip to answer the ROM's InitSCC
	// and selftest, which is exactly what this sim is for.
	.scc_rxd_a(1'b1),
	.scc_txd_a(),
	.scc_cts_a(1'b1),
	.scc_rts_a(),
	.scc_rxd_b(1'b1),
	.scc_txd_b(),

	.dbg_berr(debug_berr),
	.dbg_berr_addr(debug_data_addr),
	.dbg_overlay(debug_overlay),
	.debug_status(m_debug_status),
	.debug_status2(m_debug_status2),
	.debug_fault(debug_cpu_fault),
	.debug_halted(debug_cpu_halted),
	.eth_ena(1'b0),
	.dbg_sw(3'd0),
	.eth_mem_addr(),
	.eth_mem_rd(),
	.eth_mem_we(),
	.eth_mem_wdata(),
	.eth_mem_accept(1'b0),
	.eth_mem_rvalid(1'b0),
	.eth_mem_rdata(64'd0)
);

assign debug_pc          = m_debug_status[31:0];
assign debug_opcode      = m_debug_status[63:48];
assign debug_sr          = m_debug_status[47:32];
assign debug_a7          = m_debug_status[95:64];
assign debug_fetch_valid = ~reset;

//----------------------------------------------------------------------------
// Platform memory: plain arrays behind the beat port (see quadra800.sv for
// the contract).  ROM writes are acked and discarded, as djMEMC does.
//----------------------------------------------------------------------------
reg [31:0] ram  [0:RAM_WORDS-1]  /*verilator public*/;
reg [31:0] rom  [0:ROM_WORDS-1]  /*verilator public*/;
reg [31:0] vram [0:VRAM_WORDS-1] /*verilator public*/;

reg [1023:0] rom_file;
initial begin
	if (!$value$plusargs("rom=%s", rom_file))
		rom_file = "quadra800.rom.hex";
	$readmemh(rom_file, rom);
	// +warmstart seeds the low-memory WarmStart cookie, NOT the RAM-test
	// gate. For a sim-only RAM-test skip, see docs/quadra800-ram-test.md.
	if ($test$plusargs("warmstart")) ram['h33F] = "WLSC";
end

wire [RAM_ADDR_BITS-3:0] ram_idx  = mem_addr[RAM_ADDR_BITS-1:2];
wire [17:0]              rom_idx  = mem_addr[19:2];

function [16:0] vram_map(input [16:0] w);      // window word -> storage word
	reg [8:0] row;
	reg [7:0] col;
	begin
		row = w[16:8];
		col = w[7:0];
		if (!vram_compact)
			vram_map = (w >= VRAM_WORDS) ? (w - VRAM_FOLD) : w;
		else if (col < 8'd160)
			vram_map = {row, 7'd0} + {2'd0, row, 5'd0} + {9'd0, col};
		else
			vram_map = VRAM_TAIL + {9'd0, (col - 8'd160)};
	end
endfunction

wire [16:0]              vram_idx = vram_map(mem_addr[18:2]);

// DAFB scanout port: registered read, 1-cycle latency
always @(posedge clk_sys) vid_rdata <= vram[vram_map(vid_addr[18:2])];

// posted RAM writes pushed past the beat port (quadra800 DIRECT_WRITES)
wire [RAM_ADDR_BITS-3:0] wp_idx = mem_wp_addr[RAM_ADDR_BITS-1:2];
always @(posedge clk_sys) if (mem_wp_valid) begin
	if (mem_wp_be[3]) ram[wp_idx][31:24] <= mem_wp_data[31:24];
	if (mem_wp_be[2]) ram[wp_idx][23:16] <= mem_wp_data[23:16];
	if (mem_wp_be[1]) ram[wp_idx][15:8]  <= mem_wp_data[15:8];
	if (mem_wp_be[0]) ram[wp_idx][7:0]   <= mem_wp_data[7:0];
end

// VRAM as MacQuadra800.sv serves it: the block RAM's registered read, a
// beat's capture clock (which also writes) and its combinational ack in the
// second clock; a direct write (mem_vram_wp) is a pulse with mem_req low.
wire        mem_is_vram = (mem_memsel != 2'd0) && (mem_memsel != 2'd1);
reg  [31:0] vram_qa;
reg         vram_ph = 1'b0;
wire        mem_port_available = !ram_line_model || !ram_model_busy;
wire        vram_ack = mem_req && mem_is_vram && vram_ph && mem_port_available;
wire        va_we = (mem_req && mem_is_vram && mem_write && !vram_ph && mem_port_available) || mem_vram_wp;
assign mem_ack   = mem_ack_r | vram_ack;
assign mem_rdata = mem_is_vram ? vram_qa : mem_rdata_r;

always @(posedge clk_sys) begin
	vram_qa <= vram[vram_idx];
	if (va_we) begin
		if (mem_be[3]) vram[vram_idx][31:24] <= mem_wdata[31:24];
		if (mem_be[2]) vram[vram_idx][23:16] <= mem_wdata[23:16];
		if (mem_be[1]) vram[vram_idx][15:8]  <= mem_wdata[15:8];
		if (mem_be[0]) vram[vram_idx][7:0]   <= mem_wdata[7:0];
	end
	if (mem_req && mem_is_vram && mem_port_available) vram_ph <= !vram_ph;
end

wire ram_model_accept = ram_line_model && !reset && !ram_model_busy &&
	mem_req && !mem_ack_r && !mem_is_vram && (mem_memsel == 2'd0) && !mem_wp_valid;
wire ram_model_complete = (ram_model_accept && (mem_write || ram_first_latency == 1)) ||
	(ram_line_model && ram_model_busy && !ram_model_ack_sent &&
	 (ram_model_wait_count <= 1) && !mem_wp_valid);
wire [31:2] ram_service_addr = ram_model_accept ? mem_addr : ram_model_addr;
wire ram_service_write = ram_model_accept ? mem_write : ram_model_write;
wire [3:0] ram_service_be = ram_model_accept ? mem_be : ram_model_be;
wire [31:0] ram_service_wdata = ram_model_accept ? mem_wdata : ram_model_wdata;
wire [RAM_ADDR_BITS-3:0] ram_service_idx = ram_service_addr[RAM_ADDR_BITS-1:2];
wire [RAM_ADDR_BITS-3:0] ram_line_base = {ram_service_addr[RAM_ADDR_BITS-1:4], 2'b00};

always @(posedge clk_sys) begin
	mem_ack_r <= 0;
	if (!ram_line_model && mem_req && !mem_ack_r && !mem_is_vram) begin
		mem_ack_r <= 1;
		case (mem_memsel)
		2'd0: begin
			mem_rdata_r <= ram[ram_idx];
			if (mem_write) begin
				if (mem_be[3]) ram[ram_idx][31:24] <= mem_wdata[31:24];
				if (mem_be[2]) ram[ram_idx][23:16] <= mem_wdata[23:16];
				if (mem_be[1]) ram[ram_idx][15:8]  <= mem_wdata[15:8];
				if (mem_be[0]) ram[ram_idx][7:0]   <= mem_wdata[7:0];
			end
		end
		default: begin
			mem_rdata_r <= rom[rom_idx];
			// the emu's ROM read fetches the whole line (MacQuadra800.sv)
			if (!mem_write) begin
				rom_line       <= {rom[{rom_idx[17:2], 2'd0}], rom[{rom_idx[17:2], 2'd1}],
				                   rom[{rom_idx[17:2], 2'd2}], rom[{rom_idx[17:2], 2'd3}]};
				rom_line_tag   <= mem_addr[19:4];
				rom_line_valid <= 1'b1;
			end
		end
		endcase
	end
	if (ram_line_model) begin
		if (reset) begin
			ram_line_valid <= 0;
			ram_line_pending <= 0;
			ram_line_publish_armed <= 0;
			ram_model_busy <= 0;
			ram_model_ack_sent <= 0;
			ram_model_poisoned <= 0;
		end
		else begin
			// A pending line is visible to the machine until all four words
			// are published together. The original read still gets its ack.
			if (ram_line_publish_armed) begin
				if (ram_line_publish_count <= 1) begin
					ram_line_valid <= 1;
					ram_line_pending <= 0;
					ram_line_publish_armed <= 0;
				end
				else ram_line_publish_count <= ram_line_publish_count - 1;
			end
			if (ram_model_accept) begin
				ram_model_busy <= 1;
				ram_model_ack_sent <= 0;
				ram_model_addr <= mem_addr;
				ram_model_write <= mem_write;
				ram_model_be <= mem_be;
				ram_model_wdata <= mem_wdata;
				ram_model_wait_count <= mem_write ? 0 : ram_first_latency - 1;
				ram_model_poisoned <= 0;
				if (!mem_write) begin
					ram_line_tag <= mem_addr[26:4];
					ram_line_valid <= 0;
					ram_line_pending <= 1;
					ram_line_publish_armed <= 0;
				end
			end
			else if (ram_model_busy && !ram_model_ack_sent && !ram_model_complete &&
			         ram_model_wait_count > 1)
				ram_model_wait_count <= ram_model_wait_count - 1;
			if (ram_model_complete) begin
				mem_ack_r <= 1;
				ram_model_ack_sent <= 1;
				if (ram_service_write) begin
					mem_rdata_r <= ram[ram_service_idx];
					if (ram_service_be[3]) ram[ram_service_idx][31:24] <= ram_service_wdata[31:24];
					if (ram_service_be[2]) ram[ram_service_idx][23:16] <= ram_service_wdata[23:16];
					if (ram_service_be[1]) ram[ram_service_idx][15:8]  <= ram_service_wdata[15:8];
					if (ram_service_be[0]) ram[ram_service_idx][7:0]   <= ram_service_wdata[7:0];
				end
				else begin
					mem_rdata_r <= ram[ram_service_idx];
					if (ram_model_accept || !ram_model_poisoned) begin
						ram_line <= {ram[ram_line_base], ram[ram_line_base + 1'b1],
						             ram[ram_line_base + 2'd2], ram[ram_line_base + 2'd3]};
						if (ram_line_publish_delay == 0) begin
							ram_line_valid <= 1;
							ram_line_pending <= 0;
						end
						else begin
							ram_line_publish_count <= ram_line_publish_delay;
							ram_line_publish_armed <= 1;
						end
					end
					else ram_line_pending <= 0;
				end
			end
			if (ram_model_busy && ram_model_ack_sent && !mem_req && !ram_line_pending)
				ram_model_busy <= 0;
			if (!ram_model_busy && mem_req && !mem_ack_r && !mem_is_vram &&
			    mem_memsel != 2'd0) begin
				// ROM retains its original one-edge response in modeled mode.
				mem_ack_r <= 1;
				mem_rdata_r <= rom[rom_idx];
				if (!mem_write) begin
					rom_line       <= {rom[{rom_idx[17:2], 2'd0}], rom[{rom_idx[17:2], 2'd1}],
					                   rom[{rom_idx[17:2], 2'd2}], rom[{rom_idx[17:2], 2'd3}]};
					rom_line_tag   <= mem_addr[19:4];
					rom_line_valid <= 1'b1;
				end
			end
			// A posted write can land while the retained line is still
			// pending. It poisons publication but never cancels the read ack.
			if (mem_wp_valid || (ram_model_complete && ram_service_write)) begin
				ram_line_valid <= 0;
				ram_line_pending <= 0;
				ram_line_publish_armed <= 0;
				if (mem_wp_valid && ram_model_busy && !ram_model_ack_sent)
					ram_model_poisoned <= 1;
			end
		end
	end
end

endmodule
