// tb_ap040_cache_snoop.v -- directed bench for ap040_cache's snoop and
// port-B arbitration paths (audit findings 5.1-5.3).  These are exactly
// the paths with no other coverage: every other bench ties s_stb low.
//
// The bench drives the cache DIRECTLY: a flat memory model with a fixed
// read latency sits on the m_* side, the c_* side is exercised with
// read/write tasks, ce can be held low for chosen windows, and snoops
// are single-clk pulses INDEPENDENT of ce -- the shape cpu_wrapper's
// snoop CDC actually delivers.
//
//   T1 (5.1)  a snoop landing in a ce-frozen window must still
//             invalidate: the following read of changed memory must
//             miss and refetch.
//   T2 (5.2a) a snoop hitting the set of an in-flight fill must not be
//             undone by the fill's tag writeback, and the snooped way
//             must not be revalidated with stale data.  Swept across
//             the whole fill window.
//   T3 (5.2c) a snoop in the same cycle a lookup is accepted must not
//             let that lookup serve the killed line.  Swept.
//   T4 (5.3)  a snoop displacing a line-crossing store's invalidates
//             must not lose either set.  Swept.
//   T5 (5.4)  a bus error during a line fill (or a passed access) must
//             abandon the transfer instead of re-issuing it forever,
//             must not validate the partly-filled line, and must leave
//             the cache able to serve the exception handler's own
//             accesses.  The error is swept across all four beats.
//   T10       a completed-line sideband arriving with the first memory beat
//             must populate the fill tail locally, preserve late CPU ack,
//             and leave the completed line hitting without more bus traffic.
//   T11       an aligned write-through hit updates only its matching cached
//             longword and preserves all other ways in the same set.
//   T12       a sequential instruction hit reads the following longword ahead,
//             serves it one cycle faster (including a word at offset two),
//             chains within the line, and survives intervening D-cache traffic.
//   T13       snoops may defer a store's first-row invalidate beyond memory
//             acknowledgement; a no-gap read waits until that invalidate lands.
//
// Every test reprograms memory behind the cache and requires the next
// read to return the NEW value: a stale cached longword is the failure
// signature throughout.

