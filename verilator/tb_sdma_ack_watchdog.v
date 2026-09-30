/* tb_sdma_ack_watchdog.v -- directed bench (scsi_hang_20260928, fixed in
 * f9f6da6; docs/scsi-write-hang-20260928.md): the IOSB pseudo-DMA
 * watchdog against a long platform ACK window.
 *
 * iosb.sv's A_SDMA watchdog is meant to be frozen "while a platform block
 * transfer is in flight", but it tests only the REQUEST strobes (io_rd/io_wr).
 * ncr53c96 drops those the cycle io_ack RISES; the transfer itself (hps_io's
 * SPI stream of 256 words) runs for the whole time io_ack is high.  A guest
 * PDMA beat stalled on a full FIFO (write) or an empty one (read) therefore
 * ages the watchdog for the entire ack window.  On hardware that window is
 * Main's SPI transfer (~110-150 us) plus anything that preempts Main inside
 * it; past 2^SDMA_TIMEOUT_BITS clocks (7.94 ms at 33 MHz) the beat is released
 * with sdma_fault -> a bus error the ROM's PDMA handler does not recognise
 * (the IOSB fault latch at $50F18300 is not implemented).
 *
 * The bench: ROM-dialect select + WRITE(10) of 2 blocks, $90 with TC=1024,
 * then 256 BLIND move.l beats to the 32-bit PDMA port ($50F50100) with no DREQ
 * polling -- the ROM's SCSIWBlind.  The HPS model acks each write after LAT
 * clocks and holds the ack for ACK_LEN clocks.  SDMA_TIMEOUT_BITS is 12 here
 * (4096 clocks) so the bench runs in a second; the proportions are what
 * matter.  Then the same for a blind READ(10) of 2 blocks.
 *
 * PASS: no beat is faulted, 2 blocks written with the right bytes, and the
 * read returns them.  With ACK_LEN > 2^SDMA_TIMEOUT_BITS the iosb.sv of
 * f9f6da6~1 FAILS (faults); with the fix (freeze on io_ack too, f9f6da6)
 * it passes.
 *
 *   make tb_sdma_ack_watchdog    (exit status non-zero on FAIL;
 *   -GACK_LEN=500 is the short-ack control that passes on either iosb.sv)
 */
