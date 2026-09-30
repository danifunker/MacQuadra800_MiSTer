//============================================================================
//  quadra800 — the Wombat machine: AP68040 on djMEMC's flat 32-bit bus.
//
//  Stage 1 (ROM executes): CPU + boot overlay + address decode.  RAM, ROM
//  and VRAM live on the platform beat port (BRAM/SDRAM on MiSTer, plain
//  arrays in the Verilator sim); everything unmapped takes a bus error,
//  which is what the ROM's probe code expects of empty space.
//
//  Physical map (MAME djmemc/iosb/macquadra800 as reference):
//    $00000000-$3FFFFFFF  RAM (installed size; beyond it: berr).  While the
//                         reset overlay holds, the low 4 MB reads ROM.
//    $40000000-$4FFFFFFF  ROM, 1 MB image mirrored; writes ignored; the
//                         first read here clears the overlay.
//    $50000000-$5FFFFFFF  IOSB I/O (stage 2+; only the ID reg lives here
//                         today: $5FFF0000-$5FFFFFFF = $A55A2BAD).
//    $F9000000-$F91FFFFF  DAFB VRAM (1 MB mirrored across the window).
//    $F9800000-$F98003FF  DAFB registers (stage 2).
//
//  Platform beat port: aligned longwords, be[3] = byte at addr+0 =
//  wdata[31:24]; req level-held per beat, accept on req && !your-own-ack,
//  answer with a single-cycle ack (rdata valid with it).  Writes with
//  memsel=ROM must be discarded but still acked.
//============================================================================

module quadra800
#(
	parameter RAM_ADDR_BITS = 27,             // address space ceiling: 128 MB
	parameter CDROM         = 1,              // 0 = no CD-ROM target (rtl/ncr53c96.sv)
	parameter SONIC         = 1,              // 0 = no built-in Ethernet (rtl/sonic_mbx.sv)
	// 1 = every SONIC DMA write beat pulses the CPU's D-cache snoop (the 68040's bus-snoop
	// invalidate).  It has to be on: with it off (Ethernet builds 5 and 6) the guest bombs
	// within ten received frames although every frame and descriptor in RAM is byte-exact --
	// Apple's driver marks a recycled receive descriptor with $FF in the top byte of its
	// length longword, and a stale cached copy of that longword is a 4 GB length.
	parameter SONIC_SNOOP   = 1,
	parameter DIRECT_WRITES = 1               // store-buffer RAM writes push straight into the bridge FIFO
)
(
	input         clk,
	input         nreset,
	input         ce,

	// 25.175 MHz dot clock for the DAFB scanout (rtl/pll_video.v)
	input         clk_vid,
	input         nreset_vid,

	// installed RAM, as a real Quadra 800 configuration.  The ROM sizes
	// memory by probing at startup, so this must be settled before reset
	// releases — the top folds a change into the reset.
	//   0 = 32 MB   1 = 64 MB   2 = 128 MB
	input   [1:0] ram_cfg,
	input         mon_12in,      // DAFB monitor: 0 = 13" 640x480, 1 = 12" 512x384

	// platform memory beat port
	output reg        mem_req,
	output reg        mem_write,
	output reg [31:2] mem_addr,
	output reg  [3:0] mem_be,
	output reg [31:0] mem_wdata,
	output reg  [1:0] mem_memsel,             // 0 RAM, 1 ROM, 2 VRAM
	input      [31:0] mem_rdata,
	input             mem_ack,
	// posted RAM writes straight into the bridge's write FIFO (2026-09-23)
	output reg        mem_wp_valid,
	output reg [31:2] mem_wp_addr,
	output reg  [3:0] mem_wp_be,
	output reg [31:0] mem_wp_data,
	input             mem_wq_room,
	// a VRAM write straight into the VRAM block RAM at mem_addr/be/wdata,
	// with mem_req low (2026-09-26)
	output reg        mem_vram_wp,
	input             mem_line_valid,
	input      [26:4] mem_line_tag,
	input     [127:0] mem_line_data,
	input             mem_line_pending,
	input      [26:4] mem_line_pending_tag,
	// the ROM's retained line: the last ROM line read from DDR3 (2026-09-26)
	input             mem_rom_line_valid,
	input      [19:4] mem_rom_line_tag,
	input     [127:0] mem_rom_line_data,

	// video: DAFB scanout (VRAM fetch port + VGA)
	output     [21:2] vid_addr,
	input      [31:0] vid_rdata,
	output     [13:0] vid_stride,
	output      [7:0] VGA_R,
	output      [7:0] VGA_G,
	output      [7:0] VGA_B,
	output            VGA_HS,
	output            VGA_VS,
	output            VGA_HB,
	output            VGA_VB,
	output            CE_PIXEL,

	output signed [15:0] AUDIO_L,
	output signed [15:0] AUDIO_R,

	// SCSI disk block device
	// three SCSI targets (ID 0/1 disks, ID 3 CD-ROM): see rtl/ncr53c96.sv
	output signed [15:0] cd_snd_l,          // CD audio PCM, from the SCSI CD-ROM
	output signed [15:0] cd_snd_r,
	input   [2:0] img_mounted,
	input  [63:0] img_size,
	output [31:0] io_lba,
	output  [5:0] io_blk_cnt,               // hps_io sd_blk_cnt: blocks - 1 per transaction
	output  [2:0] io_rd,
	output  [2:0] io_wr,
	input   [2:0] io_ack,
	input  [12:0] sd_buff_addr,
	input  [15:0] sd_buff_dout,
	output [15:0] sd_buff_din,
	input         sd_buff_wr,

	// ADB input devices
	input  [10:0] ps2_key,
	input  [24:0] ps2_mouse,

	// Unix seconds from the HPS, for the RTC
	input  [32:0] timestamp,

	// SCC serial: channel A = modem port (MidiLink / PPP / MIDI),
	// channel B = printer port (LocalTalk on a real machine; TX only here)
	input         scc_rxd_a,
	output        scc_txd_a,
	input         scc_cts_a,
	output        scc_rts_a,
	input         scc_rxd_b,
	output        scc_txd_b,

	// debug
	output            dbg_berr,
	output     [31:0] dbg_berr_addr,
	output            dbg_overlay,
	output [255:0] debug_status,
	output [127:0] debug_status2,
	output        debug_fault,
	output        debug_halted,

	// built-in Ethernet: the OSD switch (latched under reset by the top) and the
	// DDR3 window port of rtl/sonic_mbx.sv (rd/we level-held until the 1-cycle
	// accept; read data with rvalid)
	input         eth_ena,
	// BRING-UP switches (OSD, latched under reset by the top; all 0 = the shipped machine):
	// [0] no store buffer / posted stores, [1] no retained-SDRAM-line fast paths,
	// [2] no D-cache snoop for SONIC DMA writes
	input   [2:0] dbg_sw,
	output [11:0] eth_mem_addr,
	output        eth_mem_rd,
	output        eth_mem_we,
	output [63:0] eth_mem_wdata,
	input         eth_mem_accept,
	input         eth_mem_rvalid,
	input  [63:0] eth_mem_rdata
);

