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

module tb_bulk_boundary;

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
	.c_fc(3'd5), .c_nocache(c_nocache), .c_post_ok(1'b0),
	.c_ack(c_ack), .c_rdata(c_rdata),
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
reg [31:0] mem [0:16383];   // 64KB
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
				else m_rdata <= mem[m_addr[15:2]];
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
integer cov_snoop_bulk = 0, cov_snoop_tag = 0, cov_error_bulk = 0;
integer cov_delayed_issued = 0, cov_ce_frozen = 0, cov_bulk = 0;
always @(posedge clk) begin
    if (nreset) begin
        if (dut.fill_line_match && s_stb) cov_snoop_bulk = cov_snoop_bulk + 1;
        if (dut.cst == dut.C_TAGW && s_stb) cov_snoop_tag = cov_snoop_tag + 1;
        if (dut.fill_line_match && inject_err) cov_error_bulk = cov_error_bulk + 1;
        if (dut.r_issued && m_line_valid && m_req) cov_delayed_issued = cov_delayed_issued + 1;
        if (!ce && dut.fill_line_match) cov_ce_frozen = cov_ce_frozen + 1;
`ifdef BULK_CANDIDATE
        if (dut.fill_line_bulk) cov_bulk = cov_bulk + 1;
`endif
    end
end

task automatic wait_idle;
    integer guard;
    begin
        guard = 0;
        while (dut.cst != dut.C_IDLE && guard < 200) begin
            @(negedge clk);
            guard++;
        end
        if (guard >= 200) $fatal(1, "cache failed to idle");
    end
endtask

task automatic setup_set(input integer scenario, output reg [31:0] victim,
                         output reg [31:0] target);
    integer way, word_no;
    reg [31:0] a, got;
    begin
        victim = 32'h00001000 + scenario*32'h100;
        target = victim + 32'h2000;
        for (way = 0; way < 5; way++) begin
            a = victim + way*32'h800;
            for (word_no = 0; word_no < 4; word_no++)
                mem[(a+4*word_no)>>2] = 32'h10000000 + ((a+4*word_no)>>2);
            if (way < 4) begin
                cpu_read(a, got);
                if (got !== mem[a>>2]) $fatal(1, "prefill mismatch scenario %0d way %0d", scenario, way);
                wait_idle();
            end
        end
    end
endtask

task automatic begin_target(input [31:0] target);
    integer guard;
    begin
        m_line_valid = 0;
        inject_err = 0;
        s_stb = 0;
        @(negedge clk);
        c_req = 1; c_write = 0; c_instr = 0; c_nocache = 0;
        c_size = 2'b10; c_addr = target;
        guard = 0;
        while (!(m_ack && m_req) && guard < 200) begin
            @(posedge clk);
            guard++;
        end
        if (guard >= 200) $fatal(1, "target first beat timeout %h", target);
        @(negedge clk);
        if (dut.r_way != 0) $fatal(1, "expected valid victim way0, got %0d", dut.r_way);
        c_req = 0;
        m_line_tag = target[31:4];
        m_line_data = {mem[target>>2], mem[(target+4)>>2],
                       mem[(target+8)>>2], mem[(target+12)>>2]};
    end
endtask

task automatic validate_after_invalidate(input integer scenario,
                                         input [31:0] victim, input [31:0] target,
                                         input [31:0] expected);
    integer reads_before;
    reg [31:0] got;
    begin
        wait_idle();
        @(negedge clk);
        m_line_valid = 0;
        s_stb = 0;
        inject_err = 0;
        ce_run = 1;
        repeat (3) @(posedge clk);
        reads_before = mread_count;
        cpu_read(target, got);
        if (got !== expected || mread_count == reads_before)
            $fatal(1, "scenario %0d stale target=%h data=%h reads=%0d",
                   scenario, target, got, mread_count-reads_before);
        wait_idle();
        reads_before = mread_count;
        cpu_read(victim, got);
        if (got !== mem[victim>>2] || mread_count == reads_before)
            $fatal(1, "scenario %0d stale victim=%h data=%h reads=%0d",
                   scenario, victim, got, mread_count-reads_before);
        wait_idle();
        $display("BOUNDARY scenario=%0d target=%08h victim=%08h refetched=PASS", scenario, target, victim);
    end
endtask

