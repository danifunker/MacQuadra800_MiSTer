`timescale 1ns/1ps
module tb_decoder_eligibility;
    reg [15:0] opcode;
    wire supported;

    ap040_pipeline_integer #(
        .EXTERNAL_STATE(1),
        .ENABLE_LOADS(1),
        .ENABLE_STORES(1),
        .ENABLE_PEA(1),
        .ENABLE_INDEXLOAD(1),
        .ENABLE_SHIFTS(1),
        .ENABLE_DISP_LEA(1),
        .ENABLE_COMPARE(1),
        .ENABLE_BRANCH(1),
        .ENABLE_FAST_READ_RETIRE(1),
        .EXTERNAL_ALU(1)
    ) dut (
        .in_opcode(opcode),
        .in_extension(16'h0000),
        .in_extension_valid(1'b1),
        .in_supported(supported)
    );

    task check;
        input [15:0] value;
        input expected;
        input [127:0] label;
        begin
            opcode = value;
            #1;
            if (supported !== expected) begin
                $display("FAIL %0s opcode=%04x supported=%b expected=%b", label, value, supported, expected);
                $fatal(1);
            end
            $display("PASS %0s opcode=%04x supported=%b", label, value, supported);
        end
    endtask

    initial begin
        check(16'h3b7c, 1'b0, "unsupported");
        check(16'h3f3c, 1'b0, "unsupported");
        check(16'h4e94, 1'b0, "unsupported");
        check(16'h4eb9, 1'b0, "unsupported");
        check(16'h4a2d, 1'b0, "unsupported");
        check(16'ha193, 1'b0, "unsupported");
        check(16'h225f, 1'b0, "unsupported");
        check(16'h7800, 1'b1, "supported MOVEQ");
        $display("PASS decoder eligibility cases=8");
        $finish;
    end
endmodule
