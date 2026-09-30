`timescale 1ns/1ps
module altdpram_edge_tb;
  reg clk=0, we=0; reg [2:0] wa=0,ra=0; reg [60:0] d=0; wire [60:0] q;
  always #5 clk=~clk;
  altdpram #(.width(61),.widthad(3),.numwords(8),.intended_device_family("Cyclone V"),.ram_block_type("MLAB"),.indata_aclr("OFF"),.wraddress_aclr("OFF"),.wrcontrol_aclr("OFF"),.indata_reg("INCLOCK"),.wraddress_reg("INCLOCK"),.wrcontrol_reg("INCLOCK"),.rdaddress_reg("UNREGISTERED"),.rdcontrol_reg("UNREGISTERED"),.outdata_reg("UNREGISTERED"),.read_during_write_mode_mixed_ports("NEW_DATA")) dut(.wren(we),.data(d),.wraddress(wa),.inclock(clk),.inclocken(1'b1),.rden(1'b1),.rdaddress(ra),.wraddressstall(1'b0),.rdaddressstall(1'b0),.byteena(1'b1),.outclock(1'b1),.outclocken(1'b1),.aclr(1'b0),.sclr(1'b0),.q(q));
  initial begin
    @(negedge clk); we=1; wa=3; ra=3; d=61'h123456789abcdef;
    @(posedge clk); #1;
    if(q !== 61'h123456789abcdef) $fatal(1,"write missing at posedge: %h",q);
    // Change external inputs immediately after edge. The registered write must remain in slot 3.
    wa=4; d=61'h555555555555555; we=0;
    #1; ra=3;
    if(q !== 61'h123456789abcdef) $fatal(1,"payload/address not captured at posedge: %h",q);
    $display("PASS altdpram write captured on posedge, asynchronous read follows address");
    $finish;
  end
endmodule
