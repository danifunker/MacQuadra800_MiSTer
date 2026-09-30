// Fixture-specific observer; no RTL changes and no guest timer dependence.
// Entry MOVEQ and exit NOP always visit S_DECODE in BOTH baseline/candidate.
// Sample #1 after each posedge, after NBA updates. Count pre-edge state over
// edges (entry_edge, exit_edge], so sum(histogram) == exit_edge-entry_edge.
// Includes kernel execution and final fallthrough dispatch; excludes initial
// entry fetch, setup, exit NOP execution, checking, and the calling wrapper.
module exact_sieve_monitor;
`define STB tb_ap040_program
`define SCO tb_ap040_program.dut.core
localparam integer ARRAY = 'h4000;
localparam integer LAST_INDEX = 'h1ffe;
localparam integer GUARD_START = 'h3fe0;
localparam integer GUARD_END = 'h6020;
localparam integer ENTRY_PC = 'h2000;
localparam integer EXIT_PC = 'h2050;

reg expected [0:LAST_INDEX];
integer expected_count = 0;
integer k, divisor, number;
reg prime;
integer edges = 0;
integer entry_edge = 0;
integer pass = 0;
integer state_cycles [0:255];
integer state_stalls [0:255];
integer i, address, got, wanted, total;
integer state_before;
reg ce_before;
reg active = 0;
reg completed_checked = 0;

// Independent oracle: trial division of every odd integer 2*i+3. This does
// not reproduce the guest's sieve marking, index stepping, or pass loops.
initial begin
    for (k = 0; k <= LAST_INDEX; k = k + 1) begin
        number = 2*k + 3;
        prime = 1;
        for (divisor = 3; divisor*divisor <= number; divisor = divisor + 2)
            if (number % divisor == 0) prime = 0;
        expected[k] = prime;
        if (prime) expected_count = expected_count + 1;
    end
    $display("SIEVE_ORACLE algorithm=odd_trial_division elements=%0d primes=%0d",
             LAST_INDEX+1, expected_count);
end

function integer memory_byte(input integer a);
    if (a & 1) memory_byte = `STB.mem[a >> 1][7:0];
    else       memory_byte = `STB.mem[a >> 1][15:8];
endfunction

task verify_result;
    begin
        if (`SCO.regfile.dreg[6] !== 32'd100 ||
            `SCO.regfile.dreg[7] !== expected_count ||
            `SCO.regfile.areg[2] !== ARRAY)
            $fatal(1, "SIEVE_FAIL phase=%0d pass=%0d D6=%h D7=%h A2=%h expected_count=%0d",
                   `STB.phase, pass, `SCO.regfile.dreg[6],
                   `SCO.regfile.dreg[7], `SCO.regfile.areg[2], expected_count);
        // ap040_cache is write-through. All kernel stores have completed
        // before the final loop-control instructions reach this boundary.
        for (address = GUARD_START; address < GUARD_END; address = address + 1) begin
            got = memory_byte(address);
            if (address >= ARRAY && address <= ARRAY + LAST_INDEX)
                wanted = expected[address-ARRAY] ? 1 : 0;
            else
                wanted = (address & 1) ? 'h5a : 'ha5;
            if (got !== wanted)
                $fatal(1, "SIEVE_FAIL phase=%0d pass=%0d address=%04x got=%02x expected=%02x",
                       `STB.phase, pass, address, got, wanted);
        end
    end
endtask

always @(posedge `STB.clk) begin
    state_before = `SCO.state;
    ce_before = `SCO.ce;
    #1;
    if (!`STB.nreset) begin
        edges = 0;
        pass = 0;
        active = 0;
        completed_checked = 0;
    end else begin
        edges = edges + 1;
        if (active) begin
            state_cycles[state_before] = state_cycles[state_before] + 1;
            if (!ce_before)
                state_stalls[state_before] = state_stalls[state_before] + 1;
        end
        if (!active && `SCO.state == 8'd4 && `SCO.pc_i == ENTRY_PC) begin
            if (`SCO.ir !== 16'h7c00 || pass >= 2)
                $fatal(1, "SIEVE_FAIL unexpected entry opcode/count");
            for (i = 0; i < 256; i = i + 1) begin
                state_cycles[i] = 0;
                state_stalls[i] = 0;
            end
            active = 1;
            entry_edge = edges;
        end else if (active && `SCO.state == 8'd4 && `SCO.pc_i == EXIT_PC) begin
            if (`SCO.ir !== 16'h4e71)
                $fatal(1, "SIEVE_FAIL exit opcode is not NOP");
            verify_result();
            total = 0;
            for (i = 0; i < 256; i = i + 1) total = total + state_cycles[i];
            if (total != edges-entry_edge)
                $fatal(1, "SIEVE_FAIL histogram/bracket mismatch");
            $display("EXACT_SIEVE phase=%0d pass=%0d condition=%0s cycles=%0d D6=%0d D7=%0d array=PASS guards=PASS",
                     `STB.phase, pass, pass == 0 ? "cold_at_call" : "repeat_no_flush",
                     edges-entry_edge, `SCO.regfile.dreg[6], `SCO.regfile.dreg[7]);
            if ($test$plusargs("sieveprof"))
                for (i = 0; i < 256; i = i + 1)
                    if (state_cycles[i] != 0)
                        $display("SIEVE_STATE phase=%0d pass=%0d state=%0d cycles=%0d ce_stalls=%0d",
                                 `STB.phase, pass, i, state_cycles[i], state_stalls[i]);
            active = 0;
            pass = pass + 1;
        end
        if (`STB.result == 1 && !completed_checked) begin
            if (active || pass != 2)
                $fatal(1, "SIEVE_FAIL guest completion without two checked kernels");
            completed_checked = 1;
        end
    end
end
`undef STB
`undef SCO
endmodule
