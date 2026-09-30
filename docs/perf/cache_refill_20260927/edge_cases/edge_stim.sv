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
