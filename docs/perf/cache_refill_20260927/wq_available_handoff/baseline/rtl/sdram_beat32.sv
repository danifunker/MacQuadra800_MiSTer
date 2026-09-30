//============================================================================
//  sdram_beat32 — 32-bit machine beats on the 16-bit MiSTer SDRAM controller.
//
//  Wraps rtl/sdram.sv (Sorgelig's, from NeoGeo_MiSTer) and the clk_sys <->
//  clk_ram handshake that used to live inline in MacQuadra800.sv.  Three things
//  here that the plain two-access bridge did not do:
//
//  * A READ FILLS A 16-BYTE LINE.  The controller programs BURST_LENGTH=8,
//    so one READ returns four aligned longwords.  All four are retained in
//    this bridge; later reads from that line complete without another SDRAM
//    command.  This matches the AP68040 cache's four-beat refill pattern and
//    removes three serialized clk_sys/clk_ram handshakes per cache miss.
//    Writes still take two accesses; NO_WRITE_BURST=1 in the mode register.
//
//  * THE RELATED CLOCKS USE TIMED HALF-CYCLE HANDOFFS.  clk_sys and clk_ram
//    are phase-aligned 1:3 outputs of the same PLL.  Capturing the request and
//    completion toggles on clk_ram's falling edge removes the two conservative
//    2FF synchronisers while leaving a timed half-cycle on every crossing.
//    Hardware-tested read latency: 7 -> 5 clk_sys (~212 -> ~151 ns).
//
//  * WRITES ARE POSTED, THROUGH AN EIGHT-ENTRY FIFO.  A write is acknowledged
//    as it enters the FIFO (from the beat port, or from the registered push
//    port quadra800 drives straight from the store buffer), and clk_ram
//    drains the FIFO back to back.  A read starts only once the FIFO is
//    empty, and clk_ram also drains queued writes before it takes a read,
//    so a read always sees every earlier write.  Before 2026-09-23 a posted
//    write held `busy` through its whole drain and the machine's service
//    FSM through its registered completion: ~6 clk_sys a store, which is
//    what bounded Whetstone on hardware.
//
//  Beat contract (clk_sys):
//   - req is level-held; a read is captured on the first cycle with
//     !busy && !ack, a write on the first with the FIFO not full; req may
//     drop as soon as ack is seen.
//   - ack is a single-cycle pulse.  For a read it means "rdata is valid";
//     for a write it means "accepted", not "in the chip".
//   - busy is high while a read is in flight or a write is not yet in the
//     chip.
//   - wp_valid pushes one write per cycle with no handshake; the caller
//     decides it a cycle ahead from wq_room (two or more free slots of eight).
//
//  Byte lanes: be[3] is the byte at addr+0 = wdata[31:24] (the machine's
//  big-endian convention), so the first SDRAM word carries wdata[31:16].
//  Nothing else reads this memory, so the in-chip order only has to agree
//  with itself.
//============================================================================

module sdram_beat32
(
	input             init,          // hold the controller in its power-up sequence
	input             clk_sys,
	input             clk_ram,       // 3x clk_sys, same PLL, phase aligned

	// beat port (clk_sys)
	input             req,
	input             we,
	input      [26:2] addr,
	input       [3:0] be,
	input      [31:0] wdata,
	output reg        ack   = 0,
	output reg [31:0] rdata = 0,
	output            busy,          // a read in flight, or a posted write not yet in the chip
	output            line_valid_o,
	output     [26:4] line_tag_o,
	output    [127:0] line_data_o,
	output            line_pending_o,
	output     [26:4] line_pending_tag_o,

	// Posted-write push (clk_sys, registered by the caller): one write into
	// the FIFO per cycle with no handshake.  The caller pushes only while
	// wq_room was high in the cycle it decided, which leaves a slot for the
	// push that decision registers.
	input             wp_valid,
	input      [26:2] wp_addr,
	input       [3:0] wp_be,
	input      [31:0] wp_data,
	output            wq_room,       // at least two free slots

	// SDRAM pins
	inout      [15:0] SDRAM_DQ,
	output     [12:0] SDRAM_A,
	output            SDRAM_DQML,
	output            SDRAM_DQMH,
	output      [1:0] SDRAM_BA,
	output            SDRAM_nCS,
	output            SDRAM_nWE,
	output            SDRAM_nRAS,
	output            SDRAM_nCAS,
	output            SDRAM_CKE,
	output            SDRAM_CLK
);