`timescale 1ns/1ps
module tb_sdma_ack_watchdog;
	parameter integer ACK_LEN = 6000;     // clocks the platform holds io_ack
	parameter integer LAT     = 300;      // clocks from request to ack
	localparam integer TOB    = 12;       // SDMA_TIMEOUT_BITS for the bench

	reg clk = 0;
	always #15.1515 clk = ~clk;
	reg nreset = 0;

	reg         sel = 0, write = 0;
	reg  [27:2] addr = 0;
	reg   [3:0] be = 0;
	reg  [31:0] wdata = 0;
	wire [31:0] rdata;
	wire        ack, fault;

	reg   [2:0] img_mounted = 0;
	reg  [63:0] img_size = 0;
	wire [31:0] io_lba;
	wire  [2:0] io_rd, io_wr;
	reg   [2:0] io_ack = 0;
	reg  [12:0] sd_buff_addr = 0;
	reg  [15:0] sd_buff_dout = 0;
	wire [15:0] sd_buff_din;
	reg         sd_buff_wr = 0;

	iosb #(.SDMA_TIMEOUT_BITS(TOB)) dut (
		.clk(clk), .nreset(nreset), .ce(1'b1),
		.sel(sel), .write(write), .addr(addr), .be(be),
		.wdata(wdata), .rdata(rdata), .ack(ack), .sdma_fault(fault),
		.vbl_irq(1'b0), .sonic_irq(1'b0), .scsi_irq(1'b0), .scsi_drq(1'b0), .asc_irq(1'b0),
		.scc_rxd_a(1'b1), .scc_txd_a(), .scc_cts_a(1'b1), .scc_rts_a(),
		.scc_rxd_b(1'b1), .scc_txd_b(),
		.ipl_n(), .audio_l(), .audio_r(), .cd_snd_l(), .cd_snd_r(),
		.img_mounted(img_mounted), .img_size(img_size),
		.io_lba(io_lba), .io_rd(io_rd), .io_wr(io_wr), .io_blk_cnt(), .io_ack(io_ack),
		.sd_buff_addr(sd_buff_addr), .sd_buff_dout(sd_buff_dout), .sd_buff_din(sd_buff_din), .sd_buff_wr(sd_buff_wr),
		.ps2_key(11'd0), .ps2_mouse(25'd0), .timestamp(33'd0),
		.stall_flt(1'b0), .berr_active(1'b0), .berr_addr(30'd0)
	);

	integer errors = 0, faults = 0, wr_blocks = 0, rd_blocks = 0, max_ackwin = 0;
	reg [7:0] disk [0:65535];

	//------------------------------------------------------------------ HPS model
	// Serves every slot: the 53C96's housekeeping (reset notice, probe) goes
	// to slot 2 at start-up.  One word per 2 clocks, the ack held ACK_LEN.
	integer k, t, sl, lba_i;
	reg rd_req;
	initial begin : hps
		forever begin
			@(posedge clk);
			if ((io_rd | io_wr) != 0) begin
				sl = io_rd[0] | io_wr[0] ? 0 : io_rd[1] | io_wr[1] ? 1 : 2;
				rd_req = io_rd[sl];
				lba_i = io_lba;
				repeat (LAT) @(posedge clk);
				io_ack[sl] <= 1;
				t = 0;
				@(posedge clk); t = t + 1;
				for (k = 0; k < 256; k = k + 1) begin
					sd_buff_addr <= k;
					if (rd_req) begin
						sd_buff_dout <= (sl == 0 && lba_i < 128) ? {disk[lba_i*512 + 2*k], disk[lba_i*512 + 2*k + 1]} : 16'h0000;
						sd_buff_wr <= 1;
					end
					@(posedge clk); t = t + 1;
					sd_buff_wr <= 0;
					@(posedge clk); t = t + 1;
					if (!rd_req && sl == 0 && lba_i < 128) begin
						disk[lba_i*512 + 2*k]     = sd_buff_din[15:8];
						disk[lba_i*512 + 2*k + 1] = sd_buff_din[7:0];
					end
				end
				while (t < ACK_LEN) begin @(posedge clk); t = t + 1; end
				io_ack[sl] <= 0;
				if (t > max_ackwin) max_ackwin = t;
				if (sl == 0) begin if (rd_req) rd_blocks = rd_blocks + 1; else wr_blocks = wr_blocks + 1; end
				@(posedge clk); @(posedge clk);
			end
		end
	end

	//------------------------------------------------------------------ beat bus
	task beat(input [31:0] a, input w, input [3:0] b, input [31:0] d, output [31:0] q, output f);
		begin
			@(posedge clk);
			addr <= a[27:2]; be <= b; wdata <= d; write <= w; sel <= 1;
			@(posedge clk);
			while (!ack) @(posedge clk);
			q = rdata; f = fault;
			sel <= 0; write <= 0;
			@(posedge clk);
		end
	endtask
	localparam [31:0] NCR = 32'h00F10000, PD_B = 32'h00F10100, PD_L = 32'h00F50100;
	reg [31:0] q; reg f;
	task reg_wr(input [3:0] r, input [7:0] d); begin beat(NCR + r*16, 1, 4'b1000, {d, 24'd0}, q, f); end endtask
	task reg_rd(input [3:0] r, output [7:0] d); begin beat(NCR + r*16, 0, 4'b1000, 32'd0, q, f); d = q[31:24]; end endtask
	task wait_int(input integer lim);
		integer g; reg [7:0] s;
		begin
			g = 0; s = 0;
			while (!s[7] && g < lim) begin reg_rd(4'h4, s); g = g + 1; end
			if (!s[7]) begin errors = errors + 1; $display("FAIL no INT"); end
		end
	endtask
	reg [7:0] st, it, cdb [0:9];
	integer i, j;
	task rom_cmd;       // DMA select + CDB via FIFO, last byte via the PDMA byte port
		begin
			reg_wr(4'h4, 8'h00);            // dest id 0
			reg_wr(4'h3, 8'h01); reg_wr(4'h0, 8'h01); reg_wr(4'h1, 8'h00);
			reg_wr(4'h3, 8'hC1);
			reg_wr(4'h3, 8'h01); reg_wr(4'h0, 8'h01); reg_wr(4'h1, 8'h00);
			reg_wr(4'h3, 8'h90);
			for (j = 0; j < 9; j = j + 1) reg_wr(4'h2, cdb[j]);
			beat(PD_B, 1, 4'b1000, {cdb[9], 24'd0}, q, f);
			wait_int(20000);
			reg_rd(4'h4, st); reg_rd(4'h5, it);
		end
	endtask
	task finish_cmd;    // wait for STATUS, ICCS, MSG ACCEPT
		begin
			wait_int(400000);
			reg_rd(4'h4, st); reg_rd(4'h5, it);
			if (st[2:0] != 3'd3) begin errors = errors + 1; $display("FAIL phase %0d after data, want STATUS", st[2:0]); end
			reg_wr(4'h3, 8'h11); wait_int(20000); reg_rd(4'h5, it);
			reg_rd(4'h2, st); if (st != 0) begin errors = errors + 1; $display("FAIL status byte %02x", st); end
			reg_rd(4'h2, st);
			reg_wr(4'h3, 8'h12); wait_int(20000); reg_rd(4'h5, it);
		end
	endtask

	integer tf0;
	reg [31:0] word;
	initial begin
		for (i = 0; i < 65536; i = i + 1) disk[i] = 8'hEE;
		repeat (40) @(posedge clk); nreset = 1; repeat (40) @(posedge clk);
		img_size <= 64'd65536; img_mounted <= 3'b001; @(posedge clk); img_mounted <= 3'b000;
		repeat (20000) @(posedge clk);       // housekeeping on slot 2 drains

		$display("== WRITE(10) 2 blocks at LBA 8, TC=1024, 256 blind move.l beats; ACK_LEN=%0d, watchdog=%0d clk", ACK_LEN, 1 << TOB);
		cdb[0]=8'h2A; cdb[1]=0; cdb[2]=0; cdb[3]=0; cdb[4]=0; cdb[5]=8; cdb[6]=0; cdb[7]=0; cdb[8]=2; cdb[9]=0;
		rom_cmd;
		if (st[2:0] != 3'd0) begin errors = errors + 1; $display("FAIL phase %0d after WRITE CDB, want DATA OUT", st[2:0]); end
		reg_wr(4'h3, 8'h01); reg_wr(4'h0, 8'h00); reg_wr(4'h1, 8'h04); reg_wr(4'h3, 8'h90);
		i = 0; tf0 = faults;
		while (i < 256) begin
			word = {i[7:0] ^ 8'h5A, i[7:0], ~i[7:0], 8'hC3};
			beat(PD_L, 1, 4'b1111, word, q, f);
			if (f) begin
				faults = faults + 1;
				$display("  beat %0d (byte %0d) FAULTED at %0t: bus error; the ROM handler would chain (no $50F18300 latch); retrying as a re-executed move.l", i, 4*i, $time);
				if (faults - tf0 > 8) begin $display("  giving up on the write"); i = 256; end
			end
			else i = i + 1;
		end
		finish_cmd;
		$display("  write: %0d blocks flushed, %0d faulted beats, longest ack window %0d clk", wr_blocks, faults - tf0, max_ackwin);
		for (i = 0; i < 256; i = i + 1)
			if ({disk[8*512 + 4*i], disk[8*512 + 4*i + 1], disk[8*512 + 4*i + 2], disk[8*512 + 4*i + 3]} !== {i[7:0] ^ 8'h5A, i[7:0], ~i[7:0], 8'hC3}) begin
				if (errors < 10) $display("FAIL disk long %0d = %02x%02x%02x%02x", i, disk[8*512 + 4*i], disk[8*512 + 4*i + 1], disk[8*512 + 4*i + 2], disk[8*512 + 4*i + 3]);
				errors = errors + 1;
			end

		$display("== READ(10) the same 2 blocks, TC=1024, 256 blind move.l reads");
		cdb[0]=8'h28;
		rom_cmd;
		if (st[2:0] != 3'd1) begin errors = errors + 1; $display("FAIL phase %0d after READ CDB, want DATA IN", st[2:0]); end
		reg_wr(4'h3, 8'h01); reg_wr(4'h0, 8'h00); reg_wr(4'h1, 8'h04); reg_wr(4'h3, 8'h90);
		i = 0; tf0 = faults;
		while (i < 256) begin
			beat(PD_L, 0, 4'b1111, 32'd0, q, f);
			if (f) begin
				faults = faults + 1;
				$display("  read beat %0d FAULTED at %0t", i, $time);
				if (faults - tf0 > 8) begin $display("  giving up on the read"); i = 256; end
			end
			else begin
				if (q !== {i[7:0] ^ 8'h5A, i[7:0], ~i[7:0], 8'hC3}) begin
					if (errors < 10) $display("FAIL read long %0d = %08x", i, q);
					errors = errors + 1;
				end
				i = i + 1;
			end
		end
		finish_cmd;
		$display("  read: %0d blocks, %0d faulted beats", rd_blocks, faults - tf0);
		if (faults != 0) begin errors = errors + 1; $display("FAIL %0d PDMA beats bus-errored during platform transfers", faults); end
		if (wr_blocks != 2) begin errors = errors + 1; $display("FAIL %0d blocks written, want 2", wr_blocks); end
		$display("RESULT: %s (ACK_LEN=%0d, errors=%0d)", errors ? "FAIL" : "PASS", ACK_LEN, errors);
		if (errors) $fatal(1, "tb_sdma_ack_watchdog: FAILED");
		$finish;
	end
	initial begin #2000000000; $display("RESULT: FAIL (global timeout)"); $fatal(1, "tb_sdma_ack_watchdog: timeout"); end
endmodule
