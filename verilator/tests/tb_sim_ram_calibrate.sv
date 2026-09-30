`timescale 1ns/1ps
// Observe one controlled RAM cache miss through emu, quadra800 and the
// optional RAM-line model. The cache's MMU request is forced; its master bus,
// platform service, and RAM model remain connected normally.
module tb_sim_ram_calibrate;
	reg clk = 0, reset = 1;
	reg stim_req = 0;
	emu dut(.clk_sys(clk), .reset(reset), .sim_status(32'd0),
	        .ps2_key(11'd0), .ps2_mouse(25'd0),
	        .ioctl_download(1'b0), .ioctl_wr(1'b0), .ioctl_addr(25'd0),
	        .ioctl_dout(16'd0), .ioctl_index(8'd0), .sd_ack(3'd0),
	        .sd_buff_addr(13'd0), .sd_buff_dout(16'd0), .sd_buff_wr(1'b0),
	        .img_mounted(3'd0), .img_readonly(1'b0), .img_size(64'd0));
	integer cycle = 0, fill_entry = -100, trace_count = 0;
	integer mem_ack_offset = -1, bus_ack_offset = -1, line_valid_offset = -1;
	integer cpu_ack_offset = -1, tagwrite_offset = -1;
	reg [2:0] prev_cst = 0;
	reg prev_busy = 0, tracing = 0, saw_tagwrite = 0, completed = 0;
	task automatic tick;
		begin clk = 0; #5; clk = 1; #1; cycle = cycle + 1; end
	endtask
	initial begin
		force dut.machine.cpu.mm_req = stim_req;
		force dut.machine.cpu.mm_write = 1'b0;
		force dut.machine.cpu.mm_instr = 1'b0;
		force dut.machine.cpu.mm_size = 2'd2;
		force dut.machine.cpu.mm_addr = 32'h00100000;
		force dut.machine.cpu.mm_nocache = 1'b0;
		force dut.machine.cpu.g_cache.cache.de = 1'b1;
		force dut.machine.overlay = 1'b0;
		repeat (10) tick();
		reset = 0;
		for (integer i = 0; i < 2000 && dut.machine.cpu.g_cache.cache.cst != 0; i = i + 1)
			tick();
		if (dut.machine.cpu.g_cache.cache.cst != 0)
			$fatal(1, "cache sweep did not finish");
		dut.ram[25'h40000] = 32'h11223344;
		dut.ram[25'h40001] = 32'h55667788;
		dut.ram[25'h40002] = 32'h99aabbcc;
		dut.ram[25'h40003] = 32'hddeeff00;
		stim_req = 1;
		for (integer i = 0; i < 100; i = i + 1) begin
			tick();
			if (dut.machine.cpu.g_cache.cache.cst == 4 && prev_cst != 4)
				fill_entry = cycle;
			if (!tracing && dut.ram_model_busy && !prev_busy &&
			    dut.machine.cpu.g_cache.cache.cst == 4 &&
			    cycle - fill_entry < 12 && dut.mem_memsel == 0 &&
			    dut.machine.cpu.g_cache.cache.r_addr[26:4] == dut.mem_addr[26:4]) begin
				tracing = 1;
				$display("CALIBRATE fill_entry=%0d ram_accept=%0d bank=%0d addr=%08h",
				         fill_entry, cycle, dut.machine.cpu.g_cache.cache.r_bank,
				         {dut.mem_addr,2'b00});
			end
			if (tracing) begin
				if (dut.mem_ack_r && mem_ack_offset < 0) mem_ack_offset = cycle - fill_entry;
				if (dut.machine.bus_miss_ack && bus_ack_offset < 0) bus_ack_offset = cycle - fill_entry;
				if (dut.ram_line_valid && line_valid_offset < 0) begin
					line_valid_offset = cycle - fill_entry;
					if (dut.ram_line != {32'h11223344,32'h55667788,32'h99aabbcc,32'hddeeff00})
						$fatal(1, "retained line data wrong");
				end
				if (dut.machine.cpu.g_cache.cache.c_ack && cpu_ack_offset < 0) begin
					cpu_ack_offset = cycle - fill_entry;
					if (dut.machine.cpu.g_cache.cache.c_rdata != 32'h11223344)
						$fatal(1, "critical word data wrong");
					stim_req = 0;
				end
				if (dut.machine.cpu.g_cache.cache.cst == 5 && tagwrite_offset < 0)
					tagwrite_offset = cycle - fill_entry;
				$display("CALIBRATE rel=%0d cst=%0d mem_req=%0d mem_ack_r=%0d bus_miss_ack=%0d line_valid=%0d line_pending=%0d fill_acked=%0d",
				         cycle - fill_entry, dut.machine.cpu.g_cache.cache.cst,
				         dut.mem_req, dut.mem_ack_r, dut.machine.bus_miss_ack,
				         dut.ram_line_valid, dut.ram_line_pending,
				         dut.machine.cpu.g_cache.cache.fill_acked);
				trace_count = trace_count + 1;
				if (dut.machine.cpu.g_cache.cache.cst == 5) saw_tagwrite = 1;
				if (!completed && saw_tagwrite && dut.machine.cpu.g_cache.cache.cst == 0) begin
					if (mem_ack_offset != 5 || bus_ack_offset != 6 ||
					    line_valid_offset != 7 || cpu_ack_offset != 7 ||
					    tagwrite_offset != 10)
						$fatal(1, "calibration offsets changed: mem=%0d bus=%0d line=%0d cpu=%0d tag=%0d",
						       mem_ack_offset, bus_ack_offset, line_valid_offset,
						       cpu_ack_offset, tagwrite_offset);
					$display("tb_sim_ram_calibrate PASS");
					completed = 1;
					$finish;
					#1;
				end
				if (trace_count > 100) $fatal(1, "RAM fill did not complete");
			end
			prev_cst = dut.machine.cpu.g_cache.cache.cst;
			prev_busy = dut.ram_model_busy;
		end
		if (!completed) $fatal(1, "no controlled RAM cache fill observed");
	end
endmodule