`timescale 1ns/1ps

module tb_edge_cases;

reg clk = 0;
always #5 clk = ~clk;

reg nreset = 0;
reg ce_run = 1;          // when 0, ce is forced low (frozen window)
wire ce = ce_run;

reg         cinv_req = 0;
reg         cinv_ic = 0, cinv_dc = 0;
wire        cinv_done;

reg         c_req = 0, c_write = 0, c_instr = 0, c_nocache = 0;
reg  [1:0]  c_size = 0;
reg  [31:0] c_addr = 0, c_wdata = 0;
reg [31:0] tb_hq_addr = 0;   // the hint the MMU would have registered
always @(posedge clk) tb_hq_addr <= c_addr;
wire        c_ack;
wire [31:0] c_rdata;

wire        m_req, m_write, m_instr;
wire  [1:0] m_size;
wire [31:0] m_addr, m_wdata;
reg  [1:0]  mem_lat = 2'd2;   // cycles before m_ack; 0 models a
                              // downstream controller-cache HIT, which is
                              // how fast this port can really answer
reg         m_ack = 0;
reg  [31:0] m_rdata = 0;
reg         m_err = 0;
reg         m_line_valid = 0;
reg  [31:4] m_line_tag = 0;
reg [127:0] m_line_data = 0;

reg         s_stb = 0;
reg  [31:0] s_addr = 0;

reg         snoop_storm = 0;
reg         s_stb_storm = 0;
// free-running chipset snoop traffic on its own driver: port B is taken
// every other cycle, which is what blitter/copper/display DMA looks like
// to this cache.  ORed into the DUT input so the snoop task keeps its own.
always @(negedge clk) begin
	if (snoop_storm) s_stb_storm <= ~s_stb_storm;
	else             s_stb_storm <= 1'b0;
end

wire c_line_stb;
wire [31:4] c_line_tag;
wire [127:0] c_line_data;
ap040_cache dut
(
	.clk(clk), .nreset(nreset), .ce(ce),
	.ie(1'b1), .de(1'b1),
	.cinv_req(cinv_req), .cinv_ic(cinv_ic), .cinv_dc(cinv_dc),
	.cinv_done(cinv_done),
	.c_req(c_req), .c_write(c_write), .c_instr(c_instr),
	.c_size(c_size), .c_addr(c_addr), .c_wdata(c_wdata),
	.c_hint_addr(c_addr), .c_hint_instr(c_instr),
	.c_ihint_addr(c_addr), .c_ihint_ptag(c_addr[31:10]), .c_ihint_match(c_req && c_instr && (tb_hq_addr == c_addr)), .c_ihold(c_req && c_instr),
	// the MMU vouches for a request only when it equals the hint it
	// registered a cycle earlier (m_hint_match); the bench's hint bus is
	// its request bus, so model that register here
	.c_hint_ptag(c_addr[31:10]), .c_hint_match(c_req && (tb_hq_addr == c_addr)),
	.c_hint_wmatch(1'b0), .c_hint_away(1'b0), .c_post_ok_hint(1'b0),   // no posting, no store fast lane here
	.c_fc(c_instr ? 3'd6 : 3'd5), .c_nocache(c_nocache), .c_post_ok(1'b0),
	.c_ack(c_ack), .c_rdata(c_rdata),
    .c_line_stb(c_line_stb), .c_line_tag(c_line_tag), .c_line_data(c_line_data),
	.m_req(m_req), .m_write(m_write), .m_instr(m_instr),
	.m_size(m_size), .m_addr(m_addr), .m_wdata(m_wdata),
	.m_fc(), .m_ack(m_ack), .m_rdata(m_rdata),
	.m_line_valid(m_line_valid), .m_line_tag(m_line_tag),
	.m_line_data(m_line_data), .m_err(m_err | inject_err),
	.s_stb(s_stb | s_stb_storm), .s_addr(s_stb_storm ? 32'h0000_C300 : s_addr)
);

integer errors = 0;

//---------------------------------------------------------------------------
// flat memory with a 2-cycle grant: enough latency that fill beats and
// their ack cycles are deterministic for the sweep offsets below
//---------------------------------------------------------------------------
reg [31:0] mem [0:16383];
reg [31:0] rom [0:16383];   // 64KB
reg  [1:0] mlat = 0;
integer mread_count = 0;

// Fault injection: while err_arm is set, an access whose address matches
// err_addr (line-aligned, beat selected by err_beat) reports a bus error
// the way ap040_bus16_adapter does -- m_err for one qualified cycle and
// NO m_ack, ever, for that transfer.
reg         err_arm = 0;
reg  [31:0] err_addr = 0;
reg  [1:0]  err_beat = 0;
integer     err_count = 0;
wire        err_hit = err_arm && m_req &&
                      (m_addr[31:4] == err_addr[31:4]) &&
                      (m_addr[3:2] == err_beat);

always @(posedge clk) begin
	m_ack <= 0;
	m_err <= 0;
	if (m_req && ce) begin
		if (mlat != mem_lat) mlat <= mlat + 1'd1;
		else begin
			mlat <= 0;
			if (err_hit) begin
				m_err <= 1;
				err_count = err_count + 1;
			end
			else begin
				m_ack <= 1;
				if (m_write) begin
					// longword stores only in this bench
					mem[m_addr[15:2]] <= m_wdata;
				end
				else m_rdata <= m_addr[31:28] == 4'h4 ? rom[m_addr[15:2]] : mem[m_addr[15:2]];
			end
		end
	end
	else mlat <= 0;
end

always @(posedge clk) begin
	if (m_ack && m_req && !m_write) mread_count = mread_count + 1;
end

//---------------------------------------------------------------------------
// helpers
//---------------------------------------------------------------------------
task cpu_read;
	input  [31:0] a;
	output [31:0] d;
	integer guard;
	begin
		@(negedge clk);
		c_req = 1; c_write = 0; c_size = 2'b10; c_addr = a;
		guard = 0;
		while (!(c_ack && ce) && guard < 200) begin
			@(posedge clk);
			guard = guard + 1;
		end
		if (guard >= 200) begin
			$display("FAIL: read timeout at %h", a);
			errors = errors + 1;
		end
		d = c_rdata;
		@(negedge clk);
		c_req = 0;
		@(posedge clk);
	end
endtask

task cpu_read_count_sized;
	input  [31:0] a;
	input   [1:0] sz;
	output [31:0] d;
	output integer cycles;
	integer guard;
	begin
		@(negedge clk);
		c_req = 1; c_write = 0; c_size = sz; c_addr = a;
		guard = 0;
		while (!(c_ack && ce) && guard < 200) begin
			@(posedge clk);
			guard = guard + 1;
		end
		if (guard >= 200) begin
			$display("FAIL: counted read timeout at %h", a);
			errors = errors + 1;
		end
		d = c_rdata;
		cycles = guard;
		@(negedge clk);
		c_req = 0;
		@(posedge clk);
	end
endtask

// Two reads with NO request-low cycle between them.  cpu_read above
// drops c_req and idles a cycle after each access, which lets a pending
// CI invalidate land before the next request is looked up -- so it can
// never expose an FSM that accepts while the invalidate is still owed.
task cpu_read_btb;
	input  [31:0] a1;
	input         ci1;
	input  [31:0] a2;
	output [31:0] o1;
	output [31:0] o2;
	integer guard;
	begin
		@(negedge clk);
		c_req = 1; c_write = 0; c_size = 2'b10; c_addr = a1; c_nocache = ci1;
		guard = 0;
		while (!(c_ack && ce) && guard < 200) begin
			@(posedge clk); guard = guard + 1;
		end
		if (guard >= 200) begin
			$display("FAIL: btb first read timeout at %h", a1);
			errors = errors + 1;
		end
		o1 = c_rdata;
		// present the next access immediately: c_req never falls
		@(negedge clk);
		c_addr = a2; c_nocache = 0;
		@(posedge clk);
		guard = 0;
		while (!(c_ack && ce) && guard < 200) begin
			@(posedge clk); guard = guard + 1;
		end
		if (guard >= 200) begin
			$display("FAIL: btb second read timeout at %h", a2);
			errors = errors + 1;
		end
		o2 = c_rdata;
		@(negedge clk);
		c_req = 0;
		@(posedge clk);
	end
endtask

// A cache-inhibited read that HITS, immediately followed by a WRITE.
// store_inv asserts combinationally while a write waits in C_IDLE and it
// blocks ci_inv; if the FSM also refuses to accept while ci_inv_pend is
// set, the write and the invalidate block each other forever.
task cpu_ci_read_then_write;
	input [31:0] a;
	input [31:0] wa;
	integer guard;
	begin
		@(negedge clk);
		c_req = 1; c_write = 0; c_size = 2'b10; c_addr = a; c_nocache = 1;
		guard = 0;
		while (!(c_ack && ce) && guard < 200) begin
			@(posedge clk); guard = guard + 1;
		end
		if (guard >= 200) begin
			$display("FAIL: CI read never completed");
			errors = errors + 1;
		end
		// present the store with no idle gap
		@(negedge clk);
		c_nocache = 0; c_write = 1; c_addr = wa; c_wdata = 32'hDEAD_5170;
		guard = 0;
		while (!(c_ack && ce) && guard < 300) begin
			@(posedge clk); guard = guard + 1;
		end
		if (guard >= 300) begin
			$display("FAIL: DEADLOCK -- store after a cache-inhibited hit never completed");
			errors = errors + 1;
		end
		@(negedge clk);
		c_req = 0; c_write = 0;
		repeat (3) @(posedge clk);
	end
endtask

task cpu_write;
	input [31:0] a;
	input [31:0] d;
	integer guard;
	begin
		@(negedge clk);
		c_req = 1; c_write = 1; c_size = 2'b10; c_addr = a; c_wdata = d;
		guard = 0;
		while (!(c_ack && ce) && guard < 200) begin
			@(posedge clk);
			guard = guard + 1;
		end
		if (guard >= 200) begin
			$display("FAIL: write timeout at %h", a);
			errors = errors + 1;
		end
		@(negedge clk);
		c_req = 0; c_write = 0;
		@(posedge clk);
	end
endtask

task cpu_write_sized;
	input [31:0] a;
	input  [1:0] sz;
	input [31:0] d;
	integer guard;
	begin
		@(negedge clk);
		c_req = 1; c_write = 1; c_size = sz; c_addr = a; c_wdata = d;
		guard = 0;
		while (!(c_ack && ce) && guard < 200) begin
			@(posedge clk);
			guard = guard + 1;
		end
		if (guard >= 200) begin
			$display("FAIL: sized write timeout at %h", a);
			errors = errors + 1;
		end
		@(negedge clk);
		c_req = 0; c_write = 0;
		@(posedge clk);
	end
endtask

// A faulting access, driven the way the core drives one: c_req is held
// until the bus error is seen (the core samples berr on the same
// qualified edge), then dropped as the core enters exception processing.
// Returns with the cache expected to be idle again.
task cpu_access_berr;
	input [31:0] a;
	input        wr;
	integer guard;
	begin
		@(negedge clk);
		c_req = 1; c_write = wr; c_size = 2'b10; c_addr = a;
		c_wdata = 32'hBADD_0BAD;
		guard = 0;
		while (!(m_err && ce) && guard < 300) begin
			@(posedge clk);
			guard = guard + 1;
		end
		if (guard >= 300) begin
			$display("FAIL: no bus error reported for %h", a);
			errors = errors + 1;
		end
		@(negedge clk);
		c_req = 0; c_write = 0;
		@(posedge clk);
	end
endtask

// After a fault the cache must stop driving the bus: no master request
// may survive more than a couple of cycles once the core has withdrawn.
task expect_bus_idle;
	input integer tno;
	integer guard;
	begin
		guard = 0;
		while (m_req && guard < 40) begin
			@(posedge clk);
			guard = guard + 1;
		end
		if (m_req) begin
			$display("FAIL test %0d: cache still driving m_req after a bus error (livelock)",
			         tno);
			errors = errors + 1;
		end
	end
endtask

task snoop;   // one free-running clk pulse, regardless of ce
	input [31:0] a;
	begin
		@(negedge clk);
		s_stb = 1; s_addr = a;
		@(negedge clk);
		s_stb = 0;
	end
endtask

task expect_read;
	input [31:0] a;
	input [31:0] v;
	input integer tno;
	reg [31:0] d;
	begin
		cpu_read(a, d);
		if (d !== v) begin
			$display("FAIL test %0d: read %h got %h expected %h",
			         tno, a, d, v);
			errors = errors + 1;
		end
	end
endtask


reg inject_err = 0;
integer cov_xline = 0, cov_xline_unacked = 0, cov_xline_bulk = 0, cov_bulk = 0;
integer cov_reset_bulk = 0, cov_mismatch = 0, cov_iline_offer = 0;
integer cov_fast_pair = 0, cov_fast_ihit = 0;
reg [31:0] offer_addr = 0;
reg [127:0] offer_expected = 0;
always @(posedge clk) if (nreset) begin
    if (dut.r_xline && dut.fill_line_match) begin
        cov_xline = cov_xline + 1;
        if (!dut.fill_acked) cov_xline_unacked = cov_xline_unacked + 1;
    end
`ifdef BULK_CANDIDATE
    if (dut.fill_line_bulk) begin
        cov_bulk = cov_bulk + 1;
        if (dut.r_xline) cov_xline_bulk = cov_xline_bulk + 1;
        if (dut.r_xline && dut.fill_acked) $fatal(1, "cross-line bulk arrived after ack");
    end
