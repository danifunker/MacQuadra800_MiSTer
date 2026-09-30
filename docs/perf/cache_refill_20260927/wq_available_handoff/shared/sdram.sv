//
// sdram.v
//
// Static RAM controller implementation using SDRAM MT48LC16M16A2
//
// Copyright (c) 2015-2019 Sorgelig
//
// Some parts of SDRAM code used from project:
// http://hamsterworks.co.nz/mediawiki/index.php/Simple_SDRAM_Controller
//
// This source file is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published
// by the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version. 
//
// This source file is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of 
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the 
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License 
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
//
// ------------------------------------------
//
// furrtek 2019-01-24 : Added ugly burst reading
// Sorgelig 2019-08   : rework, support mem copy and larger chips.
//

module sdram
(
	input             init,        // reset to initialize RAM
	input             clk,         // clock ~100MHz

	inout      [15:0] SDRAM_DQ,    // 16 bit bidirectional data bus
	output reg [12:0] SDRAM_A,     // 13 bit multiplexed address bus
	output            SDRAM_DQML,  // two byte masks
	output            SDRAM_DQMH,  // 
	output reg  [1:0] SDRAM_BA,    // two banks
	output            SDRAM_nCS,   // a single chip select
	output            SDRAM_nWE,   // write enable
	output            SDRAM_nRAS,  // row address select
	output            SDRAM_nCAS,  // columns address select
	output            SDRAM_CKE,   // clock enable
	output            SDRAM_CLK,
	input             SDRAM_EN,    // clock enable

	input             sel,
	input      [26:1] addr,        // 25 bit address for 8bit mode. addr[0] = 0 for 16bit mode for correct operations.
	output reg [15:0] dout,        // data output to cpu
	input      [15:0] din,         // data input from cpu
	input             wr,          // request write
	input       [1:0] bs,          // bit1 - write high byte, bit0 - write low byte, Ignored while reading.
	input             rd,          // request read
	output reg        ready,
	input             refresh,

	input             cpsel,
	input      [26:1] cpaddr,
	input      [15:0] cpdin,
	output reg        cprd,
	input             cpreq,
	output reg        cpbusy
);

// DQ is driven from a registered value behind an explicit output enable
// rather than by assigning 'Z inside the state machine.  Same one-cycle
// drive window, same inferred bidir buffer -- but a continuous assignment is
// a tristate form Verilator can elaborate, which is what lets verilator/
// tb_sdram.sv run this controller against a chip model.
reg [15:0] dq_out;
reg        dq_oe;
assign SDRAM_DQ = dq_oe ? dq_out : 16'bZZZZZZZZZZZZZZZZ;

assign SDRAM_nCS  = chip;
assign SDRAM_nRAS = command[2];
assign SDRAM_nCAS = command[1];
assign SDRAM_nWE  = command[0];
assign SDRAM_CKE  = 1;
assign {SDRAM_DQMH,SDRAM_DQML} = SDRAM_A[12:11];

