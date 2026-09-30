`timescale 1ps/1ps

module tb_memory_path #(
	parameter integer FAST_BYPASS = 1,
	parameter integer DIRECT_FIRST_MISS = FAST_BYPASS,
	parameter integer REGISTERED_FIRST_MISS = 0,
	parameter integer ADAPTER_LINE_HIT = FAST_BYPASS,
	parameter integer DIRECT_MEM_ACK = 1,
	parameter integer REGISTERED_LINE_HIT = 0
);

// This bench measures the post-cache transaction port, not instruction-level
// CPU throughput.  Its held request, four aligned longword addresses and
// one-cycle ack pulses reproduce ap040_cache's C_FILL contract; cache tag
// lookup/hit cycles are deliberately outside the reported MB/s figure.

localparam integer TR = 5050;
localparam integer TS = 3*TR;

reg clk_ram = 0;
reg clk_sys = 0;
always #TR clk_ram = ~clk_ram;
always #TS clk_sys = ~clk_sys;

reg nreset = 0;
reg init = 1;
reg t_req = 0;
reg t_write = 0;
reg [1:0] t_size = 2'd2;
reg [31:0] t_addr = 0;
reg [31:0] t_wdata = 0;
wire t_ack;
wire [31:0] t_rdata;
wire adapter_ack;
wire [31:0] adapter_rdata;
wire adapter_active;

wire b_req, b_write;
wire [31:2] b_addr;
wire [3:0] b_be;
wire [31:0] b_wdata;
wire b_ack;
wire [31:0] b_rdata;
reg b_ack_r = 0;
reg [31:0] b_rdata_r = 0;
reg t_fast_ack_r = 0;
reg [31:0] t_fast_rdata_r = 0;

reg svc_mem = 0;
reg svc_fast = 0;
reg mem_req = 0;
reg mem_write_r = 0;
reg [26:2] mem_addr_r = 0;
reg [3:0] mem_be_r = 0;
reg [31:0] mem_wdata_r = 0;
wire sdr_ack;
wire [31:0] sdr_rdata;
wire sdr_busy;
wire line_valid;
wire [26:4] line_tag;
wire [127:0] line_data;
wire line_pending;
wire [26:4] line_pending_tag;
wire line_match = ADAPTER_LINE_HIT && !svc_mem && b_req && !b_write &&
	              line_valid && b_addr[26:4] == line_tag;
wire line_ack = line_match && !REGISTERED_LINE_HIT;
wire line_wait = ADAPTER_LINE_HIT && !svc_mem && b_req && !b_write && line_pending &&
	             b_addr[26:4] == line_pending_tag;
wire [31:0] line_word = (b_addr[3:2] == 2'd0) ? line_data[127:96] :
	                         (b_addr[3:2] == 2'd1) ? line_data[95:64]  :
	                         (b_addr[3:2] == 2'd2) ? line_data[63:32]  :
	                                                         line_data[31:0];
wire t_line_match = FAST_BYPASS && !svc_mem && !t_fast_ack_r &&
	                !adapter_active && !adapter_ack && t_req && !t_write &&
	                t_size == 2'd2 && t_addr[1:0] == 0 && line_valid &&
	                t_addr[26:4] == line_tag;
reg t_line_ready = 0;
reg [31:2] t_line_seen = 0;
wire t_line_ack = t_line_match && t_line_ready && t_addr[31:2] == t_line_seen;
wire t_line_wait = FAST_BYPASS && !svc_mem && !t_fast_ack_r &&
	               !adapter_active && !adapter_ack && t_req && !t_write &&
	               t_size == 2'd2 && t_addr[1:0] == 0 && line_pending &&
	               t_addr[26:4] == line_pending_tag;
wire [31:0] t_line_word = (t_addr[3:2] == 2'd0) ? line_data[127:96] :
	                           (t_addr[3:2] == 2'd1) ? line_data[95:64]  :
	                           (t_addr[3:2] == 2'd2) ? line_data[63:32]  :
	                                                           line_data[31:0];
wire t_fast_eligible = DIRECT_FIRST_MISS && t_req && !t_write && t_size == 2'd2 &&
	                   t_addr[1:0] == 0;
wire t_fast_req = t_fast_eligible && !t_fast_ack_r &&
	              !t_line_match && !t_line_wait;
wire mem_fast_ack = REGISTERED_FIRST_MISS ? t_fast_ack_r :
	                (svc_mem && svc_fast && sdr_ack);
wire [31:0] mem_fast_rdata = REGISTERED_FIRST_MISS ? t_fast_rdata_r : sdr_rdata;

assign t_ack = t_line_ack || mem_fast_ack || adapter_ack;
assign t_rdata = t_line_ack ? t_line_word :
	             mem_fast_ack ? mem_fast_rdata : adapter_rdata;

always @(posedge clk_sys) begin
	if (!nreset) t_line_ready <= 0;
	else if (!t_line_match) t_line_ready <= 0;
	else if (!t_line_ready || t_line_seen != t_addr[31:2]) begin
		t_line_seen <= t_addr[31:2];
		t_line_ready <= 1;
	end
	else if (t_line_ack) t_line_ready <= 0;
end

wombat_bus32 bus32 (
	.clk(clk_sys), .nreset(nreset), .ce(1'b1),
	.t_req(t_req && !t_line_match && !t_line_wait && !t_fast_eligible),
	.t_write(t_write), .t_size(t_size), .t_addr(t_addr),
	.t_wdata(t_wdata), .t_berr(1'b0), .t_ack(adapter_ack), .t_rdata(adapter_rdata),
	.t_active(adapter_active),
	.b_req(b_req), .b_write(b_write), .b_addr(b_addr), .b_be(b_be),
	.b_wdata(b_wdata), .b_ack(b_ack), .b_rdata(b_rdata)
);

// The RAM-only subset of quadra800's service FSM.  b_ack is the same direct
// synchronous completion used by the production module.
assign b_ack = line_ack || (DIRECT_MEM_ACK && svc_mem && !svc_fast && sdr_ack) ||
	           b_ack_r;
assign b_rdata = line_ack ? line_word :
	              (DIRECT_MEM_ACK ? sdr_rdata : b_rdata_r);

always @(posedge clk_sys) begin
	if (!nreset) begin
		svc_mem <= 0;
		svc_fast <= 0;
		mem_req <= 0;
		b_ack_r <= 0;
		b_rdata_r <= 0;
		t_fast_ack_r <= 0;
		t_fast_rdata_r <= 0;
	end
	else begin
		b_ack_r <= 0;
		t_fast_ack_r <= 0;
		if (!svc_mem) begin
			if (REGISTERED_LINE_HIT && line_match && !b_ack) begin
				b_ack_r <= 1;
				b_rdata_r <= line_word;
			end
			else if (t_fast_req || (b_req && !b_ack && !line_wait)) begin
				svc_mem <= 1;
				svc_fast <= t_fast_req;
				mem_req <= 1;
				mem_write_r <= t_fast_req ? 1'b0 : b_write;
				mem_addr_r <= t_fast_req ? t_addr[26:2] : b_addr[26:2];
				mem_be_r <= t_fast_req ? 4'b1111 : b_be;
				mem_wdata_r <= t_fast_req ? 32'd0 : b_wdata;
			end
		end
		else if (sdr_ack) begin
			svc_mem <= 0;
			mem_req <= 0;
			if (REGISTERED_FIRST_MISS && svc_fast) begin
				t_fast_ack_r <= 1;
				t_fast_rdata_r <= sdr_rdata;
			end
			else if (!DIRECT_MEM_ACK && !svc_fast) begin
				b_ack_r <= 1;
				b_rdata_r <= sdr_rdata;
			end
		end
	end
end

wire [15:0] SDRAM_DQ;
wire [12:0] SDRAM_A;
wire SDRAM_DQML, SDRAM_DQMH;
wire [1:0] SDRAM_BA;
wire SDRAM_nCS, SDRAM_nWE, SDRAM_nRAS, SDRAM_nCAS, SDRAM_CKE, SDRAM_CLK;

sdram_beat32 sdr (
	.init(init), .clk_sys(clk_sys), .clk_ram(clk_ram),
	.req(mem_req), .we(mem_write_r), .addr(mem_addr_r), .be(mem_be_r),
	.wdata(mem_wdata_r), .ack(sdr_ack), .rdata(sdr_rdata), .busy(sdr_busy),
	.line_valid_o(line_valid), .line_tag_o(line_tag), .line_data_o(line_data),
	.line_pending_o(line_pending), .line_pending_tag_o(line_pending_tag),
	.wp_valid(1'b0), .wp_addr(25'd0), .wp_be(4'd0), .wp_data(32'd0), .wq_room(),
	.SDRAM_DQ(SDRAM_DQ), .SDRAM_A(SDRAM_A), .SDRAM_DQML(SDRAM_DQML),
	.SDRAM_DQMH(SDRAM_DQMH), .SDRAM_BA(SDRAM_BA), .SDRAM_nCS(SDRAM_nCS),
	.SDRAM_nWE(SDRAM_nWE), .SDRAM_nRAS(SDRAM_nRAS), .SDRAM_nCAS(SDRAM_nCAS),
	.SDRAM_CKE(SDRAM_CKE), .SDRAM_CLK(SDRAM_CLK)
);

sdram_model chip (
	.clk(SDRAM_CLK), .cke(SDRAM_CKE), .nCS(SDRAM_nCS),
	.nRAS(SDRAM_nRAS), .nCAS(SDRAM_nCAS), .nWE(SDRAM_nWE),
	.ba(SDRAM_BA), .a(SDRAM_A), .dqmh(SDRAM_DQMH), .dqml(SDRAM_DQML),
	.dq(SDRAM_DQ)
);

task automatic write32(input [31:0] a, input [31:0] d);
	begin
		@(negedge clk_sys);
		t_addr = a;
		t_wdata = d;
		t_write = 1;
		t_req = 1;
		while (!t_ack) @(negedge clk_sys);
		t_req = 0;
		t_write = 0;
	end
endtask

task automatic read32(input [31:0] a, output [31:0] d);
	begin
		@(negedge clk_sys);
		t_addr = a;
		t_write = 0;
		t_req = 1;
		while (!t_ack) @(negedge clk_sys);
		d = t_rdata;
		t_req = 0;
	end
endtask

integer i;
integer idx;
integer fails = 0;
time t0, t1, elapsed_ns;
time average_line_ns;
reg [31:0] expected [0:255];
reg [31:0] got;
reg [15:0] lfsr;

initial begin
	$display("tb_memory_path: FAST_BYPASS=%0d DIRECT_FIRST_MISS=%0d REGISTERED_FIRST_MISS=%0d ADAPTER_LINE_HIT=%0d DIRECT_MEM_ACK=%0d REGISTERED_LINE_HIT=%0d",
	         FAST_BYPASS, DIRECT_FIRST_MISS, REGISTERED_FIRST_MISS,
	         ADAPTER_LINE_HIT, DIRECT_MEM_ACK, REGISTERED_LINE_HIT);
	repeat (4) @(posedge clk_sys);
	nreset = 1;
	init = 0;
	repeat (13000) @(posedge clk_ram);

	for (i = 0; i < 64; i = i + 1)
		write32(32'h0000_4000 + 4*i, 32'hA500_0000 + i);
	@(negedge clk_sys);
	while (sdr_busy || svc_mem) @(negedge clk_sys);

	// Cache-fill-port stream: req remains high and the aligned longword
	// address advances after each direct acknowledgement, exactly as C_FILL
	// does while r_issued paces one accepted beat at a time.
	@(negedge clk_sys);
	t_addr = 32'h0000_4000;
	t_write = 0;
	t_req = 1;
	i = 0;
	t0 = $time;
	while (i < 64) begin
		@(negedge clk_sys);
		if (t_ack) begin
			if (t_rdata !== (32'hA500_0000 + i)) begin
				$display("FAIL  stream[%0d] got %08h", i, t_rdata);
				fails = fails + 1;
			end
			i = i + 1;
			t_addr = 32'h0000_4000 + 4*i;
		end
	end
	t1 = $time;
	t_req = 0;
	elapsed_ns = (t1 - t0) / 1000;
	average_line_ns = elapsed_ns / 16;

	if (fails == 0) $display("PASS  64 integrated sequential reads are data-correct");

	// Disk-like traffic alternates posted stores with cacheable reads over a
	// working set larger than the retained SDRAM line.  This catches a stale
	// line, a dropped posted write, or a request-retirement error that a pure
	// sequential read benchmark cannot expose.
	for (i = 0; i < 256; i = i + 1) begin
		expected[i] = 32'h5100_0000 + i;
		write32(32'h0000_8000 + 4*i, expected[i]);
	end
	@(negedge clk_sys);
	while (sdr_busy || svc_mem) @(negedge clk_sys);
	lfsr = 16'h1D0F;
	for (i = 0; i < 2048; i = i + 1) begin
		idx = lfsr[7:0];
		if (lfsr[8]) begin
			expected[idx] = {16'hA55A, lfsr};
			write32(32'h0000_8000 + 4*idx, expected[idx]);
		end
		else begin
			read32(32'h0000_8000 + 4*idx, got);
			if (got !== expected[idx]) begin
				if (fails < 8)
					$display("FAIL  mixed[%0d] word[%0d] got %08h expected %08h",
					         i, idx, got, expected[idx]);
				fails = fails + 1;
			end
		end
		lfsr = {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
	end
	if (fails == 0)
		$display("PASS  2048 mixed posted-write/read operations retire in order");

	$display("  integrated 64 reads  %0d ns = %0d.%0d MB/s",
	         elapsed_ns, 256000 / elapsed_ns, (2560000 / elapsed_ns) % 10);
	$display("  average 16-byte fill %0d ns", average_line_ns);
	$display("tb_memory_path: %0d failures, %0d chip protocol errors", fails, chip.errors);
	if (fails == 0 && chip.errors == 0) $display("tb_memory_path: OK");
	else                                $display("tb_memory_path: FAILED");
	$finish;
end

initial begin
	#1_000_000_000;
	$fatal(1, "tb_memory_path timeout");
end

endmodule
