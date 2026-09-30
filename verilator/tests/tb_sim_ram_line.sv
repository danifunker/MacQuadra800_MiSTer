`timescale 1ns/1ps
// Directed test of sim.v's opt-in RAM-line port, with the machine beat wires
// forced to controlled requests. Run with +ram_line_model +ram_first_latency=3
// +ram_line_publish_delay=2; the test also switches to latency 1 after poison.
module tb_sim_ram_line;
	reg clk = 0, reset = 1;
	reg req = 0, wr = 0, wp = 0;
	reg [31:2] addr = 0, wp_addr = 0;
	reg [31:0] wdata = 0, wp_data = 0;
	reg [3:0] be = 4'hf, wp_be = 4'hf;
	reg [1:0] sel = 0;
	emu dut(.clk_sys(clk), .reset(reset), .sim_status(32'd0),
	        .ps2_key(11'd0), .ps2_mouse(25'd0),
	        .ioctl_download(1'b0), .ioctl_wr(1'b0), .ioctl_addr(25'd0),
	        .ioctl_dout(16'd0), .ioctl_index(8'd0), .sd_ack(3'd0),
	        .sd_buff_addr(13'd0), .sd_buff_dout(16'd0), .sd_buff_wr(1'b0),
	        .img_mounted(3'd0), .img_readonly(1'b0), .img_size(64'd0));

	task automatic tick;
		begin clk = 0; #5; clk = 1; #1; end
	endtask
	task automatic check(input bit ok, input string what);
		if (!ok) $fatal(1, "%s", what);
	endtask
	task automatic release_request;
		begin
			req = 0;
			// Allow both the held-request guard and the pending line to drain.
			repeat (5) tick();
			check(!dut.ram_model_busy, "request guard did not release");
		end
	endtask
	task automatic read_word(input [31:2] a, input [31:0] expected);
		integer i;
		begin
			addr = a; wr = 0; req = 1;
			for (i = 1; i <= dut.ram_first_latency; i = i + 1) begin
				tick();
				check(dut.mem_ack_r == (i == dut.ram_first_latency), "first-read ack timing");
			end
			check(dut.mem_rdata_r == expected, "word rotation/read data");
			tick();
			check(!dut.mem_ack_r, "repeated ack on held request");
			release_request();
		end
	endtask

	initial begin
		force dut.mem_req = req;
		force dut.mem_write = wr;
		force dut.mem_addr = addr;
		force dut.mem_memsel = sel;
		force dut.mem_be = be;
		force dut.mem_wdata = wdata;
		force dut.mem_wp_valid = wp;
		force dut.mem_wp_addr = wp_addr;
		force dut.mem_wp_be = wp_be;
		force dut.mem_wp_data = wp_data;
		tick(); reset = 0;
		if (!dut.ram_line_model) begin
			dut.ram[0] = 32'h11223344;
			addr = 0; req = 1;
			tick(); check(dut.mem_ack_r && dut.mem_rdata_r == 32'h11223344,
			              "default beat-port response changed");
			tick(); check(!dut.mem_ack_r && !dut.ram_line_valid,
			              "default mode exposed retained line");
			$display("tb_sim_ram_line default PASS");
			$finish;
			#1;
		end
		check(dut.ram_first_latency == 3 && dut.ram_line_publish_delay == 2,
		      "test requires latency=3 publish_delay=2");
		dut.ram[0] = 32'h11223344;
		dut.ram[1] = 32'h55667788;
		dut.ram[2] = 32'h99aabbcc;
		dut.ram[3] = 32'hddeeff00;
		addr = 2; req = 1;
		tick(); check(dut.ram_line_pending && !dut.mem_ack_r, "pending at first read");
		tick(); check(!dut.mem_ack_r, "early first-read ack");
		tick(); check(dut.mem_ack_r && dut.mem_rdata_r == 32'h99aabbcc,
		              "first-read ack/data");
		check(dut.ram_line_pending && !dut.ram_line_valid, "premature line publication");
		tick(); check(dut.ram_line_pending && !dut.mem_ack_r, "pending after ack");
		tick(); check(dut.ram_line_valid && !dut.ram_line_pending, "late line publication");
		check(dut.ram_line == {32'h11223344,32'h55667788,32'h99aabbcc,32'hddeeff00},
		      "four-word line order");
		tick(); check(!dut.mem_ack_r, "duplicate held-request ack");
		release_request();
		read_word(0, 32'h11223344);
		read_word(1, 32'h55667788);
		read_word(3, 32'hddeeff00);

		// A posted write while the first read is delayed poisons the line,
		// but the read still completes from the updated RAM word.
		addr = 16; req = 1; wr = 0;
		dut.ram[16] = 32'h01020304;
		tick(); check(dut.ram_line_pending, "poison test pending");
		wp = 1; wp_addr = 16; wp_data = 32'hcafebabe;
		tick(); wp = 0;
		check(!dut.ram_line_pending && dut.ram_model_poisoned, "posted-write poison");
		tick(); check(dut.mem_ack_r && dut.mem_rdata_r == 32'hcafebabe,
		              "poisoned read still acked with updated data");
		tick(); check(!dut.ram_line_valid, "poisoned line published");
		release_request();
		// A posted write exactly when the delayed read would complete must
		// defer that ack; the request then completes once the write has landed.
		addr = 20; req = 1; dut.ram[20] = 32'h01010101;
		tick();
		tick();
		wp = 1; wp_addr = 20; wp_data = 32'h02020202;
		tick(); check(!dut.mem_ack_r && dut.ram_model_poisoned,
		              "posted write on ack edge did not defer/poison");
		wp = 0;
		tick(); check(dut.mem_ack_r && dut.mem_rdata_r == 32'h02020202,
		              "deferred read ack/data missing");
		release_request();

		// This next read completes on its acceptance edge. It must not inherit
		// the preceding request's poisoned flag.
		dut.ram_first_latency = 1;
		read_word(20, 32'h02020202);
		check(dut.ram_line_valid, "latency-one read inherited poison");

		// A write coincident with the publication edge wins over publication.
		dut.ram_line_publish_delay = 2;
		addr = 32; dut.ram[32] = 32'h11224488; req = 1;
		tick(); check(dut.mem_ack_r && dut.ram_line_pending, "publish conflict setup");
		tick(); check(dut.ram_line_pending && !dut.ram_line_valid,
		              "line published before conflict edge");
		wp = 1; wp_addr = 32; wp_data = 32'h88774422;
		tick(); wp = 0;
		check(!dut.ram_line_valid && !dut.ram_line_pending && dut.ram[32] == 32'h88774422,
		              "write coincident with publication must invalidate");
		release_request();

		// Beat-port write invalidation and reset before/after read ack.
		read_word(32, 32'h88774422);
		check(dut.ram_line_valid, "line not valid before beat write");
		addr = 32; wr = 1; wdata = 32'h12345678; req = 1;
		tick(); check(dut.mem_ack_r && !dut.ram_line_valid, "beat write invalidation");
		release_request(); wr = 0;
		dut.ram_first_latency = 3;
		addr = 48; req = 1;
		tick(); check(dut.ram_line_pending, "reset test pending");
		reset = 1; req = 0;
		tick(); check(!dut.ram_line_valid && !dut.ram_line_pending && !dut.ram_model_busy,
		              "reset before ack did not clear pending line");
		reset = 0;
		dut.ram_first_latency = 1;
		addr = 48; req = 1;
		tick(); check(dut.mem_ack_r && dut.ram_line_pending, "post-ack reset setup");
		reset = 1; req = 0;
		tick(); check(!dut.ram_line_valid && !dut.ram_line_pending && !dut.ram_model_busy,
		              "reset after ack did not clear pending line");
		$display("tb_sim_ram_line PASS");
		$finish;
	end
endmodule
