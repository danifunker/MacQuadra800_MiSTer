// Test-only retained-line publication after the first completed 32-bit
// cache beat. The target memory model is 16-bit big endian. A write or
// reset removes the offer before the cache can sample it again.
reg tb_offer_pending = 0;
integer tb_offers = 0, tb_matches = 0, tb_bulk = 0;
integer tb_write_kills = 0, tb_irq_bulk_window = 0, tb_cancel_bulk_window = 0;
integer tb_bulk_irq_same_edge = 0, tb_busy_releases = 0;
integer tb_clock = 0, tb_last_bulk = -100000;
reg tb_irq_counted = 0, tb_cancel_counted = 0;
reg tb_wait_busy_release = 0;
reg [31:0] tb_base;
integer tb_index;

always @(posedge clk) begin
    tb_clock <= tb_clock + 1;
    if (!nreset) begin
        tb_offer_pending <= 0;
        tb_irq_counted <= 0;
        tb_cancel_counted <= 0;
    end else begin
        tb_offer_pending <= dut.g_cache.cache.cst == dut.g_cache.cache.C_FILL &&
                            dut.g_cache.cache.r_issued && dut.b_ack &&
                            dut.g_cache.cache.fill_cnt == 0 &&
                            dut.g_cache.cache.r_addr[31:16] == 0 &&
                            dut.g_cache.cache.r_addr[15:8] != 8'hF1;
        if (tb_line_valid_to_cache && dut.g_cache.cache.fill_line_match)
            tb_matches <= tb_matches + 1;
`ifdef BULK_CANDIDATE
        if (dut.g_cache.cache.fill_line_bulk) begin
            if (tb_wait_busy_release)
                $fatal(1,"new bulk fill before prior mm_busy release");
            tb_bulk <= tb_bulk + 1;
            tb_last_bulk <= tb_clock;
            tb_wait_busy_release <= 1;
            if (dut.core.irq_pend && dut.core.pipe_load_active)
                tb_bulk_irq_same_edge <= tb_bulk_irq_same_edge + 1;
            $display("BULK_TRACE cycle=%0d pc=%08h core_state=%0d pipe_owner=%0d pipe_load=%0d irq_pend=%0d fill_acked=%0d",
                     tb_clock, dut.core.pc, dut.core.state, dut.core.pipe_owner,
                     dut.core.pipe_load_active, dut.core.irq_pend, dut.g_cache.cache.fill_acked);
        end
        if (tb_wait_busy_release && !dut.mm_busy) begin
            if (tb_clock-tb_last_bulk != 2)
                $fatal(1,"mm_busy release latency changed after bulk fill");
            tb_busy_releases <= tb_busy_releases + 1;
            tb_wait_busy_release <= 0;
            $display("BUSY_RELEASE cycle=%0d bulk_delta=%0d pc=%08h irq_pend=%0d",
                     tb_clock,tb_clock-tb_last_bulk,dut.core.pc,dut.core.irq_pend);
        end
        if (!tb_irq_counted && dut.core.irq_pend && tb_clock-tb_last_bulk <= 16) begin
            tb_irq_bulk_window <= tb_irq_bulk_window + 1;
            tb_irq_counted <= 1;
        end
        if (!tb_cancel_counted && dut.core.pipe_cancel && tb_clock-tb_last_bulk <= 16) begin
            tb_cancel_bulk_window <= tb_cancel_bulk_window + 1;
            tb_cancel_counted <= 1;
            $display("CANCEL_TRACE cycle=%0d bulk_delta=%0d pc=%08h",
                     tb_clock,tb_clock-tb_last_bulk,dut.core.pc);
        end
        if (!dut.core.irq_pend) tb_irq_counted <= 0;
        if (!dut.core.pipe_cancel) tb_cancel_counted <= 0;
`endif
    end
end

always @(negedge clk) begin
    if (!nreset) tb_line_valid = 0;
    else if (busstate == 2'b11 || (walker_req && walker_we) || dut.g_cache.cache.m_write) begin
        if (tb_line_valid) tb_write_kills = tb_write_kills + 1;
        tb_line_valid = 0;
    end else if (tb_offer_pending && dut.g_cache.cache.cst == dut.g_cache.cache.C_FILL) begin
        tb_base = {dut.g_cache.cache.r_addr[31:4],4'd0};
        tb_index = tb_base[15:1];
        tb_line_tag = tb_base[31:4];
        tb_line_data = {mem[tb_index],mem[tb_index+1],mem[tb_index+2],mem[tb_index+3],
                        mem[tb_index+4],mem[tb_index+5],mem[tb_index+6],mem[tb_index+7]};
        tb_line_valid = 1;
        tb_offers = tb_offers + 1;
    end else if (dut.g_cache.cache.cst != dut.g_cache.cache.C_FILL) tb_line_valid = 0;
end

final begin
    $display("RETAINED_COVERAGE offers=%0d match_edges=%0d bulk_edges=%0d write_kills=%0d bulk_irq_same_edge=%0d irq_near_bulk=%0d cancel_near_bulk=%0d busy_releases=%0d",
             tb_offers,tb_matches,tb_bulk,tb_write_kills,tb_bulk_irq_same_edge,
             tb_irq_bulk_window,tb_cancel_bulk_window,tb_busy_releases);
    if (tb_offers == 0 || tb_matches == 0)
        $fatal(1,"retained-line sideband never reached cache fill");
`ifdef BULK_CANDIDATE
    if (tb_bulk == 0 || tb_bulk_irq_same_edge != 3 ||
        tb_irq_bulk_window != 3 || tb_cancel_bulk_window != 3 ||
        tb_busy_releases != tb_bulk)
        $fatal(1,"candidate bulk/IRQ/busy coverage missing");
`endif
end
