/* tb_scc_printer.v -- the modem port (SCC channel A) as a serial printer sees it.
 *
 * WHY (2026-09-29): printing from Mac OS 8.1 through the modem port to Main's
 * "Printer" UART mode (mister_printerd on /dev/ttyS1) works for the ImageWriter
 * at 9600 but not for a StyleWriter, whose driver runs the port at 57600 with
 * DTR/CTS hardware handshake.  This bench measures the core half of that link
 * at both rates, through the real iosb.sv beat-bus adapter and scc.v at
 * SYS_CLK_HZ = 33_000_000, exactly as the machine instantiates them.
 * Write-up: docs/serial-printer-20260929.md.
 *
 * Programming: the Mac Serial Driver's async open for the modem port,
 * reconstructed from Inside Macintosh (SerReset baud constants: baud57600 = 0,
 * baud19200 = 4, baud9600 = 10, baud1200 = 94; stop1 + noParity + data8 =
 * WR4 $44, x16) and the Z8530 async recipe:
 *     WR9 $C0 once (the ROM's hardware reset), then per open
 *     WR9 $80 (channel A reset), WR4 $44, WR3 $C0, WR5 $E2 (DTR+RTS, 8 bits,
 *     Tx off), WR11 $50 (Rx+Tx clock = BRG), WR12 TC, WR13 $00, WR14 $01
 *     (BRG on, source RTxC), WR3 $C1 (Rx on), WR5 $EA (Tx on), WR15 $08,
 *     WR0 $10 x2, WR1 $00 (polled here; the driver is interrupt-driven).
 * It is NOT a trace of the ROM's own table; the register values that set the
 * rate (WR4/WR11/WR12/WR13/WR14) are the ones every Mac async driver uses.
 *
 * WHAT IT MEASURES (per rate: 57600 first, then 9600)
 *   A. TX: 64 ASCII bytes through the data register with RR0 bit 2 (Tx buffer
 *      empty) polling.  A bench decoder on scc_txd_a checks every frame and
 *      measures clk/bit from each start edge to the stop-bit edge (bit 7 of
 *      ASCII is 0, so that span is exactly 9 bits).  Pass: within 1 % of
 *      33e6/baud.
 *   B. RX: 64 bytes (00, FF, 55, AA and a pseudo-random fill) driven into
 *      rxd_a back to back (1 stop bit, no idle) at the nominal rate with the
 *      fractional bit time accumulated exactly, read back through RR0 bit 0 +
 *      the data register.  Every byte must match, no FIFO overrun, no framing
 *      error.  Then the same at -3 % / +3 % and a sweep to find where it breaks,
 *      plus the rate the HPS UART really produces (100 MHz / 16 / divisor).
 *   C. Handshake: RR0 CTS (bit 5) and DCD (bit 3) with the CTS pin driven both
 *      ways; the core's RTS pin (-> UART_RTS -> the HPS UART's CTS) vs the Rx
 *      FIFO.
 *   D. The BRG catch-alls: the divider the SCC actually uses for every
 *      (WR4, TC) the Serial Driver can program at 57600..1200.
 *
 * Build + run (from verilator/):   make tb_scc_printer
 * The SCC's own $display trace is noisy; the bench's lines start with "TB".
 * PASS criterion: last line "RESULT: PASS", exit 0.
 */