localparam [1:0] MSEL_RAM  = 2'd0,
                 MSEL_ROM  = 2'd1,
                 MSEL_VRAM = 2'd2;

// bring-up switch [1]: the retained SDRAM line as if it were never valid
wire        line_valid_sw   = mem_line_valid   && !dbg_sw[1];
wire        line_pending_sw = mem_line_pending && !dbg_sw[1];

// built-in Ethernet (sonic_mbx, below the service FSM): its interrupt, whether the
// chip is there this session, and the D-cache snoop strobe of its RAM writes
wire        sonic_irq;
wire        sonic_present;
reg         snoop_stb;

//----------------------------------------------------------------------------
// CPU bundle and the transaction-to-beat adapter
//----------------------------------------------------------------------------
wire        bus_req, bus_write, bus_instr;
wire  [1:0] bus_size;
wire [31:0] bus_addr, bus_wdata;
wire  [2:0] bus_fc;
wire        bus_ack;
wire [31:0] bus_rdata;
wire        bus_ack_adapter;
wire [31:0] bus_rdata_adapter;
wire        bus_adapter_active;
wire        bus_req_adapter;
reg         bus_line_ack;
reg  [31:0] bus_line_rdata;
reg         bus_miss_ack;
reg  [31:0] bus_miss_rdata;

assign bus_ack   = bus_line_ack || bus_miss_ack || bus_ack_adapter;
assign bus_rdata = bus_line_ack ? bus_line_rdata :
	               bus_miss_ack ? bus_miss_rdata : bus_rdata_adapter;

wire        walker_req, walker_we;
wire [31:0] walker_addr, walker_wdat;
reg         walker_ack;
reg  [31:0] walker_data;
reg         walker_berr;

reg         cpu_berr;
wire  [2:0] ipl_n;

// SCSI block port.  The engine (ncr53c96, inside iosb) talks to the block
// cache; the cache talks to hps_io through this module's io_* / sd_buff_*
// ports.  Reads hit in block RAM and are prefetched behind, writes are
// acked from RAM and flushed in the background, so the engine never has a
// write flush outstanding across a target switch (rtl/scsi_cache.sv).
wire [31:0] e_io_lba;
wire  [5:0] e_io_blk_cnt;               // the CD-DA frame fetch's block count (pass-through only)
wire  [2:0] e_io_rd, e_io_wr, e_io_ack;
wire [12:0] e_sd_buff_addr;
wire [15:0] e_sd_buff_dout, e_sd_buff_din;
wire        e_sd_buff_wr;
wire [15:0] cache_hits, cache_misses;

// CACHE_CD_OFF=1 in the qsf passes the CD-ROM slot straight through (its tags
// and mux leg go away, ~250 ALMs) -- the area lever for CPU builds that keep
// the CD target; the disks' write-behind is untouched.
`ifdef CACHE_CD_OFF
localparam CACHE_CD_SLOT = 0;
`else
localparam CACHE_CD_SLOT = 1;
`endif
// CACHE_SMALL=1 in the qsf halves the disk windows (32/32/16 sectors): the tag
// bitmaps and their muxes shrink with them -- the area lever for CPU builds.
// CACHE_TINY=1 halves them again (16/16/16, 24 M10K instead of 40): the RAM
// lever for CPU builds whose cache mirrors need the blocks (2026-09-22).
`ifdef CACHE_TINY
localparam CACHE_SECT0 = 16, CACHE_SECT1 = 16;
`elsif CACHE_SMALL
localparam CACHE_SECT0 = 32, CACHE_SECT1 = 32;
`else
localparam CACHE_SECT0 = 64, CACHE_SECT1 = 48;
`endif
`ifdef SCSI_CACHE_OFF
// SCSI_CACHE_OFF=1 (development builds only, configs/cpu_development.tcl): no
// block cache -- the engine talks to hps_io directly as it did before
// rtl/scsi_cache.sv.  The engine's block count is meaningful only for a CD
// pass-through read; a disk transfer is one block.  Guest disk I/O is slower;
// the CPU benchmarks do not touch the disk.  Boot-simulated to the Finder
// (scratch/sim_scoff2, 2026-09-23).
assign io_lba         = e_io_lba;
assign io_blk_cnt     = e_io_rd[2] ? e_io_blk_cnt : 6'd0;
assign io_rd          = e_io_rd;
assign io_wr          = e_io_wr;
assign e_io_ack       = io_ack;
assign e_sd_buff_addr = sd_buff_addr;
assign e_sd_buff_dout = sd_buff_dout;
assign sd_buff_din    = e_sd_buff_din;
assign e_sd_buff_wr   = sd_buff_wr;
assign cache_hits     = 16'd0;
assign cache_misses   = 16'd0;
`else
scsi_cache #(.SECT0(CACHE_SECT0), .SECT1(CACHE_SECT1), .SECT2(16), .PF_DEPTH(8), .CACHE_CD(CACHE_CD_SLOT)) scsi_cache (
	.clk(clk),
	.nreset(nreset),

	.e_lba(e_io_lba),
	.e_blk_cnt(e_io_blk_cnt),
	.e_rd(e_io_rd),
	.e_wr(e_io_wr),
	.e_ack(e_io_ack),
	.e_buff_addr(e_sd_buff_addr),
	.e_buff_dout(e_sd_buff_dout),
	.e_buff_din(e_sd_buff_din),
	.e_buff_wr(e_sd_buff_wr),

	.p_lba(io_lba),
	.p_blk_cnt(io_blk_cnt),
	.p_rd(io_rd),
	.p_wr(io_wr),
	.p_ack(io_ack),
	.p_buff_addr(sd_buff_addr),
	.p_buff_dout(sd_buff_dout),
	.p_buff_din(sd_buff_din),
	.p_buff_wr(sd_buff_wr),

	.img_mounted(img_mounted),
	.img_size(img_size),

	.stat_hits(cache_hits),
	.stat_misses(cache_misses)
);
`endif