`endif
    if (dut.cst == dut.C_FILL && m_line_valid && m_line_tag != dut.r_addr[31:4])
        cov_mismatch = cov_mismatch + 1;
    if (c_line_stb && c_line_tag == offer_addr[31:4]) begin
        if (c_line_data !== offer_expected)
            $fatal(1, "instruction line offer mismatch %h expected %h", c_line_data, offer_expected);
        cov_iline_offer = cov_iline_offer + 1;
    end
    if (dut.fast_pair_idle) cov_fast_pair = cov_fast_pair + 1;
    if (dut.fast_ihit) cov_fast_ihit = cov_fast_ihit + 1;
end

function automatic [7:0] mem_byte(input [31:0] a);
    reg [31:0] w;
    begin
        w = a[31:28] == 4'h4 ? rom[a[15:2]] : mem[a[15:2]];
        case (a[1:0])
          2'd0: mem_byte = w[31:24];
          2'd1: mem_byte = w[23:16];
          2'd2: mem_byte = w[15:8];
          default: mem_byte = w[7:0];
        endcase
    end
endfunction

function automatic [31:0] expected_at(input [31:0] a, input [1:0] sz);
    begin
        if (sz == 2'b00) expected_at = {24'd0, mem_byte(a)};
        else if (sz == 2'b01) expected_at = {16'd0, mem_byte(a), mem_byte(a+1)};
        else expected_at = {mem_byte(a), mem_byte(a+1), mem_byte(a+2), mem_byte(a+3)};
    end
endfunction

task automatic wait_idle;
    integer guard;
    begin
        guard = 0;
        while (dut.cst != dut.C_IDLE && guard < 300) begin
            @(negedge clk); guard++;
        end
        if (guard >= 300) $fatal(1, "cache failed to idle");
    end
endtask

task automatic sideband_line(input [31:0] a);
    reg [31:0] b;
    begin
        b = {a[31:4], 4'd0};
        m_line_tag = b[31:4];
        m_line_data = {b[31:28] == 4'h4 ? rom[b[15:2]] : mem[b[15:2]],
                       b[31:28] == 4'h4 ? rom[(b+4)>>2 & 16383] : mem[(b+4)>>2 & 16383],
                       b[31:28] == 4'h4 ? rom[(b+8)>>2 & 16383] : mem[(b+8)>>2 & 16383],
                       b[31:28] == 4'h4 ? rom[(b+12)>>2 & 16383] : mem[(b+12)>>2 & 16383]};
        m_line_valid = 1;
    end
endtask

task automatic checked_read(input [31:0] a, input [1:0] sz,
                            input bit instr, input bit prehint,
                            input bit expect_no_bus);
    integer before_reads, guard;
    reg [31:0] got, expected;
    begin
        wait_idle();
        expected = expected_at(a, sz);
        before_reads = mread_count;
        @(negedge clk);
        c_req = 0; c_instr = instr; c_write = 0; c_nocache = 0;
        c_addr = a; c_size = sz;
        if (prehint) @(negedge clk);
        c_req = 1;
        guard = 0;
        do begin
            @(posedge clk); guard++;
        end while (!c_ack && guard < 300);
        if (!c_ack) $fatal(1, "read timeout %h size=%0d instr=%0d", a, sz, instr);
        got = c_rdata;
        if (got !== expected)
            $fatal(1, "read mismatch %h size=%0d instr=%0d got=%h expected=%h", a, sz, instr, got, expected);
        @(negedge clk); c_req = 0;
        wait_idle();
        if (expect_no_bus && mread_count != before_reads)
            $fatal(1, "unexpected backing-memory read %h reads=%0d", a, mread_count-before_reads);
        $display("READ addr=%08h size=%0d instr=%0d hint=%0d no_bus=%0d data=%08h bus_reads=%0d PASS",
                 a, sz, instr, prehint, expect_no_bus, got, mread_count-before_reads);
    end
endtask

task automatic cross_case(input [31:0] base, input [3:0] offset,
                          input [1:0] sz);
    integer before_reads, word_no, before_cov;
    begin
        m_line_valid = 0;
        checked_read(base+12, 2'b10, 0, 0, 0);
        sideband_line(base+16);
        before_reads = mread_count;
        before_cov = cov_xline_unacked;
        checked_read(base+offset, sz, 0, 1, 1);
        if (cov_xline_unacked <= before_cov)
            $fatal(1, "cross-line sideband fill not reached %h", base+offset);
        m_line_valid = 0;
        for (word_no = 0; word_no < 4; word_no++)
            checked_read(base+16+4*word_no, 2'b10, 0, 1, 1);
        if (mread_count != before_reads)
            $fatal(1, "cross-line sideband used bus %h", base+offset);
        $display("CROSS base=%08h offset=%0d size=%0d set_wrap=%0d PASS",
                 base, offset, sz, base[10:4] == 7'h7f);
    end
endtask

integer i, before_reads, before_cov, word_no;
reg [31:0] reset_addr;
initial begin
    for (i = 0; i < 16384; i++) begin
        mem[i] = 32'h11223344 ^ (32'h0103070B * i);
        rom[i] = 32'hE4C2A680 ^ (32'h030B0507 * i);
    end
    repeat (5) @(posedge clk);
    nreset = 1;
    wait_idle();

    // First line hits, second line is a clean miss satisfied locally
    // before its first bus beat. The final case crosses set 127 to set 0.
    cross_case(32'h00001200, 4'd13, 2'b10);
    cross_case(32'h00001240, 4'd14, 2'b10);
    cross_case(32'h00001280, 4'd15, 2'b10);
    cross_case(32'h000012C0, 4'd15, 2'b01);
    cross_case(32'h000017F0, 4'd13, 2'b10);

    // Byte, word and long accesses at every byte lane, including a
    // within-line pair. First fill immediately from retained data.
    sideband_line(32'h00003000);
    checked_read(32'h00003000, 2'b10, 0, 0, 1);
    m_line_valid = 0;
    for (i = 0; i < 16; i++) begin
        checked_read(32'h00003000+i, 2'b00, 0, 1, 1);
        if (i < 15) checked_read(32'h00003000+i, 2'b01, 0, 1, 1);
        if (i < 13) checked_read(32'h00003000+i, 2'b10, 0, 1, 1);
    end
    $display("OFFSETS byte=16 word=15 long=13 PASS");

    // An I-cache fill must populate both the architectural data banks
    // and its private sequential/pair mirrors. Evict the private line
    // before checking each installed longword again.
    offer_addr = 32'h00003400;
    offer_expected = {mem[32'h3400>>2],mem[32'h3404>>2],mem[32'h3408>>2],mem[32'h340C>>2]};
    sideband_line(offer_addr);
    checked_read(offer_addr, 2'b10, 1, 0, 1);
    m_line_valid = 0;
    checked_read(32'h00003420, 2'b10, 1, 0, 0);
    for (word_no = 0; word_no < 4; word_no++)
        checked_read(offer_addr+4*word_no, 2'b10, 1, 1, 1);
    if (cov_iline_offer == 0) $fatal(1, "no checked instruction line offer");
    $display("INSTRUCTION mirror_offer=%0d fast_ihit=%0d PASS", cov_iline_offer, cov_fast_ihit);

    // A retained-line write can occur at one edge, then reset before
    // C_TAGW. A reset sweep must prevent those untagged words reviving.
    reset_addr = 32'h00003800;
    sideband_line(reset_addr);
    @(negedge clk);
    c_addr = reset_addr; c_size = 2'b10; c_instr = 0; c_req = 1;
    wait (dut.fill_line_match);
    @(posedge clk);
    @(negedge clk);
    if (dut.cst != dut.C_TAGW && dut.cst != dut.C_FILL)
        $fatal(1, "reset did not interrupt fill/tag boundary");
    $display("RESET_PHASE state=%0d fill_cnt=%0d candidate_bulk=%0d",
             dut.cst, dut.fill_cnt, cov_bulk);
`ifdef BULK_CANDIDATE
    if (dut.cst == dut.C_TAGW) cov_reset_bulk++;
