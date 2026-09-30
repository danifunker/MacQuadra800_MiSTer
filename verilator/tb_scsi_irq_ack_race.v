/* tb_scsi_irq_ack_race.v -- directed bench (scsi_hang_20260928, fixed in
 * f9f6da6; docs/scsi-write-hang-20260928.md): the 53C96 interrupt
 * lost in the IOSB pseudo-VIA2 when the guest acknowledges VIA2 IFR bit 3
 * after the chip has already raised its NEXT interrupt.
 *
 * iosb.sv before f9f6da6 latched the SCSI IRQ into via2_ifr[3] only on a CHANGE of the
 * 53C96 INT line (`if (scsi_irq_i != scsi_d) via2_ifr[3] <= scsi_irq_i`).
 * A write-1-to-clear of IFR bit 3 while INT is still high therefore leaves
 * the flag clear for good: no level-2 interrupt, and the 53C96 keeps INT up
 * waiting for its ISR to be read -- which the guest only does from the
 * interrupt it never gets.  The same shape bit IFR bit 1 (any-slot, fixed
 * 2026-09-18) and bit 0 (DREQ, presented live).
 *
 * Sequence (the per-sector WRITE the Mac OS 7.5.5 SCSI Manager runs, see
 * docs/scsi-write-hang-20260928.md): WRITE(10) of 2 blocks, $90 TC=512,
 * 128 move.l beats, flush, chunk INT (I_BUS) -> IFR bit 3 -> IPL 2.  The
 * "handler" reads STATUS + ISR, starts the next $90 and its 512 bytes, the
 * device flushes and the chip raises the next INT; only THEN does the
 * handler write $08 to the IFR to acknowledge the interrupt it was called
 * for.  PASS: IPL 2 is still asserted afterwards (the second INT is
 * pending), and reading the ISR then finishes the command.  The iosb.sv
 * of f9f6da6~1 FAILS (the interrupt is lost at the offsets where the IFR
 * write lands in the INT edge's clock).
 *
 *   make tb_scsi_irq_ack_race    (exit status non-zero on FAIL)
 */
