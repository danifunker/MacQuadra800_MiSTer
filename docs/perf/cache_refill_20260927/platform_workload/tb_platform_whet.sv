//============================================================================
//  tb_platform_whet -- the Speedometer Whetstone fixture on the SHIPPED
//  memory path.
//
//  scratch/p198_ret/tb_w.sv runs wombat_cpu against a fixed-latency RAM model.
//  Here the whole `quadra800` machine from $TREE/rtl is instantiated (CPU,
//  store buffer, wombat_bus32, the service FSM with its retained-line fast
//  paths and DIRECT_WRITES push port, and every device, idle), and its
//  platform beat port is wired exactly as MacQuadra800.sv wires it:
//    RAM  -> sdram_beat32 (33<->99 MHz bridge, 8-entry write FIFO) -> sdram.sv
//            (open-page BL8, refresh) -> two SDR chip models (the tb_sdram.sv
//            model, both ranks, protocol-checked; storage made a flat array
//            by the runner so 32 MB can be backdoor-loaded)
//    ROM  -> a DDR3 stand-in with +romlat=N clk_sys from request to ack
//    VRAM -> the top's two-clock BRAM handshake (not expected to be used)
//  clk_ram is exactly 3x clk_sys, both edges aligned at t=0 (tb_sdram.sv's
//  clocking; on hardware both are 0-degree outputs of one PLL).
//
//  Differences from hardware, all deliberate:
//   * the boot overlay is forced off, so the image's reset vectors at $0
//     are fetched from RAM (tb_w.sv does the same by construction);
//   * no DAFB scanout clock (VRAM is on-chip BRAM on hardware; scanout never
//     touches SDRAM), no SCSI/Ethernet/ADB activity, IPL stays 7;
//   * the ROM's DDR3 latency is a parameter, not the HPS bridge.
//============================================================================
`timescale 1ps/1ps

module tb_platform_whet;

localparam integer TR = 5050;              // clk_ram half period (99.0 MHz)
localparam integer TS = 3*TR;              // clk_sys half period (33.0 MHz)

reg clk_ram = 0, clk_sys = 0;
always #TR clk_ram = ~clk_ram;
always #TS clk_sys = ~clk_sys;

reg sdram_init = 1;
reg nreset     = 0;

//----------------------------------------------------------------------------
// the machine
//----------------------------------------------------------------------------
wire        mem_req, mem_write;
wire [31:2] mem_addr;
wire  [3:0] mem_be;
wire [31:0] mem_wdata;
wire  [1:0] mem_memsel;
wire [31:0] mem_rdata;
wire        mem_ack;
reg  [31:0] mem_rdata_r = 0;
reg         mem_ack_r   = 0;
wire        mem_wp_valid;
wire [31:2] mem_wp_addr;
wire  [3:0] mem_wp_be;
wire [31:0] mem_wp_data;
wire        sdr_wq_room, sdr_line_valid, sdr_line_pending;
wire [26:4] sdr_line_tag, sdr_line_pending_tag;
wire [127:0] sdr_line_data;
wire        sdr_ack;
wire [31:0] sdr_rdata;
wire        dbg_berr, debug_fault, debug_halted;
wire [31:0] dbg_berr_addr;

wire mem_is_ram  = (mem_memsel == 2'd0);
wire mem_is_rom  = (mem_memsel == 2'd1);
wire mem_is_vram = !mem_is_ram && !mem_is_rom;

assign mem_ack   = mem_ack_r | sdr_ack;
assign mem_rdata = sdr_ack ? sdr_rdata : mem_rdata_r;

quadra800 #(.RAM_ADDR_BITS(27), .CDROM(0), .SONIC(0)) dut (
	.clk(clk_sys), .nreset(nreset), .ce(1'b1),
	.clk_vid(1'b0), .nreset_vid(1'b0),
	.ram_cfg(2'd0), .mon_12in(1'b0),
	.mem_req(mem_req), .mem_write(mem_write), .mem_addr(mem_addr), .mem_be(mem_be),
	.mem_wdata(mem_wdata), .mem_memsel(mem_memsel), .mem_rdata(mem_rdata), .mem_ack(mem_ack),
	.mem_wp_valid(mem_wp_valid), .mem_wp_addr(mem_wp_addr), .mem_wp_be(mem_wp_be),
	.mem_wp_data(mem_wp_data), .mem_wq_room(sdr_wq_room),
	.mem_line_valid(sdr_line_valid), .mem_line_tag(sdr_line_tag), .mem_line_data(sdr_line_data),
	.mem_line_pending(sdr_line_pending), .mem_line_pending_tag(sdr_line_pending_tag),
	.vid_addr(), .vid_rdata(32'd0), .vid_stride(),
	.VGA_R(), .VGA_G(), .VGA_B(), .VGA_HS(), .VGA_VS(), .VGA_HB(), .VGA_VB(), .CE_PIXEL(),
	.AUDIO_L(), .AUDIO_R(), .cd_snd_l(), .cd_snd_r(),
	.img_mounted(3'd0), .img_size(64'd0), .io_lba(), .io_blk_cnt(), .io_rd(), .io_wr(),
	.io_ack(3'd0), .sd_buff_addr(13'd0), .sd_buff_dout(16'd0), .sd_buff_din(), .sd_buff_wr(1'b0),
	.ps2_key(11'd0), .ps2_mouse(25'd0), .timestamp(33'd0),
	.scc_rxd_a(1'b1), .scc_txd_a(), .scc_cts_a(1'b1), .scc_rts_a(), .scc_rxd_b(1'b1), .scc_txd_b(),
	.dbg_berr(dbg_berr), .dbg_berr_addr(dbg_berr_addr), .dbg_overlay(),
	.debug_status(), .debug_status2(), .debug_fault(debug_fault), .debug_halted(debug_halted),
	.eth_ena(1'b0), .dbg_sw(3'd0),
	.eth_mem_addr(), .eth_mem_rd(), .eth_mem_we(), .eth_mem_wdata(),
	.eth_mem_accept(1'b0), .eth_mem_rvalid(1'b0), .eth_mem_rdata(64'd0)
);

// The fixture image carries its own reset vectors at $0: run with the boot
// overlay already cleared (store_buffer_ok / cache_line_valid follow it).
initial force dut.overlay = 1'b0;

//----------------------------------------------------------------------------
// SDRAM: the bridge and controller from $TREE, two ranks of chip model
//----------------------------------------------------------------------------
wire [15:0] SDRAM_DQ;
wire [12:0] SDRAM_A;
wire        SDRAM_DQML, SDRAM_DQMH;
wire  [1:0] SDRAM_BA;
wire        SDRAM_nCS, SDRAM_nWE, SDRAM_nRAS, SDRAM_nCAS, SDRAM_CKE, SDRAM_CLK;

sdram_beat32 sdr (
	.init(sdram_init), .clk_sys(clk_sys), .clk_ram(clk_ram),
	.req(mem_req && mem_is_ram), .we(mem_write), .addr(mem_addr[26:2]), .be(mem_be),
	.wdata(mem_wdata), .ack(sdr_ack), .rdata(sdr_rdata), .busy(),
	.line_valid_o(sdr_line_valid), .line_tag_o(sdr_line_tag), .line_data_o(sdr_line_data),
	.line_pending_o(sdr_line_pending), .line_pending_tag_o(sdr_line_pending_tag),
	.wp_valid(mem_wp_valid), .wp_addr(mem_wp_addr[26:2]), .wp_be(mem_wp_be),
	.wp_data(mem_wp_data), .wq_room(sdr_wq_room),
	.SDRAM_DQ(SDRAM_DQ), .SDRAM_A(SDRAM_A), .SDRAM_DQML(SDRAM_DQML), .SDRAM_DQMH(SDRAM_DQMH),
	.SDRAM_BA(SDRAM_BA), .SDRAM_nCS(SDRAM_nCS), .SDRAM_nWE(SDRAM_nWE), .SDRAM_nRAS(SDRAM_nRAS),
	.SDRAM_nCAS(SDRAM_nCAS), .SDRAM_CKE(SDRAM_CKE), .SDRAM_CLK(SDRAM_CLK)
);

sdram_model chip (
	.clk(SDRAM_CLK), .cke(SDRAM_CKE), .nCS(SDRAM_nCS),
	.nRAS(SDRAM_nRAS), .nCAS(SDRAM_nCAS), .nWE(SDRAM_nWE),
	.ba(SDRAM_BA), .a(SDRAM_A), .dqmh(SDRAM_DQMH), .dqml(SDRAM_DQML), .dq(SDRAM_DQ)
);
sdram_model chip_hi (
	.clk(SDRAM_CLK), .cke(SDRAM_CKE), .nCS(~SDRAM_nCS),
	.nRAS(SDRAM_nRAS), .nCAS(SDRAM_nCAS), .nWE(SDRAM_nWE),
	.ba(SDRAM_BA), .a(SDRAM_A), .dqmh(SDRAM_DQMH), .dqml(SDRAM_DQML), .dq(SDRAM_DQ)
);

// byte address -> chip cell key, sdram.sv's decode (bank B[24:23], row
// B[22:10], col {B[25], B[9:2], half}); the high half-word of a longword is
// {byte+0, byte+1}.  All of the 32 MB image sits in rank 0 (B[26] = 0).
function automatic int sdcell(input int b, input bit lo);
	sdcell = {7'd0, b[24:23], b[22:10], b[25], b[9:2], lo};
endfunction

//----------------------------------------------------------------------------
// ROM (DDR3 on hardware) and VRAM (on-chip BRAM) beats, as MacQuadra800.sv
//----------------------------------------------------------------------------
reg [7:0] rom [0:1048575];
integer   romlat = 6, rom_wait = -1;
reg       vram_ph = 0;
longint   rom_reads = 0, rom_reads_loop = 0, vram_beats = 0;
reg       in_loop = 0;

always @(posedge clk_sys) begin
	mem_ack_r <= 0;
	if (mem_req && !mem_ack && mem_is_vram) begin
		if (!vram_ph) vram_ph <= 1;
		else begin vram_ph <= 0; mem_rdata_r <= 0; mem_ack_r <= 1; vram_beats++; end
	end
	if (mem_req && !mem_ack && mem_is_rom) begin
		if (mem_write) mem_ack_r <= 1;
		else if (rom_wait < 0) rom_wait = romlat;
		else if (rom_wait <= 1) begin
			mem_rdata_r <= {rom[{mem_addr[19:2],2'd0}], rom[{mem_addr[19:2],2'd1}],
			                rom[{mem_addr[19:2],2'd2}], rom[{mem_addr[19:2],2'd3}]};
			mem_ack_r <= 1;
			rom_wait = -1;
			rom_reads++; if (in_loop) rom_reads_loop++;
		end
		else rom_wait = rom_wait - 1;
	end
end

//----------------------------------------------------------------------------
// load, reset
//----------------------------------------------------------------------------
reg [7:0] img [0:33554431];
reg [1023:0] path, rompath;
integer fd, count, i;
longint cycles = 0, stamp_start = 0, loop_cycles = -1;

initial begin
	if (!$value$plusargs("prog=%s", path) || !$value$plusargs("rom=%s", rompath))
		$fatal(1, "missing +prog / +rom");
	if ($value$plusargs("romlat=%d", romlat)) begin end
	fd = $fopen(path, "rb"); if (!fd) $fatal(1, "RAM open failed");
	count = $fread(img, fd); $fclose(fd); if (count != 33554432) $fatal(1, "short RAM image");
	fd = $fopen(rompath, "rb"); if (!fd) $fatal(1, "ROM open failed");
	count = $fread(rom, fd); $fclose(fd); if (count != 1048576) $fatal(1, "short ROM image");
	// +any_ssp: allow a moved initial stack (the stack-alignment experiment)
	if ((!$test$plusargs("any_ssp") && {img[0],img[1],img[2],img[3]} != 32'h640000) ||
	    {img[4],img[5],img[6],img[7]} != 32'h630000)
		$fatal(1, "unexpected fixture vectors");
	// backdoor: the whole image into rank 0's cells
	for (i = 0; i < 33554432; i = i + 2)
		chip.mem[sdcell(i, i[1])] = {img[i], img[i+1]};
	$display("LOADED image into SDRAM model (romlat=%0d)", romlat);

	// controller power-up (sdram.sv's ~122 us startup), then the machine
	repeat (8) @(negedge clk_sys);
	sdram_init = 0;
	wait (sdr.sdram.state == 5);                    // STATE_IDLE
	repeat (50) @(negedge clk_sys);
	$display("SDRAM ready at %0t ps", $time);
	nreset = 1;
end

//----------------------------------------------------------------------------
// instrumentation (loop window only unless stated)
//----------------------------------------------------------------------------
// core-side (wombat_cpu's mem_req/mem_ack, same meaning as tb_w.sv's)
longint lat_count[3], lat_total[3];
longint lat_start = -1; int lat_class;
// external bus (wombat_cpu bus_req/bus_ack): class at ack
//   0 read, line hit   1 read, first miss (direct)   2 read via bus32
//   3 write direct push 4 write via bus32            5 instruction (any)
longint ext_start = -1;
int     ext_hist [6][int];
longint ext_n[6], ext_sum[6];
longint wr32_shape[int], wr32_region[int];
longint walker_n = 0, walker_sum = 0, walker_start = -1;
// store buffer
longint sb_full_cyc = 0, sb_occ[int];
// bridge
longint wq_occ[int], wq_at_read[int];
longint rd_wait_fifo = 0, wq_full_cyc = 0, wq_noroom_cyc = 0, wr_blocked_room = 0;
longint ram_reads = 0, ram_reads_miss_in_flight = 0, line_poison = 0;
reg     mem_req_d = 0;
// SDRAM controller (clk_ram)
longint sd_hit[2], sd_conflict[2], sd_closed[2], sd_refresh = 0, sd_busy = 0, sd_ramcyc = 0;
int     ipl_seen = 0, berr_seen = 0;
longint k;

initial for (int c = 0; c < 6; c++) begin ext_n[c] = 0; ext_sum[c] = 0; end
initial for (int c = 0; c < 3; c++) begin lat_count[c] = 0; lat_total[c] = 0; end
initial for (int c = 0; c < 2; c++) begin sd_hit[c] = 0; sd_conflict[c] = 0; sd_closed[c] = 0; end

wire [3:0] wq_used = sdr.wq_wp - sdr.wq_rp_sys;

always @(posedge clk_ram) if (in_loop) begin
	sd_ramcyc++;
	if (sdr.busy_r) sd_busy++;
	if (sdr.sdram.state == 5 && !(sdr.sdram.refresh ^ sdr.sdram.refresh_old) &&
	    (sdr.sdram.rd || sdr.sdram.wr)) begin
		if (sdr.sdram.req_page_hit) sd_hit[sdr.sdram.wr]++;
		else if (sdr.sdram.row_open[sdr.sdram.req_bank_idx]) sd_conflict[sdr.sdram.wr]++;
		else sd_closed[sdr.sdram.wr]++;
	end
	if (sdr.sdram.state == 5 && (sdr.sdram.refresh ^ sdr.sdram.refresh_old)) sd_refresh++;
end

always @(posedge clk_sys) if (nreset) begin
	cycles++;
	if (debug_fault || debug_halted) $fatal(1, "CPU fault/halt pc=%h", dut.cpu.core.pc_i);
	if (cycles > 400000000) $fatal(1, "timeout pc=%h", dut.cpu.core.pc_i);
	if (cycles % 2000000 == 0) $display("HEARTBEAT cycle=%0d pc=%h", cycles, dut.cpu.core.pc_i);
	if (dut.svc == 3) begin berr_seen++; $display("BUS ERROR addr=%h", {dbg_berr_addr}); end
	if (in_loop && dut.ipl_n != 3'b111) ipl_seen++;

	// core-side latency, identical bookkeeping to tb_w.sv
	if (dut.cpu.mem_req && lat_start < 0) begin
		lat_start = cycles; lat_class = dut.cpu.mem_instr ? 0 : (dut.cpu.mem_write ? 2 : 1);
	end
	if (dut.cpu.mem_ack && lat_start >= 0) begin
		if (in_loop) begin lat_count[lat_class]++; lat_total[lat_class] += cycles - lat_start + 1; end
		lat_start = -1;
	end

	// external bus
	if (dut.bus_req && ext_start < 0) ext_start = cycles;
	if (dut.bus_ack && ext_start >= 0) begin
		int c; longint l;
		c = dut.bus_instr ? 5 :
		    !dut.bus_write ? (dut.bus_line_ack ? 0 : dut.bus_miss_ack ? 1 : 2) :
		                     (dut.bus_miss_ack ? 3 : 4);
		l = cycles - ext_start + 1;
		if (in_loop) begin
			ext_n[c]++; ext_sum[c] += l; ext_hist[c][l > 40 ? 40 : int'(l)]++;
			if (c == 4 || c == 2) begin
				wr32_shape[{c[2:0], 2'b0, dut.bus_size, dut.bus_addr[3:0]}]++;
				wr32_region[{c[2:0], dut.bus_addr[27:16]}]++;
			end
		end
		ext_start = -1;
	end
	if (dut.walker_req && walker_start < 0) walker_start = cycles;
	if (dut.walker_ack && walker_start >= 0) begin
		if (in_loop) begin walker_n++; walker_sum += cycles - walker_start + 1; end
		walker_start = -1;
	end

	if (in_loop) begin
		if (dut.cpu.store_buffer.buffer_req && !dut.cpu.store_buffer.s_ack) sb_full_cyc++;
		sb_occ[int'(dut.cpu.store_buffer.count)]++;
		wq_occ[int'(wq_used)]++;
		if (sdr.wq_full) wq_full_cyc++;
		if (!sdr_wq_room) wq_noroom_cyc++;
		if (dut.bus_req && dut.bus_write && !dut.bus_ack && !sdr_wq_room &&
		    dut.bus_addr[31:30] == 2'b00) wr_blocked_room++;
		if (mem_req && mem_is_ram && !mem_write) begin
			if (!mem_req_d) begin ram_reads++; wq_at_read[int'(wq_used)]++; end
			if (!sdr.wq_empty) rd_wait_fifo++;
		end
		if (mem_wp_valid && sdr.fill_pending) line_poison++;
	end
	mem_req_d <= mem_req && !mem_ack;

	// markers, as tb_w.sv: at the external write's acknowledge
	if (dut.bus_req && dut.bus_write && dut.bus_ack && dut.bus_addr == 32'hf108) begin
		if (dut.bus_wdata[15:0] == 1) begin stamp_start = cycles; in_loop = 1; end
		else if (dut.bus_wdata[15:0] == 2) begin
			loop_cycles = cycles - stamp_start; in_loop = 0;
			$display("WHETSTONE_LOOP cycles=%0d platform=sdram romlat=%0d", loop_cycles, romlat);
		end
	end
	if (dut.bus_req && dut.bus_write && dut.bus_ack && dut.bus_addr == 32'hf102) begin
		if (dut.bus_wdata[15:0] != 16'h600d) $fatal(1, "guest failure marker %h", dut.bus_wdata[15:0]);
		finish_up();
	end
end

task automatic hist(input string name, input longint h[int]);
	string s; s = "";
	foreach (h[x]) s = {s, $sformatf(" %0d:%0d", x, h[x])};
	$display("%s%s", name, s);
endtask

task automatic dump_hex(input string file, input int lo, input int hi);
	int f; bit [15:0] w;
	f = $fopen(file, "w");
	for (int a = lo; a <= hi; a++) begin
		w = chip.mem[sdcell(a & ~1, a[1])];
		$fwrite(f, "%02h\n", a[0] ? w[7:0] : w[15:8]);
	end
	$fclose(f);
endtask

task finish_up;
	begin
		$display("WHETSTONE RETURNED cycles=%0d loop=%0d", cycles, loop_cycles);
		// let the bridge FIFO drain before reading the chip back
		repeat (400) @(posedge clk_sys);
		dump_hex("whet_globals.hex", 'h61df90, 'h61dfa3);
		dump_hex("whet_code.hex",    'h600000, 'h600b4d);
		dump_hex("whet_stack.hex",   'h63fc00, 'h63ffff);
		$display("SDRAM_PROTOCOL_ERRORS %0d", chip.errors + chip_hi.errors);
		$display("SDRAM_TIMING tRC=%0d tRCD=%0d tRP=%0d tRAS=%0d max_refresh_gap=%0d",
		         chip.min_trc, chip.min_trcd, chip.min_trp, chip.min_tras, chip.max_refresh_gap);
		$display("BERR %0d  IPL_ASSERTED_CYCLES %0d  ROM_READS total=%0d loop=%0d  VRAM_BEATS %0d",
		         berr_seen, ipl_seen, rom_reads, rom_reads_loop, vram_beats);
		$display("CORE_LAT instr n=%0d sum=%0d | read n=%0d sum=%0d | write n=%0d sum=%0d",
		         lat_count[0], lat_total[0], lat_count[1], lat_total[1], lat_count[2], lat_total[2]);
		begin
			string nm [6];
			nm[0] = "read_line_hit"; nm[1] = "read_first_miss"; nm[2] = "read_bus32";
			nm[3] = "write_direct"; nm[4] = "write_bus32"; nm[5] = "instr";
			for (int c = 0; c < 6; c++) begin
				$display("EXT %s n=%0d sum=%0d mean=%.2f", nm[c], ext_n[c], ext_sum[c],
				         ext_n[c] ? real'(ext_sum[c]) / ext_n[c] : 0.0);
				if (ext_n[c]) begin
					string s; s = "";
					foreach (ext_hist[c][x]) s = {s, $sformatf(" %0d:%0d", x, ext_hist[c][x])};
					$display("EXT_HIST %s%s", nm[c], s);
				end
			end
		end
		foreach (wr32_shape[x]) $display("BUS32_SHAPE class=%0d size=%0d addr[3:0]=%h n=%0d", x[10:8], x[5:4], x[3:0], wr32_shape[x]);
		foreach (wr32_region[x]) $display("BUS32_REGION class=%0d addr=%03h0000 n=%0d", x[14:12], x[11:0], wr32_region[x]);
		$display("WALKER n=%0d sum=%0d", walker_n, walker_sum);
		$display("STOREBUF full_stall_cycles=%0d", sb_full_cyc);
		hist("STOREBUF_OCC", sb_occ);
		$display("BRIDGE ram_reads=%0d read_wait_fifo_cycles=%0d wq_full_cycles=%0d wq_noroom_cycles=%0d write_blocked_by_room=%0d fill_poisoned_pushes=%0d",
		         ram_reads, rd_wait_fifo, wq_full_cyc, wq_noroom_cyc, wr_blocked_room, line_poison);
		hist("BRIDGE_WQ_OCC", wq_occ);
		hist("BRIDGE_WQ_AT_READ", wq_at_read);
		$display("SDRAM rd hit=%0d conflict=%0d closed=%0d | wr hit=%0d conflict=%0d closed=%0d | refresh=%0d busy=%0d/%0d clk_ram",
		         sd_hit[0], sd_conflict[0], sd_closed[0], sd_hit[1], sd_conflict[1], sd_closed[1],
		         sd_refresh, sd_busy, sd_ramcyc);
		if (chip.errors + chip_hi.errors != 0) $fatal(1, "SDRAM protocol errors");
		$finish;
	end
endtask

endmodule