// any block transfer in flight between the machine and the HPS -- on either
// side of the cache: a request strobe up, or an ack still streaming.  Holds
// the CPU's stall watchdog.
wire hps_busy = (|e_io_rd) | (|e_io_wr) | (|e_io_ack) | (|io_rd) | (|io_wr) | (|io_ack);
wire cpu_stall_flt;
wombat_cpu cpu (
	.clk(clk),
	.nreset(nreset),
	.ce(ce),
	.stall_hold(hps_busy),
	.dbg_stall_flt(cpu_stall_flt),

	.ipl(ipl_n),
	.ipl_autovector(1'b1),
	.berr(cpu_berr),
	// The retained SDRAM line is physical RAM only.  During boot overlay the
	// same low CPU addresses select ROM, so keep the sideband disabled there.
	.cache_line_valid(!overlay && line_valid_sw),
	.cache_line_tag({5'd0, mem_line_tag}),
	.cache_line_data(mem_line_data),
	.store_buffer_ok(!overlay && !dbg_sw[0]),

	.bus_req(bus_req),
	.bus_write(bus_write),
	.bus_instr(bus_instr),
	.bus_size(bus_size),
	.bus_addr(bus_addr),
	.bus_wdata(bus_wdata),
	.bus_fc(bus_fc),
	.bus_ack(bus_ack),
	.bus_rdata(bus_rdata),

	.walker_req(walker_req),
	.walker_we(walker_we),
	.walker_addr(walker_addr),
	.walker_wdat(walker_wdat),
	.walker_ack(walker_ack),
	.walker_data(walker_data),
	.walker_berr(walker_berr),

	.snoop_stb(snoop_stb),
	.snoop_addr({5'd0, dma_beat_addr, 2'b00}),

	.nresetout(),
	.nmi_ack_toggle(),
	.cacr_out(),
	.vbr_out(),
	.debug_busy(),
	.debug_fault(debug_fault),
	.debug_halted(debug_halted),
	.debug_status(debug_status),
	.debug_status2(debug_status2)
);

wire        b_req, b_write;
wire [31:2] b_addr;
wire  [3:0] b_be;
wire [31:0] b_wdata;
reg         b_ack;
reg  [31:0] b_rdata;

wombat_bus32 bus32 (
	.clk(clk),
	.nreset(nreset),
	.ce(ce),

	.t_req(bus_req_adapter),
	.t_write(bus_write),
	.t_size(bus_size),
	.t_addr(bus_addr),
	.t_wdata(bus_wdata),
	.t_berr(cpu_berr),
	.t_ack(bus_ack_adapter),
	.t_rdata(bus_rdata_adapter),
	.t_active(bus_adapter_active),

	.b_req(b_req),
	.b_write(b_write),
	.b_addr(b_addr),
	.b_be(b_be),
	.b_wdata(b_wdata),
	.b_ack(b_ack),
	.b_rdata(b_rdata)
);

//----------------------------------------------------------------------------
// IOSB — VIA1/VIA2, config regs, ID; the 3-level interrupt encoder
//----------------------------------------------------------------------------
reg         iosb_sel;
reg         iosb_write;
reg  [27:2] iosb_addr;
reg   [3:0] iosb_be;
reg  [31:0] iosb_wdata;
wire [31:0] iosb_rdata;
wire        iosb_ack;
wire        iosb_fault;   // ack released a timed-out PDMA beat -> bus error

wire dafb_vbl;

iosb #(.CDROM(CDROM)) iosb (
	.clk(clk),
	.nreset(nreset),
	.ce(ce),

	.sel(iosb_sel),
	.write(iosb_write),
	.addr(iosb_addr),
	.be(iosb_be),
	.wdata(iosb_wdata),
	.rdata(iosb_rdata),
	.ack(iosb_ack),
	.sdma_fault(iosb_fault),
	.stall_flt(cpu_stall_flt),

	.vbl_irq(dafb_vbl),
	.sonic_irq(sonic_irq),
	.scsi_irq(1'b0),
	.scsi_drq(1'b0),
	.asc_irq(1'b0),

	.scc_rxd_a(scc_rxd_a),
	.scc_txd_a(scc_txd_a),
	.scc_cts_a(scc_cts_a),
	.scc_rts_a(scc_rts_a),
	.scc_rxd_b(scc_rxd_b),
	.scc_txd_b(scc_txd_b),

	.ipl_n(ipl_n),

	.audio_l(AUDIO_L),
	.audio_r(AUDIO_R),
	.cd_snd_l(cd_snd_l),
	.cd_snd_r(cd_snd_r),

	.img_mounted(img_mounted),
	.img_size(img_size),
	.io_lba(e_io_lba),
	.io_blk_cnt(e_io_blk_cnt),
	.io_rd(e_io_rd),
	.io_wr(e_io_wr),
	.io_ack(e_io_ack),
	.sd_buff_addr(e_sd_buff_addr),
	.sd_buff_dout(e_sd_buff_dout),
	.sd_buff_din(e_sd_buff_din),
	.sd_buff_wr(e_sd_buff_wr),

	.ps2_key(ps2_key),
	.ps2_mouse(ps2_mouse),
	.timestamp(timestamp),

	// DEBUG: fault channel for the SCSI trace in iosb.sv
	.berr_active(svc == S_BERR),
	.berr_addr(svc_addr)
);

//----------------------------------------------------------------------------
// DAFB — registers at $F9800000, scanout from VRAM
//----------------------------------------------------------------------------
reg         dafb_sel;
reg         dafb_write;
reg   [9:2] dafb_addr;
reg  [31:0] dafb_wdata;
wire [31:0] dafb_rdata;
wire        dafb_ack;

dafb dafb (
	.clk_vid(clk_vid),
	.nreset_vid(nreset_vid),
	.mon_12in(mon_12in),
	.clk(clk),
	.nreset(nreset),
	.ce(ce),

	.sel(dafb_sel),
	.write(dafb_write),
	.addr(dafb_addr),
	.wdata(dafb_wdata),
	.rdata(dafb_rdata),
	.ack(dafb_ack),

	.vbl_irq(dafb_vbl),

	.vid_addr(vid_addr),
	.vid_rdata(vid_rdata),
	.vid_stride(vid_stride),

	.vga_r(VGA_R),
	.vga_g(VGA_G),
	.vga_b(VGA_B),
	.vga_hs(VGA_HS),
	.vga_vs(VGA_VS),
	.vga_hb(VGA_HB),
	.vga_vb(VGA_VB),
	.ce_pixel(CE_PIXEL)
);

//----------------------------------------------------------------------------
// Beat service: arbitrate CPU vs table walker, decode, dispatch
//----------------------------------------------------------------------------
reg        overlay;

// Installed-RAM ceiling in LONGWORDS.  Anything at or above it decodes as
// open bus (never a bus error — see the note below), which is how the ROM's
// sizing loop discovers the top of memory.
// Powers of two only.  The djMEMC bank registers (iosb's djmemc_regs) are
// stored but not honoured by this decode, so RAM is one flat linear range —
// which matches what the ROM computes only for power-of-two totals.  A
// 48 MB option was tried and hangs the ROM in a 3-instruction loop at
// $408A022A: on real hardware 48 MB is two unequal banks, and sizing it
// needs the bank decode this stub does not implement.
// Powers of two only.  48 MB was hardcoded and RE-MEASURED on the SDRAM
// branch: the ROM still hangs in a 3-instruction loop at $408A0230 with
// d7=$11 and no bus error, exactly as it did on DDR3 — so the backing store
// is NOT what rejects it.  The cause is this decode: RAM is one flat linear
// range and the djMEMC bank registers (iosb's djmemc_regs) are stored but
// never acted on.  Before the ROM remaps them, djMEMC banks appear at fixed
// strides and are sized individually; a flat map only matches what the ROM
// computes when the total is a single power-of-two bank.  Making 48 MB (and
// 20/24/36/40/72) work means implementing that bank decode — worth doing,
// but it is a feature, not a constant.
wire [29:2] ram_limit = (ram_cfg == 2'd0) ? 28'h0800000 :   // 32 MB
                        (ram_cfg == 2'd1) ? 28'h1000000 :   // 64 MB
                                            28'h2000000;    // 128 MB

// decode of a beat address; the walker sees the same physical map.
// djMEMC acknowledges its whole DRAM window: probes beyond installed RAM
// read open-bus zeros, never a bus error — the ROM's RAM sizing treats a
// berr there as a fatal hardware fault (found the hard way; QEMU agrees).
function [2:0] decode;       // 0 ram,1 rom,2 vram,3 iosb,4 berr,5 dafb,6 open,7 sonic
	input [31:2] a;
	begin
		// SONIC registers $A000-$A0FF and MAC PROM $8000-$8007, in every $40000 image of
		// the I/O block; without the chip both stay iosb's inert read-0 space
		if (sonic_present && a[31:24] == 8'h50 &&
		    (a[17:8] == 10'h0A0 || a[17:3] == 15'h1000)) decode = 3'd7;
		else if (a[31:28] == 4'h4)         decode = 3'd1;
		else if (overlay && a[31:22] == 10'd0) decode = 3'd1;
		else if (a[31:30] == 2'b00)
			decode = (a[29:2] < ram_limit) ? 3'd0 : 3'd6;
		else if (a[31:21] == 11'b1111_1001_000) decode = 3'd2;  // $F900xxxx-$F91Fxxxx
		else if (a[31:10] == 22'b1111_1001_1000_0000_0000_00) decode = 3'd5;
		else if (a[31:28] == 4'h5)         decode = 3'd3;
		else                               decode = 3'd4;
	end
endfunction

localparam S_IDLE = 3'd0, S_MEM = 3'd1, S_IOSB = 3'd2, S_BERR = 3'd3,
           S_DAFB = 3'd4, S_OPEN = 3'd5, S_SONIC = 3'd6;
reg  [2:0] svc;
reg        svc_walker;                        // owner of the beat in service
reg        svc_dma;                           // ... or the SONIC's DMA engine

// The SONIC is the machine's one bus master besides the CPU.  Its engine asks for
// one longword beat at a time; beats alternate with the CPU's so neither starves,
// and they go through the ordinary RAM port, so sdram_beat32 drops its retained
// line on a DMA write exactly as it does on a CPU write.
wire        dma_req, dma_we;
wire [26:2] dma_addr;
wire  [3:0] dma_be;
wire [31:0] dma_wdata;
reg         dma_ack;
reg  [31:0] dma_rdata;
reg         dma_turn;                         // the CPU had the last beat
reg         sonic_sel, sonic_write, sonic_prom;
reg   [7:2] sonic_addr;
reg   [3:0] sonic_be;
reg  [31:0] sonic_wdata;
wire        sonic_ack;
wire [31:0] sonic_rdata;
reg        svc_bus_direct;                    // aligned RAM miss bypassed bus32
reg  [1:0] svc_rd_off;                        // ... or a VRAM read: its offset
reg  [2:0] svc_rd_bytes;                      // and size, to right-align the data
reg [31:2] svc_addr;
// A DMA beat can also run BESIDE a parked I/O beat (S_IOSB, below), where
// svc_addr belongs to the CPU's access: the snoop address is the beat's own.
reg        dma_side;                          // a DMA beat is on the RAM port under S_IOSB
reg [26:2] dma_beat_addr;

wire        walker_pend = walker_req && walker_armed;
reg         walker_armed;

// A completed BL8 read remains in sdram_beat32 as four longwords. Serve those
// words through the same registered service-FSM acknowledgement used by every
// established platform beat. A request for the still-arriving tail waits here
// instead of launching a redundant SDRAM transaction for the same line.
wire line_cpu_match = b_req && !b_write && (decode(b_addr) == 3'd0) &&
	                  line_valid_sw && (b_addr[26:4] == mem_line_tag);
wire line_cpu_wait  = b_req && !b_write && (decode(b_addr) == 3'd0) &&
	                  line_pending_sw &&
	                  (b_addr[26:4] == mem_line_pending_tag);
wire [31:0] line_cpu_data = (b_addr[3:2] == 2'd0) ? mem_line_data[127:96] :
	                        (b_addr[3:2] == 2'd1) ? mem_line_data[95:64]  :
	                        (b_addr[3:2] == 2'd2) ? mem_line_data[63:32]  :
	                                                        mem_line_data[31:0];

// Aligned RAM longword reads are the cache-fill shape before wombat_bus32.
// Send a first miss directly into the memory service, which still captures its
// completion in registers, and return later words from the retained BL8 line
// through their own registered pulse. Adapter-active/ack, direct-miss-ack and
// line-ack guards prevent either word from being launched or acknowledged twice.
//
// The line-ack guard (2026-09-19): bus_req still carries the acknowledged
// request in the clock bus_line_ack is high.  While the CPU was the only
// master the FSM was always still in S_IDLE in that clock, so bus_line_match
// stayed high and kept bus_req_adapter low by itself.  The SONIC's DMA arm can
// leave S_IDLE in the very clock the line ack is registered: eligibility then
// drops under the ack, bus_req_adapter rose, wombat_bus32 launched a read
// nobody had asked for, and its completion acknowledged whatever request was
// on the bus by then -- a fill beat took its neighbour's word, a store was
// acknowledged without being written.  That was Open Transport's CAS/CAS2
// lists going circular under receive traffic (verilator/tb_line_dma.sv).
wire bus_ram_eligible = (svc == S_IDLE) && !walker_pend && !cpu_berr &&
	                    !bus_miss_ack && !bus_line_ack && !bus_adapter_active &&
	                    !bus_ack_adapter && bus_req && !bus_write &&
	                    (bus_size == 2'd2) && (bus_addr[1:0] == 2'b00) &&
	                    (decode(bus_addr[31:2]) == 3'd0);
wire bus_line_match = bus_ram_eligible && line_valid_sw &&
	                  (bus_addr[26:4] == mem_line_tag);
wire bus_line_wait  = bus_ram_eligible && line_pending_sw &&
	                  (bus_addr[26:4] == mem_line_pending_tag);
wire bus_first_miss = bus_ram_eligible && !bus_line_match && !bus_line_wait;

// ROM line fills.  Every ROM read loads the whole 16-byte line from DDR3 in
// one burst (MacQuadra800.sv); the cache's other three fill beats, and any
// later aligned longword read of that line, are answered from it through the
// registered line acknowledge, as RAM's retained line is.  A read of a line
// not held goes straight into S_MEM like a RAM first miss.  QuickDraw's code
// runs from ROM and misses the 8 KB I-cache hard: in the 8-bit Color test
// ROM fill beats outnumber VRAM beats several times, and each was a DDR3
// round trip of its own.
wire bus_rom_eligible = (svc == S_IDLE) && !walker_pend && !cpu_berr &&
	                    !bus_miss_ack && !bus_line_ack && !bus_adapter_active &&
	                    !bus_ack_adapter && !wr_split_pend && bus_req && !bus_write &&
	                    (bus_size == 2'd2) && (bus_addr[1:0] == 2'b00) &&
	                    (decode(bus_addr[31:2]) == 3'd1);
wire bus_rom_match = bus_rom_eligible && mem_rom_line_valid &&
	                 (bus_addr[19:4] == mem_rom_line_tag);
wire bus_rom_first = bus_rom_eligible && !bus_rom_match;
wire [31:0] bus_rom_data = (bus_addr[3:2] == 2'd0) ? mem_rom_line_data[127:96] :
	                       (bus_addr[3:2] == 2'd1) ? mem_rom_line_data[95:64]  :
	                       (bus_addr[3:2] == 2'd2) ? mem_rom_line_data[63:32]  :
	                                                 mem_rom_line_data[31:0];
wire [31:0] bus_line_data = (bus_addr[3:2] == 2'd0) ? mem_line_data[127:96] :
	                        (bus_addr[3:2] == 2'd1) ? mem_line_data[95:64]  :
	                        (bus_addr[3:2] == 2'd2) ? mem_line_data[63:32]  :
	                                                          mem_line_data[31:0];

// A RAM write inside one longword -- the store buffer's drain -- goes
// straight into the bridge's write FIFO: registered here, acknowledged next
// clock through bus_miss_ack, with no wombat_bus32 beat and no S_MEM wait.
// It used to take the adapter, S_MEM and the bridge's registered
// completion in turn, about six clocks a store, which is what bounded
// Whetstone's store stream on hardware.  Every RAM read (CPU, walker, SONIC
// DMA) waits in the bridge until the FIFO has drained, and a push drops the
// retained line, so ordering is the bridge's as before.
wire  [2:0] bus_wr_bytes = (bus_size == 2'd0) ? 3'd1 : (bus_size == 2'd1) ? 3'd2 : 3'd4;
wire  [2:0] bus_wr_end   = {1'b0, bus_addr[1:0]} + bus_wr_bytes;
wire [31:0] bus_wr_left  = (bus_size == 2'd0) ? {bus_wdata[7:0], 24'd0} :
                           (bus_size == 2'd1) ? {bus_wdata[15:0], 16'd0} : bus_wdata;
// P214: a store spanning two longwords (Pascal's 2-mod-4 stack longwords,
// a word at offset 3) is pushed as two byte-enabled longwords on
// consecutive clocks and acknowledged with the second; it used to take the
// adapter as two S_MEM beats, ten clocks a store, and filled the store
// buffer behind it (the platform fixture: 914k such stores per Whetstone
// loop, the buffer full 15 % of the time).  mem_wq_room means two free
// entries, and nothing else pushes between the halves.
reg         wr_split_pend;
reg  [31:2] wr_split_addr;
reg   [3:0] wr_split_be;
reg  [31:0] wr_split_data;
wire        bus_wr_span  = (bus_wr_end > 3'd4);
wire bus_wr_direct = (DIRECT_WRITES != 0) && (svc == S_IDLE) && !walker_pend && !cpu_berr &&
	                 !bus_miss_ack && !bus_line_ack && !bus_adapter_active && !wr_split_pend &&
	                 !bus_ack_adapter && bus_req && bus_write &&
	                 (!bus_wr_span || (decode(bus_addr[31:2] + 30'd1) == 3'd0)) &&
	                 (decode(bus_addr[31:2]) == 3'd0) && mem_wq_room;

// The same for a VRAM write inside one longword: the emu writes the VRAM
// block RAM from mem_addr/mem_be/mem_wdata on the clock mem_vram_wp is high,
// and the store buffer has its acknowledge then.  It took the adapter,
// S_MEM, the port's capture/deliver phases and the registered b_ack, five
// clocks, and the store buffer drained QuickDraw's VRAM stores at that rate
// (docs/GRAPHICS_PROFILE_20260926.md).  The next VRAM beat is decoded two
// clocks later at the earliest, after the write has landed.
wire bus_vram_direct = (DIRECT_WRITES != 0) && (svc == S_IDLE) && !walker_pend && !cpu_berr &&
	                   !bus_miss_ack && !bus_line_ack && !bus_adapter_active && !wr_split_pend &&
	                   !bus_ack_adapter && bus_req && bus_write && !bus_wr_span &&
	                   (decode(bus_addr[31:2]) == 3'd2);

// A VRAM read inside one longword goes the way of a RAM first miss: into
// S_MEM from bus_req, acknowledged through bus_miss_ack with the bytes
// right-aligned as wombat_bus32 would return them, two clocks sooner.
// QuickDraw's reads of the frame buffer are uncached, one bus beat each.
wire bus_vram_rd = (svc == S_IDLE) && !walker_pend && !cpu_berr &&
	               !bus_miss_ack && !bus_line_ack && !bus_adapter_active && !wr_split_pend &&
	               !bus_ack_adapter && bus_req && !bus_write && !bus_wr_span &&
	               (decode(bus_addr[31:2]) == 3'd2);

assign bus_req_adapter = bus_req && !bus_line_match && !bus_line_wait && !bus_wr_direct && !bus_vram_direct && !bus_vram_rd &&
	                     !bus_rom_match && !bus_rom_first && !wr_split_pend &&
	                     !bus_first_miss && !svc_bus_direct && !bus_miss_ack &&
	                     !bus_line_ack;

always @(posedge clk) begin
	if (!nreset) begin
		bus_line_ack   <= 0;
		bus_line_rdata <= 0;
	end
	else if (ce) begin
		bus_line_ack <= 0;
		if (!bus_line_ack && (bus_line_match || bus_rom_match)) begin
			bus_line_ack   <= 1;
			bus_line_rdata <= bus_rom_match ? bus_rom_data : bus_line_data;
		end
	end
end

wire cpu_want = walker_pend || bus_first_miss || bus_wr_direct || bus_vram_direct || bus_vram_rd || bus_rom_first ||
                (b_req && !b_ack && !cpu_berr && !line_cpu_wait);
wire dma_take = (SONIC != 0) && dma_req && !dma_ack && !walker_pend &&
                (dma_turn || !cpu_want);

assign dbg_berr      = (svc == S_BERR);
assign dbg_berr_addr = {svc_addr, 2'b00};
assign dbg_overlay   = overlay;

always @(posedge clk) begin
	if (!nreset) begin
		overlay      <= 1;
		svc          <= S_IDLE;
		svc_walker   <= 0;
		svc_bus_direct <= 0;
		svc_rd_off   <= 0;
		svc_rd_bytes <= 3'd4;
		svc_dma      <= 0;
		dma_side     <= 0;
		dma_beat_addr <= 0;
		dma_ack      <= 0;
		dma_rdata    <= 0;
		dma_turn     <= 0;
		snoop_stb    <= 0;
		sonic_sel    <= 0;
		sonic_write  <= 0;
		sonic_prom   <= 0;
		sonic_addr   <= 0;
		sonic_be     <= 0;
		sonic_wdata  <= 0;
		svc_addr     <= 0;
		walker_armed <= 1;
		walker_ack   <= 0;
		walker_data  <= 0;
		walker_berr  <= 0;
		b_ack        <= 0;
		b_rdata      <= 0;
		bus_miss_ack   <= 0;
		wr_split_pend  <= 0;
		bus_miss_rdata <= 0;
		mem_wp_valid   <= 0;
		mem_wp_addr    <= 0;
		mem_wp_be      <= 0;
		mem_wp_data    <= 0;
		mem_vram_wp    <= 0;
		cpu_berr     <= 0;
		mem_req      <= 0;
		mem_write    <= 0;
		mem_addr     <= 0;
		mem_be       <= 0;
		mem_wdata    <= 0;
		mem_memsel   <= MSEL_RAM;
		iosb_sel     <= 0;
		iosb_write   <= 0;
		iosb_addr    <= 0;
		iosb_be      <= 0;
		iosb_wdata   <= 0;
		dafb_sel     <= 0;
		dafb_write   <= 0;
		dafb_addr    <= 0;
		dafb_wdata   <= 0;
	end
	else if (ce) begin
		walker_ack  <= 0;
		walker_berr <= 0;
		b_ack       <= 0;
		bus_miss_ack <= 0;
		mem_wp_valid <= 0;
		mem_vram_wp  <= 0;
		cpu_berr    <= 0;
		// P214: the spanning store's second longword, ahead of everything
		if (wr_split_pend) begin
			wr_split_pend  <= 0;
			mem_wp_valid   <= 1;
			mem_wp_addr    <= wr_split_addr;
			mem_wp_be      <= wr_split_be;
			mem_wp_data    <= wr_split_data;
			bus_miss_ack   <= 1;
			bus_miss_rdata <= 0;
		end
		dma_ack     <= 0;
		snoop_stb   <= 0;
		if (!walker_req) walker_armed <= 1;
		// the ROM's own window read ends the boot overlay (the adapter path's
		// test is in S_IDLE below); a direct or line-served ROM read does too
		if (bus_rom_eligible && bus_addr[31:28] == 4'h4) overlay <= 0;

		case (svc)
		S_IDLE: begin
			// walker first: it only runs mid-translation, never starves the
			// CPU.  !b_ack/!cpu_berr: the adapter needs a cycle to retire a
			// just-completed or just-faulted beat before b_req means "next".
			// A SONIC DMA beat takes the turn after each CPU beat, or an idle bus.
			if (dma_take) begin
				svc_walker     <= 0;
				svc_bus_direct <= 0;
				dma_turn       <= 0;
				svc_addr       <= {5'd0, dma_addr};
				dma_beat_addr  <= dma_addr;
				if ({3'd0, dma_addr} < ram_limit) begin
					svc_dma    <= 1;
					mem_req    <= 1;
					mem_write  <= dma_we;
					mem_addr   <= {5'd0, dma_addr};
					mem_be     <= dma_be;
					mem_wdata  <= dma_wdata;
					mem_memsel <= MSEL_RAM;
					svc        <= S_MEM;
				end
				else begin
					dma_ack   <= 1;          // above the installed RAM: nothing there
					dma_rdata <= 32'd0;
				end
			end
			else if (cpu_want) begin
				reg [31:2] a;
				reg        wr;
				dma_turn <= 1;
				if (bus_first_miss || bus_vram_rd || bus_rom_first) begin
					svc_walker     <= 0;
					svc_bus_direct <= 1;
					svc_addr       <= bus_addr[31:2];
					svc_rd_off     <= bus_vram_rd ? bus_addr[1:0] : 2'd0;
					svc_rd_bytes   <= bus_vram_rd ? bus_wr_bytes : 3'd4;
					mem_req        <= 1;
					mem_write      <= 0;
					mem_addr       <= bus_addr[31:2];
					mem_be         <= 4'b1111;
					mem_wdata      <= 0;
					mem_memsel     <= bus_vram_rd ? MSEL_VRAM : bus_rom_first ? MSEL_ROM : MSEL_RAM;
					svc            <= S_MEM;
				end
				else if (bus_wr_direct) begin
					mem_wp_valid <= 1;
					mem_wp_addr  <= bus_addr[31:2];
					mem_wp_be    <= (4'b1111 << (3'd4 - bus_wr_bytes)) >> bus_addr[1:0];
					mem_wp_data  <= bus_wr_left >> {bus_addr[1:0], 3'd0};
					if (bus_wr_span) begin
						// the tail: the bytes from the next longword's offset 0
						wr_split_pend <= 1;
						wr_split_addr <= bus_addr[31:2] + 30'd1;
						wr_split_be   <= 4'b1111 << (4'd8 - {1'b0, bus_wr_end});
						wr_split_data <= bus_wr_left << {3'd4 - {1'b0, bus_addr[1:0]}, 3'd0};
					end
					else begin
						bus_miss_ack   <= 1;
						bus_miss_rdata <= 0;
					end
				end
				else if (bus_vram_direct) begin
					mem_vram_wp    <= 1;
					mem_addr       <= bus_addr[31:2];
					mem_be         <= (4'b1111 << (3'd4 - bus_wr_bytes)) >> bus_addr[1:0];
					mem_wdata      <= bus_wr_left >> {bus_addr[1:0], 3'd0};
					bus_miss_ack   <= 1;
					bus_miss_rdata <= 0;
				end
				else if (!walker_pend && line_cpu_match) begin
					b_ack   <= 1;
					b_rdata <= line_cpu_data;
				end
				else begin
					a  = walker_pend ? walker_addr[31:2] : b_addr;
					wr = walker_pend ? walker_we : b_write;
					svc_walker <= walker_pend;
					svc_bus_direct <= 0;
					if (walker_pend) walker_armed <= 0;
					svc_addr   <= a;
					// the ROM's own window read ends the boot overlay
					if (a[31:28] == 4'h4 && !wr) overlay <= 0;
					case (decode(a))
				3'd0, 3'd1, 3'd2: begin
					mem_req    <= 1;
					mem_write  <= wr;
					mem_addr   <= a;
					mem_be     <= walker_pend ? 4'b1111 : b_be;
					mem_wdata  <= walker_pend ? walker_wdat : b_wdata;
					mem_memsel <= decode(a) == 3'd0 ? MSEL_RAM :
					              decode(a) == 3'd1 ? MSEL_ROM : MSEL_VRAM;
					svc        <= S_MEM;
				end
				3'd3: begin
					iosb_sel   <= 1;
					iosb_write <= wr;
					iosb_addr  <= a[27:2];
					iosb_be    <= walker_pend ? 4'b1111 : b_be;
					iosb_wdata <= walker_pend ? walker_wdat : b_wdata;
					svc        <= S_IOSB;
				end
				3'd5: begin
					dafb_sel   <= 1;
					dafb_write <= wr;
					dafb_addr  <= a[9:2];
					dafb_wdata <= walker_pend ? walker_wdat : b_wdata;
					svc        <= S_DAFB;
				end
				3'd6: svc <= S_OPEN;
				3'd7: begin
					sonic_sel   <= 1;
					sonic_write <= wr;
					sonic_prom  <= (a[15:12] == 4'h8);
					sonic_addr  <= a[7:2];
					sonic_be    <= walker_pend ? 4'b1111 : b_be;
					sonic_wdata <= walker_pend ? walker_wdat : b_wdata;
					svc         <= S_SONIC;
				end
				default: svc <= S_BERR;
				endcase
				end
			end
		end
		S_MEM: if (mem_ack) begin
			mem_req <= 0;
			if (svc_dma) begin
				dma_ack   <= 1;
				dma_rdata <= mem_rdata;
				// the 68040's bus snoop: a write by the other master drops the
				// D-cache's copy of that line (dma_beat_addr is the beat's)
				snoop_stb <= mem_write && (SONIC_SNOOP != 0) && !dbg_sw[2];
				svc_dma   <= 0;
			end
			else if (svc_walker) begin
				walker_ack  <= 1;
				walker_data <= mem_rdata;
			end
			else if (svc_bus_direct) begin
				bus_miss_ack   <= 1;
				bus_miss_rdata <= (mem_rdata << {svc_rd_off, 3'd0}) >> {3'd4 - svc_rd_bytes, 3'd0};
			end
			else begin
				b_ack   <= 1;
				b_rdata <= mem_rdata;
			end
			svc_bus_direct <= 0;
			svc <= S_IDLE;
		end
		// A pseudo-DMA beat waits here, without a time limit, while the HPS
		// fetches or accepts a disk sector (iosb.sv A_SDMA).  The HPS is also
		// the SONIC model, and it is single-threaded: while it waits for a DMA
		// op list it serves no disk request.  With the FSM parked, the list
		// could not move either -- each side waited for the other until Main's
		// 250 ms DMA timeout, which then let it post the next list over the one
		// still in the engine (hardware 2026-09-19: six timeouts in a 1 MB FTP
		// download at 36 KB/s, lost pings during every application launch).
		// The RAM port is idle while an I/O beat is parked, so DMA beats run
		// beside it; the CPU is stalled in its I/O access throughout, so no
		// CPU-side shortcut can see the port busy.
		S_IOSB: begin
			if (dma_side) begin
				if (mem_ack) begin
					mem_req   <= 0;
					dma_ack   <= 1;
					dma_rdata <= mem_rdata;
					snoop_stb <= mem_write && (SONIC_SNOOP != 0) && !dbg_sw[2];
					dma_side  <= 0;
				end
			end
			else if ((SONIC != 0) && dma_req && !dma_ack && !iosb_ack) begin
				dma_beat_addr <= dma_addr;
				if ({3'd0, dma_addr} < ram_limit) begin
					dma_side   <= 1;
					mem_req    <= 1;
					mem_write  <= dma_we;
					mem_addr   <= {5'd0, dma_addr};
					mem_be     <= dma_be;
					mem_wdata  <= dma_wdata;
					mem_memsel <= MSEL_RAM;
				end
				else begin
					dma_ack   <= 1;          // above the installed RAM: nothing there
					dma_rdata <= 32'd0;
				end
			end
			if (iosb_ack) begin
				iosb_sel <= 0;
				// iosb_fault rides with the ack that releases a pseudo-DMA beat the
				// IOSB gave up on. Report it as a bus error rather than acking junk:
				// the ROM's blind PDMA path does unrolled move.l with no polling and
				// RELIES on a bus error (handler at $408D2606) to notice a failed
				// transfer. Acking zeros would silently corrupt the buffer instead.
				if (iosb_fault) begin
					if (svc_walker) walker_berr <= 1;
					else            cpu_berr    <= 1;
				end
				else if (svc_walker) begin
					walker_ack  <= 1;
					walker_data <= iosb_rdata;
				end
				else begin
					b_ack   <= 1;
					b_rdata <= iosb_rdata;
				end
				// a side beat still on the RAM port finishes as an ordinary DMA
				// beat: S_MEM's svc_dma arm acknowledges it and pulses the snoop
				if (dma_side && !mem_ack) begin
					dma_side       <= 0;
					svc_dma        <= 1;
					svc_walker     <= 0;
					svc_bus_direct <= 0;
					svc            <= S_MEM;
				end
				else svc <= S_IDLE;
			end
		end
		S_SONIC: if (sonic_ack) begin
			sonic_sel <= 0;
			if (svc_walker) begin
				walker_ack  <= 1;
				walker_data <= sonic_rdata;
			end
			else begin
				b_ack   <= 1;
				b_rdata <= sonic_rdata;
			end
			svc <= S_IDLE;
		end
		S_DAFB: if (dafb_ack) begin
			dafb_sel <= 0;
			if (svc_walker) begin
				walker_ack  <= 1;
				walker_data <= dafb_rdata;
			end
			else begin
				b_ack   <= 1;
				b_rdata <= dafb_rdata;
			end
			svc <= S_IDLE;
		end
		S_BERR: begin
			if (svc_walker) walker_berr <= 1;
			else            cpu_berr    <= 1;
			svc <= S_IDLE;
		end
		S_OPEN: begin
			if (svc_walker) begin
				walker_ack  <= 1;
				walker_data <= 32'd0;
			end
			else begin
				b_ack   <= 1;
				b_rdata <= 32'd0;
			end
			svc <= S_IDLE;
		end
		endcase
	end
end

//----------------------------------------------------------------------------
// Built-in Ethernet — DP83932 SONIC front-end; the chip model is on the ARM
// (docs in rtl/sonic_mbx.sv).  SONIC=0 (qsf: ETHERNET_OFF=1) builds a machine
// without it; eth_ena=0 (OSD) holds it in reset, off the bus and off DDR3.
//----------------------------------------------------------------------------
generate
if (SONIC != 0) begin : g_sonic
	sonic_mbx sonic (
		.clk(clk),
		.nreset(nreset),
		.ena(eth_ena),
		.present(sonic_present),

		.sel(sonic_sel),
		.write(sonic_write),
		.prom(sonic_prom),
		.addr(sonic_addr),
		.be(sonic_be),
		.wdata(sonic_wdata),
		.ack(sonic_ack),
		.rdata(sonic_rdata),
		.irq(sonic_irq),
		.cpu_sample(debug_status[47:0]),

		.dma_req(dma_req),
		.dma_we(dma_we),
		.dma_addr(dma_addr),
		.dma_be(dma_be),
		.dma_wdata(dma_wdata),
		.dma_ack(dma_ack),
		.dma_rdata(dma_rdata),

		.mem_addr(eth_mem_addr),
		.mem_rd(eth_mem_rd),
		.mem_we(eth_mem_we),
		.mem_wdata(eth_mem_wdata),
		.mem_accept(eth_mem_accept),
		.mem_rvalid(eth_mem_rvalid),
		.mem_rdata(eth_mem_rdata)
	);
end
else begin : g_no_sonic
	assign sonic_present = 1'b0;
	assign sonic_irq     = 1'b0;
	assign sonic_ack     = 1'b0;
	assign sonic_rdata   = 32'd0;
	assign dma_req       = 1'b0;
	assign dma_we        = 1'b0;
	assign dma_addr      = 25'd0;
	assign dma_be        = 4'd0;
	assign dma_wdata     = 32'd0;
	assign eth_mem_addr  = 12'd0;
	assign eth_mem_rd    = 1'b0;
	assign eth_mem_we    = 1'b0;
	assign eth_mem_wdata = 64'd0;
end
endgenerate

endmodule
