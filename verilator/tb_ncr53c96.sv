//============================================================================
//  tb_ncr53c96 — directed unit test for rtl/ncr53c96.sv.
//
//  Two driver dialects talk to this chip and they are NOT the same:
//
//    * the Quadra 800 ROM — DMA-form selects ($C1/$C2) with TC preloaded
//      and an EMPTY FIFO, the CDB arriving afterwards as FIFO writes plus
//      a trailing PDMA byte.  This is what the model was shaped around and
//      what boots Mac OS today (docs/scsi/rom-driver-scsi-access-patterns.md).
//
//    * a real Unix 53C9x driver — NetBSD's ncr53c9x, and A/UX's, which is
//      the same driver family.  On mac68k NCR_F_DMASELECT is never set, so
//      every select is FIFO-PRELOADED: $41 SELNATN (CDB only), $42 SELATN
//      (IDENTIFY + CDB), $43 SELATNS (stop after IDENTIFY, for sync
//      negotiation), $46 SELATN3 (IDENTIFY + 2 tag bytes + CDB).  After the
//      select interrupt it reads STAT, then STEP, then INTR last, and
//      demands FC|BS together with a sequence step of 0..4
//      (docs/scsi/netbsd-ncr53c9x-expectations.md section 2).
//
//  Both dialects are exercised here so that widening the model for the
//  second cannot silently break the first.  Runs in seconds and needs no
//  ROM and no disk image — the backing store is a tiny synthetic disk.
//
//    make tb_ncr53c96 && ./obj_dir_tb/tb_ncr53c96
//============================================================================
`timescale 1ns/1ps

module tb_ncr53c96;

localparam [3:0] R_TCL = 4'h0, R_TCM = 4'h1, R_FIFO = 4'h2, R_CMD = 4'h3,
                 R_STAT = 4'h4, R_SELID = 4'h4, R_INTR = 4'h5, R_STEP = 4'h6,
                 R_FFLAG = 4'h7, R_CFG1 = 4'h8;

// interrupt status bits (as the driver names them)
localparam [7:0] I_SEL = 8'h01, I_SELATN = 8'h02, I_RESEL = 8'h04,
                 I_FC = 8'h08, I_BUS = 8'h10, I_DISC = 8'h20, I_ILL = 8'h40,
                 I_RST = 8'h80;

localparam [2:0] PH_DOUT = 3'd0, PH_DIN = 3'd1, PH_CMD = 3'd2, PH_STAT = 3'd3,
                 PH_MOUT = 3'd6, PH_MIN = 3'd7;

//----------------------------------------------------------------------------
// DUT
//----------------------------------------------------------------------------
reg         clk = 0;
reg         nreset = 0;
reg         ce = 1;

reg         sel = 0, write = 0;
reg   [3:0] rs = 0;
reg   [7:0] wdata = 0;
wire  [7:0] rdata;

reg         dma_rd = 0, dma_wr = 0;
reg   [7:0] dma_wdata = 0;
wire  [7:0] dma_rdata;
wire        dma_valid, drq, irq;

reg         img_mounted = 0;
reg  [63:0] img_size = 0;
wire [31:0] io_lba;
wire        io_rd, io_wr;
reg   [2:0] io_ack = 3'b000;                 // per slot, like sd_ack
reg  [12:0] sd_buff_addr = 0;                // wide: a 5-block frame streams 1280 words
reg  [15:0] sd_buff_dout = 0;
wire  [5:0] io_blk_cnt;                      // blocks - 1 the DUT wants (the frame window: 4)
wire [15:0] sd_buff_din;
reg         sd_buff_wr = 0;

always #5 clk = ~clk;

// the disk under test is target 0 (SCSI ID 0, hps_io slot 0); the other two
// targets stay unmounted / unselected in this bench
// The synthetic block device below serves target 0 (the disk) and target 2
// (the CD-ROM) with the same bytes, so a CD read of logical block N must
// return HPS blocks 4N..4N+3.  Target 1 is mounted late (T16g).
wire [2:0] io_rd_v, io_wr_v;
assign io_rd = |io_rd_v;
assign io_wr = |io_wr_v;                     // slot 2 writes its command block

// The CD slot's windows (LBA >= $40000000: the MCDA blob, the response
// window, the command block, the next-frame window) are served by the Main
// fork's own builders through sim/cd_window.cpp (cd_win_dpi.cpp).
import "DPI-C" function int  cdwin_dpi_read(input int lba, input int sz);
import "DPI-C" function int  cdwin_dpi_rbyte(input int i);
import "DPI-C" function void cdwin_dpi_wbyte(input int i, input int b);
import "DPI-C" function void cdwin_dpi_write(input int lba);
import "DPI-C" function void cdwin_dpi_mount(input int bytes);
reg        cd_mount = 0, d1_mount = 0;
reg  [7:0] sel_id = 8'h00;                   // R_SELID the helpers write
ncr53c96 dut (
	.clk(clk), .nreset(nreset), .ce(ce),
	.sel(sel), .write(write), .rs(rs), .wdata(wdata), .rdata(rdata),
	.dma_rd(dma_rd), .dma_wr(dma_wr), .dma_wdata(dma_wdata),
	.dma_rdata(dma_rdata), .dma_valid(dma_valid), .drq(drq), .irq(irq),
	.img_mounted({cd_mount, d1_mount, img_mounted}), .img_size(img_size),
	.io_lba(io_lba), .io_rd(io_rd_v), .io_wr(io_wr_v), .io_blk_cnt(io_blk_cnt), .io_ack(io_ack),
	.sd_buff_addr(sd_buff_addr), .sd_buff_dout(sd_buff_dout),
	.sd_buff_din(sd_buff_din), .sd_buff_wr(sd_buff_wr)
);

//----------------------------------------------------------------------------
// synthetic block device — 64 blocks, byte b of block n = n*7 + b (mod 256).
// Mirrors verilator/sim/sim_blkdevice.cpp: ack rises after a latency, words
// stream in on sd_buff_wr while ack is high, ack falls when the block is done.
// Sim packing is BIG-endian (disk byte 0 in [15:8]), same as that model.
//----------------------------------------------------------------------------
localparam NBLK = 64;
reg [7:0] disk [0:NBLK*512-1];

integer k2;
reg [7:0] it2;
integer d_state = 0, d_lat = 0, d_i = 0, d_lba = 0, d_win = 0, d_r = 0;
integer d_words = 256;                       // words this transaction streams (blocks x 256)
integer d_slot = 0;                          // the slot being served (the cache's E_IDLE priority: 0, 1, 2)
integer bad_disk_req = 0;                    // disk-slot requests carrying a window address or a block count
reg [7:0] d_b0, d_b1;
integer dev_lat = 40;                        // device round trip, settable per test
integer wr_blocks = 0;                       // disk blocks the device has accepted (window writes not counted)
integer win_writes = 0;                      // command blocks the ARM side received
integer frame_reads = 0;                     // next-frame window reads (the engine's fetch loop)
integer frame_blk = -1;                      // ...and the block count the last one asked for
integer stat_reads = 0;                      // $CC status-window reads (the engine's pokes and the guest's own)
integer poke_stbs = 0;                       // fwd_stb pulses: one per forwarded transport command
integer collisions = 0;                      // cycles in which the nexus and the audio engine both hold a request while nobody owns the channel

// Per-request random latency (T22).  dev_lat_jit = 0 (the default) keeps the
// fixed dev_lat round trip every other test was written against; N > 0 adds
// 0..N clocks per request from dev_lcg, which a test seeds.  +lat_seed=S is
// XORed into T22's seeds for soak runs (0, the default, is the recorded run).
integer dev_lat_jit = 0;
reg  [31:0] dev_lcg = 32'h2600_0001;
integer lat_seed = 0;
initial if (!$value$plusargs("lat_seed=%d", lat_seed)) lat_seed = 0;
reg  [63:0] cyc = 0;                         // free-running clock count, for ordering platform events against guest-visible ones
always @(posedge clk) cyc <= cyc + 1;
// Platform-side accounting for the two-half sector buffer (T21/T22); it
// reads nothing inside the DUT, so the same checks run on any engine.
integer disk_rd_reqs = 0;                    // disk-slot block reads requested (windows not counted)
reg         rd_track = 0;                    // the test arms the overlap count below
integer rd_base = 0;                         // disk_rd_reqs at the start of the command under test (the test sets it)
integer rd_drained = 0;                      // bytes of that command the guest has taken (the test keeps it)
integer rd_ovl = 0;                          // reads raised with more than a FIFO's worth of the previous sector undrained
integer rd_ovl_max = 0;                      // ...the most bytes left to drain at one
integer wr_lba_log [0:255];                  // LBA of each accepted disk write block, indexed by wr_blocks mod 256
reg  [63:0] wr_ackfall = 0;                  // cyc at the last accepted disk write block's ack fall
reg  [63:0] stat_cyc = 0;                    // cyc the bus phase last turned STATUS
reg   [2:0] ph_d = 0;
always @(posedge clk) begin
	ph_d <= dut.phase;
	if (dut.phase == PH_STAT && ph_d != PH_STAT) stat_cyc <= cyc;
end

always @(posedge clk) if (dut.ca_fwd_stb) poke_stbs <= poke_stbs + 1;
always @(posedge clk) if (dut.nexus_req && dut.ca_io_rd && !dut.eng_owns) collisions <= collisions + 1;

always @(posedge clk) begin
	sd_buff_wr <= 0;
	case (d_state)
	0: begin
		if (io_rd || io_wr) begin
			// the lowest slot with a request bit is served (scsi_cache E_IDLE),
			// with the address and block count on the bus in this cycle --
			// which is how a merged request goes astray
			d_slot  = (io_rd_v[0] | io_wr_v[0]) ? 0 : (io_rd_v[1] | io_wr_v[1]) ? 1 : 2;
			d_lba   <= io_lba;
			d_lat   <= dev_lat;              // short but non-zero round trip (default 40)
			if (dev_lat_jit != 0) begin
				dev_lcg = dev_lcg * 1103515245 + 12345;
				d_lat <= dev_lat + ((dev_lcg >> 8) % (dev_lat_jit + 1));
			end
			d_win   = (d_slot == 2) && (io_lba >= 32'h4000_0000);
			d_words = (io_rd_v[d_slot] && d_win) ? (io_blk_cnt + 1) * 256 : 256;
			if (d_slot != 2 && (io_lba >= NBLK || io_blk_cnt != 0)) bad_disk_req <= bad_disk_req + 1;
			if (d_win && io_rd_v[d_slot]) d_r = cdwin_dpi_read(io_lba, (io_blk_cnt + 1) * 512);
			if (d_win && io_rd_v[d_slot] && io_lba == 32'h7C00_0000) begin frame_reads <= frame_reads + 1; frame_blk <= io_blk_cnt; end
			if (d_win && io_rd_v[d_slot] && io_lba == 32'h7ECC_0000) stat_reads <= stat_reads + 1;
			if (io_rd_v[d_slot] && d_slot != 2) begin
				disk_rd_reqs <= disk_rd_reqs + 1;
				// request n of the command (n >= 1) while sector n-1 still has
				// more than the 16-byte FIFO (plus slack) left for the guest
				if (rd_track && (disk_rd_reqs - rd_base) * 512 - rd_drained > 32) begin
					rd_ovl <= rd_ovl + 1;
					if ((disk_rd_reqs - rd_base) * 512 - rd_drained > rd_ovl_max) rd_ovl_max <= (disk_rd_reqs - rd_base) * 512 - rd_drained;
				end
			end
			d_state <= io_rd_v[d_slot] ? 1 : 3;
		end
	end
	// ---- read: hold ack high while the 256 words stream in
	1: begin
		if (d_lat != 0) d_lat <= d_lat - 1;
		else begin io_ack[d_slot] <= 1'b1; d_i <= 0; d_state <= 2; end
	end
	2: begin
		if (d_i < d_words) begin
			sd_buff_addr <= d_i[12:0];
			if (d_win) begin
				// the DPI bytes come back as 32-bit ints: narrow them first
				d_b0 = cdwin_dpi_rbyte(d_i*2);
				d_b1 = cdwin_dpi_rbyte(d_i*2 + 1);
				sd_buff_dout <= {d_b0, d_b1};
			end
			else sd_buff_dout <= (d_lba < NBLK) ? {disk[d_lba*512 + d_i*2], disk[d_lba*512 + d_i*2 + 1]} : 16'h0000;
			sd_buff_wr   <= 1;
			d_i          <= d_i + 1;
		end
		else begin io_ack <= 3'b000; d_state <= 0; end
	end
	// ---- write: same handshake, sampling sd_buff_din.  sbuf's port S read
	// (q_s) is REGISTERED, so sd_buff_din this cycle reflects the address
	// driven LAST cycle.  Drive addr = d_i and capture the word for d_i-1;
	// advancing the address AND capturing on the same index (as a naive
	// model does) reads every word one slot stale -- a 1-word (2-byte)
	// offset that looks like an RTL write bug but is purely a model latency
	// error.  The real platform (hps_io) and sim_blkdevice.cpp both let the
	// address settle before sampling, exactly like this.
	3: begin
		if (d_lat != 0) d_lat <= d_lat - 1;
		else begin io_ack[d_slot] <= 1'b1; d_i <= 0; d_state <= 4; end
	end
	4: begin
		// TWO-cycle round trip: the tb's sd_buff_addr register delays the
		// address one cycle, and sbuf's q_s read register delays the data a
		// second, so sd_buff_din reflects the address driven TWO cycles ago.
		if (d_i >= 2 && d_i < 258) begin
			if (d_win) begin
				cdwin_dpi_wbyte((d_i-2)*2,     sd_buff_din[15:8]);
				cdwin_dpi_wbyte((d_i-2)*2 + 1, sd_buff_din[7:0]);
			end
			else if (d_lba < NBLK) begin
				disk[d_lba*512 + (d_i-2)*2]     <= sd_buff_din[15:8];
				disk[d_lba*512 + (d_i-2)*2 + 1] <= sd_buff_din[7:0];
			end
		end
		if (d_i < 258) begin
			if (d_i < 256) sd_buff_addr <= d_i[12:0];
			d_i <= d_i + 1;
		end
		else begin
			io_ack <= 3'b000; d_state <= 0;
			if (d_win) begin cdwin_dpi_write(d_lba); win_writes <= win_writes + 1; end
			else begin
				wr_blocks <= wr_blocks + 1;
				wr_lba_log[wr_blocks % 256] <= d_lba;
				wr_ackfall <= cyc;
			end
		end
	end
	endcase
end

//----------------------------------------------------------------------------
// bus tasks
//----------------------------------------------------------------------------
integer fails = 0, checks = 0;

task expect8(input [8*24:1] what, input [7:0] got, input [7:0] want);
	begin
		checks = checks + 1;
		if (got !== want) begin
			fails = fails + 1;
			$display("  FAIL %0s: got %02X want %02X", what, got, want);
		end
	end
endtask

task expect_bits(input [8*24:1] what, input [7:0] got, input [7:0] mask);
	begin
		checks = checks + 1;
		if ((got & mask) !== mask) begin
			fails = fails + 1;
			$display("  FAIL %0s: got %02X, missing bits %02X", what, got, mask & ~got);
		end
	end
endtask

task reg_wr(input [3:0] r, input [7:0] d);
	begin
		@(negedge clk); sel = 1; write = 1; rs = r; wdata = d;
		@(negedge clk); sel = 0; write = 0;
	end
endtask

task reg_rd(input [3:0] r, output [7:0] d);
	begin
		@(negedge clk); sel = 1; write = 0; rs = r;
		#1 d = rdata;
		@(negedge clk); sel = 0;
	end
endtask

// peek without asserting sel, so polling loops consume nothing
task reg_peek(input [3:0] r, output [7:0] d);
	begin
		@(negedge clk); rs = r; #1 d = rdata;
	end
endtask

task pdma_wr(input [7:0] b);
	integer g;
	begin
		g = 0;
		@(negedge clk); dma_wr = 1; dma_wdata = b;
		@(negedge clk);
		while (!dma_valid && g < 40000) begin @(negedge clk); g = g + 1; end
		if (!dma_valid) begin
			fails = fails + 1;
			$display("  FAIL pdma_wr(%02X) never acked", b);
		end
		dma_wr = 0;
	end
endtask

task pdma_rd(output [7:0] b);
	integer g;
	begin
		g = 0;
		@(negedge clk); dma_rd = 1;
		@(negedge clk);
		while (!dma_valid && g < 40000) begin @(negedge clk); g = g + 1; end
		if (!dma_valid) begin
			fails = fails + 1;
			$display("  FAIL pdma_rd never acked");
		end
		b = dma_rdata;
		dma_rd = 0;
	end
endtask

// wait for the chip to raise INT; ok = 0 on timeout
task wait_irq(input integer limit, output integer ok);
	integer g;
	begin
		g = 0;
		while (!irq && g < limit) begin @(negedge clk); g = g + 1; end
		ok = irq ? 1 : 0;
		if (!ok) begin
			fails = fails + 1;
			$display("  FAIL no interrupt within %0d cycles", limit);
		end
	end
endtask

// the driver's read order: STAT, STEP, then INTR last (section 2.2)
task read_regs(output [7:0] st_o, output [7:0] sp_o, output [7:0] it_o);
	begin
		reg_rd(R_STAT, st_o);
		reg_rd(R_STEP, sp_o);
		reg_rd(R_INTR, it_o);
	end
endtask

task set_tc(input [15:0] n);
	begin
		reg_wr(R_TCL, n[7:0]);
		reg_wr(R_TCM, n[15:8]);
	end
endtask

//----------------------------------------------------------------------------
// stimulus
//----------------------------------------------------------------------------
reg [7:0] st, sp, it, ff, b;
integer ok, k, guard;
reg [7:0] cdb [0:11];

// ---- ROM dialect: DMA select, then CDB via FIFO writes + a trailing PDMA
// byte.  `n` = CDB length.  Leaves the chip at the command's data/status phase.
task rom_command(input integer n);
	integer j;
	begin
		reg_wr(R_SELID, sel_id);
		reg_wr(R_CMD, 8'h01);                  // flush FIFO
		set_tc(16'd1);
		reg_wr(R_CMD, 8'hC1);                  // DMA select w/o ATN
		reg_wr(R_CMD, 8'h01);                  // SCSICmd: flush
		set_tc(16'd1);
		reg_wr(R_CMD, 8'h90);                  // DMA transfer info in CMD phase
		for (j = 0; j < n-1; j = j + 1) reg_wr(R_FIFO, cdb[j]);
		pdma_wr(cdb[n-1]);                     // last byte retires TC
	end
endtask

// ---- Unix dialect: preload the FIFO, then one of the four select forms.
task unix_select(input [7:0] selcmd, input integer n, input integer identify);
	integer j;
	begin
		reg_wr(R_SELID, sel_id);
		reg_wr(R_CMD, 8'h01);                  // flush
		if (identify) reg_wr(R_FIFO, 8'h80);   // IDENTIFY, LUN 0, no disconnect
		for (j = 0; j < n; j = j + 1) reg_wr(R_FIFO, cdb[j]);
		reg_wr(R_CMD, selcmd);
	end
endtask

integer blk, byi;
integer t20_wr, t20_col;

initial begin
	for (blk = 0; blk < NBLK; blk = blk + 1)
		for (byi = 0; byi < 512; byi = byi + 1)
			disk[blk*512 + byi] = (blk*7 + byi) & 8'hFF;

	$display("== tb_ncr53c96 ==");
	repeat (4) @(negedge clk);
	nreset = 1;
	repeat (4) @(negedge clk);

	// mount: 64 blocks of 512 bytes
	img_size = 64*512;
	img_mounted = 1; @(negedge clk); @(negedge clk); img_mounted = 0;
	repeat (4) @(negedge clk);

	reg_wr(R_CMD, 8'h02);                      // chip reset
	repeat (4) @(negedge clk);

	//------------------------------------------------------------------
	$display("-- T1  ROM dialect: TEST UNIT READY");
	//------------------------------------------------------------------
	cdb[0]=8'h00; cdb[1]=0; cdb[2]=0; cdb[3]=0; cdb[4]=0; cdb[5]=0;
	rom_command(6);
	wait_irq(500, ok);
	read_regs(st, sp, it);
	expect_bits("T1 intr BS|FC", it, I_BUS | I_FC);
	expect8("T1 phase STATUS", {5'd0, st[2:0]}, {5'd0, PH_STAT});
	reg_wr(R_CMD, 8'h11);                      // ICCS
	wait_irq(500, ok);
	read_regs(st, sp, it);
	expect_bits("T1 iccs FC", it, I_FC);
	reg_rd(R_FIFO, b); expect8("T1 status GOOD", b, 8'h00);
	reg_rd(R_FIFO, b); expect8("T1 msg CMDCOMP", b, 8'h00);
	reg_wr(R_CMD, 8'h12);                      // message accept
	wait_irq(500, ok);
	read_regs(st, sp, it);
	expect_bits("T1 disconnect", it, I_DISC);

	//------------------------------------------------------------------
	$display("-- T2  ROM dialect: READ(6) block 3, first 16 bytes");
	//------------------------------------------------------------------
	cdb[0]=8'h08; cdb[1]=8'h00; cdb[2]=8'h00; cdb[3]=8'h03; cdb[4]=8'h01; cdb[5]=8'h00;
	rom_command(6);
	wait_irq(500, ok);
	read_regs(st, sp, it);
	expect_bits("T2 intr BS|FC", it, I_BUS | I_FC);
	expect8("T2 phase DATA IN", {5'd0, st[2:0]}, {5'd0, PH_DIN});
	// the ROM's 16-byte burst: TC=16, $90, gate on TC0 + FIFO>=16, drain
	set_tc(16'd16);
	reg_wr(R_CMD, 8'h90);
	guard = 0;
	reg_peek(R_STAT, st);
	reg_peek(R_FFLAG, ff);
	while (!(st[4] && ff[4]) && guard < 100000) begin
		@(negedge clk);
		reg_peek(R_STAT, st);
		reg_peek(R_FFLAG, ff);
		guard = guard + 1;
	end
	if (guard >= 100000) begin
		fails = fails + 1;
		$display("  FAIL T2 burst never gated (stat=%02X fflag=%02X)", st, ff);
	end
	for (k = 0; k < 16; k = k + 1) begin
		pdma_rd(b);
		expect8("T2 data", b, (3*7 + k) & 8'hFF);
	end
	wait_irq(500, ok);
	read_regs(st, sp, it);
	expect_bits("T2 burst done BS", it, I_BUS);

	//------------------------------------------------------------------
	$display("-- T3  Unix dialect: $42 SELATN, FIFO-preloaded IDENTIFY+CDB");
	//------------------------------------------------------------------
	reg_wr(R_CMD, 8'h02); repeat (4) @(negedge clk);   // chip reset between cases
	cdb[0]=8'h00; cdb[1]=0; cdb[2]=0; cdb[3]=0; cdb[4]=0; cdb[5]=0;
	unix_select(8'h42, 6, 1);
	wait_irq(500, ok);
	read_regs(st, sp, it);
	$display("   T3 stat=%02X step=%02X intr=%02X", st, sp, it);
	expect_bits("T3 intr BS|FC", it, I_BUS | I_FC);
	expect8("T3 step 4", sp & 8'h07, 8'd4);
	expect8("T3 phase STATUS", {5'd0, st[2:0]}, {5'd0, PH_STAT});
	reg_rd(R_FFLAG, ff);
	expect8("T3 FIFO drained", ff & 8'h1F, 8'd0);

	//------------------------------------------------------------------
	$display("-- T4  Unix dialect: $41 SELNATN (REQUEST SENSE, no IDENTIFY)");
	//------------------------------------------------------------------
	reg_wr(R_CMD, 8'h02); repeat (4) @(negedge clk);
	cdb[0]=8'h03; cdb[1]=0; cdb[2]=0; cdb[3]=0; cdb[4]=8'h12; cdb[5]=0;
	unix_select(8'h41, 6, 0);
	wait_irq(500, ok);
	read_regs(st, sp, it);
	$display("   T4 stat=%02X step=%02X intr=%02X", st, sp, it);
	expect_bits("T4 intr BS|FC", it, I_BUS | I_FC);
	expect8("T4 step 4", sp & 8'h07, 8'd4);
	expect8("T4 phase DATA IN", {5'd0, st[2:0]}, {5'd0, PH_DIN});

	//------------------------------------------------------------------
	$display("-- T5  Unix dialect: $43 SELATNS (stop after IDENTIFY)");
	//------------------------------------------------------------------
	reg_wr(R_CMD, 8'h02); repeat (4) @(negedge clk);
	cdb[0]=8'h00; cdb[1]=0; cdb[2]=0; cdb[3]=0; cdb[4]=0; cdb[5]=0;
	unix_select(8'h43, 6, 1);
	wait_irq(500, ok);
	read_regs(st, sp, it);
	$display("   T5 stat=%02X step=%02X intr=%02X", st, sp, it);
	expect_bits("T5 intr BS|FC", it, I_BUS | I_FC);
	expect8("T5 step 1", sp & 8'h07, 8'd1);
	expect8("T5 phase MESSAGE OUT", {5'd0, st[2:0]}, {5'd0, PH_MOUT});
	checks = checks + 1;
	if (it & I_ILL) begin
		fails = fails + 1;
		$display("  FAIL T5 chip reported ILLEGAL COMMAND for $43 SELATNS");
	end

	//------------------------------------------------------------------
	$display("-- T5b negotiation: SDTR out, MESSAGE REJECT in, then the CDB");
	//------------------------------------------------------------------
	// The driver flushes the CDB it had preloaded behind the IDENTIFY,
	// builds the SDTR message, and transfers it with a non-DMA TI.
	reg_rd(R_FFLAG, ff);
	$display("   T5b FIFO after $43 holds %0d byte(s) (the un-sent CDB)", ff & 8'h1F);
	reg_wr(R_CMD, 8'h01);                      // flush
	reg_wr(R_FIFO, 8'h01);                     // EXTENDED MESSAGE
	reg_wr(R_FIFO, 8'h03);                     // length 3
	reg_wr(R_FIFO, 8'h01);                     // SDTR
	reg_wr(R_FIFO, 8'd25);                     // transfer period
	reg_wr(R_FIFO, 8'd15);                     // REQ/ACK offset
	reg_wr(R_CMD, 8'h10);                      // TRANS, no DMA bit
	wait_irq(500, ok);
	read_regs(st, sp, it);
	$display("   T5b msgout stat=%02X step=%02X intr=%02X", st, sp, it);
	expect_bits("T5b msgout BS", it, I_BUS);
	expect8("T5b phase MESSAGE IN", {5'd0, st[2:0]}, {5'd0, PH_MIN});
	// message in, one byte per TI, completing with FC
	reg_wr(R_CMD, 8'h01);
	reg_wr(R_CMD, 8'h10);
	wait_irq(500, ok);
	read_regs(st, sp, it);
	expect_bits("T5b msgin FC", it, I_FC);
	reg_rd(R_FFLAG, ff);
	expect8("T5b one message byte", ff & 8'h1F, 8'd1);
	reg_rd(R_FIFO, b);
	expect8("T5b MESSAGE REJECT", b, 8'h07);
	// MSGOK must NOT disconnect here — the target is still connected and
	// wants the command it was selected for.
	reg_wr(R_CMD, 8'h12);
	wait_irq(500, ok);
	read_regs(st, sp, it);
	$display("   T5b msgok  stat=%02X step=%02X intr=%02X", st, sp, it);
	checks = checks + 1;
	if (it & I_DISC) begin
		fails = fails + 1;
		$display("  FAIL T5b MSGOK after a rejected negotiation disconnected the bus");
	end
	expect8("T5b phase COMMAND", {5'd0, st[2:0]}, {5'd0, PH_CMD});
	// now the CDB, from COMMAND phase
	cdb[0]=8'h08; cdb[1]=8'h00; cdb[2]=8'h00; cdb[3]=8'h05; cdb[4]=8'h01; cdb[5]=8'h00;
	for (k = 0; k < 6; k = k + 1) reg_wr(R_FIFO, cdb[k]);
	reg_wr(R_CMD, 8'h10);
	wait_irq(500, ok);
	read_regs(st, sp, it);
	$display("   T5b cmd    stat=%02X step=%02X intr=%02X", st, sp, it);
	expect_bits("T5b cmd BS|FC", it, I_BUS | I_FC);
	expect8("T5b phase DATA IN", {5'd0, st[2:0]}, {5'd0, PH_DIN});
	// and the data really is block 5
	set_tc(16'd16);
	reg_wr(R_CMD, 8'h90);
	guard = 0;
	reg_peek(R_STAT, st);
	reg_peek(R_FFLAG, ff);
	while (!(st[4] && ff[4]) && guard < 100000) begin
		@(negedge clk);
		reg_peek(R_STAT, st);
		reg_peek(R_FFLAG, ff);
		guard = guard + 1;
	end
	if (guard >= 100000) begin
		fails = fails + 1;
		$display("  FAIL T5b burst never gated (stat=%02X fflag=%02X)", st, ff);
	end
	for (k = 0; k < 16; k = k + 1) begin
		pdma_rd(b);
		expect8("T5b data", b, (5*7 + k) & 8'hFF);
	end

	//------------------------------------------------------------------
	$display("-- T6  Unix dialect: $46 SELATN3 (IDENTIFY + 2 tag bytes + CDB)");
	//------------------------------------------------------------------
	reg_wr(R_CMD, 8'h02); repeat (4) @(negedge clk);
	cdb[0]=8'h00; cdb[1]=0; cdb[2]=0; cdb[3]=0; cdb[4]=0; cdb[5]=0;
	reg_wr(R_SELID, 8'h00);
	reg_wr(R_CMD, 8'h01);
	reg_wr(R_FIFO, 8'hC0);                     // IDENTIFY w/ disconnect
	reg_wr(R_FIFO, 8'h20);                     // SIMPLE QUEUE TAG
	reg_wr(R_FIFO, 8'h05);                     // tag number
	for (k = 0; k < 6; k = k + 1) reg_wr(R_FIFO, cdb[k]);
	reg_wr(R_CMD, 8'h46);
	wait_irq(500, ok);
	read_regs(st, sp, it);
	$display("   T6 stat=%02X step=%02X intr=%02X", st, sp, it);
	expect_bits("T6 intr BS|FC", it, I_BUS | I_FC);
	expect8("T6 step 4", sp & 8'h07, 8'd4);
	expect8("T6 phase STATUS", {5'd0, st[2:0]}, {5'd0, PH_STAT});
	checks = checks + 1;
	if (it & I_ILL) begin
		fails = fails + 1;
		$display("  FAIL T6 chip reported ILLEGAL COMMAND for $46 SELATN3");
	end

	//------------------------------------------------------------------
	$display("-- T7  selection timeout on an empty target");
	//------------------------------------------------------------------
	// ID 5: IDs 0/1 are the disks and ID 3 is the CD-ROM drive, which
	// answers selection even with no disc (the AppleCD driver polls it)
	reg_wr(R_CMD, 8'h02); repeat (4) @(negedge clk);
	reg_wr(R_SELID, 8'h05);
	reg_wr(R_CMD, 8'h01);
	reg_wr(R_FIFO, 8'h80);
	for (k = 0; k < 6; k = k + 1) reg_wr(R_FIFO, 8'h00);
	reg_wr(R_CMD, 8'h42);
	wait_irq(500, ok);
	read_regs(st, sp, it);
	reg_rd(R_FFLAG, ff);
	$display("   T7 stat=%02X step=%02X intr=%02X fflag=%02X", st, sp, it, ff);
	expect_bits("T7 selection timeout DISC", it, I_DISC);
	expect8("T7 step 0", sp & 8'h07, 8'd0);
	// The preloaded bytes must still be countable.  A/UX's c94 driver
	// compares FIFO-flags & $1F against the 7 bytes it pushed to tell
	// "nobody answered" (benign) from "the target vanished mid-command"
	// (fatal protocol error).  Flushing here reports the fatal one for
	// every empty SCSI ID.
	expect8("T7 FIFO still holds IDENTIFY+CDB", ff & 8'h1F, 8'd7);

	//------------------------------------------------------------------
	$display("-- T8  after a timeout the chip still selects the real target");
	//------------------------------------------------------------------
	reg_wr(R_CMD, 8'h01);                      // driver flushes, as it does
	cdb[0]=8'h12; cdb[1]=0; cdb[2]=0; cdb[3]=0; cdb[4]=8'h24; cdb[5]=0;
	unix_select(8'h42, 6, 1);
	wait_irq(500, ok);
	read_regs(st, sp, it);
	$display("   T8 stat=%02X step=%02X intr=%02X", st, sp, it);
	expect_bits("T8 intr BS|FC", it, I_BUS | I_FC);
	checks = checks + 1;
	if (it & (I_DISC | I_RESEL)) begin
		fails = fails + 1;
		$display("  FAIL T8 stale DISC/RESEL survived into the next select");
	end
	expect8("T8 step 4", sp & 8'h07, 8'd4);
	expect8("T8 phase DATA IN", {5'd0, st[2:0]}, {5'd0, PH_DIN});

	//------------------------------------------------------------------
	$display("-- T9  A/UX 3.1 c94 driver, verbatim register sequence");
	//------------------------------------------------------------------
	// Transcribed from the shipped kernel (docs/scsi/aux-c94-driver.md).
	// Every check below is a branch the driver actually takes; failing any
	// of them lands in $1004fd88, which defaults req->ret to 8 =
	// "Protocol Error Processing SCSI request".
	reg_wr(R_CMD, 8'h02); repeat (4) @(negedge clk);

	//   scsiselect: $01, FIFO <- $C0 + CDB, SELID, $42
	reg_wr(R_CMD, 8'h01);
	reg_wr(R_FIFO, 8'hC0);                     // IDENTIFY, disconnect OK
	cdb[0]=8'h08; cdb[1]=8'h00; cdb[2]=8'h00; cdb[3]=8'h00; cdb[4]=8'h01; cdb[5]=8'h00;
	for (k = 0; k < 6; k = k + 1) reg_wr(R_FIFO, cdb[k]);
	reg_wr(R_SELID, 8'h00);
	reg_wr(R_CMD, 8'h42);

	//   the select-completion handler ($1004fb4e)
	wait_irq(500, ok);
	read_regs(st, sp, it);
	$display("   T9 select : stat=%02X step=%02X intr=%02X", st, sp, it);
	checks = checks + 1;
	if (it & I_RESEL) begin
		fails = fails + 1; $display("  FAIL T9 RESEL set at select - driver backs off");
	end
	checks = checks + 1;
	if (it & I_DISC) begin
		fails = fails + 1; $display("  FAIL T9 DISC set at select - driver reports a select failure");
	end
	expect8("T9 intr is exactly BS|FC", it & 8'h18, 8'h18);
	//   dophase: COMMAND (2), 4 and 5 are hard errors
	checks = checks + 1;
	if (st[2:0] == PH_CMD || st[2:0] == 3'd4 || st[2:0] == 3'd5) begin
		fails = fails + 1;
		$display("  FAIL T9 dophase rejects phase %0d", st[2:0]);
	end
	expect8("T9 phase DATA IN", {5'd0, st[2:0]}, {5'd0, PH_DIN});

	//   scsidma: TC=256 (TCM written FIRST), $90, then DREQ-paced move.w
	for (blk = 0; blk < 2; blk = blk + 1) begin
		reg_wr(R_TCM, 8'h01);
		reg_wr(R_TCL, 8'h00);
		reg_wr(R_CMD, 8'h90);
		for (k = 0; k < 128; k = k + 1) begin
			guard = 0;
			while (!drq && guard < 100000) begin @(negedge clk); guard = guard + 1; end
			if (guard >= 100000) begin
				fails = fails + 1;
				$display("  FAIL T9 DREQ never asserted, chunk %0d word %0d", blk, k);
				k = 128;
			end
			else begin
				pdma_rd(b);
				if (blk == 0 && k == 0) expect8("T9 first data byte", b, 8'h00);
				pdma_rd(b);
			end
		end
		wait_irq(2000, ok);
		read_regs(st, sp, it);
		$display("   T9 chunk%0d: stat=%02X step=%02X intr=%02X", blk, st, sp, it);
		expect_bits("T9 chunk BS", it, I_BUS);
	end
	$display("   T9 after data: phase=%0d", st[2:0]);
	expect8("T9 phase STATUS after 512 bytes", {5'd0, st[2:0]}, {5'd0, PH_STAT});

	//   status phase: $11 ICCS.  The handler at $1004ec36 FAILS on BS and
	//   only succeeds on FC — raising BS|FC here would break A/UX.
	reg_wr(R_CMD, 8'h11);
	wait_irq(500, ok);
	read_regs(st, sp, it);
	$display("   T9 iccs   : stat=%02X step=%02X intr=%02X", st, sp, it);
	checks = checks + 1;
	if (it & I_BUS) begin
		fails = fails + 1;
		$display("  FAIL T9 ICCS raised BS - A/UX treats that as a failure");
	end
	expect_bits("T9 iccs FC", it, I_FC);
	reg_rd(R_FIFO, b); expect8("T9 status byte", b, 8'h00);
	reg_rd(R_FIFO, b); expect8("T9 message byte", b, 8'h00);
	//   the driver then reads the FIFO ONE MORE TIME (tst.b) and asserts
	//   ATN if it is non-zero — which would send it looking for MESSAGE OUT
	reg_rd(R_FIFO, b);
	expect8("T9 third FIFO read is 0 (no spurious SET ATN)", b, 8'h00);
	reg_wr(R_CMD, 8'h12);
	wait_irq(500, ok);
	read_regs(st, sp, it);
	$display("   T9 msgok  : stat=%02X step=%02X intr=%02X", st, sp, it);
	expect_bits("T9 disconnect", it, I_DISC);

	//------------------------------------------------------------------
	$display("-- T10 ROM SCSI Manager: bulk READ(6) as 16-byte $90 chunks");
	//------------------------------------------------------------------
	// This is what A/UX Startup's saio ACTUALLY does, transcribed from
	// qemu-system-m68k master booting this exact ROM+disk: the ROM's
	// original-API SCSIRead reads a block as a run of TC=16 $90 chunks, each
	// drained FULLY on DRQ (lower_drq at fifo<2) and only THEN a BS
	// interrupt (reg[4]=0x91, phase still DATA IN).  The completion never
	// arrives with data in the FIFO; the LAST chunk drains, then flips to
	// STATUS.  Earlier this test asserted the opposite (16 bytes left in the
	// FIFO at completion) -- that scenario does not occur, and modelling it
	// dropped DREQ and produced the flashing-"?" regression.  512 bytes = 32
	// chunks of 16.
	reg_wr(R_CMD, 8'h02); repeat (4) @(negedge clk);
	cdb[0]=8'h08; cdb[1]=8'h00; cdb[2]=8'h00; cdb[3]=8'h05; cdb[4]=8'h01; cdb[5]=8'h00;
	rom_command(6);
	wait_irq(500, ok);
	read_regs(st, sp, it);
	expect_bits("T10 intr BS|FC", it, I_BUS | I_FC);
	expect8("T10 phase DATA IN", {5'd0, st[2:0]}, {5'd0, PH_DIN});
	for (blk = 0; blk < 32; blk = blk + 1) begin
		set_tc(16'd16);
		reg_wr(R_CMD, 8'h90);
		// ROM bulk gate: poll STATUS.TC0 + FIFO-flags bit 4, then drain 16
		guard = 0;
		reg_peek(R_STAT, st);
		reg_peek(R_FFLAG, ff);
		while (!(st[4] && ff[4]) && guard < 100000) begin
			@(negedge clk);
			reg_peek(R_STAT, st);
			reg_peek(R_FFLAG, ff);
			guard = guard + 1;
		end
		if (guard >= 100000) begin
			fails = fails + 1;
			$display("  FAIL T10 chunk %0d never gated (stat=%02X fflag=%02X)", blk, st, ff);
		end
		// DREQ must be up with a full chunk waiting, and stay up through it
		checks = checks + 1;
		if (!drq) begin
			fails = fails + 1;
			$display("  FAIL T10 DREQ down with chunk %0d in the FIFO", blk);
		end
		for (k = 0; k < 16; k = k + 1) begin
			pdma_rd(b);
			expect8("T10 data", b, (5*7 + blk*16 + k) & 8'hFF);
		end
		wait_irq(2000, ok);
		checks = checks + 1;
		if (!ok) begin
			fails = fails + 1;
			$display("  FAIL T10 chunk %0d never completed", blk);
		end
		read_regs(st, sp, it);
		reg_peek(R_FFLAG, ff);
		expect_bits("T10 chunk BS", it, I_BUS);
		// the completion always arrives with the FIFO already drained
		expect8("T10 FIFO empty at completion", ff & 8'h1F, 8'd0);
		if (blk < 31)
			expect8("T10 mid chunk still DATA IN", {5'd0, st[2:0]}, {5'd0, PH_DIN});
		else
			expect8("T10 last chunk flips to STATUS", {5'd0, st[2:0]}, {5'd0, PH_STAT});
	end
	reg_wr(R_CMD, 8'h11);
	wait_irq(500, ok);
	read_regs(st, sp, it);
	expect_bits("T10 iccs FC", it, I_FC);
	reg_rd(R_FIFO, b); expect8("T10 status GOOD", b, 8'h00);
	reg_rd(R_FIFO, b); expect8("T10 msg CMDCOMP", b, 8'h00);
	reg_wr(R_CMD, 8'h12);
	wait_irq(500, ok);
	read_regs(st, sp, it);
	expect_bits("T10 disconnect", it, I_DISC);

	//------------------------------------------------------------------
	$display("-- T11 ROM polled read: per-byte $10, phase flips ON the last byte");
	//------------------------------------------------------------------
	// Original-API SCSIRead (non-blind): one non-DMA TI per byte, INTR
	// checked as (INTR & $30) == $10 each time, byte loop ends by count,
	// then SCSIComplete polls for the phase change.  The last byte must
	// therefore arrive with phase ALREADY showing STATUS (QEMU leaves the
	// last byte in the FIFO for exactly this reason).
	reg_wr(R_CMD, 8'h02); repeat (4) @(negedge clk);
	cdb[0]=8'h12; cdb[1]=8'h00; cdb[2]=8'h00; cdb[3]=8'h00; cdb[4]=8'h24; cdb[5]=8'h00;
	rom_command(6);
	wait_irq(500, ok);
	read_regs(st, sp, it);
	expect_bits("T11 intr BS|FC", it, I_BUS | I_FC);
	expect8("T11 phase DATA IN", {5'd0, st[2:0]}, {5'd0, PH_DIN});
	for (k = 0; k < 36; k = k + 1) begin
		reg_wr(R_CMD, 8'h10);
		wait_irq(2000, ok);
		checks = checks + 1;
		if (!ok) begin
			fails = fails + 1;
			$display("  FAIL T11 no interrupt for byte %0d", k);
		end
		read_regs(st, sp, it);
		expect8("T11 INTR&$30 is BS", it & 8'h30, 8'h10);
		if (k < 35)
			expect8("T11 mid byte DATA IN", {5'd0, st[2:0]}, {5'd0, PH_DIN});
		else begin
			expect8("T11 last byte: STATUS", {5'd0, st[2:0]}, {5'd0, PH_STAT});
			reg_peek(R_FFLAG, ff);
			expect8("T11 last byte in FIFO", ff & 8'h1F, 8'd1);
		end
		reg_rd(R_FIFO, b);
		if (k == 0) expect8("T11 inquiry byte 0", b, 8'h00);
	end
	reg_wr(R_CMD, 8'h11);
	wait_irq(500, ok);
	read_regs(st, sp, it);
	expect_bits("T11 iccs FC", it, I_FC);
	reg_rd(R_FIFO, b); expect8("T11 status GOOD", b, 8'h00);
	reg_rd(R_FIFO, b); expect8("T11 msg CMDCOMP", b, 8'h00);
	reg_wr(R_CMD, 8'h12);
	wait_irq(500, ok);
	read_regs(st, sp, it);
	expect_bits("T11 disconnect", it, I_DISC);

	//------------------------------------------------------------------
	$display("-- T12 A/UX Startup saio: 512-byte READ(6) as 2x256 $90 chunks");
	//------------------------------------------------------------------
	// Transcribed VERBATIM from qemu-system-m68k master booting this exact
	// ROM+disk (hw/scsi/esp.c trace, 2026-09-01): saio issues $42 SELATN
	// with a FIFO-preloaded IDENTIFY($C0)+CDB, then reads the 512-byte block
	// as TWO $90 DMA chunks of TC=256 bytes each, draining every chunk fully
	// on DRQ before the interrupt.  The FIRST chunk ends with BS and phase
	// still DATA IN (reg[4]=0x91); the SECOND ends with command-complete,
	// phase STATUS (reg[4]=0x93).  The completion NEVER arrives with data
	// still in the FIFO -- DRQ is up throughout the drain, down before the
	// interrupt.  This is the path A/UX Startup actually fails on hardware.
	reg_wr(R_CMD, 8'h02); repeat (4) @(negedge clk);
	reg_wr(R_CMD, 8'h01);                          // flush
	reg_wr(R_FIFO, 8'hC0);                         // IDENTIFY, disconnect OK
	cdb[0]=8'h08; cdb[1]=8'h00; cdb[2]=8'h00; cdb[3]=8'h01; cdb[4]=8'h01; cdb[5]=8'h00;
	for (k = 0; k < 6; k = k + 1) reg_wr(R_FIFO, cdb[k]);
	reg_wr(R_SELID, 8'h00);
	reg_wr(R_CMD, 8'h42);                          // SELATN
	wait_irq(500, ok);
	read_regs(st, sp, it);
	$display("   T12 select : stat=%02X step=%02X intr=%02X", st, sp, it);
	expect_bits("T12 select BS|FC", it, I_BUS | I_FC);
	expect8("T12 step 4", sp & 8'h07, 8'd4);
	expect8("T12 phase DATA IN", {5'd0, st[2:0]}, {5'd0, PH_DIN});
	for (blk = 0; blk < 2; blk = blk + 1) begin
		reg_wr(R_TCM, 8'h01); reg_wr(R_TCL, 8'h00);   // TC = 256 bytes
		reg_wr(R_CMD, 8'h90);                          // DMA TI
		// the Mac reads 16 bits per PDMA access: 128 word-accesses = 256
		// bytes.  DRQ (fifo_cnt>=2) gates each 2-byte access.
		for (k = 0; k < 128; k = k + 1) begin
			guard = 0;
			while (!drq && guard < 100000) begin @(negedge clk); guard = guard + 1; end
			if (guard >= 100000) begin
				fails = fails + 1;
				$display("  FAIL T12 DREQ never asserted, chunk %0d word %0d", blk, k);
				k = 128;
			end
			else begin
				pdma_rd(b);
				expect8("T12 data hi", b, (1*7 + blk*256 + k*2)     & 8'hFF);
				pdma_rd(b);
				expect8("T12 data lo", b, (1*7 + blk*256 + k*2 + 1) & 8'hFF);
			end
		end
		wait_irq(2000, ok);
		checks = checks + 1;
		if (!ok) begin
			fails = fails + 1;
			$display("  FAIL T12 chunk %0d never completed (the block-0 hang)", blk);
		end
		read_regs(st, sp, it);
		reg_peek(R_FFLAG, ff);
		$display("   T12 chunk%0d: stat=%02X intr=%02X fflag=%02X", blk, st, it, ff);
		expect_bits("T12 chunk BS", it, I_BUS);
		if (blk == 0)
			expect8("T12 chunk0 phase still DATA IN", {5'd0, st[2:0]}, {5'd0, PH_DIN});
		else
			expect8("T12 chunk1 phase STATUS", {5'd0, st[2:0]}, {5'd0, PH_STAT});
	end
	reg_wr(R_CMD, 8'h11);                          // ICCS
	wait_irq(500, ok);
	read_regs(st, sp, it);
	expect_bits("T12 iccs FC", it, I_FC);
	reg_rd(R_FIFO, b); expect8("T12 status GOOD", b, 8'h00);
	reg_rd(R_FIFO, b); expect8("T12 msg CMDCOMP", b, 8'h00);
	reg_wr(R_CMD, 8'h12);                          // message accept
	wait_irq(500, ok);
	read_regs(st, sp, it);
	expect_bits("T12 disconnect", it, I_DISC);

	//------------------------------------------------------------------
	$display("-- T13 multi-sector READ(6): 4 blocks (2048 B) across boundaries");
	//------------------------------------------------------------------
	// fsck reads the superblock as an 8 KB (16-sector) block; T10/T12 only
	// ever read ONE sector, so the sector-prefetch path (blocks_left>1, lba
	// advancing across boundaries) was untested.  A bug here reads correct
	// bytes for sector 0 and garbage after -- which is exactly how a valid
	// superblock reads back as "BAD SUPER BLOCK: MAGIC NUMBER WRONG".  Read
	// 4 sectors from LBA 5 in one $90 (TC spans sectors) and check every
	// byte advances block*7+offset across all four.
	reg_wr(R_CMD, 8'h02); repeat (4) @(negedge clk);
	cdb[0]=8'h08; cdb[1]=8'h00; cdb[2]=8'h00; cdb[3]=8'h05; cdb[4]=8'h04; cdb[5]=8'h00;
	rom_command(6);
	wait_irq(500, ok);
	read_regs(st, sp, it);
	expect_bits("T13 intr BS|FC", it, I_BUS | I_FC);
	expect8("T13 phase DATA IN", {5'd0, st[2:0]}, {5'd0, PH_DIN});
	// one $90 with TC = 2048, DRQ-paced 2-byte reads (1024 accesses)
	set_tc(16'd2048);
	reg_wr(R_CMD, 8'h90);
	for (k = 0; k < 1024; k = k + 1) begin
		guard = 0;
		while (!drq && guard < 100000) begin @(negedge clk); guard = guard + 1; end
		if (guard >= 100000) begin
			fails = fails + 1;
			$display("  FAIL T13 DREQ stalled at access %0d (byte %0d, sector %0d)",
			         k, k*2, (k*2)/512);
			k = 1024;
		end
		else begin
			pdma_rd(b);
			expect8("T13 hi", b, ((5 + (k*2)/512)*7     + ((k*2)   % 512)) & 8'hFF);
			pdma_rd(b);
			expect8("T13 lo", b, ((5 + (k*2+1)/512)*7   + ((k*2+1) % 512)) & 8'hFF);
		end
	end
	wait_irq(2000, ok);
	read_regs(st, sp, it);
	$display("   T13 done : stat=%02X intr=%02X", st, it);
	expect_bits("T13 completion BS", it, I_BUS);
	expect8("T13 phase STATUS after 2048 bytes", {5'd0, st[2:0]}, {5'd0, PH_STAT});

	//------------------------------------------------------------------
	$display("-- T14 multi-sector WRITE(6) then read-back: 2 blocks at LBA 10");
	//------------------------------------------------------------------
	// A/UX's autorecovery WRITES to the disk (fsck repairs) as multi-sector
	// $90 DATA OUT transfers -- and the whole write path was untested.  A
	// corrupting write is exactly how a valid on-disk superblock reads back
	// with a wrong magic number after fsck "repairs" it.  Write a distinct
	// pattern across a 2-sector boundary, then read it back and require an
	// exact round-trip.
	reg_wr(R_CMD, 8'h02); repeat (4) @(negedge clk);
	cdb[0]=8'h0A; cdb[1]=8'h00; cdb[2]=8'h00; cdb[3]=8'h0A; cdb[4]=8'h02; cdb[5]=8'h00;
	rom_command(6);                                // select + WRITE(6) CDB
	wait_irq(500, ok);
	read_regs(st, sp, it);
	$display("   T14 wsel  : stat=%02X intr=%02X", st, it);
	expect_bits("T14 write select BS|FC", it, I_BUS | I_FC);
	expect8("T14 phase DATA OUT", {5'd0, st[2:0]}, {5'd0, PH_DOUT});
	// DATA OUT: TC = 1024, $90, then DRQ-paced byte writes
	reg_wr(R_CMD, 8'h01);                          // flush
	set_tc(16'd1024);
	reg_wr(R_CMD, 8'h90);
	for (k = 0; k < 1024; k = k + 1) begin
		guard = 0;
		while (!drq && guard < 100000) begin @(negedge clk); guard = guard + 1; end
		if (guard >= 100000) begin
			fails = fails + 1;
			$display("  FAIL T14 write DREQ stalled at byte %0d (sector %0d)", k, k/512);
			k = 1024;
		end
		else pdma_wr((k*5 + 3) & 8'hFF);
	end
	wait_irq(4000, ok);
	read_regs(st, sp, it);
	$display("   T14 wdone : stat=%02X intr=%02X blocks_written=%0d", st, it, wr_blocks);
	expect_bits("T14 write completion BS", it, I_BUS);
	expect8("T14 phase STATUS after write", {5'd0, st[2:0]}, {5'd0, PH_STAT});
	reg_wr(R_CMD, 8'h11); wait_irq(500, ok);       // ICCS
	reg_rd(R_FIFO, b); reg_rd(R_FIFO, b);
	reg_wr(R_CMD, 8'h12); wait_irq(500, ok);       // msgacc
	// now READ it back and require an exact round-trip
	reg_wr(R_CMD, 8'h02); repeat (4) @(negedge clk);
	cdb[0]=8'h08; cdb[1]=8'h00; cdb[2]=8'h00; cdb[3]=8'h0A; cdb[4]=8'h02; cdb[5]=8'h00;
	rom_command(6);
	wait_irq(500, ok);
	read_regs(st, sp, it);
	expect8("T14 readback phase DATA IN", {5'd0, st[2:0]}, {5'd0, PH_DIN});
	set_tc(16'd1024);
	reg_wr(R_CMD, 8'h90);
	for (k = 0; k < 512; k = k + 1) begin
		guard = 0;
		while (!drq && guard < 100000) begin @(negedge clk); guard = guard + 1; end
		if (guard >= 100000) begin
			fails = fails + 1;
			$display("  FAIL T14 readback DREQ stalled at access %0d", k);
			k = 512;
		end
		else begin
			pdma_rd(b);
			expect8("T14 rb hi", b, (k*2*5 + 3) & 8'hFF);
			pdma_rd(b);
			expect8("T14 rb lo", b, ((k*2+1)*5 + 3) & 8'hFF);
		end
	end
	wait_irq(2000, ok);
	read_regs(st, sp, it);
	expect8("T14 readback ends STATUS", {5'd0, st[2:0]}, {5'd0, PH_STAT});

	//------------------------------------------------------------------
	$display("-- T15 chunked WRITE(6): 4 blocks at LBA 20 as 8 x ($90 TC=256) -- the saio/fsck dialect");
	//------------------------------------------------------------------
	// Under A/UX Startup the ROM SCSI Manager splits one WRITE into many
	// $90 TIs of TC=256 (QEMU master esp trace of this ROM+disk: fsck's
	// 2KB superblock write-back is 8 x TC=256, cg flushes 32 x TC=256).
	// T14's single TC=1024 TI never exercised a TC expiry mid-sector, so
	// the old "trailing partial sector" flush went unseen: it flushed 256
	// real bytes plus a stale upper half per chunk, burned one block of
	// the CDB count per chunk, and flipped to STATUS halfway through the
	// data -- fsck's superblock landed smeared at 256 bytes/sector and
	// the magic number vanished.  Require: phase holds DATA OUT through
	// chunk 7, exactly 4 blocks flushed, and a byte-exact disk image.
	reg_wr(R_CMD, 8'h02); repeat (4) @(negedge clk);
	byi = wr_blocks;                               // blocks flushed so far
	cdb[0]=8'h0A; cdb[1]=8'h00; cdb[2]=8'h00; cdb[3]=8'h14; cdb[4]=8'h04; cdb[5]=8'h00;
	rom_command(6);                                // select + WRITE(6) LBA 20, 4 blocks
	wait_irq(500, ok);
	read_regs(st, sp, it);
	$display("   T15 wsel  : stat=%02X intr=%02X", st, it);
	expect_bits("T15 write select BS|FC", it, I_BUS | I_FC);
	expect8("T15 phase DATA OUT", {5'd0, st[2:0]}, {5'd0, PH_DOUT});
	reg_wr(R_CMD, 8'h01);                          // flush, as the ROM does
	for (blk = 0; blk < 8; blk = blk + 1) begin
		set_tc(16'd256);
		reg_wr(R_CMD, 8'h90);
		for (k = 0; k < 256; k = k + 1) begin
			guard = 0;
			while (!drq && guard < 100000) begin @(negedge clk); guard = guard + 1; end
			if (guard >= 100000) begin
				fails = fails + 1;
				$display("  FAIL T15 DREQ stalled at chunk %0d byte %0d", blk, k);
				k = 256;
			end
			else pdma_wr(((blk*256 + k)*11 + 7) & 8'hFF);
		end
		wait_irq(4000, ok);
		read_regs(st, sp, it);
		expect_bits("T15 chunk completion BS", it, I_BUS);
		if (blk != 7)
			expect8("T15 phase DATA OUT between chunks", {5'd0, st[2:0]}, {5'd0, PH_DOUT});
	end
	expect8("T15 phase STATUS after chunk 8", {5'd0, st[2:0]}, {5'd0, PH_STAT});
	reg_wr(R_CMD, 8'h11); wait_irq(500, ok);       // ICCS
	reg_rd(R_FIFO, b); expect8("T15 status GOOD", b, 8'h00);
	reg_rd(R_FIFO, b);
	reg_wr(R_CMD, 8'h12); wait_irq(500, ok);       // msgacc
	// the final flush is armed the same cycle STATUS is raised (a real
	// target completes with the last block still in its cache); let the
	// platform model drain it before inspecting the medium
	guard = 0;
	while (wr_blocks - byi != 4 && guard < 100000) begin @(negedge clk); guard = guard + 1; end
	$display("   T15 wdone : stat=%02X intr=%02X blocks_flushed=%0d", st, it, wr_blocks - byi);
	checks = checks + 1;
	if (wr_blocks - byi != 4) begin
		fails = fails + 1;
		$display("  FAIL T15 blocks flushed: got %0d want 4", wr_blocks - byi);
	end
	// the disk itself, byte-exact -- a smear cannot hide from this
	for (k = 0; k < 2048; k = k + 1) begin
		checks = checks + 1;
		if (disk[20*512 + k] !== (((k*11) + 7) & 8'hFF)) begin
			fails = fails + 1;
			if (fails < 12)
				$display("  FAIL T15 disk byte %0d (sector %0d+%0d): got %02X want %02X",
				         k, 20 + k/512, k%512, disk[20*512 + k], ((k*11) + 7) & 8'hFF);
		end
	end

	//==================================================================
	// CD-ROM target (SCSI ID 3, hps_io slot 4) and the second disk
	//==================================================================
	$display("-- T16a CD-ROM: INQUIRY with no disc (drive answers selection)");
	reg_wr(R_CMD, 8'h02); repeat (4) @(negedge clk);
	sel_id = 8'h03;
	cdb[0]=8'h12; cdb[1]=0; cdb[2]=0; cdb[3]=0; cdb[4]=8'd36; cdb[5]=0;
	unix_select(8'h42, 6, 1);
	wait_irq(500, ok);
	read_regs(st, sp, it);
	expect_bits("T16a intr BS|FC", it, I_BUS | I_FC);
	expect8("T16a step 4", sp & 8'h07, 8'd4);
	expect8("T16a phase DATA IN", {5'd0, st[2:0]}, {5'd0, PH_DIN});
	set_tc(16'd36);
	reg_wr(R_CMD, 8'h90);
	for (k = 0; k < 36; k = k + 1) begin
		pdma_rd(b);
		case (k)
		0:  expect8("T16a inq type CD", b, 8'h05);
		1:  expect8("T16a inq removable", b, 8'h80);
		4:  expect8("T16a inq addl len", b, 8'h31);
		8:  expect8("T16a inq vendor S", b, "S");
		16: expect8("T16a inq product C", b, "C");
		27: expect8("T16a inq product 8", b, "8");
		default: ;
		endcase
	end
	wait_irq(500, ok);
	read_regs(st, sp, it);
	expect8("T16a phase STATUS after 36", {5'd0, st[2:0]}, {5'd0, PH_STAT});
	reg_wr(R_CMD, 8'h11);
	wait_irq(500, ok);
	reg_rd(R_FIFO, b); expect8("T16a status GOOD", b, 8'h00);
	reg_rd(R_FIFO, b);
	reg_wr(R_CMD, 8'h12); wait_irq(500, ok); read_regs(st, sp, it);

	$display("-- T16b CD-ROM: TEST UNIT READY with no disc -> NOT READY / $B0");
	reg_wr(R_CMD, 8'h02); repeat (4) @(negedge clk);
	cdb[0]=8'h00; cdb[1]=0; cdb[2]=0; cdb[3]=0; cdb[4]=0; cdb[5]=0;
	unix_select(8'h42, 6, 1);
	wait_irq(500, ok);
	read_regs(st, sp, it);
	expect8("T16b phase STATUS", {5'd0, st[2:0]}, {5'd0, PH_STAT});
	reg_wr(R_CMD, 8'h11);
	wait_irq(500, ok);
	reg_rd(R_FIFO, b); expect8("T16b status CHECK", b, 8'h02);
	reg_rd(R_FIFO, b);
	reg_wr(R_CMD, 8'h12); wait_irq(500, ok); read_regs(st, sp, it);
	cdb[0]=8'h03; cdb[1]=0; cdb[2]=0; cdb[3]=0; cdb[4]=8'd18; cdb[5]=0;
	unix_select(8'h42, 6, 1);
	wait_irq(500, ok);
	read_regs(st, sp, it);
	expect8("T16b sense phase DATA IN", {5'd0, st[2:0]}, {5'd0, PH_DIN});
	set_tc(16'd18);
	reg_wr(R_CMD, 8'h90);
	for (k = 0; k < 18; k = k + 1) begin
		pdma_rd(b);
		if (k == 0)  expect8("T16b sense fmt", b, 8'h70);
		if (k == 2)  expect8("T16b sense key NOT READY", b, 8'h02);
		if (k == 12) expect8("T16b sense ASC B0", b, 8'hB0);
	end
	wait_irq(500, ok);
	reg_wr(R_CMD, 8'h11); wait_irq(500, ok);
	reg_rd(R_FIFO, b); expect8("T16b sense status GOOD", b, 8'h00);
	reg_rd(R_FIFO, b);
	reg_wr(R_CMD, 8'h12); wait_irq(500, ok); read_regs(st, sp, it);

	$display("-- T16c CD-ROM: mount 16 x 2048 (the 64-block device), READ CAPACITY");
	img_size = 64*512;
	cdwin_dpi_mount(64*512);                     // the window device follows the disc
	cd_mount = 1; @(negedge clk); @(negedge clk); cd_mount = 0;
	// the audio engine fetches its TOC blob (the device serves zeros there,
	// so it synthesizes the single-track TOC) and grinds the M:S:F divider
	guard = 0;
	while (!dut.ca_toc_ready && guard < 400000) begin @(negedge clk); guard = guard + 1; end
	$display("   TOC ready after %0d cycles (mst=%0d magic=%b%b ver=%0d disc_audio=%b)", guard,
	         dut.g_cd_audio.cd_audio_i.mst, dut.g_cd_audio.cd_audio_i.hdr_m0, dut.g_cd_audio.cd_audio_i.hdr_m1,
	         dut.g_cd_audio.cd_audio_i.hdr_ver, dut.g_cd_audio.cd_audio_i.disc_audio);
	expect8("T16c blob header parsed (MCDA v2, a data disc)", {7'd0, dut.g_cd_audio.cd_audio_i.disc_audio}, 8'h00);
	if (!(dut.g_cd_audio.cd_audio_i.hdr_m0 && dut.g_cd_audio.cd_audio_i.hdr_m1)) begin
		fails = fails + 1; $display("  FAIL T16c the MCDA magic was not seen in the blob header");
	end
	reg_wr(R_CMD, 8'h02); repeat (4) @(negedge clk);
	cdb[0]=8'h25; cdb[1]=0; cdb[2]=0; cdb[3]=0; cdb[4]=0; cdb[5]=0;
	cdb[6]=0; cdb[7]=0; cdb[8]=0; cdb[9]=0;
	unix_select(8'h42, 10, 1);
	wait_irq(500, ok);
	read_regs(st, sp, it);
	expect8("T16c phase DATA IN", {5'd0, st[2:0]}, {5'd0, PH_DIN});
	set_tc(16'd8);
	reg_wr(R_CMD, 8'h90);
	for (k = 0; k < 8; k = k + 1) begin
		pdma_rd(b);
		case (k)
		0, 1, 2: expect8("T16c cap hi", b, 8'h00);
		3: expect8("T16c cap last LBA 15", b, 8'd15);
		6: expect8("T16c blk len 0x08", b, 8'h08);
		7: expect8("T16c blk len 0x00", b, 8'h00);
		default: ;
		endcase
	end
	wait_irq(500, ok);
	reg_wr(R_CMD, 8'h11); wait_irq(500, ok);
	reg_rd(R_FIFO, b); expect8("T16c status GOOD", b, 8'h00);
	reg_rd(R_FIFO, b);
	reg_wr(R_CMD, 8'h12); wait_irq(500, ok); read_regs(st, sp, it);

	$display("-- T16d CD-ROM: READ TOC format 0, lead-out at 00:02:16");
	reg_wr(R_CMD, 8'h02); repeat (4) @(negedge clk);
	cdb[0]=8'h43; cdb[1]=8'h02; cdb[2]=0; cdb[3]=0; cdb[4]=0; cdb[5]=0;
	cdb[6]=0; cdb[7]=0; cdb[8]=8'd20; cdb[9]=0;
	unix_select(8'h42, 10, 1);
	wait_irq(500, ok);
	read_regs(st, sp, it);
	expect8("T16d phase DATA IN", {5'd0, st[2:0]}, {5'd0, PH_DIN});
	set_tc(16'd20);
	reg_wr(R_CMD, 8'h90);
	for (k = 0; k < 20; k = k + 1) begin
		pdma_rd(b);
		case (k)
		1:  expect8("T16d toc len 18", b, 8'd18);
		2:  expect8("T16d first 1", b, 8'd1);
		3:  expect8("T16d last 1", b, 8'd1);
		5:  expect8("T16d ctrl data", b, 8'h14);
		6:  expect8("T16d track 1", b, 8'd1);
		10: expect8("T16d trk1 S=2", b, 8'd2);
		14: expect8("T16d lead-out AA", b, 8'hAA);
		17: expect8("T16d lead-out M", b, 8'd0);
		18: expect8("T16d lead-out S", b, 8'd2);
		19: expect8("T16d lead-out F", b, 8'd16);
		default: ;
		endcase
	end
	wait_irq(500, ok);
	reg_wr(R_CMD, 8'h11); wait_irq(500, ok);
	reg_rd(R_FIFO, b); expect8("T16d status GOOD", b, 8'h00);
	reg_rd(R_FIFO, b);
	reg_wr(R_CMD, 8'h12); wait_irq(500, ok); read_regs(st, sp, it);

	$display("-- T16e CD-ROM: READ(10) logical block 1 = HPS blocks 4..7, 2048 bytes");
	reg_wr(R_CMD, 8'h02); repeat (4) @(negedge clk);
	cdb[0]=8'h28; cdb[1]=0; cdb[2]=0; cdb[3]=0; cdb[4]=0; cdb[5]=8'd1;
	cdb[6]=0; cdb[7]=0; cdb[8]=8'd1; cdb[9]=0;
	unix_select(8'h42, 10, 1);
	wait_irq(500, ok);
	read_regs(st, sp, it);
	expect8("T16e phase DATA IN", {5'd0, st[2:0]}, {5'd0, PH_DIN});
	set_tc(16'd2048);
	reg_wr(R_CMD, 8'h90);
	for (k = 0; k < 2048; k = k + 1) begin
		pdma_rd(b);
		if (b !== (((4 + k/512)*7 + (k%512)) & 8'hFF)) begin
			fails = fails + 1;
			if (fails < 20) $display("  FAIL T16e byte %0d: got %02X want %02X", k, b, ((4 + k/512)*7 + (k%512)) & 8'hFF);
		end
		checks = checks + 1;
	end
	wait_irq(2000, ok);
	read_regs(st, sp, it);
	expect8("T16e phase STATUS after 2048", {5'd0, st[2:0]}, {5'd0, PH_STAT});
	reg_wr(R_CMD, 8'h11); wait_irq(500, ok);
	reg_rd(R_FIFO, b); expect8("T16e status GOOD", b, 8'h00);
	reg_rd(R_FIFO, b);
	reg_wr(R_CMD, 8'h12); wait_irq(500, ok); read_regs(st, sp, it);

	$display("-- T16f CD-ROM: WRITE(6) -> CHECK, DATA PROTECT / $27");
	reg_wr(R_CMD, 8'h02); repeat (4) @(negedge clk);
	cdb[0]=8'h0A; cdb[1]=0; cdb[2]=0; cdb[3]=0; cdb[4]=1; cdb[5]=0;
	unix_select(8'h42, 6, 1);
	wait_irq(500, ok);
	read_regs(st, sp, it);
	expect8("T16f phase STATUS", {5'd0, st[2:0]}, {5'd0, PH_STAT});
	reg_wr(R_CMD, 8'h11); wait_irq(500, ok);
	reg_rd(R_FIFO, b); expect8("T16f status CHECK", b, 8'h02);
	reg_rd(R_FIFO, b);
	reg_wr(R_CMD, 8'h12); wait_irq(500, ok); read_regs(st, sp, it);
	cdb[0]=8'h03; cdb[1]=0; cdb[2]=0; cdb[3]=0; cdb[4]=8'd18; cdb[5]=0;
	unix_select(8'h42, 6, 1);
	wait_irq(500, ok);
	set_tc(16'd18);
	reg_wr(R_CMD, 8'h90);
	for (k = 0; k < 18; k = k + 1) begin
		pdma_rd(b);
		if (k == 2)  expect8("T16f sense DATA PROTECT", b, 8'h07);
		if (k == 12) expect8("T16f sense ASC 27", b, 8'h27);
	end
	wait_irq(500, ok);
	reg_wr(R_CMD, 8'h11); wait_irq(500, ok);
	reg_rd(R_FIFO, b); reg_rd(R_FIFO, b);
	reg_wr(R_CMD, 8'h12); wait_irq(500, ok); read_regs(st, sp, it);

	$display("-- T16g second disk: ID 1 times out unmounted, answers once mounted");
	reg_wr(R_CMD, 8'h02); repeat (4) @(negedge clk);
	sel_id = 8'h01;
	cdb[0]=8'h00; cdb[1]=0; cdb[2]=0; cdb[3]=0; cdb[4]=0; cdb[5]=0;
	unix_select(8'h42, 6, 1);
	wait_irq(500, ok);
	read_regs(st, sp, it);
	expect_bits("T16g unmounted DISC", it, I_DISC);
	img_size = 64*512;
	d1_mount = 1; @(negedge clk); @(negedge clk); d1_mount = 0;
	repeat (4) @(negedge clk);
	reg_wr(R_CMD, 8'h02); repeat (4) @(negedge clk);
	cdb[0]=8'h12; cdb[1]=0; cdb[2]=0; cdb[3]=0; cdb[4]=8'd36; cdb[5]=0;
	unix_select(8'h42, 6, 1);
	wait_irq(500, ok);
	read_regs(st, sp, it);
	expect8("T16g phase DATA IN", {5'd0, st[2:0]}, {5'd0, PH_DIN});
	set_tc(16'd36);
	reg_wr(R_CMD, 8'h90);
	for (k = 0; k < 36; k = k + 1) begin
		pdma_rd(b);
		if (k == 0) expect8("T16g inq type disk", b, 8'h00);
		if (k == 8) expect8("T16g inq vendor W", b, "W");
	end
	wait_irq(500, ok);
	reg_wr(R_CMD, 8'h11); wait_irq(500, ok);
	reg_rd(R_FIFO, b); expect8("T16g status GOOD", b, 8'h00);
	reg_rd(R_FIFO, b);
	reg_wr(R_CMD, 8'h12); wait_irq(500, ok); read_regs(st, sp, it);
	sel_id = 8'h00;

	$display("-- T16h CD-ROM: MODE SELECT block length 512 is REFUSED (05/26): capacity 16 x 2048, READ(6) = four HPS blocks");
	sel_id = 8'h03;
	reg_wr(R_CMD, 8'h02); repeat (4) @(negedge clk);
	cdb[0]=8'h15; cdb[1]=8'h10; cdb[2]=0; cdb[3]=0; cdb[4]=8'd12; cdb[5]=0;
	unix_select(8'h42, 6, 1);
	wait_irq(500, ok);
	read_regs(st, sp, it);
	expect8("T16h phase DATA OUT", {5'd0, st[2:0]}, {5'd0, PH_DOUT});
	reg_wr(R_CMD, 8'h01);
	set_tc(16'd12);
	reg_wr(R_CMD, 8'h90);
	for (k = 0; k < 12; k = k + 1) begin
		guard = 0;
		while (!drq && guard < 100000) begin @(negedge clk); guard = guard + 1; end
		// header 00 00 00 08, descriptor 00 000000 00 000200
		pdma_wr((k == 3) ? 8'h08 : (k == 10) ? 8'h02 : 8'h00);
	end
	wait_irq(2000, ok);
	read_regs(st, sp, it);
	expect8("T16h phase STATUS after list", {5'd0, st[2:0]}, {5'd0, PH_STAT});
	reg_wr(R_CMD, 8'h11); wait_irq(500, ok);
	reg_rd(R_FIFO, b); expect8("T16h msel 512 status CHECK", b, 8'h02);
	reg_rd(R_FIFO, b);
	reg_wr(R_CMD, 8'h12); wait_irq(500, ok); read_regs(st, sp, it);
	repeat (16) @(negedge clk);
	expect8("T16h blk512 never latched", {7'd0, dut.cd_blk512}, 8'd0);
	// the ROM's boot scan: an 8-byte list whose byte 3 still claims an
	// 8-byte descriptor -- refused too, and nothing is parsed past it
	reg_wr(R_CMD, 8'h02); repeat (4) @(negedge clk);
	cdb[0]=8'h15; cdb[1]=8'h10; cdb[2]=0; cdb[3]=0; cdb[4]=8'd8; cdb[5]=0;
	unix_select(8'h42, 6, 1);
	wait_irq(500, ok);
	reg_wr(R_CMD, 8'h01);
	set_tc(16'd8);
	reg_wr(R_CMD, 8'h90);
	for (k = 0; k < 8; k = k + 1) begin
		guard = 0;
		while (!drq && guard < 100000) begin @(negedge clk); guard = guard + 1; end
		pdma_wr((k == 3) ? 8'h08 : 8'h00);
	end
	wait_irq(2000, ok);
	read_regs(st, sp, it);                          // a driver reads INTR before the next command
	reg_wr(R_CMD, 8'h11); wait_irq(500, ok);
	reg_rd(R_FIFO, b); expect8("T16h ROM 8-byte msel status CHECK", b, 8'h02);
	reg_rd(R_FIFO, b);
	reg_wr(R_CMD, 8'h12); wait_irq(500, ok); read_regs(st, sp, it);
	repeat (16) @(negedge clk);
	expect8("T16h blk512 still 0", {7'd0, dut.cd_blk512}, 8'd0);
	reg_wr(R_CMD, 8'h02); repeat (4) @(negedge clk);
	cdb[0]=8'h25; cdb[1]=0; cdb[2]=0; cdb[3]=0; cdb[4]=0; cdb[5]=0;
	cdb[6]=0; cdb[7]=0; cdb[8]=0; cdb[9]=0;
	unix_select(8'h42, 10, 1);
	wait_irq(500, ok);
	read_regs(st, sp, it);
	expect8("T16h cap phase DATA IN", {5'd0, st[2:0]}, {5'd0, PH_DIN});
	set_tc(16'd8);
	reg_wr(R_CMD, 8'h90);
	for (k = 0; k < 8; k = k + 1) begin
		pdma_rd(b);
		case (k)
		0, 1, 2: expect8("T16h cap hi", b, 8'h00);
		3: expect8("T16h cap last LBA 15", b, 8'd15);
		6: expect8("T16h blk len 0x08", b, 8'h08);
		7: expect8("T16h blk len 0x00", b, 8'h00);
		default: ;
		endcase
	end
	wait_irq(500, ok);
	reg_wr(R_CMD, 8'h11); wait_irq(500, ok);
	reg_rd(R_FIFO, b); expect8("T16h cap status GOOD", b, 8'h00);
	reg_rd(R_FIFO, b);
	reg_wr(R_CMD, 8'h12); wait_irq(500, ok); read_regs(st, sp, it);
	// READ(6) block 4 of 2048 = HPS blocks 16..19
	reg_wr(R_CMD, 8'h02); repeat (4) @(negedge clk);
	cdb[0]=8'h08; cdb[1]=0; cdb[2]=0; cdb[3]=8'd4; cdb[4]=8'd1; cdb[5]=0;
	unix_select(8'h42, 6, 1);
	wait_irq(500, ok);
	read_regs(st, sp, it);
	expect8("T16h read phase DATA IN", {5'd0, st[2:0]}, {5'd0, PH_DIN});
	set_tc(16'd2048);
	reg_wr(R_CMD, 8'h90);
	for (k = 0; k < 2048; k = k + 1) begin
		pdma_rd(b);
		if (b !== (((16 + k/512)*7 + (k%512)) & 8'hFF)) begin
			fails = fails + 1;
			if (fails < 20) $display("  FAIL T16h byte %0d: got %02X want %02X", k, b, ((16 + k/512)*7 + (k%512)) & 8'hFF);
		end
		checks = checks + 1;
	end
	wait_irq(4000, ok);
	read_regs(st, sp, it);
	expect8("T16h phase STATUS after 2048", {5'd0, st[2:0]}, {5'd0, PH_STAT});
	reg_wr(R_CMD, 8'h11); wait_irq(500, ok);
	reg_rd(R_FIFO, b); expect8("T16h read status GOOD", b, 8'h00);
	reg_rd(R_FIFO, b);
	reg_wr(R_CMD, 8'h12); wait_irq(500, ok); read_regs(st, sp, it);
	// MODE SENSE page $30 reports the 2048-byte descriptor; a 2048 MODE SELECT is accepted
	reg_wr(R_CMD, 8'h02); repeat (4) @(negedge clk);
	cdb[0]=8'h1A; cdb[1]=0; cdb[2]=8'h30; cdb[3]=0; cdb[4]=8'd36; cdb[5]=0;
	unix_select(8'h42, 6, 1);
	wait_irq(500, ok);
	set_tc(16'd36);
	reg_wr(R_CMD, 8'h90);
	for (k = 0; k < 36; k = k + 1) begin
		pdma_rd(b);
		if (k == 3)  expect8("T16h msense bd len 8", b, 8'd8);
		if (k == 7)  expect8("T16h msense last LBA 15", b, 8'd15);
		if (k == 10) expect8("T16h msense blk len 0x08", b, 8'h08);
		if (k == 14) expect8("T16h msense APPLE", b, "A");
	end
	wait_irq(500, ok);
	reg_wr(R_CMD, 8'h11); wait_irq(500, ok);
	reg_rd(R_FIFO, b); expect8("T16h msense status GOOD", b, 8'h00);
	reg_rd(R_FIFO, b);
	reg_wr(R_CMD, 8'h12); wait_irq(500, ok); read_regs(st, sp, it);
	reg_wr(R_CMD, 8'h02); repeat (4) @(negedge clk);
	cdb[0]=8'h15; cdb[1]=8'h10; cdb[2]=0; cdb[3]=0; cdb[4]=8'd12; cdb[5]=0;
	unix_select(8'h42, 6, 1);
	wait_irq(500, ok);
	reg_wr(R_CMD, 8'h01);
	set_tc(16'd12);
	reg_wr(R_CMD, 8'h90);
	for (k = 0; k < 12; k = k + 1) begin
		guard = 0;
		while (!drq && guard < 100000) begin @(negedge clk); guard = guard + 1; end
		pdma_wr((k == 3) ? 8'h08 : (k == 10) ? 8'h08 : 8'h00);
	end
	wait_irq(2000, ok);
	reg_wr(R_CMD, 8'h11); wait_irq(500, ok);
	reg_rd(R_FIFO, b); expect8("T16h msel 2048 status GOOD", b, 8'h00);
	reg_rd(R_FIFO, b);
	reg_wr(R_CMD, 8'h12); wait_irq(500, ok); read_regs(st, sp, it);
	repeat (16) @(negedge clk);
	expect8("T16h blk512 still cleared", {7'd0, dut.cd_blk512}, 8'd0);
	sel_id = 8'h00;


	$display("-- T16i disk: MODE SENSE page $30 = Apple firmware ID page (Drive Setup / installer)");
	sel_id = 8'h00;
	reg_wr(R_CMD, 8'h02); repeat (4) @(negedge clk);
	cdb[0]=8'h1A; cdb[1]=0; cdb[2]=8'h30; cdb[3]=0; cdb[4]=8'd36; cdb[5]=0;
	unix_select(8'h42, 6, 1);
	wait_irq(500, ok);
	read_regs(st, sp, it);
	expect8("T16i phase DATA IN", {5'd0, st[2:0]}, {5'd0, PH_DIN});
	set_tc(16'd36);
	reg_wr(R_CMD, 8'h90);
	for (k = 0; k < 36; k = k + 1) begin
		pdma_rd(b);
		case (k)
		0:  expect8("T16i mode data len 35", b, 8'd35);
		2:  expect8("T16i not write protected", b, 8'h00);
		3:  expect8("T16i bd len 8", b, 8'd8);
		7:  expect8("T16i last LBA 63", b, 8'd63);
		10: expect8("T16i blk len 0x02", b, 8'h02);
		12: expect8("T16i page B0", b, 8'hB0);
		13: expect8("T16i page len 22", b, 8'h16);
		14: expect8("T16i A", b, "A");
		19: expect8("T16i space", b, " ");
		20: expect8("T16i C", b, "C");
		32: expect8("T16i C of INC", b, "C");
		35: expect8("T16i trailing space", b, " ");
		default: ;
		endcase
	end
	wait_irq(500, ok);
	read_regs(st, sp, it);
	expect8("T16i phase STATUS after 36", {5'd0, st[2:0]}, {5'd0, PH_STAT});
	reg_wr(R_CMD, 8'h11); wait_irq(500, ok);
	reg_rd(R_FIFO, b); expect8("T16i status GOOD", b, 8'h00);
	reg_rd(R_FIFO, b);
	reg_wr(R_CMD, 8'h12); wait_irq(500, ok); read_regs(st, sp, it);
	// any other page still answers the 4-byte header
	reg_wr(R_CMD, 8'h02); repeat (4) @(negedge clk);
	cdb[0]=8'h1A; cdb[1]=0; cdb[2]=8'h03; cdb[3]=0; cdb[4]=8'd36; cdb[5]=0;
	unix_select(8'h42, 6, 1);
	wait_irq(500, ok);
	set_tc(16'd4);
	reg_wr(R_CMD, 8'h90);
	for (k = 0; k < 4; k = k + 1) begin
		pdma_rd(b);
		if (k == 0) expect8("T16i page 3 hdr len 3", b, 8'd3);
	end
	wait_irq(500, ok);
	read_regs(st, sp, it);
	expect8("T16i page 3 STATUS after 4", {5'd0, st[2:0]}, {5'd0, PH_STAT});
	reg_wr(R_CMD, 8'h11); wait_irq(500, ok);
	reg_rd(R_FIFO, b); expect8("T16i page 3 status GOOD", b, 8'h00);
	reg_rd(R_FIFO, b);
	reg_wr(R_CMD, 8'h12); wait_irq(500, ok); read_regs(st, sp, it);

	$display("-- T16j install pattern: CD READ(10) (2048-byte blocks; the 512 request is refused) / disk WRITE(6) interleaved");
	// MODE SELECT 512 on the CD
	sel_id = 8'h03;
	reg_wr(R_CMD, 8'h02); repeat (4) @(negedge clk);
	cdb[0]=8'h15; cdb[1]=8'h10; cdb[2]=0; cdb[3]=0; cdb[4]=8'd12; cdb[5]=0;
	unix_select(8'h42, 6, 1);
	wait_irq(500, ok);
	reg_wr(R_CMD, 8'h01);
	set_tc(16'd12);
	reg_wr(R_CMD, 8'h90);
	for (k = 0; k < 12; k = k + 1) begin
		guard = 0;
		while (!drq && guard < 100000) begin @(negedge clk); guard = guard + 1; end
		pdma_wr((k == 3) ? 8'h08 : (k == 10) ? 8'h02 : 8'h00);
	end
	wait_irq(2000, ok);
	read_regs(st, sp, it);                          // a driver reads INTR before the next command
	reg_wr(R_CMD, 8'h11); wait_irq(500, ok);
	reg_rd(R_FIFO, b); expect8("T16j msel 512 status CHECK", b, 8'h02);
	reg_rd(R_FIFO, b);
	reg_wr(R_CMD, 8'h12); wait_irq(500, ok); read_regs(st, sp, it);
	for (blk = 0; blk < 3; blk = blk + 1) begin
		// CD READ(10) of one 2048-byte block at lba 10+blk (= HPS 40+4*blk..): TC 2048
		sel_id = 8'h03;
		reg_wr(R_CMD, 8'h02); repeat (4) @(negedge clk);
		cdb[0]=8'h28; cdb[1]=0; cdb[2]=0; cdb[3]=0; cdb[4]=0; cdb[5]=10+blk;
		cdb[6]=0; cdb[7]=0; cdb[8]=8'd1; cdb[9]=0;
		unix_select(8'h42, 10, 1);
		wait_irq(500, ok);
		read_regs(st, sp, it);
		expect8("T16j cd read phase DATA IN", {5'd0, st[2:0]}, {5'd0, PH_DIN});
		set_tc(16'd2048);
		reg_wr(R_CMD, 8'h90);
		for (k = 0; k < 2048; k = k + 1) begin
			pdma_rd(b);
			if (b !== (((40+4*blk + k/512)*7 + (k%512)) & 8'hFF)) begin
				fails = fails + 1;
				if (fails < 20) $display("  FAIL T16j cd byte %0d: got %02X want %02X", k, b, ((40+4*blk + k/512)*7 + (k%512)) & 8'hFF);
			end
			checks = checks + 1;
		end
		wait_irq(4000, ok);
		read_regs(st, sp, it);
		expect8("T16j cd phase STATUS", {5'd0, st[2:0]}, {5'd0, PH_STAT});
		reg_wr(R_CMD, 8'h11); wait_irq(500, ok);
		reg_rd(R_FIFO, b); expect8("T16j cd status GOOD", b, 8'h00);
		reg_rd(R_FIFO, b);
		reg_wr(R_CMD, 8'h12); wait_irq(500, ok); read_regs(st, sp, it);
		// disk WRITE(6) of 2 blocks at lba 30+2*blk in 256-byte chunks
		sel_id = 8'h00;
		reg_wr(R_CMD, 8'h02); repeat (4) @(negedge clk);
		byi = wr_blocks;
		cdb[0]=8'h0A; cdb[1]=0; cdb[2]=0; cdb[3]=30+2*blk; cdb[4]=8'd2; cdb[5]=0;
		unix_select(8'h42, 6, 1);
		wait_irq(500, ok);
		read_regs(st, sp, it);
		expect8("T16j write phase DATA OUT", {5'd0, st[2:0]}, {5'd0, PH_DOUT});
		reg_wr(R_CMD, 8'h01);
		for (k2 = 0; k2 < 4; k2 = k2 + 1) begin
			set_tc(16'd256);
			reg_wr(R_CMD, 8'h90);
			for (k = 0; k < 256; k = k + 1) begin
				guard = 0;
				while (!drq && guard < 100000) begin @(negedge clk); guard = guard + 1; end
				if (guard >= 100000) begin
					fails = fails + 1;
					$display("  FAIL T16j DREQ stalled at chunk %0d byte %0d", k2, k);
					k = 256;
				end
				else pdma_wr(((k2*256 + k)*3 + blk) & 8'hFF);
			end
			wait_irq(4000, ok);
			read_regs(st, sp, it);
		end
		expect8("T16j phase STATUS after write", {5'd0, st[2:0]}, {5'd0, PH_STAT});
		reg_wr(R_CMD, 8'h11); wait_irq(500, ok);
		reg_rd(R_FIFO, b); expect8("T16j write status GOOD", b, 8'h00);
		reg_rd(R_FIFO, b);
		reg_wr(R_CMD, 8'h12); wait_irq(500, ok); read_regs(st, sp, it);
		guard = 0;
		while (wr_blocks - byi != 2 && guard < 100000) begin @(negedge clk); guard = guard + 1; end
		checks = checks + 1;
		if (wr_blocks - byi != 2) begin fails = fails + 1; $display("  FAIL T16j blocks flushed %0d", wr_blocks - byi); end
		for (k = 0; k < 1024; k = k + 1) begin
			if (disk[(30+2*blk)*512 + k] !== ((k*3 + blk) & 8'hFF)) begin
				fails = fails + 1;
				if (fails < 20) $display("  FAIL T16j disk byte %0d: got %02X want %02X", k, disk[(30+2*blk)*512 + k], (k*3 + blk) & 8'hFF);
			end
			checks = checks + 1;
		end
	end
	// back to 2048
	sel_id = 8'h03;
	reg_wr(R_CMD, 8'h02); repeat (4) @(negedge clk);
	cdb[0]=8'h15; cdb[1]=8'h10; cdb[2]=0; cdb[3]=0; cdb[4]=8'd12; cdb[5]=0;
	unix_select(8'h42, 6, 1);
	wait_irq(500, ok);
	reg_wr(R_CMD, 8'h01);
	set_tc(16'd12);
	reg_wr(R_CMD, 8'h90);
	for (k = 0; k < 12; k = k + 1) begin
		guard = 0;
		while (!drq && guard < 100000) begin @(negedge clk); guard = guard + 1; end
		pdma_wr((k == 3) ? 8'h08 : (k == 10) ? 8'h08 : 8'h00);
	end
	wait_irq(2000, ok);
	reg_wr(R_CMD, 8'h11); wait_irq(500, ok);
	reg_rd(R_FIFO, b); reg_rd(R_FIFO, b);
	reg_wr(R_CMD, 8'h12); wait_irq(500, ok); read_regs(st, sp, it);
	sel_id = 8'h00;

	$display("-- T16k CD-ROM: START/STOP eject takes the disc away until a bus reset (ROM CD boot)");
	sel_id = 8'h03;
	reg_wr(R_CMD, 8'h02); repeat (4) @(negedge clk);
	cdb[0]=8'h1B; cdb[1]=0; cdb[2]=0; cdb[3]=0; cdb[4]=8'h02; cdb[5]=0;
	unix_select(8'h42, 6, 1);
	wait_irq(500, ok);
	read_regs(st, sp, it);
	expect8("T16k eject phase STATUS", {5'd0, st[2:0]}, {5'd0, PH_STAT});
	reg_wr(R_CMD, 8'h11); wait_irq(2000, ok);      // the eject is a round trip to the ARM now
	reg_rd(R_FIFO, b); expect8("T16k eject status GOOD", b, 8'h00);
	reg_rd(R_FIFO, b);
	reg_wr(R_CMD, 8'h12); wait_irq(500, ok); read_regs(st, sp, it);
	reg_wr(R_CMD, 8'h02); repeat (4) @(negedge clk);
	cdb[0]=8'h00; cdb[1]=0; cdb[2]=0; cdb[3]=0; cdb[4]=0; cdb[5]=0;
	unix_select(8'h42, 6, 1);
	wait_irq(500, ok);
	reg_wr(R_CMD, 8'h11); wait_irq(500, ok);
	reg_rd(R_FIFO, b); expect8("T16k TUR after eject CHECK", b, 8'h02);
	reg_rd(R_FIFO, b);
	reg_wr(R_CMD, 8'h12); wait_irq(500, ok); read_regs(st, sp, it);
	reg_wr(R_CMD, 8'h03);                          // RESET SCSI BUS
	repeat (8) @(negedge clk);
	reg_rd(R_INTR, b);                             // clear the reset interrupt
	repeat (8) @(negedge clk);
	reg_wr(R_CMD, 8'h02); repeat (4) @(negedge clk);
	cdb[0]=8'h00; cdb[1]=0; cdb[2]=0; cdb[3]=0; cdb[4]=0; cdb[5]=0;
	unix_select(8'h42, 6, 1);
	wait_irq(500, ok);
	reg_wr(R_CMD, 8'h11); wait_irq(500, ok);
	reg_rd(R_FIFO, b); expect8("T16k TUR after bus reset GOOD", b, 8'h00);
	reg_rd(R_FIFO, b);
	reg_wr(R_CMD, 8'h12); wait_irq(500, ok); read_regs(st, sp, it);
	sel_id = 8'h00;

	$display("-- T16l slow HPS: disk WRITE then CD READ back to back while the last flush is in flight");
	dev_lat = 3000;
	for (blk = 0; blk < 3; blk = blk + 1) begin
		// disk WRITE(6) of 2 blocks at lba 36+2*blk, 256-byte chunks, as the ROM does
		sel_id = 8'h00;
		reg_wr(R_CMD, 8'h02); repeat (4) @(negedge clk);
		byi = wr_blocks;
		cdb[0]=8'h0A; cdb[1]=0; cdb[2]=0; cdb[3]=36+2*blk; cdb[4]=8'd2; cdb[5]=0;
		unix_select(8'h42, 6, 1);
		wait_irq(500, ok);
		read_regs(st, sp, it);
		expect8("T16l write phase DATA OUT", {5'd0, st[2:0]}, {5'd0, PH_DOUT});
		reg_wr(R_CMD, 8'h01);
		for (k2 = 0; k2 < 4; k2 = k2 + 1) begin
			set_tc(16'd256);
			reg_wr(R_CMD, 8'h90);
			for (k = 0; k < 256; k = k + 1) begin
				guard = 0;
				while (!drq && guard < 100000) begin @(negedge clk); guard = guard + 1; end
				if (guard >= 100000) begin
					fails = fails + 1;
					$display("  FAIL T16l DREQ stalled at chunk %0d byte %0d", k2, k);
					k = 256;
				end
				else pdma_wr(((k2*256 + k)*7 + blk + 1) & 8'hFF);
			end
			wait_irq(20000, ok);
			read_regs(st, sp, it);
		end
		expect8("T16l phase STATUS after write", {5'd0, st[2:0]}, {5'd0, PH_STAT});
		reg_wr(R_CMD, 8'h11); wait_irq(500, ok);
		reg_rd(R_FIFO, b); expect8("T16l write status GOOD", b, 8'h00);
		reg_rd(R_FIFO, b);
		reg_wr(R_CMD, 8'h12); wait_irq(500, ok); read_regs(st, sp, it);
		// NO wait for the flush: the CD READ(10) follows at once (2048-byte blocks here)
		sel_id = 8'h03;
		reg_wr(R_CMD, 8'h02); repeat (4) @(negedge clk);
		cdb[0]=8'h28; cdb[1]=0; cdb[2]=0; cdb[3]=0; cdb[4]=0; cdb[5]=13+blk;
		cdb[6]=0; cdb[7]=0; cdb[8]=8'd1; cdb[9]=0;
		unix_select(8'h42, 10, 1);
		wait_irq(500, ok);
		read_regs(st, sp, it);
		expect8("T16l cd read phase DATA IN", {5'd0, st[2:0]}, {5'd0, PH_DIN});
		set_tc(16'd2048);
		reg_wr(R_CMD, 8'h90);
		for (k = 0; k < 2048; k = k + 1) begin
			pdma_rd(b);
			if (b !== ((((13+blk)*4 + k/512)*7 + (k%512)) & 8'hFF)) begin
				fails = fails + 1;
				if (fails < 20) $display("  FAIL T16l cd byte %0d: got %02X want %02X", k, b, (((13+blk)*4 + k/512)*7 + (k%512)) & 8'hFF);
			end
			checks = checks + 1;
		end
		wait_irq(20000, ok);
		read_regs(st, sp, it);
		expect8("T16l cd phase STATUS", {5'd0, st[2:0]}, {5'd0, PH_STAT});
		reg_wr(R_CMD, 8'h11); wait_irq(500, ok);
		reg_rd(R_FIFO, b); expect8("T16l cd status GOOD", b, 8'h00);
		reg_rd(R_FIFO, b);
		reg_wr(R_CMD, 8'h12); wait_irq(500, ok); read_regs(st, sp, it);
		// the written blocks must have landed intact despite the read behind them
		guard = 0;
		while (wr_blocks - byi != 2 && guard < 200000) begin @(negedge clk); guard = guard + 1; end
		checks = checks + 1;
		if (wr_blocks - byi != 2) begin fails = fails + 1; $display("  FAIL T16l blocks flushed %0d", wr_blocks - byi); end
		for (k = 0; k < 1024; k = k + 1) begin
			if (disk[(36+2*blk)*512 + k] !== ((k*7 + blk + 1) & 8'hFF)) begin
				fails = fails + 1;
				if (fails < 20) $display("  FAIL T16l disk byte %0d: got %02X want %02X", k, disk[(36+2*blk)*512 + k], (k*7 + blk + 1) & 8'hFF);
			end
			checks = checks + 1;
		end
	end
	dev_lat = 40;
	sel_id = 8'h00;

	$display("-- T16m disk: MODE SELECT(6) list accepted, VERIFY / SYNCHRONIZE CACHE / FORMAT UNIT GOOD");
	sel_id = 8'h00;
	reg_wr(R_CMD, 8'h02); repeat (4) @(negedge clk);
	cdb[0]=8'h15; cdb[1]=8'h10; cdb[2]=0; cdb[3]=0; cdb[4]=8'd12; cdb[5]=0;
	unix_select(8'h42, 6, 1);
	wait_irq(500, ok);
	read_regs(st, sp, it);
	expect8("T16m msel phase DATA OUT", {5'd0, st[2:0]}, {5'd0, PH_DOUT});
	reg_wr(R_CMD, 8'h01);
	set_tc(16'd12);
	reg_wr(R_CMD, 8'h90);
	for (k = 0; k < 12; k = k + 1) begin
		guard = 0;
		while (!drq && guard < 100000) begin @(negedge clk); guard = guard + 1; end
		pdma_wr((k == 3) ? 8'h08 : (k == 10) ? 8'h02 : 8'h00);
	end
	wait_irq(2000, ok);
	read_regs(st, sp, it);
	expect8("T16m msel phase STATUS", {5'd0, st[2:0]}, {5'd0, PH_STAT});
	reg_wr(R_CMD, 8'h11); wait_irq(500, ok);
	reg_rd(R_FIFO, b); expect8("T16m msel status GOOD", b, 8'h00);
	reg_rd(R_FIFO, b);
	reg_wr(R_CMD, 8'h12); wait_irq(500, ok); read_regs(st, sp, it);
	// the disk is still a 512-byte device afterwards
	reg_wr(R_CMD, 8'h02); repeat (4) @(negedge clk);
	cdb[0]=8'h25; cdb[1]=0; cdb[2]=0; cdb[3]=0; cdb[4]=0; cdb[5]=0; cdb[6]=0; cdb[7]=0; cdb[8]=0; cdb[9]=0;
	unix_select(8'h42, 10, 1);
	wait_irq(500, ok);
	set_tc(16'd8);
	reg_wr(R_CMD, 8'h90);
	for (k = 0; k < 8; k = k + 1) begin
		pdma_rd(b);
		if (k == 3) expect8("T16m cap last LBA 63", b, 8'd63);
		if (k == 6) expect8("T16m blk len 0x02", b, 8'h02);
	end
	wait_irq(500, ok);
	reg_wr(R_CMD, 8'h11); wait_irq(500, ok);
	reg_rd(R_FIFO, b); expect8("T16m cap status GOOD", b, 8'h00);
	reg_rd(R_FIFO, b);
	reg_wr(R_CMD, 8'h12); wait_irq(500, ok); read_regs(st, sp, it);
	// VERIFY(10) without BytChk, SYNCHRONIZE CACHE, FORMAT UNIT, SEND DIAGNOSTIC: straight to GOOD
	for (k2 = 0; k2 < 4; k2 = k2 + 1) begin
		reg_wr(R_CMD, 8'h02); repeat (4) @(negedge clk);
		case (k2)
		0: begin cdb[0]=8'h2F; cdb[1]=0; cdb[2]=0; cdb[3]=0; cdb[4]=0; cdb[5]=8'd4; cdb[6]=0; cdb[7]=0; cdb[8]=8'd2; cdb[9]=0; unix_select(8'h42, 10, 1); end
		1: begin cdb[0]=8'h35; cdb[1]=0; cdb[2]=0; cdb[3]=0; cdb[4]=0; cdb[5]=0; cdb[6]=0; cdb[7]=0; cdb[8]=0; cdb[9]=0; unix_select(8'h42, 10, 1); end
		2: begin cdb[0]=8'h04; cdb[1]=0; cdb[2]=0; cdb[3]=0; cdb[4]=0; cdb[5]=0; unix_select(8'h42, 6, 1); end
		3: begin cdb[0]=8'h1D; cdb[1]=8'h04; cdb[2]=0; cdb[3]=0; cdb[4]=0; cdb[5]=0; unix_select(8'h42, 6, 1); end
		endcase
		wait_irq(500, ok);
		read_regs(st, sp, it);
		expect8("T16m no-op phase STATUS", {5'd0, st[2:0]}, {5'd0, PH_STAT});
		reg_wr(R_CMD, 8'h11); wait_irq(500, ok);
		reg_rd(R_FIFO, b); expect8("T16m no-op status GOOD", b, 8'h00);
		reg_rd(R_FIFO, b);
		reg_wr(R_CMD, 8'h12); wait_irq(500, ok); read_regs(st, sp, it);
	end
	// an unknown opcode still CHECKs (ILLEGAL REQUEST)
	reg_wr(R_CMD, 8'h02); repeat (4) @(negedge clk);
	cdb[0]=8'h0E; cdb[1]=0; cdb[2]=0; cdb[3]=0; cdb[4]=0; cdb[5]=0;
	unix_select(8'h42, 6, 1);
	wait_irq(500, ok);
	reg_wr(R_CMD, 8'h11); wait_irq(500, ok);
	reg_rd(R_FIFO, b); expect8("T16m unknown opcode CHECK", b, 8'h02);
	reg_rd(R_FIFO, b);
	reg_wr(R_CMD, 8'h12); wait_irq(500, ok); read_regs(st, sp, it);
	cdb[0]=8'h03; cdb[1]=0; cdb[2]=0; cdb[3]=0; cdb[4]=8'd18; cdb[5]=0;
	unix_select(8'h42, 6, 1);
	wait_irq(500, ok);
	set_tc(16'd18);
	reg_wr(R_CMD, 8'h90);
	for (k = 0; k < 18; k = k + 1) begin
		pdma_rd(b);
		if (k == 2)  expect8("T16m sense ILLEGAL REQUEST", b, 8'h05);
		if (k == 12) expect8("T16m sense ASC 20", b, 8'h20);
	end
	wait_irq(500, ok);
	reg_wr(R_CMD, 8'h11); wait_irq(500, ok);
	reg_rd(R_FIFO, b); reg_rd(R_FIFO, b);
	reg_wr(R_CMD, 8'h12); wait_irq(500, ok); read_regs(st, sp, it);

	$display("-- T16n Mac OS style write: WRITE(10) of 4 blocks as ONE DMA transfer (TC=2048) on a slow device");
	dev_lat = 3000;
	sel_id = 8'h00;
	reg_wr(R_CMD, 8'h02); repeat (4) @(negedge clk);
	byi = wr_blocks;
	cdb[0]=8'h2A; cdb[1]=0; cdb[2]=0; cdb[3]=0; cdb[4]=0; cdb[5]=8'd44; cdb[6]=0; cdb[7]=0; cdb[8]=8'd4; cdb[9]=0;
	unix_select(8'h42, 10, 1);
	wait_irq(500, ok);
	read_regs(st, sp, it);
	expect8("T16n phase DATA OUT", {5'd0, st[2:0]}, {5'd0, PH_DOUT});
	reg_wr(R_CMD, 8'h01);
	set_tc(16'd2048);
	reg_wr(R_CMD, 8'h90);
	for (k = 0; k < 2048; k = k + 1) begin
		guard = 0;
		while (!drq && guard < 200000) begin @(negedge clk); guard = guard + 1; end
		if (guard >= 200000) begin
			fails = fails + 1;
			$display("  FAIL T16n DREQ never returned at byte %0d (block %0d)", k, k/512);
			k = 2048;
		end
		else pdma_wr(((k*5) + 7) & 8'hFF);
	end
	wait_irq(200000, ok);
	read_regs(st, sp, it);
	$display("   T16n after 2048 bytes: stat=%02X intr=%02X flushed=%0d", st, it, wr_blocks - byi);
	// the target must reach STATUS on its own once the last block is flushed
	guard = 0;
	while (st[2:0] != PH_STAT && guard < 400000) begin @(negedge clk); guard = guard + 1; read_regs(st, sp, it); end
	expect8("T16n phase STATUS after the write", {5'd0, st[2:0]}, {5'd0, PH_STAT});
	reg_wr(R_CMD, 8'h11); wait_irq(500, ok);
	reg_rd(R_FIFO, b); expect8("T16n status GOOD", b, 8'h00);
	reg_rd(R_FIFO, b);
	reg_wr(R_CMD, 8'h12); wait_irq(500, ok); read_regs(st, sp, it);
	guard = 0;
	while (wr_blocks - byi != 4 && guard < 400000) begin @(negedge clk); guard = guard + 1; end
	checks = checks + 1;
	if (wr_blocks - byi != 4) begin fails = fails + 1; $display("  FAIL T16n blocks flushed %0d (want 4)", wr_blocks - byi); end
	for (k = 0; k < 2048; k = k + 1) begin
		if (disk[44*512 + k] !== (((k*5) + 7) & 8'hFF)) begin
			fails = fails + 1;
			if (fails < 20) $display("  FAIL T16n disk byte %0d: got %02X want %02X", k, disk[44*512 + k], ((k*5) + 7) & 8'hFF);
		end
		checks = checks + 1;
	end
	dev_lat = 40;

	$display("-- T16o stress: 80 rounds of CD READ / disk READ / disk WRITE(10) with random lengths, latencies and pacing");
	begin : stress
		integer rnd, it, nb, lb, lat, gap, kk, fails0;
		reg [7:0] bb;
		rnd = 32'h5EED1234;
		fails0 = fails;
		for (it = 0; it < 80 && fails == fails0; it = it + 1) begin
			if (it % 10 == 0) $display("   T16o round %0d at %0t", it, $time);
			// --- CD READ(10), 1..3 logical blocks (2048-byte mode) at lba 3..4
			rnd = rnd * 1103515245 + 12345; nb = 1 + ((rnd >> 16) % 2);
			rnd = rnd * 1103515245 + 12345; lb = 3;                        // HPS 12..19, never written by another test
			rnd = rnd * 1103515245 + 12345; dev_lat = 40 + ((rnd >> 16) % 3000);
			sel_id = 8'h03;
			reg_wr(R_CMD, 8'h02); repeat (4) @(negedge clk);
			cdb[0]=8'h28; cdb[1]=0; cdb[2]=0; cdb[3]=0; cdb[4]=0; cdb[5]=lb[7:0]; cdb[6]=0; cdb[7]=0; cdb[8]=nb[7:0]; cdb[9]=0;
			unix_select(8'h42, 10, 1);
			wait_irq(2000, ok);
			set_tc(nb * 2048);
			reg_wr(R_CMD, 8'h90);
			for (kk = 0; kk < nb * 2048; kk = kk + 1) begin
				pdma_rd(bb);
				if (bb !== (((lb*4 + kk/512)*7 + (kk%512)) & 8'hFF)) begin
					fails = fails + 1;
					if (fails < fails0 + 6) $display("  FAIL T16o it=%0d cd byte %0d: got %02X want %02X", it, kk, bb, ((lb*4 + kk/512)*7 + (kk%512)) & 8'hFF);
				end
				checks = checks + 1;
			end
			wait_irq(200000, ok);
			read_regs(st, sp, it2);
			if (st[2:0] != PH_STAT) begin fails = fails + 1; $display("  FAIL T16o it=%0d cd read did not reach STATUS (stat=%02X)", it, st); end
			reg_wr(R_CMD, 8'h11); wait_irq(2000, ok);
			reg_rd(R_FIFO, bb); if (bb !== 8'h00) begin fails = fails + 1; $display("  FAIL T16o it=%0d cd status %02X", it, bb); end
			reg_rd(R_FIFO, bb);
			reg_wr(R_CMD, 8'h12); wait_irq(2000, ok); read_regs(st, sp, it2);
			// --- disk READ(10), 1..4 blocks at lba 56..59
			rnd = rnd * 1103515245 + 12345; nb = 1 + ((rnd >> 16) % 4);
			rnd = rnd * 1103515245 + 12345; lb = 56 + ((rnd >> 16) % 4);  // 56..59 never written
			rnd = rnd * 1103515245 + 12345; dev_lat = 40 + ((rnd >> 16) % 3000);
			sel_id = 8'h00;
			reg_wr(R_CMD, 8'h02); repeat (4) @(negedge clk);
			cdb[0]=8'h28; cdb[1]=0; cdb[2]=0; cdb[3]=0; cdb[4]=0; cdb[5]=lb[7:0]; cdb[6]=0; cdb[7]=0; cdb[8]=nb[7:0]; cdb[9]=0;
			unix_select(8'h42, 10, 1);
			wait_irq(2000, ok);
			set_tc(nb * 512);
			reg_wr(R_CMD, 8'h90);
			for (kk = 0; kk < nb * 512; kk = kk + 1) begin
				pdma_rd(bb);
				checks = checks + 1;
			end
			wait_irq(200000, ok);
			read_regs(st, sp, it2);
			if (st[2:0] != PH_STAT) begin fails = fails + 1; $display("  FAIL T16o it=%0d disk read did not reach STATUS (stat=%02X)", it, st); end
			reg_wr(R_CMD, 8'h11); wait_irq(2000, ok);
			reg_rd(R_FIFO, bb); reg_rd(R_FIFO, bb);
			reg_wr(R_CMD, 8'h12); wait_irq(2000, ok); read_regs(st, sp, it2);
			// --- disk WRITE(10), 1..4 blocks at lba 60, one TI, random inter-byte gaps
			rnd = rnd * 1103515245 + 12345; nb = 1 + ((rnd >> 16) % 4);
			rnd = rnd * 1103515245 + 12345; lb = 60;                       // 60..63, rewritten each round
			rnd = rnd * 1103515245 + 12345; dev_lat = 40 + ((rnd >> 16) % 3000);
			rnd = rnd * 1103515245 + 12345; gap = (rnd >> 16) % 4;
			reg_wr(R_CMD, 8'h02); repeat (4) @(negedge clk);
			byi = wr_blocks;
			cdb[0]=8'h2A; cdb[1]=0; cdb[2]=0; cdb[3]=0; cdb[4]=0; cdb[5]=lb[7:0]; cdb[6]=0; cdb[7]=0; cdb[8]=nb[7:0]; cdb[9]=0;
			unix_select(8'h42, 10, 1);
			wait_irq(2000, ok);
			read_regs(st, sp, it2);
			if (st[2:0] != PH_DOUT) begin fails = fails + 1; $display("  FAIL T16o it=%0d write not in DATA OUT (stat=%02X)", it, st); end
			reg_wr(R_CMD, 8'h01);
			set_tc(nb * 512);
			reg_wr(R_CMD, 8'h90);
			for (kk = 0; kk < nb * 512; kk = kk + 1) begin
				guard = 0;
				while (!drq && guard < 200000) begin @(negedge clk); guard = guard + 1; end
				if (guard >= 200000) begin
					fails = fails + 1;
					$display("  FAIL T16o it=%0d WRITE DREQ never returned at byte %0d of %0d (lat=%0d gap=%0d)", it, kk, nb*512, dev_lat, gap);
					kk = nb * 512;
				end
				else begin
					pdma_wr((kk*3 + it) & 8'hFF);
					repeat (gap) @(negedge clk);
				end
			end
			wait_irq(200000, ok);
			guard = 0; read_regs(st, sp, it2);
			while (st[2:0] != PH_STAT && guard < 400000) begin @(negedge clk); guard = guard + 1; read_regs(st, sp, it2); end
			if (st[2:0] != PH_STAT) begin fails = fails + 1; $display("  FAIL T16o it=%0d write never reached STATUS (stat=%02X intr=%02X flushed=%0d of %0d)", it, st, it2, wr_blocks - byi, nb); end
			reg_wr(R_CMD, 8'h11); wait_irq(2000, ok);
			reg_rd(R_FIFO, bb); if (bb !== 8'h00) begin fails = fails + 1; $display("  FAIL T16o it=%0d write status %02X", it, bb); end
			reg_rd(R_FIFO, bb);
			reg_wr(R_CMD, 8'h12); wait_irq(2000, ok); read_regs(st, sp, it2);
			guard = 0;
			while (wr_blocks - byi != nb && guard < 400000) begin @(negedge clk); guard = guard + 1; end
			checks = checks + 1;
			if (wr_blocks - byi != nb) begin fails = fails + 1; $display("  FAIL T16o it=%0d blocks flushed %0d want %0d", it, wr_blocks - byi, nb); end
			for (kk = 0; kk < nb * 512; kk = kk + 1) begin
				if (disk[lb*512 + kk] !== ((kk*3 + it) & 8'hFF)) begin
					fails = fails + 1;
					if (fails < fails0 + 6) $display("  FAIL T16o it=%0d disk byte %0d: got %02X want %02X", it, kk, disk[lb*512 + kk], (kk*3 + it) & 8'hFF);
				end
				checks = checks + 1;
			end
		end
		$display("   T16o rounds completed: %0d, failures added: %0d", it, fails - fails0);
	end
	dev_lat = 40;
	sel_id = 8'h00;

	$display("-- T16p cross-target: a disk WRITE(10) then immediately a CD READ(10) select on a SLOW device");
	// This is the installer deadlock: the disk write must not report STATUS
	// until its final block has flushed, or the CD select switches cur_tgt
	// and the flush ack is lost.
	dev_lat = 4000;
	sel_id = 8'h00;
	reg_wr(R_CMD, 8'h02); repeat (4) @(negedge clk);
	byi = wr_blocks;
	cdb[0]=8'h2A; cdb[1]=0; cdb[2]=0; cdb[3]=0; cdb[4]=0; cdb[5]=8'd50; cdb[6]=0; cdb[7]=0; cdb[8]=8'd2; cdb[9]=0;
	unix_select(8'h42, 10, 1);
	wait_irq(2000, ok);
	read_regs(st, sp, it);
	expect8("T16p write phase DATA OUT", {5'd0, st[2:0]}, {5'd0, PH_DOUT});
	reg_wr(R_CMD, 8'h01);
	set_tc(16'd1024);
	reg_wr(R_CMD, 8'h90);
	for (k = 0; k < 1024; k = k + 1) begin
		guard = 0;
		while (!drq && guard < 200000) begin @(negedge clk); guard = guard + 1; end
		if (guard >= 200000) begin fails = fails + 1; $display("  FAIL T16p write DREQ stall at %0d", k); k = 1024; end
		else pdma_wr((k*3 + 5) & 8'hFF);
	end
	// the write must NOT reach STATUS until the flush lands: poll, it should
	// still be in DATA OUT (or transitioning) with the flush outstanding
	wait_irq(200000, ok);
	guard = 0; read_regs(st, sp, it);
	while (st[2:0] != PH_STAT && guard < 400000) begin @(negedge clk); guard = guard + 1; read_regs(st, sp, it); end
	expect8("T16p write reached STATUS", {5'd0, st[2:0]}, {5'd0, PH_STAT});
	reg_wr(R_CMD, 8'h11); wait_irq(2000, ok);
	reg_rd(R_FIFO, b); expect8("T16p write status GOOD", b, 8'h00);
	reg_rd(R_FIFO, b);
	reg_wr(R_CMD, 8'h12); wait_irq(2000, ok); read_regs(st, sp, it);
	// blocks landed
	guard = 0;
	while (wr_blocks - byi != 2 && guard < 400000) begin @(negedge clk); guard = guard + 1; end
	expect8("T16p 2 blocks flushed", (wr_blocks - byi == 2) ? 8'd1 : 8'd0, 8'd1);
	// NOW select the CD for a READ(10) -- this used to deadlock.  (variant A:
	// let the disk flush finish first to isolate the byte count from the overlap)
	dev_lat = 40;
	$display("   T16p pre-CD state: fifo_cnt=%0d buf_valid=%b sbuf_pos=%0d sbuf_len=%0d flush_pending=%b io_discard=%b", dut.fifo_cnt, dut.buf_valid, dut.sbuf_pos, dut.sbuf_len, dut.flush_pending, dut.io_discard);
	sel_id = 8'h03;
	reg_wr(R_CMD, 8'h02); repeat (4) @(negedge clk);
	cdb[0]=8'h28; cdb[1]=0; cdb[2]=0; cdb[3]=0; cdb[4]=0; cdb[5]=8'd1; cdb[6]=0; cdb[7]=0; cdb[8]=8'd1; cdb[9]=0;
	unix_select(8'h42, 10, 1);
	wait_irq(2000, ok);
	read_regs(st, sp, it);
	expect8("T16p CD read phase DATA IN", {5'd0, st[2:0]}, {5'd0, PH_DIN});
	$display("   T16p at DATA IN: fifo_cnt=%0d buf_valid=%b sbuf_pos=%0d sbuf_len=%0d blocks_left=%0d", dut.fifo_cnt, dut.buf_valid, dut.sbuf_pos, dut.sbuf_len, dut.blocks_left);
	set_tc(16'd2048);
	reg_wr(R_CMD, 8'h90);
	byi = 0;                                        // reuse as a delivered-byte count
	// DREQ-paced move.w like the ROM (and T9): one DRQ wait per TWO bytes.
	// Data-in DRQ needs >= 2 bytes in the FIFO (the 53C96 leaves the last
	// odd byte for the processor), so a loop that waits for DRQ before every
	// single byte strands the final one -- that was the "1-byte residual"
	// this test used to print as a WARN.
	for (k = 0; k < 1024; k = k + 1) begin
		guard = 0;
		while (!drq && guard < 400000) begin @(negedge clk); guard = guard + 1; end
		if (guard >= 400000) k = 1024;              // no more bytes coming
		else begin pdma_rd(b); pdma_rd(b); byi = byi + 2; end
	end
	// the point of this test: the CD read after a disk WRITE must NOT deadlock
	// (before the flush-ack routing fix it hung forever with 0 bytes served).
	checks = checks + 1;
	if (byi < 2040) begin fails = fails + 1; $display("  FAIL T16p CD-after-write DEADLOCK: only %0d/2048 bytes served", byi); end
	else if (byi != 2048) begin fails = fails + 1; $display("  FAIL T16p CD-after-write served %0d/2048 bytes", byi); end
	// drain to a clean STATUS regardless
	guard = 0; read_regs(st, sp, it);
	while (st[2:0] != PH_STAT && guard < 20000) begin @(negedge clk); guard = guard + 1; read_regs(st, sp, it); end
	if (st[2:0] == PH_STAT) begin
		reg_wr(R_CMD, 8'h11); wait_irq(2000, ok);
		reg_rd(R_FIFO, b); reg_rd(R_FIFO, b);
		reg_wr(R_CMD, 8'h12); wait_irq(2000, ok); read_regs(st, sp, it);
	end
	dev_lat = 40;
	sel_id = 8'h00;

	$display("-- T17 CD-ROM: Apple $C1 READ TOC header / lead-out / track 1, $CC AUDIO STATUS");
	sel_id = 8'h03;
	// header: {01, last BCD 01, 00, 00}
	reg_wr(R_CMD, 8'h02); repeat (4) @(negedge clk);
	cdb[0]=8'hC1; cdb[1]=0; cdb[2]=0; cdb[3]=0; cdb[4]=0; cdb[5]=0; cdb[6]=0; cdb[7]=0; cdb[8]=8'd4; cdb[9]=8'h00;
	unix_select(8'h42, 10, 1);
	wait_irq(500, ok); read_regs(st, sp, it);
	expect8("T17 hdr phase DATA IN", {5'd0, st[2:0]}, {5'd0, PH_DIN});
	set_tc(16'd4); reg_wr(R_CMD, 8'h90);
	pdma_rd(b); expect8("T17 hdr[0]", b, 8'h01);
	pdma_rd(b); expect8("T17 hdr[1] last=01", b, 8'h01);
	pdma_rd(b); expect8("T17 hdr[2]", b, 8'h00);
	pdma_rd(b); expect8("T17 hdr[3]", b, 8'h00);
	wait_irq(500, ok); reg_wr(R_CMD, 8'h11); wait_irq(500, ok);
	reg_rd(R_FIFO, b); expect8("T17 hdr status GOOD", b, 8'h00); reg_rd(R_FIFO, b);
	reg_wr(R_CMD, 8'h12); wait_irq(500, ok); read_regs(st, sp, it);
	// lead-out: the Apple table is disc-LBA MSF (no +150): 16 frames = 00:00:16 BCD
	reg_wr(R_CMD, 8'h02); repeat (4) @(negedge clk);
	cdb[9]=8'h40;
	unix_select(8'h42, 10, 1);
	wait_irq(500, ok); read_regs(st, sp, it);
	set_tc(16'd4); reg_wr(R_CMD, 8'h90);
	pdma_rd(b); expect8("T17 leadout M", b, 8'h00);
	pdma_rd(b); expect8("T17 leadout S", b, 8'h00);
	pdma_rd(b); expect8("T17 leadout F", b, 8'h16);
	pdma_rd(b); expect8("T17 leadout pad", b, 8'h00);
	wait_irq(500, ok); reg_wr(R_CMD, 8'h11); wait_irq(500, ok);
	reg_rd(R_FIFO, b); reg_rd(R_FIFO, b);
	reg_wr(R_CMD, 8'h12); wait_irq(500, ok); read_regs(st, sp, it);
	// track 1 descriptor: {ctrl $14, 00, 00, 00} (LBA 0, no +150)
	reg_wr(R_CMD, 8'h02); repeat (4) @(negedge clk);
	cdb[5]=8'h01; cdb[9]=8'h80;
	unix_select(8'h42, 10, 1);
	wait_irq(500, ok); read_regs(st, sp, it);
	set_tc(16'd4); reg_wr(R_CMD, 8'h90);
	pdma_rd(b); expect8("T17 trk1 ctrl", b, 8'h14);
	pdma_rd(b); expect8("T17 trk1 M", b, 8'h00);
	pdma_rd(b); expect8("T17 trk1 S", b, 8'h00);
	pdma_rd(b); expect8("T17 trk1 F", b, 8'h00);
	wait_irq(500, ok); reg_wr(R_CMD, 8'h11); wait_irq(500, ok);
	reg_rd(R_FIFO, b); reg_rd(R_FIFO, b);
	reg_wr(R_CMD, 8'h12); wait_irq(500, ok); read_regs(st, sp, it);
	// AUDIO STATUS: idle (5), 0, ctrl, MSF
	reg_wr(R_CMD, 8'h02); repeat (4) @(negedge clk);
	cdb[0]=8'hCC; cdb[1]=0; cdb[2]=0; cdb[3]=0; cdb[4]=0; cdb[5]=0; cdb[6]=0; cdb[7]=0; cdb[8]=8'd6; cdb[9]=0;
	unix_select(8'h42, 10, 1);
	wait_irq(500, ok); read_regs(st, sp, it);
	expect8("T17 astat phase DATA IN", {5'd0, st[2:0]}, {5'd0, PH_DIN});
	set_tc(16'd6); reg_wr(R_CMD, 8'h90);
	pdma_rd(b); expect8("T17 astat idle", b, 8'h05);
	pdma_rd(b); expect8("T17 astat[1]", b, 8'h00);
	pdma_rd(b); expect8("T17 astat ctrl", b, 8'h14);
	for (k = 0; k < 3; k = k + 1) pdma_rd(b);
	wait_irq(500, ok); reg_wr(R_CMD, 8'h11); wait_irq(500, ok);
	reg_rd(R_FIFO, b); expect8("T17 astat status GOOD", b, 8'h00); reg_rd(R_FIFO, b);
	reg_wr(R_CMD, 8'h12); wait_irq(500, ok); read_regs(st, sp, it);
	sel_id = 8'h00;

	// A shutdown resets the SCSI bus and ejects the CD right after.  The
	// reset owes the ARM a $FE notice; on a slow platform that write is still
	// in flight when the eject's own forward is raised, and the second must
	// queue behind the first (both reach the ARM, STATUS waits for both).
	$display("-- T18 CD-ROM: eject selected while the bus-reset notice is still in flight (forwards serialize)");
	dev_lat = 3000;
	byi = win_writes;
	reg_wr(R_CMD, 8'h03);                          // RESET SCSI BUS: $FE owed
	repeat (8) @(negedge clk);
	reg_rd(R_INTR, b);
	repeat (60) @(negedge clk);                    // the notice is being written now
	sel_id = 8'h03;
	reg_wr(R_CMD, 8'h02); repeat (4) @(negedge clk);
	cdb[0]=8'h1B; cdb[1]=0; cdb[2]=0; cdb[3]=0; cdb[4]=8'h02; cdb[5]=0;
	unix_select(8'h42, 6, 1);
	wait_irq(20000, ok);
	read_regs(st, sp, it);
	expect8("T18 eject phase STATUS", {5'd0, st[2:0]}, {5'd0, PH_STAT});
	reg_wr(R_CMD, 8'h11); wait_irq(20000, ok);     // held until both forwards are acked
	reg_rd(R_FIFO, b); expect8("T18 eject status GOOD", b, 8'h00);
	reg_rd(R_FIFO, b);
	reg_wr(R_CMD, 8'h12); wait_irq(500, ok); read_regs(st, sp, it);
	guard = 0;
	while (win_writes - byi < 2 && guard < 20000) begin @(negedge clk); guard = guard + 1; end
	checks = checks + 1;
	if (win_writes - byi != 2) begin fails = fails + 1; $display("  FAIL T18 command blocks received %0d, want 2", win_writes - byi); end
	reg_wr(R_CMD, 8'h02); repeat (4) @(negedge clk);
	cdb[0]=8'h00; cdb[1]=0; cdb[2]=0; cdb[3]=0; cdb[4]=0; cdb[5]=0;
	unix_select(8'h42, 6, 1);
	wait_irq(500, ok);
	reg_wr(R_CMD, 8'h11); wait_irq(500, ok);
	reg_rd(R_FIFO, b); expect8("T18 TUR after eject CHECK", b, 8'h02);
	reg_rd(R_FIFO, b);
	reg_wr(R_CMD, 8'h12); wait_irq(500, ok); read_regs(st, sp, it);
	reg_wr(R_CMD, 8'h03);                          // RESET SCSI BUS: the disc is back
	repeat (8) @(negedge clk);
	reg_rd(R_INTR, b);
	repeat (8000) @(negedge clk);                  // let that notice complete on the slow device
	dev_lat = 40;
	sel_id = 8'h00;

	// Phase 2: the transport commands are forwarded to the ARM's playhead, the
	// engine asks the ARM its state ($CC window) after each one and streams
	// frames from the next-frame window while it says "playing"; the status
	// commands come from the response window.  The device is the flat
	// 16-sector disc: the ARM plays silence, but the state and the playhead
	// are real (sim/cd_window.cpp = the Main fork's own mac_cdrom_play.cpp).
	$display("-- T19 CD-ROM: PLAY AUDIO MSF forwarded, status poked, frames fetched; $CC/$C2/$42 from the window; PAUSE/RESUME/STOP");
	sel_id = 8'h03;
	byi = win_writes; k2 = frame_reads; it2 = stat_reads[7:0];
	// PLAY AUDIO MSF 00:02:00 .. 00:02:08 = disc LBA 0..8 (the +150 form)
	reg_wr(R_CMD, 8'h02); repeat (4) @(negedge clk);
	cdb[0]=8'h47; cdb[1]=0; cdb[2]=0; cdb[3]=8'd0; cdb[4]=8'd2; cdb[5]=8'd0; cdb[6]=8'd0; cdb[7]=8'd2; cdb[8]=8'd8; cdb[9]=0;
	unix_select(8'h42, 10, 1);
	wait_irq(500, ok); read_regs(st, sp, it);
	expect8("T19 play phase STATUS", {5'd0, st[2:0]}, {5'd0, PH_STAT});
	reg_wr(R_CMD, 8'h11); wait_irq(2000, ok);      // STATUS waits for the ARM's ack
	reg_rd(R_FIFO, b); expect8("T19 play status GOOD", b, 8'h00);
	reg_rd(R_FIFO, b);
	reg_wr(R_CMD, 8'h12); wait_irq(500, ok); read_regs(st, sp, it);
	if (win_writes - byi != 1) begin fails = fails + 1; $display("  FAIL T19 command blocks received %0d, want 1", win_writes - byi); end
	// the engine asks the ARM: playing
	guard = 0;
	while (dut.g_cd_audio.cd_audio_i.ast != 8'd0 && guard < 20000) begin @(negedge clk); guard = guard + 1; end
	expect8("T19 engine state after the poke: play", dut.g_cd_audio.cd_audio_i.ast, 8'h00);
	if (stat_reads[7:0] - it2 != 8'd1) begin fails = fails + 1; $display("  FAIL T19 status pokes %0d, want 1", stat_reads[7:0] - it2); end
	// ...and fills both halves from the next-frame window, 5 blocks each
	guard = 0;
	while (dut.g_cd_audio.cd_audio_i.fr_valid != 2'b11 && guard < 40000) begin @(negedge clk); guard = guard + 1; end
	expect8("T19 both frame halves valid", {6'd0, dut.g_cd_audio.cd_audio_i.fr_valid}, 8'h03);
	if (frame_reads - k2 != 2) begin fails = fails + 1; $display("  FAIL T19 frame reads %0d, want 2", frame_reads - k2); end
	expect8("T19 frame read is a 5-block transaction", frame_blk[7:0], 8'd4);
	expect8("T19 generation latched", {7'd0, dut.g_cd_audio.cd_audio_i.gen_r == dut.g_cd_audio.cd_audio_i.pad_gen}, 8'h01);
	// AUDIO STATUS from the window: playing, ctrl $14
	reg_wr(R_CMD, 8'h02); repeat (4) @(negedge clk);
	cdb[0]=8'hCC; cdb[1]=0; cdb[2]=0; cdb[3]=0; cdb[4]=0; cdb[5]=0; cdb[6]=0; cdb[7]=0; cdb[8]=8'd6; cdb[9]=0;
	unix_select(8'h42, 10, 1);
	wait_irq(500, ok); read_regs(st, sp, it);
	expect8("T19 astat phase DATA IN", {5'd0, st[2:0]}, {5'd0, PH_DIN});
	set_tc(16'd6); reg_wr(R_CMD, 8'h90);
	pdma_rd(b); expect8("T19 astat play", b, 8'h00);
	pdma_rd(b); expect8("T19 astat[1]", b, 8'h00);
	pdma_rd(b); expect8("T19 astat ctrl", b, 8'h14);
	for (k = 0; k < 3; k = k + 1) pdma_rd(b);
	wait_irq(500, ok); reg_wr(R_CMD, 8'h11); wait_irq(500, ok);
	reg_rd(R_FIFO, b); expect8("T19 astat status GOOD", b, 8'h00); reg_rd(R_FIFO, b);
	reg_wr(R_CMD, 8'h12); wait_irq(500, ok); read_regs(st, sp, it);
	// READ Q SUBCODE from the window: ctrl, track 1 BCD, index 1, then MSF;
	// the playhead sits two frames in (two fetches): abs F = 02
	reg_wr(R_CMD, 8'h02); repeat (4) @(negedge clk);
	cdb[0]=8'hC2; cdb[8]=8'd9;
	unix_select(8'h42, 10, 1);
	wait_irq(500, ok); read_regs(st, sp, it);
	set_tc(16'd9); reg_wr(R_CMD, 8'h90);
	pdma_rd(b); expect8("T19 subq ctrl", b, 8'h14);
	pdma_rd(b); expect8("T19 subq track", b, 8'h01);
	pdma_rd(b); expect8("T19 subq index", b, 8'h01);
	for (k = 0; k < 5; k = k + 1) pdma_rd(b);
	pdma_rd(b); expect8("T19 subq abs F = 2 frames in", b, 8'h02);
	wait_irq(500, ok); reg_wr(R_CMD, 8'h11); wait_irq(500, ok);
	reg_rd(R_FIFO, b); expect8("T19 subq status GOOD", b, 8'h00); reg_rd(R_FIFO, b);
	reg_wr(R_CMD, 8'h12); wait_irq(500, ok); read_regs(st, sp, it);
	// READ SUB-CHANNEL format 1: audio status $11 (playing), format byte 1
	reg_wr(R_CMD, 8'h02); repeat (4) @(negedge clk);
	cdb[0]=8'h42; cdb[1]=0; cdb[2]=8'h40; cdb[3]=8'h01; cdb[4]=0; cdb[5]=0; cdb[6]=0; cdb[7]=0; cdb[8]=8'd16; cdb[9]=0;
	unix_select(8'h42, 10, 1);
	wait_irq(500, ok); read_regs(st, sp, it);
	set_tc(16'd16); reg_wr(R_CMD, 8'h90);
	pdma_rd(b);
	pdma_rd(b); expect8("T19 subch audio status playing", b, 8'h11);
	pdma_rd(b); pdma_rd(b);
	pdma_rd(b); expect8("T19 subch format 1", b, 8'h01);
	for (k = 0; k < 11; k = k + 1) pdma_rd(b);
	wait_irq(500, ok); reg_wr(R_CMD, 8'h11); wait_irq(500, ok);
	reg_rd(R_FIFO, b); expect8("T19 subch status GOOD", b, 8'h00); reg_rd(R_FIFO, b);
	reg_wr(R_CMD, 8'h12); wait_irq(500, ok); read_regs(st, sp, it);
	// the cadence consumes a frame (588 samples at 44.1 kHz of a 33 MHz clock)
	// and the freed half is refilled
	guard = 0;
	while (frame_reads - k2 < 3 && guard < 800000) begin @(negedge clk); guard = guard + 1; end
	if (frame_reads - k2 != 3) begin fails = fails + 1; $display("  FAIL T19 third frame not fetched after a frame was consumed (%0d reads)", frame_reads - k2); end
	else $display("   T19 third frame fetched after %0d cycles", guard);
	// PAUSE: forwarded, the poke says paused, the buffered frames are dropped
	reg_wr(R_CMD, 8'h02); repeat (4) @(negedge clk);
	cdb[0]=8'h4B; cdb[1]=0; cdb[2]=0; cdb[3]=0; cdb[4]=0; cdb[5]=0; cdb[6]=0; cdb[7]=0; cdb[8]=8'h00; cdb[9]=0;
	unix_select(8'h42, 10, 1);
	wait_irq(500, ok); read_regs(st, sp, it);
	reg_wr(R_CMD, 8'h11); wait_irq(2000, ok);
	reg_rd(R_FIFO, b); expect8("T19 pause status GOOD", b, 8'h00); reg_rd(R_FIFO, b);
	reg_wr(R_CMD, 8'h12); wait_irq(500, ok); read_regs(st, sp, it);
	guard = 0;
	while (dut.g_cd_audio.cd_audio_i.ast != 8'd1 && guard < 20000) begin @(negedge clk); guard = guard + 1; end
	expect8("T19 engine state after PAUSE", dut.g_cd_audio.cd_audio_i.ast, 8'h01);
	expect8("T19 one poke per forwarded command (PLAY, PAUSE)", poke_stbs[7:0], 8'd2);
	expect8("T19 frames dropped on PAUSE", {6'd0, dut.g_cd_audio.cd_audio_i.fr_valid}, 8'h00);
	k2 = frame_reads;
	repeat (50000) @(negedge clk);
	if (frame_reads != k2) begin fails = fails + 1; $display("  FAIL T19 fetches while paused"); end
	// RESUME: playing again, the fetch loop restarts
	reg_wr(R_CMD, 8'h02); repeat (4) @(negedge clk);
	cdb[8]=8'h01;
	unix_select(8'h42, 10, 1);
	wait_irq(500, ok); read_regs(st, sp, it);
	reg_wr(R_CMD, 8'h11); wait_irq(2000, ok);
	reg_rd(R_FIFO, b); expect8("T19 resume status GOOD", b, 8'h00); reg_rd(R_FIFO, b);
	reg_wr(R_CMD, 8'h12); wait_irq(500, ok); read_regs(st, sp, it);
	guard = 0;
	while (frame_reads - k2 < 2 && guard < 60000) begin @(negedge clk); guard = guard + 1; end
	expect8("T19 engine state after RESUME", dut.g_cd_audio.cd_audio_i.ast, 8'h00);
	if (frame_reads - k2 != 2) begin fails = fails + 1; $display("  FAIL T19 frame reads after RESUME %0d, want 2", frame_reads - k2); end
	// STOP PLAY: idle, nothing buffered
	reg_wr(R_CMD, 8'h02); repeat (4) @(negedge clk);
	cdb[0]=8'h4E; cdb[8]=0;
	unix_select(8'h42, 10, 1);
	wait_irq(500, ok); read_regs(st, sp, it);
	reg_wr(R_CMD, 8'h11); wait_irq(2000, ok);
	reg_rd(R_FIFO, b); expect8("T19 stop status GOOD", b, 8'h00); reg_rd(R_FIFO, b);
	reg_wr(R_CMD, 8'h12); wait_irq(500, ok); read_regs(st, sp, it);
	guard = 0;
	while (dut.g_cd_audio.cd_audio_i.ast != 8'd5 && guard < 20000) begin @(negedge clk); guard = guard + 1; end
	expect8("T19 engine state after STOP", dut.g_cd_audio.cd_audio_i.ast, 8'h05);
	expect8("T19 one poke per forwarded command (RESUME, STOP)", poke_stbs[7:0], 8'd4);
	expect8("T19 nothing buffered after STOP", {6'd0, dut.g_cd_audio.cd_audio_i.fr_valid}, 8'h00);
	// AUDIO STATUS: idle
	reg_wr(R_CMD, 8'h02); repeat (4) @(negedge clk);
	cdb[0]=8'hCC; cdb[1]=0; cdb[2]=0; cdb[3]=0; cdb[4]=0; cdb[5]=0; cdb[6]=0; cdb[7]=0; cdb[8]=8'd6; cdb[9]=0;
	unix_select(8'h42, 10, 1);
	wait_irq(500, ok); read_regs(st, sp, it);
	set_tc(16'd6); reg_wr(R_CMD, 8'h90);
	pdma_rd(b); expect8("T19 astat idle after STOP", b, 8'h05);
	for (k = 0; k < 5; k = k + 1) pdma_rd(b);
	wait_irq(500, ok); reg_wr(R_CMD, 8'h11); wait_irq(500, ok);
	reg_rd(R_FIFO, b); reg_rd(R_FIFO, b);
	reg_wr(R_CMD, 8'h12); wait_irq(500, ok); read_regs(st, sp, it);
	sel_id = 8'h00;

	// The nexus and the audio engine decide their channel requests in the
	// same cycle from the same registered state -- the nexus on !io_busy,
	// the engine on ch_grant -- so both can go up together.  Make it happen
	// on purpose: the engine's status poke (its housekeeping read after a
	// forwarded transport command) is in flight on a slow platform, the
	// cadence frees a half meanwhile so the frame fetch waits in F_REQ, and
	// a nexus request waits on io_busy; the cycle after the poke's ack falls
	// both are raised.  Before the channel owner register the platform saw
	// the DISK's flush with the engine's address and block count (a write
	// into nowhere and, its ack masked, the same request served again for
	// ever: the Quad Squad image with system error 41 and the AppleCD
	// player's "drive not responding", 2026-09-16).  Twice: a disk WRITE
	// flush, then a guest AUDIO STATUS window read.  The test asserts its
	// own preconditions, so a drift of the cadence against the 300,000-cycle
	// device shows as a failure, never as a silent pass.
	$display("-- T20 CD-ROM: a disk WRITE flush, then a guest $CC read, raised in the same cycle as the engine's frame fetch (channel owner)");
	sel_id = 8'h03;
	k2 = frame_reads; byi = collisions;
	// (a) PLAY AUDIO MSF 00:02:00 .. 00:02:16 (the whole 16-sector disc):
	// forwarded, poked, both halves fetched
	reg_wr(R_CMD, 8'h02); repeat (4) @(negedge clk);
	cdb[0]=8'h47; cdb[1]=0; cdb[2]=0; cdb[3]=8'd0; cdb[4]=8'd2; cdb[5]=8'd0; cdb[6]=8'd0; cdb[7]=8'd2; cdb[8]=8'd16; cdb[9]=0;
	unix_select(8'h42, 10, 1);
	wait_irq(500, ok); read_regs(st, sp, it);
	reg_wr(R_CMD, 8'h11); wait_irq(2000, ok);
	reg_rd(R_FIFO, b); expect8("T20 play status GOOD", b, 8'h00); reg_rd(R_FIFO, b);
	reg_wr(R_CMD, 8'h12); wait_irq(500, ok); read_regs(st, sp, it);
	guard = 0;
	while (dut.g_cd_audio.cd_audio_i.fr_valid != 2'b11 && guard < 40000) begin @(negedge clk); guard = guard + 1; end
	expect8("T20 playing with both halves valid", {6'd0, dut.g_cd_audio.cd_audio_i.fr_valid}, 8'h03);
	if (frame_reads - k2 != 2) begin fails = fails + 1; $display("  FAIL T20 frame reads %0d, want 2", frame_reads - k2); end

	// (b) the platform turns slow.  A second PLAY (the ARM moves its playhead;
	// the engine keeps playing what it holds until the next frame's pad shows
	// the new generation) takes 300,000 cycles to forward and its status
	// poke another 300,000; one frame is ~442,000 cycles, so the cadence
	// frees a half while the poke is in flight and the fetch queues in F_REQ.
	dev_lat = 300000;
	reg_wr(R_CMD, 8'h02); repeat (4) @(negedge clk);
	cdb[0]=8'h47; cdb[1]=0; cdb[2]=0; cdb[3]=8'd0; cdb[4]=8'd2; cdb[5]=8'd4; cdb[6]=8'd0; cdb[7]=8'd2; cdb[8]=8'd16; cdb[9]=0;
	unix_select(8'h42, 10, 1);
	wait_irq(500, ok); read_regs(st, sp, it);
	reg_wr(R_CMD, 8'h11); wait_irq(320000, ok);        // STATUS is held until the forward's ack
	reg_rd(R_FIFO, b); expect8("T20 play 2 status GOOD", b, 8'h00); reg_rd(R_FIFO, b);
	reg_wr(R_CMD, 8'h12); wait_irq(500, ok); read_regs(st, sp, it);
	guard = 0;
	while (!dut.g_cd_audio.cd_audio_i.hk_act && guard < 200) begin @(negedge clk); guard = guard + 1; end
	expect8("T20 status poke in flight", {7'd0, dut.g_cd_audio.cd_audio_i.hk_act}, 8'h01);

	// (c) a disk WRITE(6) of one block at LBA 60, pushed as one TC=512 TI:
	// the bytes drain into the sector buffer while the poke is out, the
	// flush waits on io_busy (so does the chunk's bus service: nexus_io)
	sel_id = 8'h00;
	t20_wr = wr_blocks;
	reg_wr(R_CMD, 8'h02); repeat (4) @(negedge clk);
	cdb[0]=8'h0A; cdb[1]=0; cdb[2]=0; cdb[3]=8'd60; cdb[4]=8'd1; cdb[5]=0;
	unix_select(8'h42, 6, 1);
	wait_irq(500, ok); read_regs(st, sp, it);
	expect8("T20 write phase DATA OUT", {5'd0, st[2:0]}, {5'd0, PH_DOUT});
	reg_wr(R_CMD, 8'h01);
	set_tc(16'd512); reg_wr(R_CMD, 8'h90);
	for (k = 0; k < 512; k = k + 1) begin
		guard = 0;
		while (!drq && guard < 100000) begin @(negedge clk); guard = guard + 1; end
		if (guard >= 100000) begin fails = fails + 1; $display("  FAIL T20 DREQ stalled at byte %0d", k); k = 512; end
		else pdma_wr((k*5 + 3) & 8'hFF);
	end
	// the preconditions: the poke still out, the flush waiting on it, and
	// the cadence frees a half before the poke ends -> the fetch queues
	guard = 0;
	while (dut.g_cd_audio.cd_audio_i.fst != 2'd1 && dut.g_cd_audio.cd_audio_i.hk_act && guard < 500000) begin @(negedge clk); guard = guard + 1; end
	expect8("T20 poke still in flight when the fetch queued", {7'd0, dut.g_cd_audio.cd_audio_i.hk_act}, 8'h01);
	expect8("T20 fetch waiting in F_REQ", {6'd0, dut.g_cd_audio.cd_audio_i.fst}, 8'h01);
	expect8("T20 flush waiting on io_busy", {7'd0, (dut.sbuf_pos == 10'd512) && !dut.io_wr_i && !dut.flush_pending}, 8'h01);
	dev_lat = 40;                                   // whatever follows the poke is quick
	guard = 0;
	while (dut.g_cd_audio.cd_audio_i.hk_act && guard < 320000) begin @(negedge clk); guard = guard + 1; end
	repeat (8) @(negedge clk);
	if (collisions - byi == 0) begin fails = fails + 1; $display("  FAIL T20 no same-cycle collision was produced (the flush vs the fetch)"); end
	else $display("   T20 flush/fetch collision cycles: %0d", collisions - byi);
	// the write completes: its bus service comes once the flush (and the
	// engine's fetch behind it) is done, with STATUS showing
	wait_irq(20000, ok); read_regs(st, sp, it);
	expect8("T20 phase STATUS after the write", {5'd0, st[2:0]}, {5'd0, PH_STAT});
	reg_wr(R_CMD, 8'h11); wait_irq(500, ok);
	reg_rd(R_FIFO, b); expect8("T20 write status GOOD", b, 8'h00); reg_rd(R_FIFO, b);
	reg_wr(R_CMD, 8'h12); wait_irq(500, ok); read_regs(st, sp, it);
	// the block landed where it was sent, once, intact; no disk request went
	// out with the engine's address or block count
	guard = 0;
	while (wr_blocks - t20_wr != 1 && guard < 20000) begin @(negedge clk); guard = guard + 1; end
	checks = checks + 1;
	if (wr_blocks - t20_wr != 1) begin fails = fails + 1; $display("  FAIL T20 disk blocks written %0d, want 1", wr_blocks - t20_wr); end
	for (k = 0; k < 512; k = k + 1) begin
		if (disk[60*512 + k] !== ((k*5 + 3) & 8'hFF)) begin
			fails = fails + 1;
			if (fails < 20) $display("  FAIL T20 disk byte %0d: got %02X want %02X", k, disk[60*512 + k], (k*5 + 3) & 8'hFF);
		end
		checks = checks + 1;
	end
	expect8("T20 no disk request astray", bad_disk_req[7:0], 8'd0);
	// the queued frame fetch went out after the flush, 5 blocks at its own
	// address; the poke's answer was "playing"; the new position's frames
	// fill both halves (the generation change drops the old one)
	guard = 0;
	while (frame_reads - k2 < 3 && guard < 20000) begin @(negedge clk); guard = guard + 1; end
	if (frame_reads - k2 < 3) begin fails = fails + 1; $display("  FAIL T20 the queued frame fetch never went out (%0d frame reads)", frame_reads - k2); end
	expect8("T20 frame read is a 5-block transaction", frame_blk[7:0], 8'd4);
	expect8("T20 engine playing after the poke", dut.g_cd_audio.cd_audio_i.ast, 8'h00);
	guard = 0;
	while (dut.g_cd_audio.cd_audio_i.fr_valid != 2'b11 && guard < 40000) begin @(negedge clk); guard = guard + 1; end
	expect8("T20 both halves valid again", {6'd0, dut.g_cd_audio.cd_audio_i.fr_valid}, 8'h03);

	// (d) the same collision with a guest window read: a third PLAY, its
	// poke in flight, the cadence frees a half, the guest's AUDIO STATUS
	// waits on io_busy
	sel_id = 8'h03;
	dev_lat = 300000;
	reg_wr(R_CMD, 8'h02); repeat (4) @(negedge clk);
	cdb[0]=8'h47; cdb[1]=0; cdb[2]=0; cdb[3]=8'd0; cdb[4]=8'd2; cdb[5]=8'd8; cdb[6]=8'd0; cdb[7]=8'd2; cdb[8]=8'd16; cdb[9]=0;
	unix_select(8'h42, 10, 1);
	wait_irq(500, ok); read_regs(st, sp, it);
	reg_wr(R_CMD, 8'h11); wait_irq(320000, ok);
	reg_rd(R_FIFO, b); expect8("T20 play 3 status GOOD", b, 8'h00); reg_rd(R_FIFO, b);
	reg_wr(R_CMD, 8'h12); wait_irq(500, ok); read_regs(st, sp, it);
	guard = 0;
	while (!dut.g_cd_audio.cd_audio_i.hk_act && guard < 200) begin @(negedge clk); guard = guard + 1; end
	expect8("T20 status poke 3 in flight", {7'd0, dut.g_cd_audio.cd_audio_i.hk_act}, 8'h01);
	t20_col = collisions; k2 = frame_reads;
	reg_wr(R_CMD, 8'h02); repeat (4) @(negedge clk);
	cdb[0]=8'hCC; cdb[1]=0; cdb[2]=0; cdb[3]=0; cdb[4]=0; cdb[5]=0; cdb[6]=0; cdb[7]=0; cdb[8]=8'd6; cdb[9]=0;
	unix_select(8'h42, 10, 1);
	wait_irq(500, ok); read_regs(st, sp, it);
	expect8("T20 astat phase DATA IN", {5'd0, st[2:0]}, {5'd0, PH_DIN});
	guard = 0;
	while (dut.g_cd_audio.cd_audio_i.fst != 2'd1 && dut.g_cd_audio.cd_audio_i.hk_act && guard < 500000) begin @(negedge clk); guard = guard + 1; end
	expect8("T20 poke 3 still in flight when the fetch queued", {7'd0, dut.g_cd_audio.cd_audio_i.hk_act}, 8'h01);
	expect8("T20 fetch waiting in F_REQ (2)", {6'd0, dut.g_cd_audio.cd_audio_i.fst}, 8'h01);
	expect8("T20 window read waiting on io_busy", {7'd0, (dut.blocks_left == 32'd1) && !dut.io_rd_i && (dut.phase == PH_DIN)}, 8'h01);
	dev_lat = 40;
	guard = 0;
	while (dut.g_cd_audio.cd_audio_i.hk_act && guard < 320000) begin @(negedge clk); guard = guard + 1; end
	repeat (8) @(negedge clk);
	if (collisions - t20_col == 0) begin fails = fails + 1; $display("  FAIL T20 no same-cycle collision was produced (the window read vs the fetch)"); end
	else $display("   T20 window-read/fetch collision cycles: %0d", collisions - t20_col);
	// the guest gets its 6 bytes from its own window, the engine its frame
	set_tc(16'd6); reg_wr(R_CMD, 8'h90);
	pdma_rd(b); expect8("T20 astat after the collision: playing", b, 8'h00);
	pdma_rd(b); expect8("T20 astat[1]", b, 8'h00);
	pdma_rd(b); expect8("T20 astat ctrl", b, 8'h14);
	for (k = 0; k < 3; k = k + 1) pdma_rd(b);
	// the chunk ends while the engine's fetch behind the window read is
	// still out: the phase must move to STATUS now, not when the fetch ends
	// (the AppleCD player's first poll after PLAY hung in DATA IN, 2026-09-16)
	wait_irq(500, ok); read_regs(st, sp, it);
	expect8("T20 fetch still in flight at the chunk end", {7'd0, dut.ca_io_active}, 8'h01);
	expect8("T20 astat phase STATUS at the chunk end", {5'd0, st[2:0]}, {5'd0, PH_STAT});
	reg_wr(R_CMD, 8'h11); wait_irq(500, ok);
	reg_rd(R_FIFO, b); expect8("T20 astat status GOOD", b, 8'h00); reg_rd(R_FIFO, b);
	reg_wr(R_CMD, 8'h12); wait_irq(500, ok); read_regs(st, sp, it);
	guard = 0;
	while (frame_reads - k2 < 1 && guard < 20000) begin @(negedge clk); guard = guard + 1; end
	if (frame_reads - k2 < 1) begin fails = fails + 1; $display("  FAIL T20 the queued frame fetch never went out after the window read"); end
	expect8("T20 frame read is a 5-block transaction (2)", frame_blk[7:0], 8'd4);
	expect8("T20 engine playing after poke 3", dut.g_cd_audio.cd_audio_i.ast, 8'h00);
	guard = 0;
	while (dut.g_cd_audio.cd_audio_i.fr_valid != 2'b11 && guard < 40000) begin @(negedge clk); guard = guard + 1; end
	expect8("T20 both halves valid again (2)", {6'd0, dut.g_cd_audio.cd_audio_i.fr_valid}, 8'h03);
	expect8("T20 no disk request astray (2)", bad_disk_req[7:0], 8'd0);

	// (e) STOP, so the engine is idle for whatever follows
	reg_wr(R_CMD, 8'h02); repeat (4) @(negedge clk);
	cdb[0]=8'h4E; cdb[8]=0;
	unix_select(8'h42, 10, 1);
	wait_irq(500, ok); read_regs(st, sp, it);
	reg_wr(R_CMD, 8'h11); wait_irq(2000, ok);
	reg_rd(R_FIFO, b); expect8("T20 stop status GOOD", b, 8'h00); reg_rd(R_FIFO, b);
	reg_wr(R_CMD, 8'h12); wait_irq(500, ok); read_regs(st, sp, it);
	guard = 0;
	while (dut.g_cd_audio.cd_audio_i.ast != 8'd5 && guard < 20000) begin @(negedge clk); guard = guard + 1; end
	expect8("T20 engine idle after STOP", dut.g_cd_audio.cd_audio_i.ast, 8'h05);
	sel_id = 8'h00;

	//------------------------------------------------------------------
	$display("-- T21 ROM boot read shape: 2 PIO bytes + 510 DMA per sector, next PIO TI issued before the sector lands");
	//------------------------------------------------------------------
	// READ(10) of 4 blocks on a slow device (3000-clock round trip).  Per
	// sector the ROM driver takes 2 bytes by non-DMA TI ($10), then 510 by
	// DMA TI, flushes the FIFO twice and issues the next sector's first
	// non-DMA TI BEFORE the prefetched sector has landed.  Every byte must
	// be handed over, and STATUS only after the last one.  The two-half
	// buffer as first committed (583a98c) ended the command here with the
	// last sector unread, which hung the boot at the happy Mac.
	begin : t21
		integer fails0, sec, kk, g, lb, nb;
		reg [7:0] bb, want;
		fails0 = fails; lb = 48; nb = 4;
		dev_lat = 3000;
		sel_id = 8'h00;
		reg_wr(R_CMD, 8'h02); repeat (4) @(negedge clk);
		cdb[0]=8'h28; cdb[1]=0; cdb[2]=0; cdb[3]=0; cdb[4]=0; cdb[5]=lb[7:0]; cdb[6]=0; cdb[7]=0; cdb[8]=nb[7:0]; cdb[9]=0;
		unix_select(8'h42, 10, 1);
		wait_irq(4000, ok);
		read_regs(st, sp, it2);
		expect8("T21 phase DATA IN", {5'd0, st[2:0]}, {5'd0, PH_DIN});
		for (sec = 0; sec < nb && fails == fails0; sec = sec + 1) begin
			for (kk = 0; kk < 2; kk = kk + 1) begin
				g = sec * 512 + kk;
				reg_wr(R_CMD, 8'h10);
				wait_irq(40000, ok);
				read_regs(st, sp, it2);
				reg_rd(R_FIFO, bb);
				want = disk[lb*512 + g];
				checks = checks + 1;
				if (bb !== want || (st[2:0] != PH_DIN && st[2:0] != PH_STAT)) begin
					fails = fails + 1;
					$display("  FAIL T21 sector %0d PIO byte %0d: got %02X want %02X, phase %0d intr %02X (blocks_left=%0d buf_valid=%0d sbuf_pos=%0d)",
					         sec, kk, bb, want, st[2:0], it2, dut.blocks_left, dut.buf_valid, dut.sbuf_pos);
				end
				if (st[2:0] == PH_STAT) begin
					fails = fails + 1;
					$display("  FAIL T21 STATUS after PIO byte %0d of sector %0d (of %0d): the command ended with %0d bytes unread", kk, sec, nb, nb*512 - g - 1);
					kk = 2; sec = nb;
				end
			end
			if (sec < nb) begin
				set_tc(16'd510);
				reg_wr(R_CMD, 8'h90);
				for (kk = 2; kk < 512; kk = kk + 1) begin
					g = sec * 512 + kk;
					pdma_rd(bb);
					want = disk[lb*512 + g];
					checks = checks + 1;
					if (bb !== want) begin
						fails = fails + 1;
						if (fails < fails0 + 6) $display("  FAIL T21 sector %0d DMA byte %0d: got %02X want %02X", sec, kk, bb, want);
					end
				end
				wait_irq(200000, ok);
				read_regs(st, sp, it2);
				expect8("T21 phase after the sector", {5'd0, st[2:0]}, {5'd0, (sec == nb - 1) ? PH_STAT : PH_DIN});
				reg_wr(R_CMD, 8'h01); reg_wr(R_CMD, 8'h01);
			end
		end
		if (st[2:0] != PH_STAT) begin
			guard = 0;
			while (st[2:0] != PH_STAT && guard < 100000) begin @(negedge clk); guard = guard + 1; read_regs(st, sp, it2); end
		end
		reg_wr(R_CMD, 8'h11); wait_irq(4000, ok);
		reg_rd(R_FIFO, bb); reg_rd(R_FIFO, bb);
		reg_wr(R_CMD, 8'h12); wait_irq(4000, ok); read_regs(st, sp, it2);
		dev_lat = 40;
		$display("   T21 failures added: %0d", fails - fails0);
	end
	sel_id = 8'h00;

	//------------------------------------------------------------------
	$display("-- T22 two-half buffer: READ(10)/WRITE(10) of 8 blocks x 6 rounds, random 200-2000-clock acks, random guest pauses");
	//------------------------------------------------------------------
	// Even rounds: one TI for all 8 blocks (TC=4096).  Odd rounds: one TI
	// per sector with the interrupt taken between sectors (the System 7.5.5
	// SCSI Manager's shape).  Each round: READ(10) of 8 blocks at lba 48
	// (every byte checked, 8 requests), then WRITE(10) of 8 blocks at lba 24
	// (the data, the LBA order, and the last chunk's interrupt and the
	// status byte only after the last flush's ack fell).  Every platform
	// request is acked after dev_lat + 0..dev_lat_jit clocks; each sector
	// gets a random guest pause profile (none; 1/64 bytes 10-210 clk; 1/16
	// bytes 50-650 clk).  Across the six READs at least one request must be
	// raised while the guest is still draining the previous sector -- the
	// overlap the two halves exist for, which the single-buffer engine
	// (703b22a) never makes.
	begin : t22
		integer rep, mode, kk, g, sec, nsec, tcn, nb, lb, rnd, pmode, fails0, ovl0, wcc, wccfp, nw0, j, req0, ovl_tot, phase_early;
		reg [7:0] bb, want;
		reg [63:0] irq_cyc;
		fails0 = fails; ovl_tot = 0; phase_early = 0;
		nb = 8;
		rnd = 32'h0260_2929;
		for (rep = 0; rep < 6; rep = rep + 1) begin
			mode = rep % 2;
			nsec = mode ? nb : 1;
			tcn  = mode ? 512 : nb * 512;
			// ---- READ(10) of 8 blocks at lba 48
			lb = 48;
			dev_lcg = (32'h0000_1000 + rep * 977) ^ lat_seed;
			dev_lat = 200; dev_lat_jit = 1800;
			sel_id = 8'h00;
			reg_wr(R_CMD, 8'h02); repeat (4) @(negedge clk);
			ovl0 = rd_ovl; req0 = disk_rd_reqs;
			rd_base = disk_rd_reqs; rd_drained = 0; rd_track = 1;
			cdb[0]=8'h28; cdb[1]=0; cdb[2]=0; cdb[3]=0; cdb[4]=0; cdb[5]=lb[7:0]; cdb[6]=0; cdb[7]=0; cdb[8]=nb[7:0]; cdb[9]=0;
			unix_select(8'h42, 10, 1);
			wait_irq(4000, ok);
			read_regs(st, sp, it2);
			expect8("T22 read phase DATA IN", {5'd0, st[2:0]}, {5'd0, PH_DIN});
			for (sec = 0; sec < nsec; sec = sec + 1) begin
				set_tc(tcn[15:0]);
				reg_wr(R_CMD, 8'h90);
				for (kk = 0; kk < tcn; kk = kk + 1) begin
					g = mode ? sec * 512 + kk : kk;
					if (g % 512 == 0) begin rnd = rnd * 1103515245 + 12345; pmode = (rnd >> 16) % 3; end
					pdma_rd(bb);
					rd_drained = rd_drained + 1;
					want = disk[lb*512 + g];
					checks = checks + 1;
					if (bb !== want) begin
						fails = fails + 1;
						if (fails < fails0 + 8) $display("  FAIL T22 rep=%0d read byte %0d (block %0d): got %02X want %02X", rep, g, g/512, bb, want);
					end
					rnd = rnd * 1103515245 + 12345;
					if (pmode == 1 && ((rnd >> 16) % 64) == 0) repeat (10 + ((rnd >> 22) % 200)) @(negedge clk);
					if (pmode == 2 && ((rnd >> 16) % 16) == 0) repeat (50 + ((rnd >> 22) % 600)) @(negedge clk);
				end
				wait_irq(200000, ok);
				read_regs(st, sp, it2);
				if (sec < nsec - 1) expect8("T22 read mid phase DATA IN", {5'd0, st[2:0]}, {5'd0, PH_DIN});
			end
			rd_track = 0;
			expect8("T22 read phase STATUS", {5'd0, st[2:0]}, {5'd0, PH_STAT});
			reg_wr(R_CMD, 8'h11); wait_irq(4000, ok);
			reg_rd(R_FIFO, bb); expect8("T22 read status GOOD", bb, 8'h00);
			reg_rd(R_FIFO, bb);
			reg_wr(R_CMD, 8'h12); wait_irq(4000, ok); read_regs(st, sp, it2);
			$display("   T22 rep %0d (%0s) READ : requests %0d, raised while the guest was still draining %0d",
			         rep, mode ? "TI per sector" : "one TI", disk_rd_reqs - req0, rd_ovl - ovl0);
			checks = checks + 1;
			if (disk_rd_reqs - req0 != nb) begin fails = fails + 1; $display("  FAIL T22 rep=%0d read made %0d requests (want %0d)", rep, disk_rd_reqs - req0, nb); end
			ovl_tot = ovl_tot + (rd_ovl - ovl0);

			// ---- WRITE(10) of 8 blocks at lba 24
			lb = 24;
			dev_lcg = (32'h0000_7000 + rep * 1231) ^ lat_seed;
			nw0 = wr_blocks; wcc = 0; wccfp = 0;
			reg_wr(R_CMD, 8'h02); repeat (4) @(negedge clk);
			cdb[0]=8'h2A; cdb[1]=0; cdb[2]=0; cdb[3]=0; cdb[4]=0; cdb[5]=lb[7:0]; cdb[6]=0; cdb[7]=0; cdb[8]=nb[7:0]; cdb[9]=0;
			unix_select(8'h42, 10, 1);
			wait_irq(4000, ok);
			read_regs(st, sp, it2);
			expect8("T22 write phase DATA OUT", {5'd0, st[2:0]}, {5'd0, PH_DOUT});
			reg_wr(R_CMD, 8'h01);
			irq_cyc = 0;
			for (sec = 0; sec < nsec; sec = sec + 1) begin
				set_tc(tcn[15:0]);
				reg_wr(R_CMD, 8'h90);
				for (kk = 0; kk < tcn; kk = kk + 1) begin
					g = mode ? sec * 512 + kk : kk;
					if (g % 512 == 0) begin rnd = rnd * 1103515245 + 12345; pmode = (rnd >> 16) % 3; end
					guard = 0;
					while (!drq && guard < 200000) begin @(negedge clk); guard = guard + 1; end
					if (guard >= 200000) begin
						fails = fails + 1;
						$display("  FAIL T22 rep=%0d WRITE DREQ never returned at byte %0d", rep, g);
						kk = tcn; sec = nsec;
					end
					else begin
						pdma_wr((g*13 + rep*29 + (g >> 9)) & 8'hFF);
						rnd = rnd * 1103515245 + 12345;
						if (pmode == 1 && ((rnd >> 16) % 64) == 0) repeat (10 + ((rnd >> 22) % 200)) @(negedge clk);
						if (pmode == 2 && ((rnd >> 16) % 16) == 0) repeat (50 + ((rnd >> 22) % 600)) @(negedge clk);
					end
				end
				wait_irq(200000, ok);
				irq_cyc = cyc;
				wcc = wcc + 1;
				if (io_wr || d_state == 3 || d_state == 4) wccfp = wccfp + 1;   // a flush still with the platform
				read_regs(st, sp, it2);
				if (sec < nsec - 1) expect8("T22 write mid phase DATA OUT", {5'd0, st[2:0]}, {5'd0, PH_DOUT});
			end
			// the last chunk's interrupt must follow the last flush's ack fall
			checks = checks + 1;
			if (!(irq_cyc > wr_ackfall) || wr_blocks - nw0 != nb) begin
				fails = fails + 1;
				$display("  FAIL T22 rep=%0d last chunk interrupt at %0d, last flush ack fell at %0d, flushes done %0d",
				         rep, irq_cyc, wr_ackfall, wr_blocks - nw0);
			end
			guard = 0;
			while (st[2:0] != PH_STAT && guard < 400000) begin @(negedge clk); guard = guard + 1; read_regs(st, sp, it2); end
			expect8("T22 write phase STATUS", {5'd0, st[2:0]}, {5'd0, PH_STAT});
			// the phase bits read STATUS from the moment the last flush is
			// RAISED (for the ROM's PIO write loop); informational
			if (stat_cyc < wr_ackfall) phase_early = phase_early + 1;
			reg_wr(R_CMD, 8'h11); wait_irq(4000, ok);
			// the status byte is delivered (I_FC) only after the last flush's ack fell, all 8 accepted
			checks = checks + 1;
			if (!(cyc > wr_ackfall) || wr_blocks - nw0 != nb) begin
				fails = fails + 1;
				$display("  FAIL T22 rep=%0d status delivered at %0d, last flush ack fell at %0d, flushes done %0d", rep, cyc, wr_ackfall, wr_blocks - nw0);
			end
			reg_rd(R_FIFO, bb); expect8("T22 write status GOOD", bb, 8'h00);
			reg_rd(R_FIFO, bb);
			reg_wr(R_CMD, 8'h12); wait_irq(4000, ok); read_regs(st, sp, it2);
			dev_lat = 40; dev_lat_jit = 0;
			// the LBA sequence the device accepted, in order
			for (j = 0; j < nb; j = j + 1) begin
				checks = checks + 1;
				if (wr_lba_log[(nw0 + j) % 256] != lb + j) begin
					fails = fails + 1;
					$display("  FAIL T22 rep=%0d flush %0d went to lba %0d (want %0d)", rep, j, wr_lba_log[(nw0 + j) % 256], lb + j);
				end
			end
			// the flushed data
			for (g = 0; g < nb * 512; g = g + 1) begin
				checks = checks + 1;
				if (disk[lb*512 + g] !== ((g*13 + rep*29 + (g >> 9)) & 8'hFF)) begin
					fails = fails + 1;
					if (fails < fails0 + 16) $display("  FAIL T22 rep=%0d disk byte %0d (block %0d): got %02X want %02X", rep, g, g/512, disk[lb*512 + g], (g*13 + rep*29 + (g >> 9)) & 8'hFF);
				end
			end
			$display("   T22 rep %0d (%0s) WRITE: flushes %0d (lba %0d..%0d), chunk completions %0d, with a flush in flight %0d; last-chunk INT %0d clk after the last ack fell",
			         rep, mode ? "TI per sector" : "one TI", wr_blocks - nw0, wr_lba_log[nw0 % 256], wr_lba_log[(nw0 + nb - 1) % 256],
			         wcc, wccfp, irq_cyc - wr_ackfall);
		end
		checks = checks + 1;
		if (ovl_tot == 0) begin fails = fails + 1; $display("  FAIL T22 no read request overlapped a guest drain (single-buffer behaviour)"); end
		$display("   T22 prefetches overlapping a drain: %0d (most bytes left to drain at one: %0d)", ovl_tot, rd_ovl_max);
		$display("   T22 info: the phase bits turned STATUS while the last flush was outstanding in %0d of 6 writes", phase_early);
		// ---- informational: a POLLING initiator (watches the phase bits,
		// never waits for the chunk INT) issues ICCS as soon as it sees
		// STATUS.  ICCS is not held for a flush in flight, so the status
		// byte can arrive before the last block is accepted; reported, not
		// checked.
		begin : t22_poll
			integer nwp;
			reg [63:0] fc_cyc;
			lb = 24; dev_lcg = 32'h0000_9999 ^ lat_seed; dev_lat = 200; dev_lat_jit = 1800; nwp = wr_blocks;
			reg_wr(R_CMD, 8'h02); repeat (4) @(negedge clk);
			cdb[0]=8'h2A; cdb[1]=0; cdb[2]=0; cdb[3]=0; cdb[4]=0; cdb[5]=lb[7:0]; cdb[6]=0; cdb[7]=0; cdb[8]=nb[7:0]; cdb[9]=0;
			unix_select(8'h42, 10, 1);
			wait_irq(4000, ok); read_regs(st, sp, it2);
			reg_wr(R_CMD, 8'h01); set_tc(16'd4096); reg_wr(R_CMD, 8'h90);
			for (g = 0; g < nb * 512; g = g + 1) begin
				guard = 0;
				while (!drq && guard < 200000) begin @(negedge clk); guard = guard + 1; end
				pdma_wr((g*7 + 5) & 8'hFF);
			end
			guard = 0; reg_peek(R_STAT, st);
			while (st[2:0] != PH_STAT && guard < 400000) begin guard = guard + 1; reg_peek(R_STAT, st); end
			reg_wr(R_CMD, 8'h11);
			guard = 0;
			while (!(irq && dut.istatus[3]) && guard < 400000) begin @(negedge clk); guard = guard + 1; end
			fc_cyc = cyc;
			$display("   T22 info (polling initiator): I_FC with %0d of 8 flushes accepted -> status %0s the data was accepted",
			         wr_blocks - nwp, (wr_blocks - nwp == nb && fc_cyc > wr_ackfall) ? "AFTER" : "BEFORE");
			// finish the command and let the last flush land before the summary
			read_regs(st, sp, it2);
			reg_rd(R_FIFO, bb); reg_rd(R_FIFO, bb);
			reg_wr(R_CMD, 8'h12);
			guard = 0;
			while ((!irq || wr_blocks - nwp != nb) && guard < 400000) begin @(negedge clk); guard = guard + 1; end
			read_regs(st, sp, it2);
			dev_lat = 40; dev_lat_jit = 0;
		end
		$display("   T22 failures added: %0d", fails - fails0);
	end
	sel_id = 8'h00;

	$display("== tb_ncr53c96: %0d checks, %0d failures ==", checks, fails);

	if (fails != 0) $display("RESULT: FAIL");
	else            $display("RESULT: PASS");
	$finish;
end

initial begin
	#400_000_000;
	$display("== tb_ncr53c96: TIMEOUT ==");
	$display("RESULT: FAIL");
	$finish;
end

endmodule
