// Behavioural stand-in for the Altera altddio_out primitive, so the SDRAM
// controller elaborates outside Quartus.  rtl/sdram.sv uses exactly one
// instance, with datain_h=0 / datain_l=1, to derive SDRAM_CLK: the output is
// datain_h while outclock is high and datain_l while it is low, which for
// those constants is simply ~outclock — a chip clock whose rising edge lands
// in the MIDDLE of an FPGA cycle.  That half-period is where the command
// setup and the read-data hold margin come from at 99 MHz, so a testbench
// that models it any other way is not modelling this design.
module altddio_out #(
  parameter extend_oe_disable = "", parameter intended_device_family = "",
  parameter invert_output = "", parameter lpm_hint = "", parameter lpm_type = "",
  parameter oe_reg = "", parameter power_up_high = "", parameter width = 1
)(
  input  [width-1:0] datain_h,
  input  [width-1:0] datain_l,
  input              outclock,
  input              outclocken,
  input              aclr, input aset, input sclr, input sset, input oe,
  output [width-1:0] dataout
);
  assign dataout = outclock ? datain_h : datain_l;
endmodule