`endif
    c_req = 0; m_line_valid = 0; nreset = 0;
    repeat (3) @(posedge clk);
    @(negedge clk); nreset = 1;
    wait_idle();
    before_reads = mread_count;
    checked_read(reset_addr, 2'b10, 0, 0, 0);
    if (mread_count == before_reads) $fatal(1, "reset did not invalidate partial fill");
    $display("RESET interrupted_fill=PASS refetched=PASS");

    // Stale line sideband tags across the RAM/ROM address-space switch
    // must never feed the other region's fill. This is a direct-port
    // identity test; the full ROM service path is outside this bench.
    sideband_line(32'h00004000);
    before_cov = cov_mismatch;
    checked_read(32'h40004020, 2'b10, 0, 0, 0);
    if (cov_mismatch == before_cov) $fatal(1, "RAM sideband/ROM fill mismatch not exercised");
    sideband_line(32'h40004020);
    before_cov = cov_mismatch;
    checked_read(32'h00004040, 2'b10, 0, 0, 0);
    if (cov_mismatch == before_cov) $fatal(1, "ROM sideband/RAM fill mismatch not exercised");
    m_line_valid = 0;
    checked_read(32'h40004020, 2'b10, 0, 1, 1);
    checked_read(32'h00004040, 2'b10, 0, 1, 1);
    $display("RAM_ROM stale_sideband_tag_mismatch=%0d PASS", cov_mismatch);

    if (cov_xline_unacked < 5 || cov_mismatch == 0 || cov_iline_offer == 0 ||
        cov_fast_pair == 0 || cov_fast_ihit == 0)
        $fatal(1, "coverage missing xline=%0d mismatch=%0d iline=%0d pair=%0d ihit=%0d",
               cov_xline_unacked, cov_mismatch, cov_iline_offer, cov_fast_pair, cov_fast_ihit);
`ifdef BULK_CANDIDATE
    if (cov_bulk < 7 || cov_xline_bulk != 5 || cov_reset_bulk == 0)
        $fatal(1, "candidate bulk coverage missing bulk=%0d xline_bulk=%0d reset=%0d",
               cov_bulk, cov_xline_bulk, cov_reset_bulk);
`endif
    $display("COVERAGE xline=%0d xline_before_ack=%0d xline_bulk=%0d bulk=%0d reset_bulk=%0d mismatch=%0d iline=%0d fast_pair=%0d fast_ihit=%0d",
             cov_xline,cov_xline_unacked,cov_xline_bulk,cov_bulk,cov_reset_bulk,cov_mismatch,cov_iline_offer,cov_fast_pair,cov_fast_ihit);
    $display("ALL EDGE CASES PASSED");
    $finish;
end
initial begin
    #10_000_000;
    $fatal(1, "edge-case timeout");
end
endmodule
