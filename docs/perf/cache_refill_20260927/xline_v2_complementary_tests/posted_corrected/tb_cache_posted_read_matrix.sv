// Posted store/read overlap against an independent byte oracle.
// 216 warm-cache cases: size, address relation, latency, snoop/CE, admission.
// An early cached read under a pending store must touch disjoint words;
// returned bytes are scored against the independent oracle at its ACK edge.
`timescale 1ns/1ps
module tb_posted_read_matrix;
    reg clk=0; always #5 clk=~clk;
    reg reset_n=0, ce=1, req=0, wr=0, post=1, ack=0, err=0;
    reg [1:0] size=2;
    reg [31:0] addr=0, wdata=0, rdata=0;
    reg [31:0] hint=0;
    always @(posedge clk) hint<=addr;
    wire done, mreq, mwr;
    wire [31:0] data, ma, mw;
    wire [1:0] ms;
    reg snoop=0; reg [31:0] snoop_addr=0;
    integer fast_mode;
    reg error_arm=0;
    reg [7:0] memory[0:65535], expected[0:31];
    reg [7:0] oracle[0:65535];
    integer delay_cycles=0, remaining=0, reads=0, writes=0;
    integer i,j,k,n,b,base,offset,form,warm,mode,lat,cases=0,before_reads;
    reg [31:0] value, wanted;
    ap040_cache dut(
        .clk(clk),.nreset(reset_n),.ce(ce),.ie(1'b1),.de(1'b1),
        .cinv_req(1'b0),.cinv_ic(1'b0),.cinv_dc(1'b0),.cinv_done(),
        .c_req(req),.c_write(wr),.c_instr(1'b0),.c_size(size),
        .c_addr(addr),.c_wdata(wdata),.c_fc(3'd5),.c_nocache(1'b0),
        .c_hint_addr(addr),.c_hint_instr(1'b0),.c_hint_ptag(addr[31:10]),
        .c_ihint_addr(addr),.c_ihint_ptag(addr[31:10]),.c_ihint_match(1'b0),.c_ihold(1'b0),
        .c_hint_match(req && hint==addr),.c_hint_wmatch(fast_mode != 0 && req && wr),
        .c_post_ok_hint(post && fast_mode != 0),.c_post_ok(post),.c_ack(done),.c_rdata(data),
        .m_req(mreq),.m_write(mwr),.m_instr(),.m_size(ms),.m_addr(ma),
        .m_wdata(mw),.m_fc(),.m_ack(ack),.m_rdata(rdata),.m_err(err),
        .m_line_valid(1'b0),.m_line_tag(28'd0),.m_line_data(128'd0),
        .s_stb(snoop),.s_addr(snoop_addr));

    // Completion is a pulse; no second acceptance in its acknowledge cycle.
    always @(posedge clk) begin
        if (ce) begin
            ack<=0; err<=0;
            if (mreq && !ack && !err) begin
                if (remaining < delay_cycles) remaining<=remaining+1;
                else begin
                    remaining<=0;
                    n=ms==0?1:(ms==1?2:4);
                    if (error_arm && mwr) begin
                        // Model a split platform transfer whose first byte
                        // reached RAM before a later beat reported an error.
                        memory[ma]=mw>>(8*(n-1));
                        err<=1;
                    end else begin
                        ack<=1; rdata=0;
                        if(mwr) writes=writes+1; else reads=reads+1;
                        for(b=0;b<n;b=b+1)
                            if(mwr) memory[ma+b]=mw>>(8*(n-b-1));
                            else rdata=(rdata<<8)|memory[ma+b];
                    end
                end
            end else remaining<=0;
        end
    end

    task idle;
        integer guard;
        begin
            guard=0;
            while(dut.cst!=0 || mreq || ack || err) begin
                @(negedge clk); guard=guard+1;
                if(guard>1000) $fatal(1,"cache did not drain state=%0d",dut.cst);
            end
        end
    endtask
    task access(input bit write_op,input [31:0] address,input [1:0] sz,
                input [31:0] payload,output [31:0] result);
        integer guard;
        begin
            @(negedge clk);req=1;wr=write_op;addr=address;size=sz;wdata=payload;
            guard=0;
            while(!(done && ce)) begin
                @(posedge clk);guard=guard+1;
                if(guard>1000) $fatal(1,"request timeout %h state=%0d",address,dut.cst);
            end
            result=data;
            @(negedge clk);req=0;wr=0;
            @(negedge clk);
        end
    endtask
    task setup(input integer address,input integer residency);
        begin
            @(negedge clk);reset_n=0;req=0;wr=0;ce=1;error_arm=0;snoop=0;
            repeat(3) @(negedge clk);
            reset_n=1;
            repeat(600) @(negedge clk);
            base=address;
            for(j=0;j<32;j=j+1) begin
                expected[j]=8'h40+j;memory[base+j]=expected[j];
            end
            if(residency&1) begin access(0,base,2,0,value);idle;end
            if(residency&2) begin access(0,base+16,2,0,value);idle;end
        end
    endtask
    task check_bytes;
        begin
            idle;
            for(k=0;k<32;k=k+4) begin
                wanted={expected[k],expected[k+1],expected[k+2],expected[k+3]};
                access(0,base+k,2,0,value);
                if(value!==wanted) $fatal(1,"cached bytes mismatch at %h got=%h expected=%h",base+k,value,wanted);
                idle;
            end
            for(k=0;k<32;k=k+1)
                if(memory[base+k]!==expected[k]) $fatal(1,"RAM byte mismatch at %h",base+k);
            cases=cases+1;
        end
    endtask

    integer szcase, relation, latency_case, injection, overlap_cases=0;
    integer observed_pending=0, observed_prepared=0, case_pending=0, early_read_acks=0;
    reg [31:0] expected_read_at_ack;
    reg [31:0] captured_store_address; integer captured_store_bytes;
    integer start_writes, q, bytes_written;
    reg [31:0] read_address, read_result, expected_result;
    reg [31:0] dma_address;
    always @(posedge clk) if(reset_n && ce && req && !wr && dut.post_active) begin
        observed_pending=observed_pending+1;
        case_pending=case_pending+1;
        if(done) begin
            // Independent address/word overlap, not the cache fast_hit/pp_clash predicate.
            if((addr>>2)<=((captured_store_address+captured_store_bytes-1)>>2) &&
               ((addr+3)>>2)>=(captured_store_address>>2))
                $fatal(1,"pending-store read acknowledged on overlapping word");
            early_read_acks=early_read_acks+1;
        end
        if(dut.cd_rd_en && !dut.iline_read) observed_prepared=observed_prepared+1;
    end
    task post_and_read;
        integer guard;
        begin
            @(negedge clk);captured_store_address='h5004;captured_store_bytes=szcase==0?1:szcase==1?2:4;
            req=1;wr=1;addr='h5004;size=szcase;wdata='ha1b2c3d4;
            guard=0;
            begin : store_wait
                forever begin
                    @(posedge clk);guard=guard+1;
                    if(done && ce) disable store_wait;
                    if(guard>1000) $fatal(1,"store timeout");
                end
            end
            @(negedge clk);req=1;wr=0;addr=read_address;size=2;wdata=0;
            guard=0;
            begin : read_wait
                forever begin
                    @(posedge clk);guard=guard+1;
                    if(done && ce) begin
                        read_result=data;
                        // DMA writes use negedge, so this pre-NBA ACK snapshot is atomic.
                        expected_read_at_ack={oracle[read_address],oracle[read_address+1],oracle[read_address+2],oracle[read_address+3]};
                        if(read_result!==expected_read_at_ack)$fatal(1,"read bytes mismatch at ACK");
                        disable read_wait;
                    end
                    if(guard>1000) $fatal(1,"read timeout");
                end
            end
            @(negedge clk);req=0;
        end
    endtask
    initial begin
        for(i=0;i<65536;i=i+1) begin
            memory[i]=(i*13+7)&255;oracle[i]=memory[i];
        end
        for(fast_mode=0;fast_mode<2;fast_mode=fast_mode+1)
        for(szcase=0;szcase<3;szcase=szcase+1)
        for(relation=0;relation<4;relation=relation+1)
        for(latency_case=0;latency_case<3;latency_case=latency_case+1)
        for(injection=0;injection<3;injection=injection+1) begin
            @(negedge clk);reset_n=0;req=0;wr=0;ce=1;snoop=0;error_arm=0;post=1;
            repeat(3) @(negedge clk);reset_n=1;
            repeat(600) @(negedge clk);
            delay_cycles=latency_case==0?0:latency_case==1?2:6;
            case(relation)
                0:read_address='h5004;
                1:read_address='h5008;
                2:read_address='h5014;
                3:read_address='h6004;
            endcase
            // Both the written and read lines are resident before overlap.
            access(0,'h5004,2,0,value);idle;
            access(0,read_address,2,0,value);idle;
            expected_result={oracle[read_address],oracle[read_address+1],oracle[read_address+2],oracle[read_address+3]};
            if(value!==expected_result) $fatal(1,"warm oracle mismatch");
            bytes_written=szcase==0?1:szcase==1?2:4;
            for(q=0;q<bytes_written;q=q+1)
                oracle['h5004+q]=32'ha1b2c3d4>>(8*(bytes_written-q-1));
            // Same-word DMA modifies an untouched guard byte. Other cases
            // modify the read's final byte, disjoint from the CPU store.
            dma_address=relation==0?read_address+8:read_address+3;
            start_writes=writes;case_pending=0;
            fork
                post_and_read;
                begin
                    if(injection!=0) begin
                        wait(dut.post_active);
                        @(negedge clk);
                        if(injection==2) ce=0;
                        oracle[dma_address]=oracle[dma_address]^8'h5a;
                        memory[dma_address]=oracle[dma_address];
                        snoop_addr=dma_address;snoop=1;
                        repeat(2) @(negedge clk);
                        snoop=0;ce=1;
                    end
                end
            join
            idle;
            expected_result={oracle[read_address],oracle[read_address+1],oracle[read_address+2],oracle[read_address+3]};
            if(read_result!==expected_read_at_ack)
                $fatal(1,"saved ACK oracle mismatch size=%0d relation=%0d latency=%0d injection=%0d got=%h expected=%h",szcase,relation,delay_cycles,injection,read_result,expected_read_at_ack);
            if(writes-start_writes!=1) $fatal(1,"store did not reach memory exactly once");
            for(q='h5000;q<'h5020;q=q+1)
                if(memory[q]!==oracle[q]) $fatal(1,"RAM store/guard mismatch at %h",q);
            for(q=0;q<16;q=q+4) begin
                access(0,'h5000+q,2,0,value);idle;
                expected_result={oracle['h5000+q],oracle['h5001+q],oracle['h5002+q],oracle['h5003+q]};
                if(value!==expected_result) $fatal(1,"cached store/guard mismatch size=%0d relation=%0d latency=%0d injection=%0d addr=%h got=%h expected=%h",szcase,relation,delay_cycles,injection,32'h5000+q,value,expected_result);
            end
            access(0,read_address,2,0,value);idle;
            expected_result={oracle[read_address],oracle[read_address+1],oracle[read_address+2],oracle[read_address+3]};
            if(value!==expected_result) $fatal(1,"cached read repeat mismatch");
            if(delay_cycles==6 && injection==0 && case_pending==0) $fatal(1,"missing pending read coverage");
            overlap_cases=overlap_cases+1;
        end
        if(overlap_cases!=216) $fatal(1,"matrix incomplete");
        $display("POSTED_MATRIX PASS cases=%0d pending=%0d prepared=%0d early_disjoint_acks=%0d",overlap_cases,observed_pending,observed_prepared,early_read_acks);
        $finish;
    end
    initial begin #10000000; $fatal(1,"global timeout");end
endmodule