// Start each refresh slot at 764 cycles.  A BL8 already in flight can defer
// the command by up to eight clocks; this guard keeps the worst observed gap
// within the SDRAM's 7.8 us distributed-refresh interval at 99 MHz.
reg        refresh = 0;
reg  [9:0] refcnt  = 0;

always @(posedge clk_ram) begin
	refcnt <= refcnt + 1'b1;
	if (refcnt == 10'd763) begin
		refcnt  <= 0;
		refresh <= ~refresh;
	end
end

// ---- clk_sys side: hand one beat over, wait for the ack toggle ----------
reg        req_tgl  = 0;
reg        rbusy    = 0;             // a read beat is in flight
reg        fill_poisoned = 0;        // a push arrived while the line fill was reading
wire       line_done_now;
reg        ack_seen = 0;
reg        posted   = 0;             // the beat in flight was acked at capture
reg [26:2] r_addr;
reg [31:0] r_wdata;
reg  [3:0] r_be;
reg        r_we;

// ---- the posted-write FIFO (2026-09-23) ----------------------------------
// A posted write used to hold `busy` through its whole drain -- the request
// toggle across, two controller WRITEs, the completion toggle back -- so
// the next beat waited ~18 clk_ram (6 clk_sys) per store, and Whetstone's
// store stream ran at the bridge's round-trip rate.  Writes now enter a
// eight-entry FIFO on clk_sys and are acknowledged there; clk_ram drains it
// back to back and returns its read pointer through the same falling-edge
// handoff as the toggles.  A read still waits until every queued write has
// reached the chip (the FIFO is empty and nothing is in flight), so ordering
// is exactly as before.  Entries are written on clk_sys and read on clk_ram
// only after the write pointer that publishes them has crossed.
wire [60:0] wq_q;
wire wq_push_bus = !init && !wp_valid && req && we && !rbusy && !ack && !fill_pending && !wq_full;
wire wq_push = !init && (wp_valid || wq_push_bus);
wire [60:0] wq_push_data = wp_valid ? {wp_addr, wp_data, wp_be} : {addr, wdata, be};
// The queue slot is only consumed after publication through wq_wp_handoff.
// Explicit asynchronous MLAB read preserves the existing capture edge.
`ifdef VERILATOR
// Behavioral counterpart for queue simulation: synchronous write, asynchronous
// read. It intentionally models settled post-write data; it does not assert a
// device-level mixed-port collision guarantee. The direct Quartus primitive
// branch below is what synthesis and the actual-primitive test exercise.
reg [60:0] wq_mem_model [0:7];
integer wq_model_i;
initial for (wq_model_i = 0; wq_model_i < 8; wq_model_i = wq_model_i + 1) wq_mem_model[wq_model_i] = 61'd0;
always @(posedge clk_sys) if (wq_push) wq_mem_model[wq_wp[2:0]] <= wq_push_data;
assign wq_q = wq_mem_model[wq_rp[2:0]];
`else
altdpram #(
    .width(61), .widthad(3), .numwords(8),
    .intended_device_family("Cyclone V"), .ram_block_type("MLAB"),
    .indata_aclr("OFF"), .wraddress_aclr("OFF"), .wrcontrol_aclr("OFF"),
    .indata_reg("INCLOCK"), .wraddress_reg("INCLOCK"),
    .wrcontrol_reg("INCLOCK"), .rdaddress_reg("UNREGISTERED"),
    .rdcontrol_reg("UNREGISTERED"), .outdata_reg("UNREGISTERED"),
    .read_during_write_mode_mixed_ports("NEW_DATA")
) wq_mem (
    .wren(wq_push), .data(wq_push_data), .wraddress(wq_wp[2:0]),
    .inclock(clk_sys), .inclocken(1'b1),
    .rden(1'b1), .rdaddress(wq_rp[2:0]),
    .wraddressstall(1'b0), .rdaddressstall(1'b0), .byteena(1'b1),
    .outclock(1'b1), .outclocken(1'b1), .aclr(1'b0), .sclr(1'b0), .q(wq_q)
);
`endif
reg   [3:0] wq_wp   = 0;             // clk_sys: next free slot (bit 3 = wrap)
reg   [3:0] wq_rp   = 0;             // clk_ram: next slot to drain
reg   [3:0] wq_wp_handoff = 0;       // wq_wp seen on clk_ram's falling edge
reg   [3:0] wq_rp_handoff = 0;       // wq_rp seen on clk_ram's falling edge
// The read pointer crosses into clk_sys through one plain register, and
// everything clk_sys derives from it (full, empty, room) is computed from
// that register: the falling-edge handoff leaves half a clk_ram period, which
// the room decision's path into quadra800's write registers did not meet
// (P186 fit, -1.369 ns).  The extra clock only overstates the fill.
reg   [3:0] wq_rp_sys = 0;
always @(posedge clk_sys) wq_rp_sys <= wq_rp_handoff;
wire        wq_full  = (wq_wp[2:0] == wq_rp_sys[2:0]) && (wq_wp[3] != wq_rp_sys[3]);
wire        wq_empty = (wq_wp == wq_rp_sys);
wire  [3:0] wq_used  = wq_wp - wq_rp_sys;
// two free slots: one for a push already decided, one for this decision
assign wq_room = (wq_used <= 4'd6);
assign busy = rbusy || !wq_empty;

// ---- clk_ram side: one burst read, or two 16-bit writes ----------------
reg        req_seen = 0;
reg        busy_r   = 0;
// The request fields the controller consumes, re-registered on clk_ram when
// the request is taken.  r_addr/r_wdata/r_be/r_we are clk_sys registers and
// are held for the whole beat, so this costs nothing; it turns every
// clk_sys -> clk_ram data path into a plain register-to-register hop instead
// of letting the fitter time them through the controller's page-hit compare.
reg [26:2] a_ram  = 0;
reg [31:0] d_ram  = 0;
reg  [3:0] be_ram = 0;
reg        we_ram = 0;
reg        acc      = 0;             // write half: 0 = high word, 1 = low
reg        wq_act   = 0;             // clk_ram: the access in flight is a FIFO write
reg        rd_burst = 0;
reg  [2:0] rd_word  = 0;
reg        ready_d  = 0;
reg [31:0] hold     = 0;
reg [31:0] line_hold [0:3];
reg        ack_tgl  = 0;
reg        line_done_tgl = 0;

wire [15:0] dout;
wire        ready;

// clk_sys and clk_ram are 0-degree outputs of the same PLL, with an exact
// 1:3 frequency ratio.  They are related clocks, not asynchronous domains.
// The old bridge nevertheless put a two-flop synchronizer in each direction,
// which burned about 60% of a read beat after the SDRAM burst itself became
// fast.  Transfer the toggles on clk_ram's falling edge instead: it is 5 ns
// from either adjacent clk_ram rising edge and can never coincide with a
// clk_sys rising edge.  The request payload remains held for the entire beat;
// the read payload is copied alongside the completion toggle.
//
// These are deliberately separate falling-edge registers.  The controller
// remains wholly rising-edge logic, and TimeQuest can time both half-cycle
// paths because the clocks share a PLL.
reg        req_handoff  = 0;
reg        ack_handoff  = 0;
reg        line_done_handoff = 0;
reg [31:0] data_handoff = 0;
reg [31:0] line_handoff [0:3];

// One fully captured SDRAM burst, indexed as four machine longwords.  The
// tag includes the chip select.  Any accepted write invalidates it before
// the posted acknowledgement, preserving read-after-write ordering.
reg        line_valid = 0;
reg [26:4] line_tag = 0;
reg [31:0] line_data [0:3];
reg        fill_pending = 0;
reg        line_done_seen = 0;
wire       line_hit = line_valid && addr[26:4] == line_tag;
assign     line_done_now = (line_done_handoff != line_done_seen);
integer    line_i;

assign line_valid_o       = line_valid;
assign line_tag_o         = line_tag;
assign line_data_o        = {line_data[0], line_data[1], line_data[2], line_data[3]};
assign line_pending_o     = fill_pending;
assign line_pending_tag_o = r_addr[26:4];

always @(negedge clk_ram) begin
	wq_wp_handoff <= wq_wp;
	wq_rp_handoff <= wq_rp;
	req_handoff  <= req_tgl;
	ack_handoff  <= ack_tgl;
	line_done_handoff <= line_done_tgl;
	data_handoff <= hold;
	for (line_i = 0; line_i < 4; line_i = line_i + 1)
		line_handoff[line_i] <= line_hold[line_i];
end

always @(posedge clk_sys) begin
	ack <= 0;

	if (init) begin
		line_valid     <= 0;
		fill_pending   <= 0;
		line_done_seen <= line_done_handoff;
	end
	else if (line_done_now) begin
		line_done_seen <= line_done_handoff;
		line_tag       <= r_addr[26:4];
		// a write pushed while this fill was reading is not in its data
		line_valid     <= !fill_poisoned && !wp_valid;
		fill_poisoned  <= 0;
		fill_pending   <= 0;
		for (line_i = 0; line_i < 4; line_i = line_i + 1)
			line_data[line_i] <= line_handoff[line_i];
	end

	// the push port: never refused (the caller checked wq_room); a beat
	// request waits out the clock a push takes the FIFO
	if (!init && wp_valid) begin
		if (fill_pending && !line_done_now) fill_poisoned <= 1;
		wq_wp      <= wq_wp + 4'd1;
		line_valid <= 0;
	end
	if (!init && req && !wp_valid && !rbusy && !ack && !fill_pending && !we && line_hit) begin
		// The request is still acknowledged synchronously, but needs no
		// clk_ram transaction.  Keeping rbusy low permits the next line beat
		// to be accepted as soon as the requester retires this ack.
		rdata <= line_data[addr[3:2]];
		ack   <= 1;
	end
	else if (!init && req && !wp_valid && we && !rbusy && !ack && !fill_pending && !wq_full) begin
		// posted into the FIFO: the drain is invisible from here
		wq_wp      <= wq_wp + 4'd1;
		line_valid <= 0;
		ack        <= 1;
	end
	else if (!init && req && !wp_valid && !we && !rbusy && !ack && !fill_pending && wq_empty) begin
		r_addr  <= addr;
		r_wdata <= wdata;
		r_be    <= be;
		r_we    <= we;
		req_tgl <= ~req_tgl;
		rbusy    <= 1;
		posted  <= 0;
		line_valid   <= 0;
		fill_pending <= 1;
	end

	if (rbusy && (ack_handoff != ack_seen)) begin
		ack_seen <= ack_handoff;
		rbusy     <= 0;
		posted   <= 0;
		if (!posted) begin
			rdata <= data_handoff;
			ack   <= 1;
		end
	end
end

// rd/wr are held for the whole access: the controller may still be walking
// back to its idle state when a request arrives, and it samples the request
// only there.  Completion is the RISING edge of ready — ready sits low
// before the very first access and through the ~122 us power-up sequence,
// so waiting on the edge cannot false-trigger or deadlock.
//
// rd_burst drops rd as soon as the first word arrives.  The controller remains
// in RDWAIT through the BL8 tail, so a held request cannot be recaptured while
// the remaining seven words are collected.
wire rd = busy_r && !we_ram && !rd_burst;
wire wr = busy_r &&  we_ram;

wire [1:0] rd_slot = a_ram[3:2] + rd_word[2:1];

always @(posedge clk_ram) begin
	ready_d  <= ready;

	if (rd_burst) begin
		if (!rd_word[0]) line_hold[rd_slot][31:16] <= dout;
		else begin
			line_hold[rd_slot][15:0] <= dout;
			if (rd_slot == a_ram[3:2]) begin
				hold    <= {line_hold[rd_slot][31:16], dout};
				// Release the requested longword immediately.  The rest of the
				// BL8 transfer continues into line_hold while fill_pending keeps
				// any following request from launching a second SDRAM command.
				ack_tgl <= ~ack_tgl;
			end
		end

		if (rd_word == 3'd7) begin
			rd_burst     <= 0;
			busy_r       <= 0;
			line_done_tgl <= ~line_done_tgl;
		end
		else rd_word <= rd_word + 1'b1;
	end
	else if (!busy_r) begin
		if (wq_wp_handoff != wq_rp) begin
			acc      <= 0;
			rd_word  <= 0;
			busy_r   <= 1;
			wq_act   <= 1;
			a_ram    <= wq_q[60:36];
			d_ram    <= wq_q[35:4];
			be_ram   <= wq_q[3:0];
			we_ram   <= 1;
		end
		else if (req_handoff != req_seen) begin
			req_seen <= req_handoff;
			acc      <= 0;
			rd_word  <= 0;
			busy_r   <= 1;
			a_ram    <= r_addr;
			d_ram    <= r_wdata;
			be_ram   <= r_be;
			we_ram   <= r_we;
		end
	end
	else if (ready && !ready_d) begin
		if (!we_ram) begin
			line_hold[a_ram[3:2]][31:16] <= dout;
			rd_word  <= 1;
			rd_burst <= 1;
		end
		else if (!acc) acc <= 1;     // second half of the write
		else begin
			busy_r  <= 0;
			if (wq_act) begin
				wq_act <= 0;
				wq_rp  <= wq_rp + 4'd1;   // the slot is free once it is in the chip
			end
			else ack_tgl <= ~ack_tgl;
		end
	end
end

sdram sdram
(
	.init      (init),
	.clk       (clk_ram),
	.SDRAM_EN  (1'b1),

	.SDRAM_DQ  (SDRAM_DQ),
	.SDRAM_A   (SDRAM_A),
	.SDRAM_DQML(SDRAM_DQML),
	.SDRAM_DQMH(SDRAM_DQMH),
	.SDRAM_BA  (SDRAM_BA),
	.SDRAM_nCS (SDRAM_nCS),
	.SDRAM_nWE (SDRAM_nWE),
	.SDRAM_nRAS(SDRAM_nRAS),
	.SDRAM_nCAS(SDRAM_nCAS),
	.SDRAM_CKE (SDRAM_CKE),
	.SDRAM_CLK (SDRAM_CLK),

	.sel       (1'b1),
	.addr      ({a_ram, acc}),           // word address; acc picks the half
	.dout      (dout),
	.din       (acc ? d_ram[15:0] : d_ram[31:16]),
	.wr        (wr),
	.bs        (acc ? be_ram[1:0] : be_ram[3:2]),
	.rd        (rd),
	.ready     (ready),
	.refresh   (refresh),

	.cpsel     (1'b0),
	.cpaddr    (26'd0),
	.cpdin     (16'd0),
	.cprd      (),
	.cpreq     (1'b0),
	.cpbusy    ()
);

endmodule
