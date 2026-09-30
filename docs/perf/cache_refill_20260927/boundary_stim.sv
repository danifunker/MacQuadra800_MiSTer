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
