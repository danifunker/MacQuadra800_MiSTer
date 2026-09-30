	//------------------------------------------------------------------------
	// p260_qual_20260929: T_P260, the two-half sector buffer under random
	// platform latency and a randomly pausing guest.  Six rounds, alternating
	// the guest protocol: even rounds one TI for all 8 blocks (TC=4096), odd
	// rounds one TI per sector with the interrupt taken between sectors (the
	// System 7.5.5 SCSI Manager's shape).  Each round: READ(10) of 8 blocks
	// at lba 48 (every byte checked against the device), then WRITE(10) of 8
	// blocks at lba 24 (data, LBA order, STATUS only after the last flush's
	// ack fell).  Every platform request is acked after a random 200..2000
	// clocks; the guest pauses per sector at random (none / light / heavy).
	//------------------------------------------------------------------------
	$display("-- T_P260 two-half buffer: READ(10)/WRITE(10) of 8 blocks, random 200-2000-clock acks, random guest pauses");
	begin : p260
		integer rep, mode, kk, g, sec, nsec, tcn, nb, lb, rnd, pmode, fails0, pf0, ovl0, wcc0, wccfp0, nw0, j, req0, ovl_tot;
		reg [7:0] bb, want;
		reg [63:0] irq_cyc;
		fails0 = fails; ovl_tot = 0;
		nb = 8;
		rnd = 32'h0260_2929;
		for (rep = 0; rep < 6; rep = rep + 1) begin
			mode = rep % 2;
			nsec = mode ? nb : 1;
			tcn  = mode ? 512 : nb * 512;
			// ================= READ(10) of 8 blocks at lba 48
			lb = 48;
			p6_dlcg = 32'h0000_1000 + rep * 977;
			p6_on = 1;
			pf0 = p6_pf_rise; ovl0 = p6_pf_ovl; req0 = p6_nreq;
			sel_id = 8'h00;
			reg_wr(R_CMD, 8'h02); repeat (4) @(negedge clk);
			cdb[0]=8'h28; cdb[1]=0; cdb[2]=0; cdb[3]=0; cdb[4]=0; cdb[5]=lb[7:0]; cdb[6]=0; cdb[7]=0; cdb[8]=nb[7:0]; cdb[9]=0;
			unix_select(8'h42, 10, 1);
			wait_irq(4000, ok);
			read_regs(st, sp, it2);
			expect8("T_P260 read phase DATA IN", {5'd0, st[2:0]}, {5'd0, PH_DIN});
			for (sec = 0; sec < nsec; sec = sec + 1) begin
				set_tc(tcn[15:0]);
				reg_wr(R_CMD, 8'h90);
				for (kk = 0; kk < tcn; kk = kk + 1) begin
					g = mode ? sec * 512 + kk : kk;
					if (g % 512 == 0) begin rnd = rnd * 1103515245 + 12345; pmode = (rnd >> 16) % 3; end
					pdma_rd(bb);
					want = disk[lb*512 + g];
					checks = checks + 1;
					if (bb !== want) begin
						fails = fails + 1;
						if (fails < fails0 + 8) $display("  FAIL T_P260 rep=%0d read byte %0d (block %0d): got %02X want %02X", rep, g, g/512, bb, want);
					end
					rnd = rnd * 1103515245 + 12345;
					if (pmode == 1 && ((rnd >> 16) % 64) == 0) repeat (10 + ((rnd >> 22) % 200)) @(negedge clk);
					if (pmode == 2 && ((rnd >> 16) % 16) == 0) repeat (50 + ((rnd >> 22) % 600)) @(negedge clk);
				end
				wait_irq(200000, ok);
				read_regs(st, sp, it2);
				if (sec < nsec - 1) expect8("T_P260 read mid-command phase DATA IN", {5'd0, st[2:0]}, {5'd0, PH_DIN});
			end
			expect8("T_P260 read phase STATUS", {5'd0, st[2:0]}, {5'd0, PH_STAT});
			reg_wr(R_CMD, 8'h11); wait_irq(4000, ok);
			reg_rd(R_FIFO, bb); expect8("T_P260 read status GOOD", bb, 8'h00);
			reg_rd(R_FIFO, bb);
			reg_wr(R_CMD, 8'h12); wait_irq(4000, ok); read_regs(st, sp, it2);
			$display("   T_P260 rep %0d (%0s) READ : requests %0d, prefetches %0d, raised while the guest was still draining %0d",
			         rep, mode ? "TI per sector" : "one TI", p6_nreq - req0, p6_pf_rise - pf0, p6_pf_ovl - ovl0);
			checks = checks + 1;
			if (p6_nreq - req0 != nb) begin fails = fails + 1; $display("  FAIL T_P260 rep=%0d read made %0d requests (want %0d)", rep, p6_nreq - req0, nb); end
			ovl_tot = ovl_tot + (p6_pf_ovl - ovl0);

			// ================= WRITE(10) of 8 blocks at lba 24
			lb = 24;
			p6_dlcg = 32'h0000_7000 + rep * 1231;
			nw0 = p6_nw; wcc0 = p6_wcc; wccfp0 = p6_wcc_fp; req0 = p6_nreq;
			reg_wr(R_CMD, 8'h02); repeat (4) @(negedge clk);
			cdb[0]=8'h2A; cdb[1]=0; cdb[2]=0; cdb[3]=0; cdb[4]=0; cdb[5]=lb[7:0]; cdb[6]=0; cdb[7]=0; cdb[8]=nb[7:0]; cdb[9]=0;
			unix_select(8'h42, 10, 1);
			wait_irq(4000, ok);
			read_regs(st, sp, it2);
			expect8("T_P260 write phase DATA OUT", {5'd0, st[2:0]}, {5'd0, PH_DOUT});
			reg_wr(R_CMD, 8'h01);
			irq_cyc = 0;
			for (sec = 0; sec < nsec; sec = sec + 1) begin
				set_tc(tcn[15:0]);
				reg_wr(R_CMD, 8'h90);
				for (kk = 0; kk < tcn; kk = kk + 1) begin
					g = mode ? sec * 512 + kk : kk;
					if (g % 512 == 0) begin rnd = rnd * 1103515245 + 12345; pmode = (rnd >> 16) % 3; end
					guard = 0;
					while (!drq && guard < 200000) begin @(negedge clk); guard = guard + 1; end
					if (guard >= 200000) begin
						fails = fails + 1;
						$display("  FAIL T_P260 rep=%0d WRITE DREQ never returned at byte %0d", rep, g);
						kk = tcn; sec = nsec;
					end
					else begin
						pdma_wr((g*13 + rep*29 + (g >> 9)) & 8'hFF);
						rnd = rnd * 1103515245 + 12345;
						if (pmode == 1 && ((rnd >> 16) % 64) == 0) repeat (10 + ((rnd >> 22) % 200)) @(negedge clk);
						if (pmode == 2 && ((rnd >> 16) % 16) == 0) repeat (50 + ((rnd >> 22) % 600)) @(negedge clk);
					end
				end
				wait_irq(200000, ok);
				irq_cyc = p6_cyc;
				read_regs(st, sp, it2);
				if (sec < nsec - 1) expect8("T_P260 write mid-command phase DATA OUT", {5'd0, st[2:0]}, {5'd0, PH_DOUT});
			end
			// the last chunk's interrupt must follow the last flush's ack fall
			checks = checks + 1;
			if (!(irq_cyc > p6_wr_ackfall) || p6_nw - nw0 != nb) begin
				fails = fails + 1;
				$display("  FAIL T_P260 rep=%0d last chunk interrupt at %0d, last flush ack fell at %0d, flushes done %0d",
				         rep, irq_cyc, p6_wr_ackfall, p6_nw - nw0);
			end
			guard = 0;
			while (st[2:0] != PH_STAT && guard < 400000) begin @(negedge clk); guard = guard + 1; read_regs(st, sp, it2); end
			expect8("T_P260 write phase STATUS", {5'd0, st[2:0]}, {5'd0, PH_STAT});
			// the phase bits read STATUS from the moment the last flush is RAISED
			// (pre-P260 behaviour, for the ROM's PIO write loop); informational
			if (p6_stat_cyc < p6_wr_ackfall) p6_phase_early = p6_phase_early + 1;
			reg_wr(R_CMD, 8'h11); wait_irq(4000, ok);
			// the status byte is delivered (I_FC) only after the last flush's ack fell, all 8 accepted
			checks = checks + 1;
			if (!(p6_cyc > p6_wr_ackfall) || p6_nw - nw0 != nb) begin
				fails = fails + 1;
				$display("  FAIL T_P260 rep=%0d status delivered at %0d, last flush ack fell at %0d, flushes done %0d", rep, p6_cyc, p6_wr_ackfall, p6_nw - nw0);
			end
			reg_rd(R_FIFO, bb); expect8("T_P260 write status GOOD", bb, 8'h00);
			reg_rd(R_FIFO, bb);
			reg_wr(R_CMD, 8'h12); wait_irq(4000, ok); read_regs(st, sp, it2);
			p6_on = 0;
			// the LBA sequence the device accepted, in order
			for (j = 0; j < nb; j = j + 1) begin
				checks = checks + 1;
				if (p6_wlba[nw0 + j] != lb + j) begin
					fails = fails + 1;
					$display("  FAIL T_P260 rep=%0d flush %0d went to lba %0d (want %0d)", rep, j, p6_wlba[nw0 + j], lb + j);
				end
			end
			// the flushed data
			for (g = 0; g < nb * 512; g = g + 1) begin
				checks = checks + 1;
				if (disk[lb*512 + g] !== ((g*13 + rep*29 + (g >> 9)) & 8'hFF)) begin
					fails = fails + 1;
					if (fails < fails0 + 16) $display("  FAIL T_P260 rep=%0d disk byte %0d (block %0d): got %02X want %02X", rep, g, g/512, disk[lb*512 + g], (g*13 + rep*29 + (g >> 9)) & 8'hFF);
				end
			end
			$display("   T_P260 rep %0d (%0s) WRITE: flushes %0d (lba %0d..%0d in order), chunk completions %0d, with a flush in flight %0d; last-chunk INT %0d clk after the last ack fell (phase bits read STATUS %0d clk before it)",
			         rep, mode ? "TI per sector" : "one TI", p6_nw - nw0, p6_wlba[nw0], p6_wlba[nw0 + nb - 1],
			         p6_wcc - wcc0, p6_wcc_fp - wccfp0, irq_cyc - p6_wr_ackfall, p6_wr_ackfall - p6_stat_cyc);
		end
		checks = checks + 1;
		if (ovl_tot == 0) begin fails = fails + 1; $display("  FAIL T_P260 no prefetch overlapped a guest drain"); end
		$display("   T_P260 info: the phase bits turned STATUS while the last flush was outstanding in %0d of 6 writes (flush raised -> phase STATUS, unchanged from before P260)", p6_phase_early);
		// ---- informational: a POLLING initiator (watches the phase bits, never waits
		// for the chunk INT) issues ICCS as soon as it sees STATUS
		begin : p260_poll
			integer nwp;
			reg [63:0] fc_cyc;
			lb = 24; p6_dlcg = 32'h0000_9999; p6_on = 1; nwp = p6_nw;
			reg_wr(R_CMD, 8'h02); repeat (4) @(negedge clk);
			cdb[0]=8'h2A; cdb[1]=0; cdb[2]=0; cdb[3]=0; cdb[4]=0; cdb[5]=lb[7:0]; cdb[6]=0; cdb[7]=0; cdb[8]=nb[7:0]; cdb[9]=0;
			unix_select(8'h42, 10, 1);
			wait_irq(4000, ok); read_regs(st, sp, it2);
			reg_wr(R_CMD, 8'h01); set_tc(16'd4096); reg_wr(R_CMD, 8'h90);
			for (g = 0; g < nb * 512; g = g + 1) begin
				guard = 0;
				while (!drq && guard < 200000) begin @(negedge clk); guard = guard + 1; end
				pdma_wr((g*7 + 5) & 8'hFF);
			end
			guard = 0; reg_peek(R_STAT, st);
			while (st[2:0] != PH_STAT && guard < 400000) begin guard = guard + 1; reg_peek(R_STAT, st); end
			reg_wr(R_CMD, 8'h11);
			guard = 0;
			while (!(irq && dut.istatus[3]) && guard < 400000) begin @(negedge clk); guard = guard + 1; end
			fc_cyc = p6_cyc;
			$display("   T_P260 info (polling initiator): ICCS issued on seeing STATUS; I_FC at %0d with %0d of 8 flushes accepted, last flush ack fell at %0d -> status %0s the data was accepted",
			         fc_cyc, p6_nw - nwp, p6_wr_ackfall, (p6_nw - nwp == nb && fc_cyc > p6_wr_ackfall) ? "AFTER" : "BEFORE");
			p6_on = 0;
		end
		$display("   T_P260 total: prefetches overlapping a drain %0d (most bytes left to drain at one: %0d), failures added %0d", ovl_tot, p6_rem_max, fails - fails0);
		$display("T_P260 RESULT: %0s", (fails == fails0) ? "PASS" : "FAIL");
	end
	sel_id = 8'h00;

