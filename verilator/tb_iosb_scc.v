/* tb_iosb_scc.v — unit test for the SCC's beat-bus adapter inside rtl/iosb.sv.
 *
 * WHY THIS EXISTS (2026-08-31): rtl/scc.v arrives from the MacLC/MacIIvi
 * lineage, where it hangs off a minimigmac 16-bit dataController with
 * _cpuLDS/_cpuUDS.  wombat33 drives it from a 32-bit AP68040 beat bus through
 * iosb.sv, so the adapter (address decode, A1-from-byte-enable, the CS window,
 * and the ack timing) is entirely NEW CODE with no upstream to inherit bugs
 * or fixes from.  It is therefore the part most worth simulating before a
 * Quartus fit + hardware boot, which is the only other way to test it.
 *
 * The two things that would silently half-work on hardware:
 *   - CS window: scc.v consumes an access on a cen pulse with CS high, then
 *     needs CS LOW across another cen pulse to clear cs_access_done and apply
 *     the deferred pointer cleanup / RX-FIFO pop.  Ack too early and every
 *     SECOND access is swallowed -- which looks like a flaky chip, not a bus
 *     bug.  Section 3 is the explicit back-to-back regression.
 *   - Channel decode: rs = { A2, A1 } where A1 is carried by the byte enable,
 *     not by addr.  Get it wrong and channel A/B swap, or control/data swap.
 *
 * Register map (MAME macquadra800.cpp:163 + z80scc dc_ab):
 *   $5000C000 B control   $5000C002 A control
 *   $5000C004 B data      $5000C006 A data
 *
 * WHAT IT CHECKS
 *   1. Decode/plumbing: WR9 hardware reset then read RR0 on channel A --
 *      TxEmpty (bit 2) must be set.  Proves address decode, the byte lane,
 *      the CS window and the read path all line up.
 *   2. Channels are independent: programming A must not disturb B's RR0.
 *   3. Back-to-back accesses: N reads in a row all return the same RR0.  With
 *      a too-early ack the 2nd/4th/... reads return stale or zero.
 *   4. End-to-end TX at 33 MHz: the MIDI recipe (WR4=$84, WR11=$28) must put
 *      1056 clk/bit on scc_txd_a -- i.e. exactly 31250 baud at SYS_CLK_HZ =
 *      33_000_000.  This is the check that the clock re-parameterisation
 *      actually reached the instance inside iosb, not just the module default.
 *
 * Build + run (Verilator 5.x, from verilator/; the flags and the iosb.sv
 * dependency list are IOSB_TB / IOSB_TB_DEPS in the Makefile):
 *   make tb_iosb_scc
 * PASS criterion: last line "RESULT: PASS", exit 0 (non-zero on FAIL).
 */