integer i;
reg [31:0] victim, target, new_value;
integer reads_before;
initial begin
    for (i = 0; i < 16384; i++) mem[i] = 32'h10000000 + i;
    repeat (5) @(posedge clk);
    nreset = 1;
    wait_idle();
    // 0: snoop exactly when the sideband supplies the first local tail word
    setup_set(0, victim, target);
    begin_target(target);
    m_line_valid = 1;
    new_value = 32'hD0000000;
    mem[target>>2] = new_value;
    s_stb = 1; s_addr = target;
    #1;
    if (!dut.fill_line_match) $fatal(1, "scenario 0 did not reach local fill state=%0d count=%0d issued=%0d mreq=%0d mack=%0d line_tag=%h raddr=%h",
                                     dut.cst,dut.fill_cnt,dut.r_issued,m_req,m_ack,m_line_tag,dut.r_addr);
    @(negedge clk);
    s_stb = 0;
    validate_after_invalidate(0, victim, target, new_value);

    // 1: snoop on tag commit after the local fill writes.
    setup_set(1, victim, target);
    begin_target(target);
    m_line_valid = 1;
    wait (dut.cst == dut.C_TAGW);
    @(negedge clk);
    if (dut.cst != dut.C_TAGW) $fatal(1, "scenario 1 missed tag edge");
    new_value = 32'hD0000001;
    mem[target>>2] = new_value;
    s_stb = 1; s_addr = target;
    @(negedge clk);
    s_stb = 0;
    validate_after_invalidate(1, victim, target, new_value);

    // 2: error on a valid local sideband beat must suppress the bulk write.
    setup_set(2, victim, target);
    begin_target(target);
    m_line_valid = 1;
    inject_err = 1;
    new_value = 32'hD0000002;
    mem[target>>2] = new_value;
    #1;
    if (!dut.fill_line_match) $fatal(1, "scenario 2 did not reach local fill");
`ifdef BULK_CANDIDATE
    if (dut.fill_line_bulk) $fatal(1, "bulk not gated by error");
`endif
    @(negedge clk);
    inject_err = 0;
    validate_after_invalidate(2, victim, target, new_value);

    // 3: a retained line offered after the second beat was issued cannot
    // cancel that outstanding memory transaction.
    setup_set(3, victim, target);
    reads_before = mread_count;
    begin_target(target);
    wait (dut.r_issued && dut.fill_cnt == 1 && m_req);
    @(negedge clk);
    m_line_valid = 1;
    if (dut.fill_line_match) $fatal(1, "issued beat incorrectly abandoned");
    wait_idle();
    @(negedge clk);
    m_line_valid = 0;
    if (mread_count - reads_before != 2)
        $fatal(1, "delayed sideband expected 2 bus beats, got %0d", mread_count-reads_before);
    begin
        reg [31:0] got;
        reads_before = mread_count;
        cpu_read(target, got);
        if (got !== mem[target>>2] || mread_count != reads_before)
            $fatal(1, "delayed sideband target did not hit");
        wait_idle();
        $display("BOUNDARY scenario=3 delayed_sideband=PASS reads=2");
    end

    // 4: free-running snoop while CE is frozen across local fill.
    setup_set(4, victim, target);
    begin_target(target);
    m_line_valid = 1;
    ce_run = 0;
    new_value = 32'hD0000004;
    mem[target>>2] = new_value;
    s_stb = 1; s_addr = target;
    repeat (2) @(negedge clk);
    if (dut.cst != dut.C_FILL) $fatal(1, "CE freeze moved fill state");
    s_stb = 0;
    ce_run = 1;
    validate_after_invalidate(4, victim, target, new_value);

    if (cov_snoop_bulk == 0 || cov_snoop_tag == 0 ||
        cov_error_bulk == 0 || cov_delayed_issued == 0 || cov_ce_frozen == 0)
        $fatal(1, "coverage missing snoop_bulk=%0d snoop_tag=%0d error=%0d issued=%0d frozen=%0d",
               cov_snoop_bulk,cov_snoop_tag,cov_error_bulk,cov_delayed_issued,cov_ce_frozen);
`ifdef BULK_CANDIDATE
    if (cov_bulk == 0) $fatal(1, "candidate bulk path not exercised");
`endif
    $display("COVERAGE snoop_bulk=%0d snoop_tag=%0d error_bulk=%0d delayed_issued=%0d ce_frozen=%0d candidate_bulk=%0d",
             cov_snoop_bulk,cov_snoop_tag,cov_error_bulk,cov_delayed_issued,cov_ce_frozen,cov_bulk);
    $display("ALL BOUNDARY TESTS PASSED");
    $finish;
end
initial begin
    #4_000_000;
    $fatal(1, "boundary timeout");
end
endmodule
