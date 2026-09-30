//============================================================================
//  tb_sdram — directed unit test for rtl/sdram_beat32.sv + rtl/sdram.sv
//  against a behavioural SDR SDRAM chip model.
//
//  The GUI sim (sim.v) backs RAM with a plain array, so nothing in this repo
//  ever exercised the real memory path: not the burst capture, not the posted
//  write, not the two clock-domain crossings, not the chip protocol.  A boot
//  is a terrible place to find out — the first RAM beat is ~122 us of
//  power-up sequence away, and a swapped halfword looks like a Sad Mac hours
//  later.  This drives the beat port directly and finishes in seconds.
//
//    NB: no comment line here may start, right after the slashes, with the
//    simulator's own name -- that parses as a metacomment and errors out.
//      $ make tb_sdram
//
//  Every check prints PASS or FAIL; the run ends with a count, plus the
//  measured beat latencies and sustained rates the speed work is about.
//============================================================================
`timescale 1ps/1ps

module tb_sdram;

// clk_ram = 99.0099 MHz, clk_sys exactly a third of it, both from t=0 — which
// is what the PLL gives the real design (same PLL, phase aligned), and what
// makes the toggle handshakes here behave the way they do on the board.
localparam integer TR = 5050;              // clk_ram half period, ps
localparam integer TS = 3*TR;              // clk_sys half period, ps

reg clk_ram = 0;
reg clk_sys = 0;
always #TR clk_ram = ~clk_ram;
always #TS clk_sys = ~clk_sys;

reg         init  = 1;
reg wp_valid = 0;
reg [26:2] wp_addr = 0;
reg [3:0] wp_be = 0;
reg [31:0] wp_data = 0;
wire wq_room;
integer max_queue_used = 0;
always @(negedge clk_sys)
    if (dut.wq_used > max_queue_used) max_queue_used = dut.wq_used;
reg         req   = 0;
reg         we    = 0;
reg  [26:2] addr  = 0;
reg   [3:0] be    = 0;
reg  [31:0] wdata = 0;
wire        ack;
wire [31:0] rdata;
wire        busy;

wire [15:0] SDRAM_DQ;
wire [12:0] SDRAM_A;
wire        SDRAM_DQML, SDRAM_DQMH;
wire  [1:0] SDRAM_BA;
wire        SDRAM_nCS, SDRAM_nWE, SDRAM_nRAS, SDRAM_nCAS, SDRAM_CKE, SDRAM_CLK;

sdram_beat32 dut
(
	.init(init), .clk_sys(clk_sys), .clk_ram(clk_ram),
	.req(req), .we(we), .addr(addr), .be(be), .wdata(wdata),
	.ack(ack), .rdata(rdata), .busy(busy),
	.line_valid_o(), .line_tag_o(), .line_data_o(),
	.line_pending_o(), .line_pending_tag_o(),
	.wp_valid(wp_valid), .wp_addr(wp_addr), .wp_be(wp_be), .wp_data(wp_data), .wq_room(wq_room),
	.SDRAM_DQ(SDRAM_DQ), .SDRAM_A(SDRAM_A),
	.SDRAM_DQML(SDRAM_DQML), .SDRAM_DQMH(SDRAM_DQMH), .SDRAM_BA(SDRAM_BA),
	.SDRAM_nCS(SDRAM_nCS), .SDRAM_nWE(SDRAM_nWE), .SDRAM_nRAS(SDRAM_nRAS),
	.SDRAM_nCAS(SDRAM_nCAS), .SDRAM_CKE(SDRAM_CKE), .SDRAM_CLK(SDRAM_CLK)
);

sdram_model chip
(
	.clk(SDRAM_CLK), .cke(SDRAM_CKE), .nCS(SDRAM_nCS),
	.nRAS(SDRAM_nRAS), .nCAS(SDRAM_nCAS), .nWE(SDRAM_nWE),
	.ba(SDRAM_BA), .a(SDRAM_A), .dqmh(SDRAM_DQMH), .dqml(SDRAM_DQML),
	.dq(SDRAM_DQ)
);

// MiSTer 128 MB modules contain a second 64 MB rank whose chip select is the
// inverse of the connector's nCS level.  Sharing all other pins here models
// that board wiring and catches row/refresh state accidentally shared across
// ranks; on smaller modules this second device is simply absent.
sdram_model chip_hi
(
	.clk(SDRAM_CLK), .cke(SDRAM_CKE), .nCS(~SDRAM_nCS),
	.nRAS(SDRAM_nRAS), .nCAS(SDRAM_nCAS), .nWE(SDRAM_nWE),
	.ba(SDRAM_BA), .a(SDRAM_A), .dqmh(SDRAM_DQMH), .dqml(SDRAM_DQML),
	.dq(SDRAM_DQ)
);

//----------------------------------------------------------------------------
// scoreboard
//----------------------------------------------------------------------------
integer fails  = 0;
integer checks = 0;

task check(input cond, input string what);
	begin
		checks = checks + 1;
		if (cond) $display("PASS  %s", what);
		else begin $display("FAIL  %s", what); fails = fails + 1; end
	end
endtask

task check_eq32(input [31:0] g, input [31:0] e, input string what);
	begin
		checks = checks + 1;
		if (g === e) $display("PASS  %s", what);
		else begin
			$display("FAIL  %s -- got %08h want %08h", what, g, e);
			fails = fails + 1;
		end
	end
endtask

//----------------------------------------------------------------------------
// beat driver — mirrors quadra800.sv's S_MEM: hold req, drop it on the ack
//----------------------------------------------------------------------------
integer    last_cycles;
reg [31:0] got;

// Stimulus changes on the NEGEDGE and is sampled there too.  Driving on the
// posedge races the DUT at the same edge, and a posted write acks in the
// cycle it is captured -- a one-cycle pulse that a posedge sampler can miss
// entirely, after which it sits on a still-asserted req and the beat is
// issued a second time.  (Which is a real property worth knowing: this
// bridge WILL re-capture a req that is still up once busy falls.  quadra800
// drops mem_req on the ack, so the machine never does that.)
//
// n counts clk_sys posedges from the one that captures the beat to the one
// that acks it, so it measures the memory path and not the machine's FSM.
task automatic beat(input bit we_i, input [26:2] a, input [3:0] be_i,
                    input [31:0] wd);
	integer n;
	begin
		@(negedge clk_sys);
		req   = 1;
		we    = we_i;
		addr  = a;
		be    = be_i;
		wdata = wd;
		n = 0;
		forever begin
			@(negedge clk_sys);
			n = n + 1;
			if (ack) begin
				got = rdata;
				req = 0;
				break;
			end
		end
		last_cycles = n;
	end
endtask

task automatic wr32(input [26:2] a, input [3:0] be_i, input [31:0] d);
	beat(1'b1, a, be_i, d);
endtask

task automatic rd32(input [26:2] a);
	beat(1'b0, a, 4'b1111, 32'd0);
endtask

// a posted write is only really finished when the drain has left the bridge
task automatic drain;
	begin
		@(negedge clk_sys);
		while (busy) @(negedge clk_sys);
	end
endtask

// A critical-word-first read may already be acknowledged while the BL8 tail
// is still being installed in the bridge's line buffer.
task automatic fill_drain;
	begin
		@(negedge clk_sys);
		while (dut.fill_pending) @(negedge clk_sys);
	end
endtask

// A beat address that walks all four banks and two rows.  Mind the offsets:
// the field is addr[26:2], so bank = addr[24:23] sits at value bit 21 and
// row = addr[22:10] starts at value bit 8.  (addr[26] is the chip select,
// which is a second device this model does not have.)
function [26:2] spread(input integer k);
	spread = (k[1:0] * 25'h20_0000) + (k[2] ? 25'h00_0100 : 25'd0) + 25'h40;
endfunction

//----------------------------------------------------------------------------
integer i;
time    t0, t1, dr, dw;
integer rd_cycles, page_rd_cycles, wr_cycles, hit_rd_cycles;
integer acts0, acts1, pres0;
reg [31:0] exp;
reg  [3:0] m;

initial begin
	$display("");
	$display("tb_sdram: sdram_beat32 + sdram.sv against a chip model");
	$display("");

	repeat (4) @(posedge clk_sys);
	init <= 0;

	// the controller's own power-up sequence is ~12100 clk_ram cycles
	repeat (13000) @(posedge clk_ram);
	@(posedge clk_sys);
	check(chip.mode_set && chip_hi.mode_set,
	      "both ranks saw LOAD MODE REGISTER during startup");
	check(chip.cl == 3'd2 && chip.bl == 8 &&
	      chip_hi.cl == 3'd2 && chip_hi.bl == 8,
	      "both ranks program CAS latency 2, burst length 8");

	//--------------------------------------------------------------------
	// 1. round trip, and the two halves the right way round
	//--------------------------------------------------------------------
	wr32(25'h000100, 4'b1111, 32'h1122_3344);
	wr32(25'h000101, 4'b1111, 32'h5566_7788);
	drain();
	rd32(25'h000100);
	check_eq32(got, 32'h1122_3344, "read back the first longword");
	rd32(25'h000101);
	check_eq32(got, 32'h5566_7788, "read back the second longword");

	// The burst capture is the point of the exercise, and a swap of the two
	// halves would still round-trip through THIS bridge (it writes in the
	// same order it reads).  So check the chip's own array: big end first.
	check(chip.peek(25'h000100, 1'b0) == 16'h1122 &&
	      chip.peek(25'h000100, 1'b1) == 16'h3344,
	      "in the chip, the high halfword is at the even word address");

	// Start at slot 2 so the sequential BL8 wraps 2,3,0,1.  Every cached
	// longword must still land in its address-selected slot.
	wr32(25'h000102, 4'b1111, 32'h99AA_BBCC);
	wr32(25'h000103, 4'b1111, 32'hDDEE_FF00);
	drain();
	rd32(25'h000102);
	check_eq32(got, 32'h99AA_BBCC, "critical word returns from a wrapped BL8 fill");
	fill_drain();
	rd32(25'h000100); check_eq32(got, 32'h1122_3344, "BL8 wrap caches slot 0");
	rd32(25'h000101); check_eq32(got, 32'h5566_7788, "BL8 wrap caches slot 1");
	rd32(25'h000103); check_eq32(got, 32'hDDEE_FF00, "BL8 wrap caches slot 3");

	//--------------------------------------------------------------------
	// 1b. page hits, independent bank rows, and an explicit row conflict
	//--------------------------------------------------------------------
	// Keep refresh outside this short directed window so command counts say
	// exactly what the page scheduler did rather than including maintenance.
	@(negedge clk_ram); dut.refcnt = 0;
	rd32(25'h000104); // establish the row even if earlier refresh closed it
	fill_drain();
	@(negedge clk_ram); dut.refcnt = 0;
	acts0 = chip.active_count;
	pres0 = chip.precharge_count;
	for (i = 0; i < 4; i = i + 1) rd32(25'h000108 + 4*i);
	check(chip.active_count == acts0 && chip.precharge_count == pres0,
	      "same-row reads reuse the open page");

	rd32(25'h200100); // bank 1, same row/column
	check(chip.active_count == acts0 + 1 && chip.precharge_count == pres0,
	      "a different bank activates without closing bank 0");
	rd32(25'h000101);
	check(chip.active_count == acts0 + 1,
	      "returning to bank 0 reuses its independently open row");

	rd32(25'h000200); // bank 0, next row
	check(chip.active_count == acts0 + 2 && chip.precharge_count == pres0 + 1,
	      "same-bank row conflict precharges and reactivates");

	// The same bank/row may be open independently in both ranks.  A shared
	// four-bank tracker would omit rank 1's ACT here and the model would reject
	// its write; the retained-line tag must distinguish the ranks as well.
	wr32(25'h000600, 4'b1111, 32'h1357_9BDF);
	drain();
	wr32(25'h1000600, 4'b1111, 32'h2468_ACE0);
	drain();
	acts0 = chip.active_count;
	acts1 = chip_hi.active_count;
	rd32(25'h000600);
	check_eq32(got, 32'h1357_9BDF, "rank 0 retains its own data");
	fill_drain();
	rd32(25'h1000600);
	check_eq32(got, 32'h2468_ACE0, "rank 1 retains distinct data");
	fill_drain();
	check(chip.active_count == acts0 && chip_hi.active_count == acts1,
	      "same row remains independently open in both ranks");
	// The refcnt reset above intentionally lengthened one refresh interval.
	// Exclude only that test-induced gap from the later maintenance report.
	@(negedge clk_ram);
	chip.t_refresh = 0; chip.max_refresh_gap = 0;
	chip_hi.t_refresh = 0; chip_hi.max_refresh_gap = 0;

	//--------------------------------------------------------------------
	// 2. byte enables, all sixteen masks
	//--------------------------------------------------------------------
	for (i = 0; i < 16; i = i + 1) begin
		m = i[3:0];
		wr32(25'h000200 + i, 4'b1111, 32'h0000_0000);
		drain();
		wr32(25'h000200 + i, m, 32'hAABB_CCDD);
		drain();
		rd32(25'h000200 + i);
		exp = { m[3] ? 8'hAA : 8'h00, m[2] ? 8'hBB : 8'h00,
		        m[1] ? 8'hCC : 8'h00, m[0] ? 8'hDD : 8'h00 };
		check_eq32(got, exp, $sformatf("byte enables %04b merge correctly", m));
	end

	//--------------------------------------------------------------------
	// 3. a posted write is still ordered against what follows it
	//--------------------------------------------------------------------
	wr32(25'h000300, 4'b1111, 32'hDEAD_BEEF);
	rd32(25'h000300);                   // no drain(): straight down the pipe
	check_eq32(got, 32'hDEAD_BEEF, "read immediately after a posted write");

	wr32(25'h000301, 4'b1111, 32'h0000_0001);
	wr32(25'h000301, 4'b1111, 32'h0000_0002);
	wr32(25'h000301, 4'b1111, 32'h0000_0003);
	rd32(25'h000301);
	check_eq32(got, 32'h0000_0003, "back-to-back posted writes retire in order");


    // Push fast enough to fill the queue, wrap both pointers many times,
    // then overwrite selected bytes before checking independent readback.
    fill_drain();
    drain();
    @(negedge clk_sys);
    for (i = 0; i < 128; i = i + 1) begin
        while (!wq_room) @(negedge clk_sys);
        wp_addr = 25'h800 + i;
        wp_data = 32'hABC00000 + i;
        wp_be = 4'hf;
        wp_valid = 1;
        @(negedge clk_sys);
        wp_valid = 0;
    end
    // No explicit drain: the ordinary read must wait for earlier pushes.
    rd32(25'h87f);
    check_eq32(got, 32'hABC0007F, "push queue read-after-write ordering");
    fill_drain();
    @(negedge clk_sys);
    for (i = 0; i < 128; i = i + 1) begin
        while (!wq_room) @(negedge clk_sys);
        wp_addr = 25'h800 + i;
        wp_data = 32'h12345678;
        wp_be = i[3:0];
        wp_valid = 1;
        @(negedge clk_sys);
        wp_valid = 0;
    end
    for (i = 0; i < 128; i = i + 1) begin
        rd32(25'h800 + i);
        m = i[3:0];
        exp = 32'hABC00000 + i;
        if (m[3]) exp[31:24] = 8'h12;
        if (m[2]) exp[23:16] = 8'h34;
        if (m[1]) exp[15:8] = 8'h56;
        if (m[0]) exp[7:0] = 8'h78;
        check_eq32(got, exp, $sformatf("push queue wrap/mask word %0d", i));
    end
    if (max_queue_used < 6) $fatal(1, "queue stress did not fill queue: %0d", max_queue_used);
    $display("PASS push stress exercised queue occupancy %0d", max_queue_used);

	//--------------------------------------------------------------------
	// 4. all four banks, and across a refresh
	//--------------------------------------------------------------------
	for (i = 0; i < 8; i = i + 1) begin
		wr32(spread(i), 4'b1111, 32'hC0DE_0000 + i);
		drain();
	end
	for (i = 0; i < 8; i = i + 1) begin
		rd32(spread(i));
		check_eq32(got, 32'hC0DE_0000 + i,
		           $sformatf("bank/row spread %0d round trip", i));
	end

	repeat (3000) @(posedge clk_ram);   // ~30 us: several refresh cycles
	rd32(25'h000100);
	check_eq32(got, 32'h1122_3344, "data survives auto-refresh");
	rd32(25'h1000600);
	check_eq32(got, 32'h2468_ACE0, "rank 1 data survives auto-refresh");

	//--------------------------------------------------------------------
	// 5. what it all costs
	//--------------------------------------------------------------------
	drain();
	wr32(25'h000500, 4'b1111, 32'hCAFE_BABE); // invalidate the read line
	drain();
	rd32(25'h000100);   rd_cycles = last_cycles;
	fill_drain();
	rd32(25'h000101);   hit_rd_cycles = last_cycles;
	wr32(25'h000180, 4'b1111, 32'h0123_4567); // same row, invalidate line
	drain();
	rd32(25'h000100);   page_rd_cycles = last_cycles;
	fill_drain();
	drain();
	wr32(25'h000100, 4'b1111, 32'h1122_3344);  wr_cycles = last_cycles;
	drain();

	t0 = $time;
	for (i = 0; i < 64; i = i + 1) wr32(25'h000400 + i, 4'b1111, 32'h5A00_0000 + i);
	drain();
	t1 = $time;
	dw = (t1 - t0) / 1000;

	t0 = $time;
	for (i = 0; i < 64; i = i + 1) rd32(25'h000400 + i);
	t1 = $time;
	dr = (t1 - t0) / 1000;

	for (i = 0; i < 64; i = i + 1) begin
		rd32(25'h000400 + i);
		if (got !== (32'h5A00_0000 + i)) begin
			$display("FAIL  sequential stream [%0d]: got %08h", i, got);
			fails = fails + 1;
		end
	end
	checks = checks + 1;
	$display("PASS  64-deep sequential write stream reads back intact");

	$display("");
	$display("  cold read / critical  %0d clk_sys (%0d ns)",
	         rd_cycles, (rd_cycles * 2 * TS) / 1000);
	$display("  page-hit read         %0d clk_sys (%0d ns)",
	         page_rd_cycles, (page_rd_cycles * 2 * TS) / 1000);
	$display("  buffered line read    %0d clk_sys (%0d ns)",
	         hit_rd_cycles, (hit_rd_cycles * 2 * TS) / 1000);
	$display("  isolated write beat   %0d clk_sys (%0d ns)  [posted]",
	         wr_cycles, (wr_cycles * 2 * TS) / 1000);
	$display("  64 sequential reads   %0d ns = %0d.%0d MB/s",
	         dr, 256000 / dr, (2560000 / dr) % 10);
	$display("  64 sequential writes  %0d ns = %0d.%0d MB/s (to drained)",
	         dw, 256000 / dw, (2560000 / dw) % 10);

	$display("\n  rank 0:");
	chip.report_timing();
	$display("  rank 1:");
	chip_hi.report_timing();

	$display("");
	$display("tb_sdram: %0d checks, %0d failures, %0d chip protocol errors",
	         checks, fails, chip.errors + chip_hi.errors);
	if (fails == 0 && chip.errors == 0 && chip_hi.errors == 0)
		$display("tb_sdram: OK");
	else $fatal(1, "tb_sdram: FAILED");
	$finish;
end

// a hung handshake must not hang the run
initial begin
	#1_000_000_000;                     // 1 ms
	$display("FAIL  tb_sdram: timeout");
	$display("  req=%b we=%b busy=%b ack=%b | busy_r=%b acc=%b rd_burst=%b ready=%b",
	         req, we, busy, ack, dut.busy_r, dut.acc, dut.rd_burst, dut.ready);
	$display("  req_tgl=%b req_handoff=%b req_seen=%b | ack_tgl=%b ack_handoff=%b ack_seen=%b posted=%b",
	         dut.req_tgl, dut.req_handoff, dut.req_seen,
	         dut.ack_tgl, dut.ack_handoff, dut.ack_seen, dut.posted);
	$display("  req=%b we=%b busy=%b ack=%b | busy_r=%b acc=%b rd_burst=%b ready=%b",
	         req, we, busy, ack, dut.busy_r, dut.acc, dut.rd_burst, dut.ready);
	$display("  sdram.state=%0d chip=%b nCS=%b cmd=%b | rd=%b wr=%b",
	         dut.sdram.state, dut.sdram.chip, SDRAM_nCS,
	         {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE}, dut.rd, dut.wr);
	$fatal(1);
end

endmodule


//============================================================================
//  sdram_model — behavioural SDR SDRAM: enough of one to hold this controller
//  to the protocol.  Bank/row state, CAS latency, sequential bursts,
//  auto-precharge, write byte masking, refresh bookkeeping.
//
//  Geometry is what sdram.sv's address mapping implies (see
//  docs/sdram-vram-sharing.md §2): 4 banks, 13 row bits, 10 column bits, so
//  one chip select covers 64 MB.  Storage is associative, so a sparse test
//  costs nothing.
//
//  Read-side DQM is deliberately not modelled: this controller drives DQM=00
//  for the whole of every read (it puts the mask in SDRAM_A[12:11] and holds
//  cas_addr from the RD command through the burst), so there is nothing to
//  model and a wrong guess at the two-cycle DQM read latency would only
//  invent failures.  Write DQM is modelled — that is where the byte enables
//  actually live.
//============================================================================
module sdram_model
(
	input        clk,                   // SDRAM_CLK
	input        cke,
	input        nCS, nRAS, nCAS, nWE,
	input  [1:0] ba,
	input [12:0] a,
	input        dqmh, dqml,
	inout [15:0] dq
);

localparam [2:0] CMD_LOAD_MODE = 3'b000, CMD_REFRESH  = 3'b001,
                 CMD_PRECHARGE = 3'b010, CMD_ACTIVE   = 3'b011,
                 CMD_WRITE     = 3'b100, CMD_READ     = 3'b101,
                 CMD_BST       = 3'b110, CMD_NOP      = 3'b111;

bit [15:0] mem [int];

integer errors   = 0;
bit     mode_set = 0;
bit [2:0] cl     = 3'd2;
integer bl       = 1;

bit        row_open [0:3];
bit [12:0] row      [0:3];

integer now       = 0;                  // chip clocks since power-up
integer t_act [0:3];                    // last ACTIVE per bank
integer t_pre [0:3];                    // when the bank last (started to) precharge
integer t_refresh = 0;

integer min_trc = 9999, min_trcd = 9999, min_trp = 9999, min_tras = 9999;
integer max_refresh_gap = 0;
integer active_count = 0, precharge_count = 0;

// Conservative 99 MHz requirements for the supported MiSTer SDRAM parts.
// The controller may exceed these; going below one is a protocol failure.
localparam integer T_RCD = 2;
localparam integer T_RP  = 3;
localparam integer T_RAS = 5;
localparam integer T_RC  = 7;
localparam integer T_RFC = 7;

// read pipeline; a word placed at index cl-1+j is driven j cycles after the
// first, and reaches the pins CAS-latency cycles after the RD command
bit        pipe_v [0:15];
bit [15:0] pipe_d [0:15];
bit        dq_drive = 0;
bit [15:0] dq_val   = 0;

assign dq = dq_drive ? dq_val : 16'bZZZZZZZZZZZZZZZZ;

function int key(input [1:0] b, input [12:0] r, input [9:0] c);
	key = {7'd0, b, r, c};
endfunction

// beat word -> chip cell, using sdram.sv's own decode:
//   bank = addr[24:23]   row = addr[22:10]   col = {addr[25], addr[9:1]}
function [15:0] peek(input [26:2] la, input lo);
	int k;
	begin
		k = key(la[24:23], la[22:10], {la[25], la[9:2], lo});
		peek = mem.exists(k) ? mem[k] : 16'hFFFF;
	end
endfunction

task report_timing;
	begin
		$display("");
		$display("  chip protocol, informational (clk_ram cycles @ 99 MHz):");
		$display("    min ACT->ACT same bank (tRC)  %0d", min_trc);
		$display("    min ACT->RD/WR         (tRCD) %0d", min_trcd);
		$display("    min PRE->ACT           (tRP)  %0d", min_trp);
		$display("    min ACT->PRE           (tRAS) %0d", min_tras);
		$display("    max gap between refreshes     %0d", max_refresh_gap);
	end
endtask

task err(input string what);
	begin
		$display("CHIP  %s (at chip cycle %0d)", what, now);
		errors = errors + 1;
	end
endtask

integer i;
initial begin
	for (i = 0; i < 4; i = i + 1) begin
		row_open[i] = 0; t_act[i] = -9999; t_pre[i] = -9999;
	end
	for (i = 0; i < 16; i = i + 1) pipe_v[i] = 0;
end

wire [2:0] cmd = nCS ? CMD_NOP : {nRAS, nCAS, nWE};

integer b, col, bcol, j, k;

always @(posedge clk) begin
	if (cke) begin
		now = now + 1;

		// ---- drive whatever the pipeline says is due, then shift --------
		dq_drive <= pipe_v[0];
		dq_val   <= pipe_d[0];
		for (j = 0; j < 15; j = j + 1) begin
			pipe_v[j] = pipe_v[j+1];
			pipe_d[j] = pipe_d[j+1];
		end
		pipe_v[15] = 0;

		case (cmd)
		CMD_LOAD_MODE: begin
			mode_set = 1;
			cl = a[6:4];
			bl = 1 << a[2:0];
			for (i = 0; i < 4; i = i + 1)
				if (row_open[i]) err("LOAD MODE with a row open");
		end

		CMD_REFRESH: begin
			for (i = 0; i < 4; i = i + 1)
				if (row_open[i]) err("AUTO REFRESH with a row open");
			if (t_refresh > 0 && (now - t_refresh) > max_refresh_gap)
				max_refresh_gap = now - t_refresh;
			t_refresh = now;
		end

		CMD_PRECHARGE: begin
			precharge_count = precharge_count + 1;
			for (i = 0; i < 4; i = i + 1)
				if (a[10] || i == ba) begin
					if (row_open[i]) begin
						if ((now - t_act[i]) < min_tras) min_tras = now - t_act[i];
						if ((now - t_act[i]) < T_RAS)
							err($sformatf("tRAS violation on bank %0d: %0d < %0d",
							              i, now - t_act[i], T_RAS));
					end
					row_open[i] = 0;
					t_pre[i]    = now;
				end
		end

		CMD_ACTIVE: begin
			b = ba;
			active_count = active_count + 1;
			if (row_open[b])
				err($sformatf("ACTIVE on bank %0d with row %0d still open", b, row[b]));
			if (!mode_set) err("ACTIVE before the mode register was loaded");
			if ((now - t_pre[b]) < min_trp) min_trp = now - t_pre[b];
			if ((now - t_act[b]) < min_trc) min_trc = now - t_act[b];
			if ((now - t_pre[b]) < T_RP)
				err($sformatf("tRP violation on bank %0d: %0d < %0d",
				              b, now - t_pre[b], T_RP));
			if ((now - t_act[b]) < T_RC)
				err($sformatf("tRC violation on bank %0d: %0d < %0d",
				              b, now - t_act[b], T_RC));
			if (t_refresh > 0 && (now - t_refresh) < T_RFC)
				err($sformatf("tRFC violation: %0d < %0d", now - t_refresh, T_RFC));
			row_open[b] = 1;
			row[b]      = a;
			t_act[b]    = now;
		end

		CMD_READ, CMD_WRITE: begin
			b   = ba;
			col = a[9:0];
			if (!row_open[b])
				err($sformatf("%s to bank %0d with no row open",
				              cmd == CMD_READ ? "READ" : "WRITE", b));
			else begin
				if ((now - t_act[b]) < min_trcd) min_trcd = now - t_act[b];
				if ((now - t_act[b]) < T_RCD)
					err($sformatf("tRCD violation on bank %0d: %0d < %0d",
					              b, now - t_act[b], T_RCD));
				if (cmd == CMD_READ) begin
					if (dq_drive) err("READ while the chip is still driving DQ");
					// sequential burst, wrapping inside the aligned block
					for (j = 0; j < bl; j = j + 1) begin
						bcol = (col & ~(bl-1)) | ((col + j) & (bl-1));
						k = key(b[1:0], row[b], bcol[9:0]);
						pipe_v[cl - 1 + j] = 1;
						pipe_d[cl - 1 + j] = mem.exists(k) ? mem[k] : 16'hFFFF;
					end
				end
				else begin
					if (dq_drive) err("WRITE while the chip is still driving DQ");
					// NO_WRITE_BURST=1: one location, DQM masking the bytes
					k = key(b[1:0], row[b], col[9:0]);
					if (!(dqmh && dqml)) begin
						if (!mem.exists(k)) mem[k] = 16'hFFFF;
						if (!dqmh) mem[k][15:8] = dq[15:8];
						if (!dqml) mem[k][7:0]  = dq[7:0];
					end
				end
				// auto-precharge closes the row once the burst has finished
				if (a[10]) begin
					if ((now - t_act[b]) < min_tras) min_tras = now - t_act[b];
					row_open[b] = 0;
					t_pre[b]    = now + ((cmd == CMD_READ && bl > cl) ? bl - cl : 1);
				end
			end
		end
		default: ;
		endcase
	end
end

endmodule
