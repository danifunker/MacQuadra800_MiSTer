//============================================================================
//  wombat_bus32 — splits AP68040 post-cache transactions (right-aligned
//  data, any alignment) into aligned longword beats with byte enables:
//  the shape djMEMC, IOSB and the platform RAM/ROM consume.
//
//  Beat contract:
//   - b_req is level-held per beat; the 2nd beat of a split follows with a
//     new address while b_req stays high, so consumers accept on
//     "b_req && !their-own-registered-ack" (never on a req edge).
//   - b_ack: single-cycle pulse, b_rdata valid with it.
//   - b_be[3] = byte at b_addr+0 = b_wdata[31:24] (big-endian lanes);
//     be is valid for reads too (narrow device registers decode it).
//   - t_berr aborts the in-flight transaction: no ack, request dropped;
//     the CPU core samples the same pulse and builds the fault frame.
//============================================================================

module wombat_bus32
(
	input             clk,
	input             nreset,
	input             ce,

	// CPU-side transaction (wombat_cpu bus_*)
	input             t_req,
	input             t_write,
	input       [1:0] t_size,     // AP040_SZ_B/W/L = 0/1/2
	input      [31:0] t_addr,
	input      [31:0] t_wdata,    // right-aligned by size
	input             t_berr,
	output reg        t_ack,
	output reg [31:0] t_rdata,    // right-aligned by size, valid at t_ack
	output            t_active,

	// beat side: aligned longwords with byte lanes
	output reg        b_req,
	output reg        b_write,
	output reg [31:2] b_addr,
	output reg  [3:0] b_be,
	output reg [31:0] b_wdata,
	input             b_ack,
	input      [31:0] b_rdata
);

// operand byte count and left-aligned write stream of a new transaction
wire [2:0] f_bytes = (t_size == 2'd0) ? 3'd1 : (t_size == 2'd1) ? 3'd2 : 3'd4;
wire [31:0] f_wsh  = (t_size == 2'd0) ? {t_wdata[7:0],  24'd0} :
                     (t_size == 2'd1) ? {t_wdata[15:0], 16'd0} : t_wdata;
wire  [1:0] f_off  = t_addr[1:0];
wire  [2:0] f_end  = {1'b0, f_off} + f_bytes;      // 1..7; >4 means split
wire  [2:0] f_n0   = (f_end > 3'd4) ? (3'd4 - {1'b0, f_off}) : f_bytes;

// be mask covering `count` bytes starting at longword offset `start`
function [3:0] lanes;
	input [1:0] start;
	input [2:0] count;
	lanes = (4'b1111 << (3'd4 - count)) >> start;
endfunction

reg        active;
reg        second;      // a split's 2nd beat is (or will be) in flight
reg  [1:0] r_off;
reg  [2:0] r_bytes;
reg  [2:0] r_end;
reg [31:0] r_wsh;
reg [31:0] r_stream;    // beat-0 read bytes, left-aligned at the top

wire [31:0] rd_stream0 = b_rdata << {r_off, 3'd0};
wire  [2:0] r_n0       = 3'd4 - {1'b0, r_off};

assign t_active = active;

always @(posedge clk) begin
	if (!nreset) begin
		active  <= 0;
		second  <= 0;
		t_ack   <= 0;
		t_rdata <= 0;
		b_req   <= 0;
		b_write <= 0;
		b_addr  <= 0;
		b_be    <= 0;
		b_wdata <= 0;
		r_off   <= 0;
		r_bytes <= 0;
		r_end   <= 0;
		r_wsh   <= 0;
		r_stream <= 0;
	end
	else if (ce) begin
		t_ack <= 0;

		if (active && t_berr) begin
			active <= 0;
			second <= 0;
			b_req  <= 0;
		end
		else if (!active) begin
			if (t_req && !t_ack) begin
				active  <= 1;
				second  <= 0;
				r_off   <= f_off;
				r_bytes <= f_bytes;
				r_end   <= f_end;
				r_wsh   <= f_wsh;
				b_req   <= 1;
				b_write <= t_write;
				b_addr  <= t_addr[31:2];
				b_be    <= lanes(f_off, f_n0);
				b_wdata <= f_wsh >> {f_off, 3'd0};
			end
		end
		else if (b_ack) begin
			if (!second && r_end > 3'd4) begin
				// split: issue the tail beat at the next longword
				second   <= 1;
				r_stream <= rd_stream0;
				b_addr   <= b_addr + 1'b1;
				b_be     <= lanes(2'd0, r_end - 3'd4);
				b_wdata  <= r_wsh << {r_n0, 3'd0};
			end
			else begin
				active <= 0;
				second <= 0;
				b_req  <= 0;
				t_ack  <= 1;
				// tail bytes below the operand fall off in the final shift
				t_rdata <= (second ? (r_stream | (b_rdata >> {r_n0, 3'd0}))
				                   : rd_stream0) >> {(3'd4 - r_bytes), 3'd0};
			end
		end
	end
end

endmodule