localparam BURST_LENGTH        = 8;
localparam BURST_CODE          = (BURST_LENGTH == 8) ? 3'b011 : (BURST_LENGTH == 4) ? 3'b010 : (BURST_LENGTH == 2) ? 3'b001 : 3'b000;  // 000=1, 001=2, 010=4, 011=8
localparam ACCESS_TYPE         = 1'b0;     // 0=sequential, 1=interleaved
localparam CAS_LATENCY         = 3'd2;     // 2 for < 100MHz, 3 for >100MHz
localparam OP_MODE             = 2'b00;    // only 00 (standard operation) allowed
localparam NO_WRITE_BURST      = 1'b1;     // 0= write burst enabled, 1=only single access write
localparam MODE                = {3'b000, NO_WRITE_BURST, OP_MODE, CAS_LATENCY, ACCESS_TYPE, BURST_CODE};

localparam sdram_startup_cycles= 14'd12100;// 100us, plus a little more, @ 100MHz
localparam cycles_per_refresh  = 14'd780;  // (64000*100)/8192-1 Calc'd as (64ms @ 100MHz)/8192 rose
localparam startup_refresh_max = 14'b11111111111111;

// SDRAM commands
wire [2:0] CMD_NOP             = 3'b111;
wire [2:0] CMD_ACTIVE          = 3'b011;
wire [2:0] CMD_READ            = 3'b101;
wire [2:0] CMD_WRITE           = 3'b100;
wire [2:0] CMD_PRECHARGE       = 3'b010;
wire [2:0] CMD_AUTO_REFRESH    = 3'b001;
wire [2:0] CMD_LOAD_MODE       = 3'b000;

reg [13:0] refresh_count = startup_refresh_max - sdram_startup_cycles;
reg  [2:0] command;
reg        chip;

localparam STATE_STARTUP =  0;
localparam STATE_WAIT    =  1;
localparam STATE_RW      =  2;
localparam STATE_WAITCP  =  3;
localparam STATE_CP      =  4;
localparam STATE_IDLE    =  5;
localparam STATE_IDLE_1  =  6;
localparam STATE_IDLE_2  =  7;
localparam STATE_IDLE_3  =  8;
localparam STATE_IDLE_4  =  9;
localparam STATE_IDLE_5  = 10;
localparam STATE_RFSH    = 11;
localparam STATE_RDWAIT  = 12;
localparam STATE_RPRE_1  = 13;
localparam STATE_RPRE_2  = 14;
localparam STATE_RPRE_3  = 15;
localparam STATE_FPRE_1  = 16;
localparam STATE_FPRE_2  = 17;
localparam STATE_FPRE_3  = 18;
localparam STATE_CPPRE_1 = 19;
localparam STATE_CPPRE_2 = 20;
localparam STATE_CPPRE_3 = 21;
localparam STATE_RPRE_RAS  = 22;
localparam STATE_FPRE_RAS  = 23;
localparam STATE_CPPRE_RAS = 24;
localparam STATE_FPRE_4    = 25;
localparam STATE_CPPRE_4   = 26;


// These live at module scope rather than inside the always block below.  As
// block-local statics with initialisers they were both blocking- and
// non-blocking-assigned, which Verilator calls unsupported -- and waiving the
// warning does not make it work: the whole always block silently stops
// executing the moment startup finishes.  Hoisting them is identical for
// synthesis (they were already static, and an initialiser on a reg is the
// power-up value either way) and it makes the state machine visible to a
// waveform viewer.
reg [CAS_LATENCY:0] data_ready_delay = 0;
reg  [3:0] read_tail = 0;
reg        saved_wr;
reg [12:0] cas_addr;
reg  [1:0] saved_bank;
reg [12:0] saved_row;
reg        saved_chip;
reg [15:0] saved_data;
reg  [8:0] cpcnt;
reg        old_cpreq = 0;
reg  [4:0] state = STATE_STARTUP;
reg        refresh_old = 0;
// A 128 MB MiSTer module has two 64 MB ranks.  SDRAM_nCS selects rank 0
// directly and is inverted on the module for rank 1, so open-page state is
// per {rank,bank}, not merely per bank.
// Both arrays are read combinationally every clk_ram cycle from an index
// that arrives from the request side, so they MUST stay logic registers.
// Left to itself Quartus infers an M10K for open_row and retimes the
// request-side address register into it -- a dual-clock RAM whose read port
// runs on clk_sys with DONT_CARE mixed-port read-during-write, which is not
// what this RTL (or tb_sdram) describes, and its output reached command[]
// through the worst path in the design (+0.34 ns at one placement).
(* ramstyle = "logic" *) reg  [7:0] row_open = 0;
(* ramstyle = "logic" *) reg [12:0] open_row [0:7];
(* ramstyle = "logic" *) reg  [2:0] bank_age [0:7];
// Registered predicate, equivalent to bank_age >= 5 after each edge.
(* ramstyle = "logic" *) reg [7:0] bank_tras_ready;
integer age_i;

wire  [1:0] req_bank = addr[24:23];
wire [12:0] req_row  = addr[22:10];
wire  [2:0] req_bank_idx = {addr[26], req_bank};
wire  [2:0] saved_bank_idx = {saved_chip, saved_bank};
wire req_page_hit = row_open[req_bank_idx] && open_row[req_bank_idx] == req_row;
wire req_tras_ok  = bank_tras_ready[req_bank_idx];
wire all_tras_ok  = (!row_open[0] || bank_tras_ready[0]) &&
	                 (!row_open[1] || bank_tras_ready[1]) &&
	                 (!row_open[2] || bank_tras_ready[2]) &&
	                 (!row_open[3] || bank_tras_ready[3]) &&
	                 (!row_open[4] || bank_tras_ready[4]) &&
	                 (!row_open[5] || bank_tras_ready[5]) &&
	                 (!row_open[6] || bank_tras_ready[6]) &&
	                 (!row_open[7] || bank_tras_ready[7]);

always @(posedge clk) begin
	refresh_count <= refresh_count+1'b1;
	for (age_i = 0; age_i < 8; age_i = age_i + 1) begin
		if (row_open[age_i] && bank_age[age_i] != 3'd7)
			bank_age[age_i] <= bank_age[age_i] + 1'b1;
        if (row_open[age_i] && bank_age[age_i] >= 3'd4)
            bank_tras_ready[age_i] <= 1'b1;
    end

	data_ready_delay <= data_ready_delay>>1;
	if(data_ready_delay[0]) ready <= 1;

	dout  <= SDRAM_DQ;
	dq_oe <= 0;

	if(SDRAM_EN) begin
		command <= CMD_NOP;
		case (state)
			STATE_STARTUP: begin
				//------------------------------------------------------------------------
				//-- This is the initial startup state, where we wait for at least 100us
				//-- before starting the start sequence
				//-- 
				//-- The initialisation is sequence is 
				//--  * de-assert SDRAM_CKE
				//--  * 100us wait, 
				//--  * assert SDRAM_CKE
				//--  * wait at least one cycle, 
				//--  * PRECHARGE
				//--  * wait 2 cycles
				//--  * REFRESH, 
				//--  * tREF wait
				//--  * REFRESH, 
				//--  * tREF wait 
				//--  * LOAD_MODE_REG 
				//--  * 2 cycles wait
				//------------------------------------------------------------------------
				SDRAM_A    <= 0;
				SDRAM_BA   <= 0;

				if (refresh_count == (startup_refresh_max-64)) chip <= 0;
				if (refresh_count == (startup_refresh_max-32)) chip <= 1;

				// All the commands during the startup are NOPS, except these
				if (refresh_count == startup_refresh_max-63 || refresh_count == startup_refresh_max-31) begin
					// ensure all rows are closed
					command     <= CMD_PRECHARGE;
					SDRAM_A[10] <= 1;  // all banks
					SDRAM_BA    <= 2'b00;
				end
				if (refresh_count == startup_refresh_max-55 || refresh_count == startup_refresh_max-23) begin
					// these refreshes need to be at least tREF (66ns) apart
					command     <= CMD_AUTO_REFRESH;
				end
				if (refresh_count == startup_refresh_max-47 || refresh_count == startup_refresh_max-15) begin
					command     <= CMD_AUTO_REFRESH;
				end
				if (refresh_count == startup_refresh_max-39 || refresh_count == startup_refresh_max-7) begin
					// Now load the mode register
					command     <= CMD_LOAD_MODE;
					SDRAM_A     <= MODE;
				end

				//------------------------------------------------------
				//-- if startup is complete then go into idle mode,
				//-- get prepared to accept a new command, and schedule
				//-- the first refresh cycle
				//------------------------------------------------------
				if (!refresh_count) begin
					state   <= STATE_IDLE;
					ready   <= 1;
					refresh_count <= 0;
				end
				cpbusy <= 0;
			end
			
			STATE_RFSH: begin
				state         <= STATE_IDLE_5;
				command       <= CMD_AUTO_REFRESH;
				chip          <= 1;
			end

			STATE_IDLE_5: state <= STATE_IDLE_4;
			STATE_IDLE_4: state <= STATE_IDLE_3;
			STATE_IDLE_3: state <= STATE_IDLE_2;
			STATE_IDLE_2: state <= STATE_IDLE_1;
			STATE_IDLE_1: state <= STATE_IDLE;

			STATE_IDLE: begin
				if (refresh ^ refresh_old) begin
					refresh_old<= refresh;
					chip       <= 0;
					if (row_open != 0) begin
						if (all_tras_ok) begin
							command     <= CMD_PRECHARGE;
							SDRAM_A[10] <= 1;
							SDRAM_BA    <= 0;
							state       <= STATE_FPRE_1;
						end
						else state <= STATE_FPRE_RAS;
					end
					else begin
						command <= CMD_AUTO_REFRESH;
						state   <= STATE_RFSH;
					end
				end
				else if (sel & (rd | wr)) begin
					// A10 is deliberately zero: CPU rows stay open.  Row conflicts,
					// refresh and the copy port close them explicitly below.
					{cas_addr[12:9],saved_bank,saved_row,cas_addr[8:0]} <=
						{~wr ? 2'b00 : ~bs, 1'b0, addr[25:1]};
					chip       <= addr[26];
					saved_chip <= addr[26];
					saved_data <= din;
					saved_wr   <= wr;
					ready      <= 0;
					if (req_page_hit) begin
						SDRAM_BA <= req_bank;
						state    <= STATE_RW;
					end
					else if (row_open[req_bank_idx]) begin
						if (req_tras_ok) begin
							command     <= CMD_PRECHARGE;
							SDRAM_BA    <= req_bank;
							SDRAM_A[10] <= 0;
							row_open[req_bank_idx] <= 0;
							state       <= STATE_RPRE_1;
						end
						else state <= STATE_RPRE_RAS;
					end
					else begin
						command            <= CMD_ACTIVE;
						SDRAM_BA           <= req_bank;
						SDRAM_A            <= req_row;
						row_open[req_bank_idx] <= 1;
						open_row[req_bank_idx] <= req_row;
						bank_age[req_bank_idx] <= 0;
                    bank_tras_ready[req_bank_idx] <= 0;
						state              <= STATE_WAIT;
					end
				end
				else begin
					cpbusy     <= 0;
					cprd       <= 0;
					old_cpreq  <= cpreq;
					if(~old_cpreq & cpreq & cpsel) begin
						{cas_addr[12:9],saved_bank,saved_row,cas_addr[8:0]} <=
							{2'b00, 1'b0, cpaddr[25:1]};
						chip    <= cpaddr[26];
						saved_chip <= cpaddr[26];
						cpbusy  <= 1;
						cpcnt   <= 511;
						cprd    <= 1;
						if (row_open == 0) begin
							command  <= CMD_ACTIVE;
							chip     <= cpaddr[26];
							SDRAM_BA <= cpaddr[24:23];
							SDRAM_A  <= cpaddr[22:10];
							state    <= STATE_WAITCP;
						end
						else if (all_tras_ok) begin
							command     <= CMD_PRECHARGE;
							SDRAM_A[10] <= 1;
							SDRAM_BA    <= 0;
							chip        <= 0;
							state       <= STATE_CPPRE_1;
						end
						else state <= STATE_CPPRE_RAS;
					end
				end
			end

			// An explicit precharge may not precede tRAS.  Requests and refresh
			// remain latched while the saturating per-bank age counters finish.
			STATE_RPRE_RAS: begin
				if (bank_tras_ready[saved_bank_idx]) begin
					command                <= CMD_PRECHARGE;
					chip                   <= saved_chip;
					SDRAM_BA               <= saved_bank;
					SDRAM_A[10]            <= 0;
					row_open[saved_bank_idx] <= 0;
					state                  <= STATE_RPRE_1;
				end
			end

			STATE_FPRE_RAS: begin
				if (all_tras_ok) begin
					command     <= CMD_PRECHARGE;
					SDRAM_A[10] <= 1;
					SDRAM_BA    <= 0;
					chip        <= 0;
					state       <= STATE_FPRE_1;
				end
			end

			STATE_CPPRE_RAS: begin
				if (all_tras_ok) begin
					command     <= CMD_PRECHARGE;
					SDRAM_A[10] <= 1;
					SDRAM_BA    <= 0;
					chip        <= 0;
					state       <= STATE_CPPRE_1;
				end
			end

			// Three command spacings from PRE to ACT give 30.3 ns at 99 MHz,
			// safely above the 20 ns-class tRP of supported MiSTer SDRAM.
			STATE_RPRE_1: state <= STATE_RPRE_2;
			STATE_RPRE_2: state <= STATE_RPRE_3;
			STATE_RPRE_3: begin
				command                <= CMD_ACTIVE;
				chip                   <= saved_chip;
				SDRAM_BA               <= saved_bank;
				SDRAM_A                <= saved_row;
				row_open[saved_bank_idx] <= 1;
				open_row[saved_bank_idx] <= saved_row;
				bank_age[saved_bank_idx] <= 0;
                    bank_tras_ready[saved_bank_idx] <= 0;
				state                  <= STATE_WAIT;
			end

			// PRECHARGE ALL must reach both ranks.  The board inverts nCS for
			// rank 1, so issue the command once at each level, then leave a full
			// tRP before the paired refresh commands.
			STATE_FPRE_1: begin
				command     <= CMD_PRECHARGE;
				chip        <= 1;
				SDRAM_A[10] <= 1;
				SDRAM_BA    <= 0;
				row_open    <= 0;
				state       <= STATE_FPRE_2;
			end
			STATE_FPRE_2: state <= STATE_FPRE_3;
			STATE_FPRE_3: state <= STATE_FPRE_4;
			STATE_FPRE_4: begin
				command <= CMD_AUTO_REFRESH;
				chip    <= 0;
				state   <= STATE_RFSH;
			end

			STATE_CPPRE_1: begin
				command     <= CMD_PRECHARGE;
				chip        <= 1;
				SDRAM_A[10] <= 1;
				SDRAM_BA    <= 0;
				row_open    <= 0;
				state       <= STATE_CPPRE_2;
			end
			STATE_CPPRE_2: state <= STATE_CPPRE_3;
			STATE_CPPRE_3: state <= STATE_CPPRE_4;
			STATE_CPPRE_4: begin
				command  <= CMD_ACTIVE;
				chip     <= saved_chip;
				SDRAM_BA <= saved_bank;
				SDRAM_A  <= saved_row;
				state    <= STATE_WAITCP;
			end

			STATE_WAIT: state <= STATE_RW;
			STATE_RW: begin
				state         <= saved_wr ? STATE_IDLE_1 : STATE_RDWAIT;
				SDRAM_BA      <= saved_bank;
				SDRAM_A       <= cas_addr;
				if(saved_wr) begin
					command    <= CMD_WRITE;
					dq_out     <= saved_data;
					dq_oe      <= 1;
					ready      <= 1;
				end
				else begin
					command    <= CMD_READ;
					data_ready_delay[CAS_LATENCY] <= 1;
					read_tail <= BURST_LENGTH - 1;
				end
			end

			STATE_RDWAIT: begin
				// Keep the command scheduler quiescent until every word of the
				// programmed burst has left DQ.  With BL8 the bridge retains the
				// whole 16-byte line; precharge/refresh or a second READ before
				// the tail completes would terminate or overlap that transfer.
				if (!data_ready_delay[0] && ready && read_tail != 0) begin
					read_tail <= read_tail - 1'b1;
					if (read_tail == 1) state <= STATE_IDLE_1;
				end
			end

			STATE_WAITCP: state <= STATE_CP;
			STATE_CP: begin
				SDRAM_A       <= {2'b00, !cpcnt, cas_addr[9:0]};
				cas_addr[8:0] <= cas_addr[8:0] + 1'd1;
				cpcnt         <= cpcnt - 1'd1;
				command       <= CMD_WRITE;
				dq_out        <= cpdin;
				dq_oe         <= 1;
				if(!cpcnt) begin
					state      <= STATE_IDLE_4;
					cprd       <= 0;
				end
			end
		endcase

		if (init) begin
			state         <= STATE_STARTUP;
			refresh_count <= startup_refresh_max - sdram_startup_cycles;
			row_open      <= 0;
            bank_tras_ready <= 8'hff;
			bank_age[0]   <= 7;
			bank_age[1]   <= 7;
			bank_age[2]   <= 7;
			bank_age[3]   <= 7;
			bank_age[4]   <= 7;
			bank_age[5]   <= 7;
			bank_age[6]   <= 7;
			bank_age[7]   <= 7;
			read_tail     <= 0;
		end
	end
	else begin
		ready    <= 1;
		cpbusy   <= 0;
		cprd     <= 0;
		dout     <= 0;
		SDRAM_A  <= 0;
		SDRAM_BA <= 0;
		command  <= 0;
		chip     <= 0;
	end
end

altddio_out
#(
	.extend_oe_disable("OFF"),
	.intended_device_family("Cyclone V"),
	.invert_output("OFF"),
	.lpm_hint("UNUSED"),
	.lpm_type("altddio_out"),
	.oe_reg("UNREGISTERED"),
	.power_up_high("OFF"),
	.width(1)
)
sdramclk_ddr
(
	.datain_h(1'b0),
	.datain_l(1'b1),
	.outclock(clk),
	.dataout(SDRAM_CLK),
	.aclr(1'b0),
	.aset(1'b0),
	.oe(1'b1),
	.outclocken(1'b1),
	.sclr(1'b0),
	.sset(1'b0)
);
 
endmodule