`timescale 1ns/1ps

module tb_iosb_scc;

	// 33.000 MHz — wombat33's clk_sys, the whole point of the exercise
	reg clk = 0;
	always #15.1515 clk = ~clk;

	reg nreset = 0;

	// beat bus
	reg         sel   = 0;
	reg         write = 0;
	reg  [27:2] addr  = 0;
	reg   [3:0] be    = 4'b0000;
	reg  [31:0] wdata = 0;
	wire [31:0] rdata;
	wire        ack;

	wire scc_txd_a, scc_rts_a, scc_txd_b;

	integer errors = 0;

	task check(input [255:0] name, input integer got, input integer exp);
		begin
			if (got !== exp) begin
				$display("FAIL %0s: got %0d ($%0h), expected %0d ($%0h)",
				         name, got, got, exp, exp);
				errors = errors + 1;
			end else begin
				$display("  ok  %0s = %0d ($%0h)", name, got, got);
			end
		end
	endtask

	iosb dut (
		.clk(clk), .nreset(nreset), .ce(1'b1),
		.sel(sel), .write(write), .addr(addr), .be(be),
		.wdata(wdata), .rdata(rdata), .ack(ack), .sdma_fault(),
		.vbl_irq(1'b0), .scsi_irq(1'b0), .scsi_drq(1'b0), .asc_irq(1'b0),
		.scc_rxd_a(1'b1), .scc_txd_a(scc_txd_a),
		.scc_cts_a(1'b1), .scc_rts_a(scc_rts_a),
		.scc_rxd_b(1'b1), .scc_txd_b(scc_txd_b),
		.ipl_n(), .audio_l(), .audio_r(),
		.img_mounted(1'b0), .img_size(64'd0),
		.io_lba(), .io_rd(), .io_wr(), .io_ack(1'b0),
		.sd_buff_addr(8'd0), .sd_buff_dout(16'd0), .sd_buff_din(), .sd_buff_wr(1'b0),
		.ps2_key(11'd0), .ps2_mouse(25'd0),
		.timestamp(33'd0)
	);

	// One beat.  `a` is the full byte address; the SCC lives on the upper byte
	// of each 16-bit word, so bit 1 of the address picks the lane: A+0 -> be[3]
	// (word 0), A+2 -> be[1] (word 1).
	task beat(input integer a, input integer is_write, input [7:0] d,
	          output [7:0] rd);
		begin
			@(posedge clk);
			addr  <= a[27:2];
			be    <= a[1] ? 4'b0010 : 4'b1000;
			wdata <= a[1] ? {16'h0000, d, 8'h00} : {d, 24'h000000};
			write <= is_write[0];
			sel   <= 1;
			// sel is held until the ack, exactly as quadra800.sv drives it
			@(posedge clk);
			while (!ack) @(posedge clk);
			rd = a[1] ? rdata[15:8] : rdata[31:24];
			sel   <= 0;
			write <= 0;
			@(posedge clk);
		end
	endtask

	// SCC control register write: point at the register, then write it.
	task wr_reg(input integer ctl_addr, input [3:0] regno, input [7:0] val);
		reg [7:0] dummy;
		begin
			beat(ctl_addr, 1, {4'd0, regno}, dummy);
			beat(ctl_addr, 1, val,           dummy);
		end
	endtask

	localparam A_CTL = 32'h5000C002, A_DATA = 32'h5000C006;
	localparam B_CTL = 32'h5000C000, B_DATA = 32'h5000C004;

	// iosb takes the offset within $50000000, so strip the base
	localparam OFF   = 32'h50000000;

	reg [7:0] v, v2, first;
	integer i;
	integer t0, t1, period;

	initial begin
		nreset = 0;
		repeat (40) @(posedge clk);
		nreset = 1;
		repeat (40) @(posedge clk);

		$display("== 1. decode + CS window: WR9 reset, then RR0 on channel A ==");
		// WR9 = $C0: force hardware reset
		wr_reg(A_CTL - OFF, 4'd9, 8'hC0);
		repeat (60) @(posedge clk);
		// RR0 read: pointer defaults to 0 after the access completes
		beat(A_CTL - OFF, 0, 8'h00, v);
		$display("  RR0(A) = $%02h", v);
		check("RR0(A) TxEmpty (bit 2)", (v[2] === 1'b1) ? 1 : 0, 1);

		$display("== 2. channels are independent ==");
		beat(B_CTL - OFF, 0, 8'h00, v2);
		$display("  RR0(B) = $%02h", v2);
		check("RR0(B) TxEmpty (bit 2)", (v2[2] === 1'b1) ? 1 : 0, 1);

		$display("== 3. back-to-back accesses (the too-early-ack regression) ==");
		beat(A_CTL - OFF, 0, 8'h00, first);
		for (i = 0; i < 6; i = i + 1) begin
			beat(A_CTL - OFF, 0, 8'h00, v);
			if (v !== first) begin
				$display("FAIL back-to-back read %0d: got $%02h, expected $%02h",
				         i, v, first);
				errors = errors + 1;
			end
		end
		$display("  ok  7 consecutive RR0 reads all returned $%02h", first);

		$display("== 4. end-to-end TX at 33 MHz: MIDI recipe must give 1056 clk/bit ==");
		wr_reg(A_CTL - OFF, 4'd9, 8'hC0);          // hardware reset
		repeat (60) @(posedge clk);
		wr_reg(A_CTL - OFF, 4'd4, 8'h84);          // x32 clock, 8N1
		wr_reg(A_CTL - OFF, 4'd3, 8'hC1);          // Rx 8 bits, Rx enable
		wr_reg(A_CTL - OFF, 4'd5, 8'h68);          // Tx 8 bits, Tx enable
		wr_reg(A_CTL - OFF, 4'd11, 8'h28);         // RX+TX clock from TRxC
		wr_reg(A_CTL - OFF, 4'd14, 8'h00);         // BRG off
		repeat (40) @(posedge clk);

		beat(A_DATA - OFF, 1, 8'h55, v);           // $55 = alternating bits

		// measure one bit period on the start-bit edge and the first data edge
		@(negedge scc_txd_a);                       // start bit
		t0 = $time;
		@(posedge scc_txd_a);                       // first '1' of $55
		t1 = $time;
		// ns -> clk at 33 MHz: clk = ns * 33 / 1000 (a clk is 30.303 ns)
		period = ((t1 - t0) * 33) / 1000;
		$display("  measured %0d ns for 1 bit = %0d clk (= %0d baud)",
		         t1 - t0, period, 1000000000 / (t1 - t0));
		if (period < 1052 || period > 1060) begin
			$display("FAIL TX bit period: %0d clk, expected 1056 +/-4", period);
			errors = errors + 1;
		end else begin
			$display("  ok  TX bit period ~%0d clk (31250 baud at 33 MHz = 1056)",
			         period);
		end

		$display("");
		if (errors == 0) $display("RESULT: PASS");
		else             $display("RESULT: FAIL (%0d error(s))", errors);
		if (errors != 0) $fatal(1, "tb_iosb_scc: FAILED");
		$finish;
	end

	// watchdog
	initial begin
		#40_000_000;
		$display("RESULT: FAIL (timeout)");
		$fatal(1, "tb_iosb_scc: timeout");
	end

endmodule
