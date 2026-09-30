`timescale 1ps/1ps
`include "ap040_defs.svh"

module tb_refill_path;
    wire clk_sys, clk_ram;
    reg nreset = 0, init = 1;
    reg prep_mode = 1;
    reg prep_req = 0, prep_write = 0;
    reg [31:0] prep_addr = 0, prep_wdata = 0;
    wire plat_ack;
    wire [31:0] plat_rdata;
    wire sdr_busy, line_valid, line_pending;
    wire [26:4] line_tag;
    wire [127:0] line_data;

    reg c_req = 0;
    reg c_instr = 0;
    reg [31:0] c_addr = 0;
    reg [1:0] c_size = `AP040_SZ_L;
    reg sideband_en = 0;
    wire c_ack, c_busy, m_req, m_write, m_instr, m_posted;
    wire [31:0] c_rdata, m_addr, m_wdata;
    wire [1:0] m_size;
    wire [2:0] m_fc;
    wire [31:4] c_line_tag;
    wire [127:0] c_line_data;
    wire c_line_stb, cinv_done, c_fast_ready, c_ack_q;
    wire plat_req = prep_mode ? prep_req : m_req;
    wire plat_write = prep_mode ? prep_write : m_write;
    wire [1:0] plat_size = prep_mode ? `AP040_SZ_L : m_size;
    wire [31:0] plat_addr = prep_mode ? prep_addr : m_addr;
    wire [31:0] plat_wdata = prep_mode ? prep_wdata : m_wdata;

    refill_platform #(
        .FAST_BYPASS(1), .DIRECT_FIRST_MISS(1),
        .REGISTERED_FIRST_MISS(1), .ADAPTER_LINE_HIT(1),
        .DIRECT_MEM_ACK(0), .REGISTERED_LINE_HIT(1)
    ) plat (
        .clk_sys(clk_sys), .clk_ram(clk_ram), .nreset(nreset), .init(init),
        .t_req(plat_req), .t_write(plat_write), .t_size(plat_size),
        .t_addr(plat_addr), .t_wdata(plat_wdata),
        .t_ack(plat_ack), .t_rdata(plat_rdata),
        .sdr_busy(sdr_busy), .line_valid(line_valid), .line_tag(line_tag),
        .line_data(line_data), .line_pending(line_pending)
    );

    ap040_cache cache (
        .clk(clk_sys), .nreset(nreset), .ce(1'b1),
        .ie(1'b1), .de(1'b1),
        .cinv_req(1'b0), .cinv_ic(1'b0), .cinv_dc(1'b0), .cinv_done(cinv_done),
        .c_req(c_req), .c_write(1'b0), .c_instr(c_instr), .c_size(c_size),
        .c_addr(c_addr), .c_hint_addr(c_addr), .c_hint_instr(c_instr),
        .c_hint_ptag(c_addr[31:10]), .c_hint_match(1'b0), .c_hint_wmatch(1'b0),
        .c_hint_away(1'b0), .c_fast_ready(c_fast_ready), .c_ack_q(c_ack_q),
        .c_ihint_addr(c_addr), .c_ihint_ptag(c_addr[31:10]),
        .c_ihint_match(1'b0), .c_ihold(c_instr),
        .c_wdata(32'd0), .c_fc(c_instr ? 3'd6 : 3'd5), .c_nocache(1'b0),
        .c_post_ok(1'b0), .c_post_ok_hint(1'b0),
        .c_ack(c_ack), .c_posting(), .c_rdata(c_rdata),
        .c_line_stb(c_line_stb), .c_line_tag(c_line_tag),
        .c_line_data(c_line_data), .c_busy(c_busy), .m_posted(m_posted),
        .m_req(m_req), .m_write(m_write), .m_instr(m_instr),
        .m_size(m_size), .m_addr(m_addr), .m_wdata(m_wdata), .m_fc(m_fc),
        .m_ack(prep_mode ? 1'b0 : plat_ack),
        .m_rdata(plat_rdata),
        .m_line_valid(sideband_en && line_valid),
        .m_line_tag({5'd0, line_tag}), .m_line_data(line_data),
        .m_err(1'b0), .s_stb(1'b0), .s_addr(32'd0)
    );

    integer cycle = 0;
    integer start_cycle = 0;
    integer case_id = -1;
    reg active = 0;
    reg line_seen = 0;
    always @(posedge clk_sys) begin
        cycle <= cycle + 1;
        if (active) begin
            if (cache.cst == cache.C_FILL && cache.fill_cnt == 0 && !cache.r_issued)
                $display("EVENT case=%0d cycle=%0d kind=fill_enter rel=%0d beat=%0d way=%0d",
                         case_id, cycle, cycle-start_cycle, cache.r_beat, cache.r_way);
            if (plat.sdr_ack)
                $display("EVENT case=%0d cycle=%0d kind=sdr_ack rel=%0d data=%08h",
                         case_id, cycle, cycle-start_cycle, plat.sdr_rdata);
            if (plat.t_fast_ack_r)
                $display("EVENT case=%0d cycle=%0d kind=bus_ack rel=%0d data=%08h",
                         case_id, cycle, cycle-start_cycle, plat_rdata);
            if (line_valid && line_tag == c_addr[26:4] && !line_seen) begin
                $display("EVENT case=%0d cycle=%0d kind=line_valid rel=%0d",
                         case_id, cycle, cycle-start_cycle);
                line_seen <= 1;
            end
            if (cache.fill_line_match || (cache.cst == cache.C_FILL && cache.r_issued && plat_ack))
                $display("EVENT case=%0d cycle=%0d kind=fill_step rel=%0d count=%0d word=%0d source=%s",
                         case_id, cycle, cycle-start_cycle, cache.fill_cnt,
                         cache.r_beat, cache.fill_line_match ? "sideband" : "bus");
            if (c_ack)
                $display("EVENT case=%0d cycle=%0d kind=critical_ack rel=%0d data=%08h",
                         case_id, cycle, cycle-start_cycle, c_rdata);
            if (cache.tag_we && cache.cst == cache.C_TAGW)
                $display("EVENT case=%0d cycle=%0d kind=tag_commit rel=%0d",
                         case_id, cycle, cycle-start_cycle);
        end
    end

    task automatic write32(input [31:0] a, input [31:0] d);
        integer timeout;
        begin
            @(negedge clk_sys);
            prep_addr = a;
            prep_wdata = d;
            prep_write = 1;
            prep_req = 1;
            timeout = 0;
            while (!plat_ack && timeout < 10000) begin
                @(negedge clk_sys);
                timeout++;
            end
            if (!plat_ack) $fatal(1, "preload write timeout at %h", a);
            prep_req = 0;
            prep_write = 0;
        end
    endtask

    task automatic check_line_hits(input [31:0] base, input integer first_index);
        integer word_no, timeout;
        reg [31:0] alternate_line;
        begin
            if (c_instr) begin
                // Replace the cache's private one-line instruction offer
                // before verifying that all four words reached its RAM banks.
                alternate_line = 32'h46A0;
                while (c_ack) @(negedge clk_sys);
                @(negedge clk_sys);
                c_addr = alternate_line;
                c_size = `AP040_SZ_L;
                c_req = 1;
                timeout = 0;
                do begin
                    @(negedge clk_sys);
                    timeout++;
                    if (m_req) $fatal(1, "instruction eviction issued bus request");
                end while (!c_ack && timeout < 10);
                if (!c_ack) $fatal(1, "instruction eviction timed out");
                c_req = 0;
                $display("ILINE_EVICT base=%08h alternate=%08h PASS", base, alternate_line);
            end
            for (word_no = 0; word_no < 4; word_no++) begin
                while (c_ack) @(negedge clk_sys);
                @(negedge clk_sys);
                c_addr = base + 4*word_no;
                c_size = `AP040_SZ_L;
                c_req = 1;
                timeout = 0;
                do begin
                    @(negedge clk_sys);
                    timeout++;
                    if (m_req) $fatal(1, "hit issued bus request addr=%h", c_addr);
                end while (!c_ack && timeout < 10);
                if (!c_ack || c_rdata !== (32'hA5000000 + first_index + word_no))
                    $fatal(1, "line hit mismatch addr=%h data=%h cycles=%0d",
                           c_addr, c_rdata, timeout);
                c_req = 0;
            end
            $display("HITS base=%08h instr=%0d all_four_words=PASS no_bus=PASS", base, c_instr);
        end
    endtask

    task automatic warm_alternate_iline;
        integer timeout;
        begin
            while (cache.cst != cache.C_IDLE || c_ack) @(negedge clk_sys);
            @(negedge clk_sys);
            c_instr = 1;
            c_size = `AP040_SZ_L;
            c_addr = 32'h46A0;
            sideband_en = 1;
            c_req = 1;
            timeout = 0;
            do begin
                @(negedge clk_sys);
                timeout++;
            end while (!c_ack && timeout < 10000);
            if (!c_ack || c_rdata !== 32'hA50001A8)
                $fatal(1, "alternate instruction line warm failed");
            c_req = 0;
            while (cache.cst != cache.C_IDLE || c_busy) @(negedge clk_sys);
            @(negedge clk_sys);
            $display("ILINE_WARM alternate=000046a0 PASS");
        end
    endtask

    task automatic measure(input integer id, input [31:0] a,
                           input [1:0] sz, input bit sb, input bit instr,
                           input [31:0] expected);
        integer timeout;
        begin
            while (cache.cst != cache.C_IDLE || c_ack) @(negedge clk_sys);
            @(negedge clk_sys);
            c_addr = a;
            c_size = sz;
            c_instr = instr;
            sideband_en = sb;
            c_req = 1;
            case_id = id;
            start_cycle = cycle;
            line_seen = 0;
            active = 1;
            $display("CASE id=%0d sideband=%0d instr=%0d addr=%08h size=%0d start=%0d",
                     id, sb, instr, a, sz, start_cycle);
            timeout = 0;
            do begin
                @(negedge clk_sys);
                timeout++;
            end while (!c_ack && timeout < 10000);
            if (!c_ack) $fatal(1, "cache ack timeout case %0d", id);
            if (c_rdata !== expected)
                $fatal(1, "data mismatch case %0d got=%08h expected=%08h",
                       id, c_rdata, expected);
            c_req = 0;
            timeout = 0;
            while ((cache.cst != cache.C_IDLE || c_busy) && timeout < 10000) begin
                @(negedge clk_sys);
                timeout++;
            end
            if (timeout >= 10000) $fatal(1, "tag timeout case %0d", id);
            @(negedge clk_sys);
            active = 0;
            check_line_hits({a[31:4], 4'd0}, ({a[31:4], 4'd0} - 32'h4000) / 4);
        end
    endtask

    integer i;
    reg [31:0] a;
    initial begin
        repeat (4) @(posedge clk_sys);
        nreset = 1;
        init = 0;
        repeat (13000) @(posedge clk_ram);
        for (i = 0; i < 80; i++)
            write32(32'h00004000 + 4*i, 32'hA5000000 + i);
        for (i = 0; i < 5; i++) begin
            for (integer j = 0; j < 4; j++) begin
                a = 32'h4200 + 32'h800*i + 4*j;
                write32(a, 32'hA5000000 + (a - 32'h4000)/4);
                a = 32'h4300 + 32'h800*i + 4*j;
                write32(a, 32'hA5000000 + (a - 32'h4000)/4);
                a = 32'h4400 + 32'h800*i + 4*j;
                write32(a, 32'hA5000000 + (a - 32'h4000)/4);
                a = 32'h4500 + 32'h800*i + 4*j;
                write32(a, 32'hA5000000 + (a - 32'h4000)/4);
            end
        end
        for (i = 0; i < 4; i++) begin
            a = 32'h46A0 + 4*i;
            write32(a, 32'hA5000000 + (a - 32'h4000)/4);
        end
        @(negedge clk_sys);
        while (sdr_busy || plat.svc_mem) @(negedge clk_sys);
        prep_mode = 0;
        while (cache.cst != cache.C_IDLE) @(negedge clk_sys);
        measure(0, 32'h00004000, `AP040_SZ_L, 0, 0, 32'hA5000000);
        measure(1, 32'h00004014, `AP040_SZ_L, 0, 0, 32'hA5000005);
        measure(2, 32'h00004028, `AP040_SZ_L, 0, 0, 32'hA500000A);
        measure(3, 32'h0000403C, `AP040_SZ_L, 0, 0, 32'hA500000F);
        measure(4, 32'h00004045, `AP040_SZ_L, 0, 0, 32'h000011A5);
        measure(5, 32'h00004050, `AP040_SZ_L, 1, 0, 32'hA5000014);
        measure(6, 32'h00004064, `AP040_SZ_L, 1, 0, 32'hA5000019);
        measure(7, 32'h00004078, `AP040_SZ_L, 1, 0, 32'hA500001E);
        measure(8, 32'h0000408C, `AP040_SZ_L, 1, 0, 32'hA5000023);
        measure(9, 32'h00004095, `AP040_SZ_L, 1, 0, 32'h000025A5);
        warm_alternate_iline();
        measure(10, 32'h000040A0, `AP040_SZ_L, 0, 1, 32'hA5000028);
        measure(11, 32'h000040B4, `AP040_SZ_L, 0, 1, 32'hA500002D);
        measure(12, 32'h000040C8, `AP040_SZ_L, 0, 1, 32'hA5000032);
        measure(13, 32'h000040DC, `AP040_SZ_L, 0, 1, 32'hA5000037);
        measure(14, 32'h000040E0, `AP040_SZ_L, 1, 1, 32'hA5000038);
        measure(15, 32'h000040F4, `AP040_SZ_L, 1, 1, 32'hA500003D);
        measure(16, 32'h00004108, `AP040_SZ_L, 1, 1, 32'hA5000042);
        measure(17, 32'h0000411C, `AP040_SZ_L, 1, 1, 32'hA5000047);
        // Five lines at one set: invalid ways 0..3, then one replacement.
        // The second set repeats this with the retained-line sideband.
        for (i = 0; i < 5; i++) begin
            a = 32'h4200 + 32'h800*i + 4*(i % 4);
            measure(18+i, a, `AP040_SZ_L, 0, 0,
                    32'hA5000000 + (a - 32'h4000)/4);
        end
        for (i = 0; i < 5; i++) begin
            a = 32'h4300 + 32'h800*i + 4*(i % 4);
            measure(23+i, a, `AP040_SZ_L, 1, 0,
                    32'hA5000000 + (a - 32'h4000)/4);
        end
        for (i = 0; i < 5; i++) begin
            a = 32'h4400 + 32'h800*i + 4*(i % 4);
            measure(28+i, a, `AP040_SZ_L, 0, 1,
                    32'hA5000000 + (a - 32'h4000)/4);
        end
        for (i = 0; i < 5; i++) begin
            a = 32'h4500 + 32'h800*i + 4*(i % 4);
            measure(33+i, a, `AP040_SZ_L, 1, 1,
                    32'hA5000000 + (a - 32'h4000)/4);
        end
        $display("PASS integrated cache/refill cases; chip_errors=%0d", plat.chip.errors);
        if (plat.chip.errors != 0) $fatal(1, "SDRAM protocol errors");
        $finish;
    end
    initial begin
        #2_000_000_000;
        $fatal(1, "integrated refill timeout");
    end
endmodule