`timescale 1ns/1ps
module tb_scsi_irq_ack_race;
	parameter integer LAT = 300;
	reg clk = 0;
	always #15.1515 clk = ~clk;
	reg nreset = 0;
	reg         sel = 0, write = 0;
	reg  [27:2] addr = 0;
	reg   [3:0] be = 0;
	reg  [31:0] wdata = 0;
	wire [31:0] rdata;
	wire        ack, fault;
	wire  [2:0] ipl_n;
	reg   [2:0] img_mounted = 0;
	reg  [63:0] img_size = 0;
	wire [31:0] io_lba;
	wire  [2:0] io_rd, io_wr;
	reg   [2:0] io_ack = 0;
	reg  [12:0] sd_buff_addr = 0;
	reg  [15:0] sd_buff_dout = 0;
	wire [15:0] sd_buff_din;
	reg         sd_buff_wr = 0;

	iosb dut (
		.clk(clk), .nreset(nreset), .ce(1'b1),
		.sel(sel), .write(write), .addr(addr), .be(be),
		.wdata(wdata), .rdata(rdata), .ack(ack), .sdma_fault(fault),
		.vbl_irq(1'b0), .sonic_irq(1'b0), .scsi_irq(1'b0), .scsi_drq(1'b0), .asc_irq(1'b0),
		.scc_rxd_a(1'b1), .scc_txd_a(), .scc_cts_a(1'b1), .scc_rts_a(),
		.scc_rxd_b(1'b1), .scc_txd_b(),
		.ipl_n(ipl_n), .audio_l(), .audio_r(), .cd_snd_l(), .cd_snd_r(),
		.img_mounted(img_mounted), .img_size(img_size),
		.io_lba(io_lba), .io_rd(io_rd), .io_wr(io_wr), .io_blk_cnt(), .io_ack(io_ack),
		.sd_buff_addr(sd_buff_addr), .sd_buff_dout(sd_buff_dout), .sd_buff_din(sd_buff_din), .sd_buff_wr(sd_buff_wr),
		.ps2_key(11'd0), .ps2_mouse(25'd0), .timestamp(33'd0),
		.stall_flt(1'b0), .berr_active(1'b0), .berr_addr(30'd0)
	);

	integer errors = 0, wr_blocks = 0;
	// HPS model: any slot, ack after LAT, 256 words, 1 word per 2 clocks
	integer k, sl;
	reg rd_req;
	initial begin : hps
		forever begin
			@(posedge clk);
			if ((io_rd | io_wr) != 0) begin
				sl = io_rd[0] | io_wr[0] ? 0 : io_rd[1] | io_wr[1] ? 1 : 2;
				rd_req = io_rd[sl];
				repeat (LAT) @(posedge clk);
				io_ack[sl] <= 1;
				@(posedge clk);
				for (k = 0; k < 256; k = k + 1) begin
					sd_buff_addr <= k;
					if (rd_req) begin sd_buff_dout <= 16'h0000; sd_buff_wr <= 1; end
					@(posedge clk); sd_buff_wr <= 0; @(posedge clk);
				end
				io_ack[sl] <= 0;
				if (sl == 0 && !rd_req) wr_blocks = wr_blocks + 1;
				@(posedge clk); @(posedge clk);
			end
		end
	end

	task beat(input [31:0] a, input w, input [3:0] b, input [31:0] d, output [31:0] q);
		begin
			@(posedge clk);
			addr <= a[27:2]; be <= b; wdata <= d; write <= w; sel <= 1;
			@(posedge clk);
			while (!ack) @(posedge clk);
			q = rdata;
			sel <= 0; write <= 0;
			@(posedge clk);
		end
	endtask
	localparam [31:0] NCR = 32'h00F10000, PD_B = 32'h00F10100, PD_L = 32'h00F50100;
	localparam [31:0] V2_IFR = 32'h00F03A00, V2_IER = 32'h00F03C00;
	reg [31:0] q;
	task reg_wr(input [3:0] r, input [7:0] d); begin beat(NCR + r*16, 1, 4'b1000, {d, 24'd0}, q); end endtask
	task reg_rd(input [3:0] r, output [7:0] d); begin beat(NCR + r*16, 0, 4'b1000, 32'd0, q); d = q[31:24]; end endtask
	task via2_wr(input [31:0] a, input [7:0] d); begin beat(a, 1, 4'b1000, {d, 24'd0}, q); end endtask
	task via2_rd(input [31:0] a, output [7:0] d); begin beat(a, 0, 4'b1000, 32'd0, q); d = q[31:24]; end endtask
	task wait_ipl2(input integer lim, output integer ok);
		integer g;
		begin g = 0; while (ipl_n != 3'b101 && g < lim) begin @(posedge clk); g = g + 1; end ok = (ipl_n == 3'b101); end
	endtask
	task wait_chip_int(input integer lim);
		integer g; reg [7:0] s;
		begin g = 0; s = 0; while (!s[7] && g < lim) begin reg_rd(4'h4, s); g = g + 1; end
		      if (!s[7]) begin errors = errors + 1; $display("FAIL chip INT never rose"); end end
	endtask
	task push512;
		integer i;
		begin for (i = 0; i < 128; i = i + 1) beat(PD_L, 1, 4'b1111, {i[7:0], 8'hA5, ~i[7:0], 8'h3C}, q); end
	endtask

	reg [7:0] st, it, ifr, cdb [0:9];
	integer j, ok, d, lost;
	initial begin
		repeat (40) @(posedge clk); nreset = 1; repeat (40) @(posedge clk);
		img_size <= 64'd65536; img_mounted <= 3'b001; @(posedge clk); img_mounted <= 3'b000;
		repeat (20000) @(posedge clk);
		via2_wr(V2_IFR, 8'h7F);                   // clear everything
		via2_wr(V2_IER, 8'h88);                   // enable the SCSI IRQ (bit 3)

		// select + WRITE(10) 2 blocks at LBA 8 (ROM dialect)
		cdb[0]=8'h2A; cdb[1]=0; cdb[2]=0; cdb[3]=0; cdb[4]=0; cdb[5]=8; cdb[6]=0; cdb[7]=0; cdb[8]=2; cdb[9]=0;
		reg_wr(4'h4, 8'h00);
		reg_wr(4'h3, 8'h01); reg_wr(4'h0, 8'h01); reg_wr(4'h1, 8'h00); reg_wr(4'h3, 8'hC1);
		reg_wr(4'h3, 8'h01); reg_wr(4'h0, 8'h01); reg_wr(4'h1, 8'h00); reg_wr(4'h3, 8'h90);
		for (j = 0; j < 9; j = j + 1) reg_wr(4'h2, cdb[j]);
		beat(PD_B, 1, 4'b1000, {cdb[9], 24'd0}, q);
		wait_chip_int(20000);
		reg_rd(4'h4, st); reg_rd(4'h5, it);      // command-phase INT consumed
		via2_wr(V2_IFR, 8'h08);                   // ...and its IFR flag (nothing pending now)

		$display("== sector 1: $90 TC=512, 512 bytes, wait for the chunk INT on IPL 2");
		reg_wr(4'h0, 8'h00); reg_wr(4'h1, 8'h02); reg_wr(4'h3, 8'h90);
		push512;
		wait_ipl2(200000, ok);
		if (!ok) begin errors = errors + 1; $display("FAIL sector 1 INT never reached IPL 2"); end
		else $display("  ok  IPL 2 for sector 1's chunk INT");

		$display("== 'handler': read STATUS + ISR, start sector 2, its INT rises, THEN ack IFR bit 3");
		reg_rd(4'h4, st); reg_rd(4'h5, it);
		reg_wr(4'h0, 8'h00); reg_wr(4'h1, 8'h02); reg_wr(4'h3, 8'h90);
		push512;
		wait_chip_int(200000);                    // sector 2 flushed, chip INT up again
		via2_rd(V2_IFR, ifr);
		$display("  before the late ack: VIA2 IFR=%02x ipl_n=%b", ifr, ipl_n);
		via2_wr(V2_IFR, 8'h08);                   // the handler acknowledges "its" interrupt
		repeat (8) @(posedge clk);
		via2_rd(V2_IFR, ifr);
		$display("  after the late ack:  VIA2 IFR=%02x ipl_n=%b (chip INT still up: STATUS bit 7)", ifr, ipl_n);
		if (ipl_n != 3'b101 || !ifr[3]) begin
			errors = errors + 1;
			$display("FAIL the pending 53C96 interrupt is gone from the VIA2: IFR bit 3=%b, IPL=%b -- the guest waits for it for ever", ifr[3], ~ipl_n);
		end
		else $display("  ok  the second INT is still pending on IPL 2");
		// finish the command the way the guest would once interrupted
		reg_rd(4'h4, st); reg_rd(4'h5, it);
		if (st[2:0] != 3'd3) begin errors = errors + 1; $display("FAIL phase %0d, want STATUS", st[2:0]); end
		reg_wr(4'h3, 8'h11); wait_chip_int(20000); reg_rd(4'h5, it); reg_rd(4'h2, st); reg_rd(4'h2, st);
		reg_wr(4'h3, 8'h12); wait_chip_int(20000); reg_rd(4'h5, it);
		via2_wr(V2_IFR, 8'h08);
		repeat (8) @(posedge clk);
		if (ipl_n != 3'b111) begin errors = errors + 1; $display("FAIL IPL still %b after every INT was read", ~ipl_n); end
		if (wr_blocks != 2) begin errors = errors + 1; $display("FAIL %0d blocks written", wr_blocks); end

		// ---- part B: an unrelated IFR write (the VBL dispatcher's
		// move.b #$02,IFR -- it clears nothing) landing in the SAME clock
		// as the 53C96 INT edge.  iosb.sv's IFR write assigns all of
		// via2_ifr[6:0] after the edge latch in the same always block, so
		// the edge is overwritten with the old 0.  Sweep the write across
		// the edge, one sector per offset.
		$display("== part B: WRITE(10) of 24 blocks, one TI per sector; IFR=$02 written 0..23 clocks after the flush ack falls");
		cdb[0]=8'h2A; cdb[5]=16; cdb[8]=24;
		reg_wr(4'h4, 8'h00);
		reg_wr(4'h3, 8'h01); reg_wr(4'h0, 8'h01); reg_wr(4'h1, 8'h00); reg_wr(4'h3, 8'hC1);
		reg_wr(4'h3, 8'h01); reg_wr(4'h0, 8'h01); reg_wr(4'h1, 8'h00); reg_wr(4'h3, 8'h90);
		for (j = 0; j < 9; j = j + 1) reg_wr(4'h2, cdb[j]);
		beat(PD_B, 1, 4'b1000, {cdb[9], 24'd0}, q);
		wait_chip_int(20000);
		reg_rd(4'h4, st); reg_rd(4'h5, it);
		via2_wr(V2_IFR, 8'h08);
		lost = 0;
		for (d = 0; d < 24; d = d + 1) begin
			reg_wr(4'h0, 8'h00); reg_wr(4'h1, 8'h02); reg_wr(4'h3, 8'h90);
			push512;
			@(negedge io_ack[0]);
			repeat (d) @(posedge clk);
			via2_wr(V2_IFR, 8'h02);
			wait_chip_int(20000);
			repeat (4) @(posedge clk);
			via2_rd(V2_IFR, ifr);
			if (ipl_n != 3'b101) begin
				lost = lost + 1;
				$display("  offset %0d: INT up, VIA2 IFR=%02x, IPL=%b -> interrupt LOST", d, ifr, ~ipl_n);
			end
			reg_rd(4'h4, st); reg_rd(4'h5, it);    // the handler: STATUS, ISR
			via2_wr(V2_IFR, 8'h08);
		end
		reg_rd(4'h4, st);
		if (st[2:0] != 3'd3) begin errors = errors + 1; $display("FAIL part B phase %0d after 24 sectors, want STATUS", st[2:0]); end
		reg_wr(4'h3, 8'h11); wait_chip_int(20000); reg_rd(4'h5, it); reg_rd(4'h2, st); reg_rd(4'h2, st);
		reg_wr(4'h3, 8'h12); wait_chip_int(20000); reg_rd(4'h5, it); via2_wr(V2_IFR, 8'h08);
		$display("  part B: %0d of 24 offsets lost the interrupt", lost);
		if (lost != 0) errors = errors + 1;
		$display("RESULT: %s (errors=%0d)", errors ? "FAIL" : "PASS", errors);
		if (errors) $fatal(1, "tb_scsi_irq_ack_race: FAILED");
		$finish;
	end
	initial begin #2000000000; $display("RESULT: FAIL (global timeout)"); $fatal(1, "tb_scsi_irq_ack_race: timeout"); end
endmodule