`timescale 1ns/1ps

module tb_scc_printer;

	reg clk = 0;
	always #15.1515 clk = ~clk;          // 33.000 MHz
	localparam real FCLK = 33.0e6;

	reg nreset = 0;
	reg [63:0] cyc = 0;
	always @(posedge clk) cyc <= cyc + 1;

	// beat bus
	reg         sel   = 0;
	reg         write = 0;
	reg  [27:2] addr  = 0;
	reg   [3:0] be    = 4'b0000;
	reg  [31:0] wdata = 0;
	wire [31:0] rdata;
	wire        ack;

	reg  rxd = 1'b1;
	reg  cts_pin = 1'b1;
	wire txd, rts_pin, txd_b;

	integer errors = 0;

	iosb dut (
		.clk(clk), .nreset(nreset), .ce(1'b1),
		.sel(sel), .write(write), .addr(addr), .be(be),
		.wdata(wdata), .rdata(rdata), .ack(ack), .sdma_fault(),
		.vbl_irq(1'b0), .scsi_irq(1'b0), .scsi_drq(1'b0), .asc_irq(1'b0),
		.scc_rxd_a(rxd), .scc_txd_a(txd),
		.scc_cts_a(cts_pin), .scc_rts_a(rts_pin),
		.scc_rxd_b(1'b1), .scc_txd_b(txd_b),
		.ipl_n(), .audio_l(), .audio_r(),
		.img_mounted(1'b0), .img_size(64'd0),
		.io_lba(), .io_rd(), .io_wr(), .io_ack(1'b0),
		.sd_buff_addr(8'd0), .sd_buff_dout(16'd0), .sd_buff_din(), .sd_buff_wr(1'b0),
		.ps2_key(11'd0), .ps2_mouse(25'd0),
		.timestamp(33'd0)
	);

	localparam A_CTL = 32'h0000C002, A_DATA = 32'h0000C006;   // offsets in $50000000

	task beat(input integer a, input integer is_write, input [7:0] d, output [7:0] rd);
		begin
			@(posedge clk);
			addr  <= a[27:2];
			be    <= a[1] ? 4'b0010 : 4'b1000;
			wdata <= a[1] ? {16'h0000, d, 8'h00} : {d, 24'h000000};
			write <= is_write[0];
			sel   <= 1;
			@(posedge clk);
			while (!ack) @(posedge clk);
			rd = a[1] ? rdata[15:8] : rdata[31:24];
			sel   <= 0;
			write <= 0;
			@(posedge clk);
		end
	endtask

	task wr_reg(input [3:0] regno, input [7:0] val);
		reg [7:0] dummy;
		begin
			if (regno != 0) beat(A_CTL, 1, {4'd0, regno}, dummy);
			beat(A_CTL, 1, val, dummy);
		end
	endtask

	task rd_rr(input [3:0] regno, output [7:0] v);
		reg [7:0] dummy;
		begin
			if (regno != 0) beat(A_CTL, 1, {4'd0, regno}, dummy);
			beat(A_CTL, 0, 8'h00, v);
		end
	endtask

	task idle(input integer n);
		integer k;
		begin
			for (k = 0; k < n; k = k + 1) @(posedge clk);
		end
	endtask

	// Serial Driver style async open of channel A (see header)
	task serial_open(input [7:0] wr4, input [15:0] tc);
		begin
			wr_reg(9, 8'h80);
			idle(20);
			wr_reg(4, wr4);
			wr_reg(3, 8'hC0);
			wr_reg(5, 8'hE2);
			wr_reg(11, 8'h50);
			wr_reg(12, tc[7:0]);
			wr_reg(13, tc[15:8]);
			wr_reg(14, 8'h01);
			wr_reg(3, 8'hC1);
			wr_reg(5, 8'hEA);
			wr_reg(15, 8'h08);
			wr_reg(0, 8'h10);
			wr_reg(0, 8'h10);
			wr_reg(1, 8'h00);
			idle(40);
		end
	endtask

	// Empty the Rx FIFO.  A channel reset (WR9 $80) does not clear it in
	// scc.v -- only the WR9 $C0 hardware reset does -- so a new open can
	// start with stale bytes from the previous test.
	task drain_rx;
		reg [7:0] v, d;
		begin
			rd_rr(0, v);
			while (v[0]) begin
				beat(A_DATA, 0, 8'h00, d);
				rd_rr(0, v);
			end
		end
	endtask

	// ------------------------------------------------------------------
	// TX decoder on txd
	// ------------------------------------------------------------------
	reg [8*64-1:0] MSG = "Quadra 800 modem port -> Printer test 0123456789 ABCDEFGHIJKLMN\015";
	function [7:0] msg_byte(input integer i);
		msg_byte = MSG[(63 - i) * 8 +: 8];
	endfunction

	real    t_exp = 3437.5;      // expected clk/bit, set per section
	integer mon_on = 0;
	integer mon_state = 0;       // 0 idle, 1 in frame
	reg [63:0] mon_t0;
	integer mon_bit;
	reg [9:0] mon_sh;
	reg [7:0] tx_got [0:127];
	integer tx_n = 0;
	integer tx_bad_stop = 0;
	real    span_min, span_max, span_sum, span_s;
	integer span_n;
	reg     txd_r = 1'b1;
	reg [63:0] last_stop_end;
	real    gap_sum; integer gap_n;

	always @(posedge clk) begin
		txd_r <= txd;
		if (mon_on) begin
			if (mon_state == 0) begin
				if (txd_r && !txd) begin
					mon_state <= 1;
					mon_t0    <= cyc;
					mon_bit   <= 0;
					if (tx_n > 0) begin
						gap_sum = gap_sum + (cyc - last_stop_end);
						gap_n   = gap_n + 1;
					end
				end
			end else begin
				// the 9-bit span: start edge -> rising edge into the stop bit
				if (!txd_r && txd && mon_bit == 9) begin
					span_s = (cyc - mon_t0) / 9.0;
					if (span_n == 0 || span_s < span_min) span_min = span_s;
					if (span_n == 0 || span_s > span_max) span_max = span_s;
					span_sum = span_sum + span_s;
					span_n   = span_n + 1;
				end
				if (cyc == mon_t0 + $rtoi((mon_bit + 0.5) * t_exp)) begin
					mon_sh[mon_bit] <= txd;
					if (mon_bit == 9) begin
						tx_got[tx_n] <= mon_sh[8:1];
						if (!txd) tx_bad_stop = tx_bad_stop + 1;
						tx_n <= tx_n + 1;
						mon_state <= 0;
						last_stop_end <= mon_t0 + $rtoi(10.0 * t_exp);
					end
					mon_bit <= mon_bit + 1;
				end
			end
		end
	end

	task tx_test(input integer baud, input [15:0] tc);
		integer i, bad;
		reg [7:0] v;
		real nominal;
		begin
			nominal = FCLK / baud;
			t_exp   = nominal;
			serial_open(8'h44, tc);
			$display("TB   divider in use: baud_divid_speed_a = %0d (nominal %0.2f)",
			         dut.scc_inst.baud_divid_speed_a, nominal);
			tx_n = 0; tx_bad_stop = 0; span_n = 0; span_sum = 0; gap_sum = 0; gap_n = 0;
			mon_state = 0; mon_on = 1;
			for (i = 0; i < 64; i = i + 1) begin
				// Tx buffer empty poll, about once per bit time
				rd_rr(0, v);
				while (!v[2]) begin
					idle($rtoi(nominal));
					rd_rr(0, v);
				end
				beat(A_DATA, 1, msg_byte(i), v);
			end
			// drain
			while (tx_n < 64) @(posedge clk);
			idle($rtoi(2 * nominal));
			mon_on = 0;
			bad = 0;
			for (i = 0; i < 64; i = i + 1)
				if (tx_got[i] !== msg_byte(i)) begin
					if (bad < 4) $display("TB   FAIL TX byte %0d: got %02h expected %02h", i, tx_got[i], msg_byte(i));
					bad = bad + 1;
				end
			$display("TB   TX %0d baud: %0d/64 frames decoded right, %0d bad stop bits", baud, 64 - bad, tx_bad_stop);
			$display("TB   TX %0d baud: clk/bit over %0d 9-bit spans: min %0.2f max %0.2f mean %0.3f  (nominal %0.3f, error %0.3f %%)",
			         baud, span_n, span_min, span_max, span_sum / span_n, nominal,
			         100.0 * ((span_sum / span_n) - nominal) / nominal);
			$display("TB   TX %0d baud: mean idle gap between frames %0.1f clk (%0.2f bit times) -> %0.0f chars/s of %0.0f",
			         baud, gap_sum / gap_n, (gap_sum / gap_n) / nominal,
			         FCLK / (10.0 * nominal + gap_sum / gap_n), baud / 10.0);
			if (bad != 0 || tx_bad_stop != 0) errors = errors + 1;
			if ((span_sum / span_n) < 0.99 * nominal || (span_sum / span_n) > 1.01 * nominal) begin
				$display("TB   FAIL TX bit period outside 1 %%");
				errors = errors + 1;
			end
		end
	endtask

	// ------------------------------------------------------------------
	// RX: bench transmitter + polled reader
	// ------------------------------------------------------------------
	reg [7:0] rx_pat [0:63];
	reg [7:0] rx_got [0:127];
	integer rx_n;
	integer overruns = 0, frame_errs = 0;
	integer sending = 0;

	reg fe_r = 1'b0;
	always @(posedge clk) begin
		fe_r <= dut.scc_inst.frame_err_a;
		if (dut.scc_inst.rx_wr_a && dut.scc_inst.rx_queue_pos_a == 2'd3) overruns = overruns + 1;
		if (dut.scc_inst.frame_err_a && !fe_r) frame_errs = frame_errs + 1;
	end

	integer bad_stop_at = -1;     // frame index sent with a 0 stop bit
	task drive_frames(input real cpb);
		real t;
		integer i, b;
		reg [9:0] fr;
		reg [63:0] base;
		begin
			sending = 1;
			@(posedge clk);
			base = cyc;
			t = 0.0;
			for (i = 0; i < 64; i = i + 1) begin
				fr = {(i == bad_stop_at) ? 1'b0 : 1'b1, rx_pat[i], 1'b0};
				for (b = 0; b < 10; b = b + 1) begin
					rxd <= fr[b];
					t = t + cpb;
					while (cyc < base + $rtoi(t + 0.5)) @(posedge clk);
				end
			end
			rxd <= 1'b1;
			sending = 0;
		end
	endtask

	task rx_reader(input real nominal);
		reg [7:0] v, d;
		reg [63:0] tlimit;
		begin
			rx_n = 0;
			tlimit = cyc + $rtoi(64 * 12 * nominal) + 200000;
			while (rx_n < 64 && cyc < tlimit) begin
				rd_rr(0, v);
				if (v[0]) begin
					beat(A_DATA, 0, 8'h00, d);
					rx_got[rx_n] = d;
					rx_n = rx_n + 1;
				end else
					idle($rtoi(2 * nominal));   // ~5 polls per character
			end
			// anything still arriving (a garbled stream can make extra frames)
			idle($rtoi(12 * nominal));
			rd_rr(0, v);
			while (v[0]) begin
				beat(A_DATA, 0, 8'h00, d);
				if (rx_n < 128) rx_got[rx_n] = d;
				rx_n = rx_n + 1;
				rd_rr(0, v);
			end
		end
	endtask

	// returns number of mismatching bytes
	task rx_test(input integer baud, input [15:0] tc, input real rate, input [255:0] label, output integer nbad);
		integer i;
		real nominal, cpb;
		integer ov0, fe0;
		begin
			nominal = FCLK / baud;
			cpb = FCLK / rate;
			serial_open(8'h44, tc);
			drain_rx;
			// rxuart (wbuart32) leaves reset only after the line has idled
			// 16 bit times (line_synch); a real sender is idle after an open
			idle($rtoi(20 * nominal));
			ov0 = overruns; fe0 = frame_errs;
			fork
				drive_frames(cpb);
				rx_reader(nominal);
			join
			nbad = 0;
			for (i = 0; i < 64; i = i + 1)
				if (i >= rx_n || rx_got[i] !== rx_pat[i]) nbad = nbad + 1;
			if (rx_n != 64) nbad = nbad + (rx_n > 64 ? rx_n - 64 : 0);
			$display("TB   RX %0d baud, sender %0.1f baud (%0s, %0.2f clk/bit, %0.2f %%): %0d bytes read, %0d wrong, %0d overrun, %0d framing errors",
			         baud, rate, label, cpb, 100.0 * (rate - baud) / baud, rx_n, nbad,
			         overruns - ov0, frame_errs - fe0);
		end
	endtask

	// ------------------------------------------------------------------
	// D: divider table
	// ------------------------------------------------------------------
	// ideal = the Z8530 formula on the modelled 3.6864 MHz RTxC
	task div_row(input [7:0] wr4, input [15:0] tc, input [255:0] what);
		integer got, mult;
		real want;
		begin
			serial_open(wr4, tc);
			idle(10);
			got  = dut.scc_inst.baud_divid_speed_a;
			mult = (wr4[7:6] == 2'b00) ? 1 : (wr4[7:6] == 2'b01) ? 16 : (wr4[7:6] == 2'b10) ? 32 : 64;
			want = 3686400.0 / (2.0 * (tc + 2) * mult);
			$display("TB   WR4=$%02h TC=%0d (%0s): divider %0d clk/bit = %0.0f baud, formula %0.1f baud  [%0s]",
			         wr4, tc, what, got, FCLK / got, want,
			         ((FCLK / got) > 0.99 * want && (FCLK / got) < 1.01 * want) ? "ok" : "CATCH-ALL");
		end
	endtask

	integer i, nb, s;
	reg [7:0] v, r0a, r0b;
	reg [31:0] lfsr;
	real hps57600, hps9600;
	integer lo_ok, hi_ok;

	initial begin
		lfsr = 32'h1234_5678;
		for (i = 0; i < 64; i = i + 1) begin
			lfsr = {lfsr[30:0], lfsr[31] ^ lfsr[21] ^ lfsr[1] ^ lfsr[0]};
			rx_pat[i] = lfsr[7:0];
		end
		rx_pat[0] = 8'h00; rx_pat[1] = 8'hFF; rx_pat[2] = 8'h55; rx_pat[3] = 8'hAA;
		rx_pat[4] = 8'h00; rx_pat[5] = 8'h00; rx_pat[6] = 8'h1B; rx_pat[7] = 8'h11;
		rx_pat[8] = 8'h13; rx_pat[9] = 8'h0D;

		// HPS UART: 100 MHz l4_sp_clk / (16 * round(100e6 / 16 / baud))
		hps57600 = 100.0e6 / (16.0 * 109.0);
		hps9600  = 100.0e6 / (16.0 * 651.0);

		nreset = 0;
		idle(40);
		nreset = 1;
		idle(40);
		wr_reg(9, 8'hC0);                   // ROM hardware reset
		idle(60);

		$display("TB == A. TX at 57600 (WR4=$44 x16, TC=0) ==");
		tx_test(57600, 16'd0);
		$display("TB == A. TX at 9600 (WR4=$44 x16, TC=10) ==");
		tx_test(9600, 16'd10);

		$display("TB == B. RX at 57600 ==");
		rx_test(57600, 16'd0, 57600.0, "nominal", nb);          if (nb) errors = errors + 1;
		rx_test(57600, 16'd0, hps57600, "HPS UART real", nb);   if (nb) errors = errors + 1;
		rx_test(57600, 16'd0, 57600.0 * 0.97, "-3 %", nb);      if (nb) errors = errors + 1;
		rx_test(57600, 16'd0, 57600.0 * 1.03, "+3 %", nb);      if (nb) errors = errors + 1;
		$display("TB == B. RX at 9600 ==");
		rx_test(9600, 16'd10, 9600.0, "nominal", nb);           if (nb) errors = errors + 1;
		rx_test(9600, 16'd10, hps9600, "HPS UART real", nb);    if (nb) errors = errors + 1;
		rx_test(9600, 16'd10, 9600.0 * 0.97, "-3 %", nb);       if (nb) errors = errors + 1;
		rx_test(9600, 16'd10, 9600.0 * 1.03, "+3 %", nb);       if (nb) errors = errors + 1;

		$display("TB == B'. RX tolerance sweep at 57600 (informational) ==");
		lo_ok = 0; hi_ok = 0;
		for (s = 4; s <= 8; s = s + 1) begin
			rx_test(57600, 16'd0, 57600.0 * (1.0 - s / 100.0), "sweep", nb);
			if (nb == 0) lo_ok = s;
			rx_test(57600, 16'd0, 57600.0 * (1.0 + s / 100.0), "sweep", nb);
			if (nb == 0) hi_ok = s;
		end
		$display("TB   clean up to -%0d %% / +%0d %% (of the 4..8 %% steps)", lo_ok, hi_ok);

		$display("TB == B''. mismatched rates: a 57600 sender into a 9600 receiver and back ==");
		rx_test(9600, 16'd10, 57600.0, "57600 into 9600", nb);
		rx_test(57600, 16'd0, 9600.0, "9600 into 57600", nb);

		$display("TB == B'''. one framing error in a back-to-back 57600 stream (byte 20 sent with a 0 stop bit) ==");
		bad_stop_at = 20;
		rx_test(57600, 16'd0, 57600.0, "frame error at 20", nb);
		bad_stop_at = -1;
		$display("TB   (rxuart drops to RESET_IDLE on a framing error and waits for 16 idle bit times)");

		$display("TB == C. handshake lines ==");
		serial_open(8'h44, 16'd0);
		drain_rx;
		idle($rtoi(20 * FCLK / 57600.0));
		cts_pin = 1'b1; idle(200); rd_rr(0, r0a);
		cts_pin = 1'b0; idle(200); rd_rr(0, r0b);
		cts_pin = 1'b1;
		$display("TB   RR0 with CTS pin 1: $%02h (CTS bit5=%0d DCD bit3=%0d); with CTS pin 0: $%02h (CTS bit5=%0d DCD bit3=%0d)",
		         r0a, r0a[5], r0a[3], r0b, r0b[5], r0b[3]);
		$display("TB   WR5=$EA asserts DTR+RTS in the register; the scc has no DTR pin and its rts pin = %0d with the Rx FIFO empty",
		         rts_pin);
		// one byte into the FIFO, leave it unread
		rx_pat[0] = 8'h41;
		fork
			drive_frames(FCLK / 57600.0);
			begin idle($rtoi(64 * 10 * FCLK / 57600.0 / 64.0) + 2000); end
		join_any
		idle(100);
		$display("TB   rts pin with %0d byte(s) waiting in the Rx FIFO: %0d", dut.scc_inst.rx_queue_pos_a, rts_pin);
		// flush
		wait (sending == 0);
		idle(2000);
		rd_rr(0, v);
		while (v[0]) begin beat(A_DATA, 0, 8'h00, v); rd_rr(0, v); end
		$display("TB   rts pin after draining the FIFO: %0d", rts_pin);
		rx_pat[0] = 8'h00;

		$display("TB == D. divider the SCC uses per Serial Driver setting ==");
		div_row(8'h44, 16'd0, "57600 8N1");
		div_row(8'h4C, 16'd0, "57600 8N2");
		div_row(8'h44, 16'd4, "19200 8N1");
		div_row(8'h44, 16'd10, "9600 8N1");
		div_row(8'h4C, 16'd10, "9600 8N2");
		div_row(8'h44, 16'd22, "4800 8N1");
		div_row(8'h44, 16'd46, "2400 8N1");
		div_row(8'h44, 16'd94, "1200 8N1");
		div_row(8'h4C, 16'd94, "1200 8N2");
		div_row(8'h44, 16'd189, "600 8N1");
		div_row(8'h4C, 16'd190, "600 8N2 TC=190");
		div_row(8'h04, 16'd0, "x1 clock TC=0, not a driver rate");

		$display("TB");
		if (errors == 0) $display("TB RESULT: PASS");
		else             $display("TB RESULT: FAIL (%0d error(s))", errors);
		$display("RESULT: %0s", errors == 0 ? "PASS" : "FAIL");
		if (errors != 0) $fatal(1, "tb_scc_printer: FAILED");
		$finish;
	end

endmodule
