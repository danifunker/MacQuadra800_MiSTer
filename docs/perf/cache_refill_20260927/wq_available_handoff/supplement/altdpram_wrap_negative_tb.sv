`timescale 1ns/1ps
module altdpram_wrap_tb;
  reg clk=0, we=0;
  reg [2:0] wa=0, ra=0;
  reg [60:0] data=0;
  wire [60:0] q;
  reg [3:0] wp=0; // FIFO write pointer; slot is wp[2:0]
  reg [3:0] edge_wp;
  reg [60:0] expected, old_value, poison;
  integer i;
  always #5 clk=~clk;
  always @(posedge clk) if (we) wp <= wp + 4'd1;

  // Exactly match the frozen sdram_beat32.sv queue's primitive configuration.
  altdpram #(
    .width(61), .widthad(3), .numwords(8),
    .intended_device_family("Cyclone V"), .ram_block_type("MLAB"),
    .indata_aclr("OFF"), .wraddress_aclr("OFF"), .wrcontrol_aclr("OFF"),
    .indata_reg("INCLOCK"), .wraddress_reg("INCLOCK"),
    .wrcontrol_reg("INCLOCK"), .rdaddress_reg("UNREGISTERED"),
    .rdcontrol_reg("UNREGISTERED"), .outdata_reg("UNREGISTERED"),
    .rdaddress_aclr("ON"), .rdcontrol_aclr("ON"),
    .outdata_aclr("ON"), .outdata_sclr("ON"),
    .read_during_write_mode_mixed_ports("NEW_DATA")
  ) dut (
    .wren(we), .data(data), .wraddress(wa ^ 3'd1),
    .inclock(clk), .inclocken(1'b1),
    .rden(1'b1), .rdaddress(ra),
    .wraddressstall(1'b0), .rdaddressstall(1'b0), .byteena(1'b1),
    .outclock(1'b1), .outclocken(1'b1), .aclr(1'b0), .sclr(1'b0), .q(q)
  );

  initial begin
    // Each write is presented before an edge at the FIFO's current slot.
    // The four-bit pointer advances immediately after that edge, like wq_wp.
    for (i=0; i<256; i=i+1) begin
      @(negedge clk);
      expected = 61'h123456789abcdef ^ i;
      edge_wp = wp;
      old_value = dut.mem_data[edge_wp[2:0]];
      wa = edge_wp[2:0]; ra = wp[2:0]; data = expected; we = 1'b1;
      #1;
      if (dut.mem_data[edge_wp[2:0]] !== old_value || q !== old_value)
        $fatal(1,"early write before edge iter=%0d slot=%0d q=%h old=%h",i,edge_wp[2:0],q,old_value);

      @(posedge clk); #0.1;
      if (dut.mem_data[edge_wp[2:0]] !== expected)
        $fatal(1,"captured write missing iter=%0d slot=%0d got=%h expected=%h",i,edge_wp[2:0],dut.mem_data[edge_wp[2:0]],expected);
      if (wp !== (edge_wp + 4'd1))
        $fatal(1,"FIFO pointer did not advance on write edge iter=%0d old=%d new=%d",i,edge_wp,wp);
      if (q !== expected)
        $fatal(1,"async read not valid just after write edge iter=%0d slot=%0d q=%h expected=%h",i,wa,q,expected);

      // The FIFO advances its source address on this write edge. Poison the
      // external input immediately; registered address/data/control must hold.
      poison = ~expected;
      wa = wp[2:0]; data = poison; we = 1'b0;
      #0.1;
      if (dut.mem_data[edge_wp[2:0]] !== expected)
        $fatal(1,"post-edge input change altered written slot iter=%0d",i);

      // One 10 ns clock after capture, the original slot remains readable.
      @(posedge clk); #0.1;
      if (q !== expected)
        $fatal(1,"read not valid 10.1ns after write edge iter=%0d slot=%0d q=%h expected=%h",i,edge_wp[2:0],q,expected);
      ra = edge_wp[2:0]; #0.1;
      if (q !== expected)
        $fatal(1,"asynchronous read failed after address selection iter=%0d q=%h expected=%h",i,q,expected);
    end
    $display("PASS actual altdpram model: 256 posedge writes, 32 slot wraps; no early writes, captured address/data retained, async reads valid immediately and 10.1ns later");
    $finish;
  end
endmodule
