	//------------------------------------------------------------------------
	// p260_qual_20260929: T_P260b, the ROM's boot-time read shape.  READ(10)
	// of 4 blocks on a slow device (3000-clock round trip); per sector the
	// driver takes 2 bytes by non-DMA TI ($10), then 510 by DMA TI, then
	// flushes the FIFO twice and issues the next sector's first non-DMA TI
	// BEFORE the prefetched sector has landed.  The last sector must be
	// handed over byte for byte; STATUS only after its last byte.
	//------------------------------------------------------------------------
	$display("-- T_P260b ROM boot read shape: 2 PIO bytes + 510 DMA per sector, next PIO TI issued before the sector lands");
	begin : p260b
		integer fails0, sec, kk, g, lb, nb;
		reg [7:0] bb, want;
		fails0 = fails; lb = 48; nb = 4;
		dev_lat = 3000;
		sel_id = 8'h00;
		reg_wr(R_CMD, 8'h02); repeat (4) @(negedge clk);
		cdb[0]=8'h28; cdb[1]=0; cdb[2]=0; cdb[3]=0; cdb[4]=0; cdb[5]=lb[7:0]; cdb[6]=0; cdb[7]=0; cdb[8]=nb[7:0]; cdb[9]=0;
		unix_select(8'h42, 10, 1);
		wait_irq(4000, ok);
		read_regs(st, sp, it2);
		expect8("T_P260b phase DATA IN", {5'd0, st[2:0]}, {5'd0, PH_DIN});
		for (sec = 0; sec < nb && fails == fails0; sec = sec + 1) begin
			for (kk = 0; kk < 2; kk = kk + 1) begin
				g = sec * 512 + kk;
				reg_wr(R_CMD, 8'h10);
				wait_irq(40000, ok);
				read_regs(st, sp, it2);
				reg_rd(R_FIFO, bb);
				want = disk[lb*512 + g];
				checks = checks + 1;
				if (bb !== want || (st[2:0] != PH_DIN && st[2:0] != PH_STAT)) begin
					fails = fails + 1;
					$display("  FAIL T_P260b sector %0d PIO byte %0d: got %02X want %02X, phase %0d intr %02X (blocks_left=%0d pf_valid=%0d buf_valid=%0d sbuf_pos=%0d)",
					         sec, kk, bb, want, st[2:0], it2, dut.blocks_left, dut.pf_valid, dut.buf_valid, dut.sbuf_pos);
				end
				if (st[2:0] == PH_STAT) begin
					fails = fails + 1;
					$display("  FAIL T_P260b STATUS after PIO byte %0d of sector %0d (of %0d): the command ended with %0d bytes unread", kk, sec, nb, nb*512 - g - 1);
					kk = 2; sec = nb;
				end
			end
			if (sec < nb) begin
				set_tc(16'd510);
				reg_wr(R_CMD, 8'h90);
				for (kk = 2; kk < 512; kk = kk + 1) begin
					g = sec * 512 + kk;
					pdma_rd(bb);
					want = disk[lb*512 + g];
					checks = checks + 1;
					if (bb !== want) begin
						fails = fails + 1;
						if (fails < fails0 + 6) $display("  FAIL T_P260b sector %0d DMA byte %0d: got %02X want %02X", sec, kk, bb, want);
					end
				end
				wait_irq(200000, ok);
				read_regs(st, sp, it2);
				expect8("T_P260b phase after the sector", {5'd0, st[2:0]}, {5'd0, (sec == nb - 1) ? PH_STAT : PH_DIN});
				reg_wr(R_CMD, 8'h01); reg_wr(R_CMD, 8'h01);
			end
		end
		if (st[2:0] != PH_STAT) begin
			guard = 0;
			while (st[2:0] != PH_STAT && guard < 100000) begin @(negedge clk); guard = guard + 1; read_regs(st, sp, it2); end
		end
		reg_wr(R_CMD, 8'h11); wait_irq(4000, ok);
		reg_rd(R_FIFO, bb); reg_rd(R_FIFO, bb);
		reg_wr(R_CMD, 8'h12); wait_irq(4000, ok); read_regs(st, sp, it2);
		dev_lat = 40;
		$display("T_P260b RESULT: %0s (failures added %0d)", (fails == fails0) ? "PASS" : "FAIL", fails - fails0);
	end
	sel_id = 8'h00;

