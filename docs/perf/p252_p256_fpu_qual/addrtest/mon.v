module p256mon;
  // counts clocks in which S_FPU_DEC takes P256's inline source / destination path
  wire clk = tb_ap040_program.dut.core.clk;
  integer nsrc = 0, ndst = 0;
  always @(posedge clk) begin
    if (tb_ap040_program.dut.core.state == 8'd153) begin
      if (tb_ap040_program.dut.core.fp_inl_src) nsrc = nsrc + 1;
      if (tb_ap040_program.dut.core.fp_inl_dst) ndst = ndst + 1;
    end
  end
  always @(tb_ap040_program.phase) $display("P256MON before phase %0d: inl_src_clocks=%0d inl_dst_clocks=%0d", tb_ap040_program.phase, nsrc, ndst);
  final $display("P256MON end: inl_src_clocks=%0d inl_dst_clocks=%0d", nsrc, ndst);
endmodule
