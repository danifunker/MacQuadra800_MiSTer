from pathlib import Path
import sys

script = Path(__file__).resolve()
root = next(p for p in script.parents if (p / "verilator/tb_memory_path.sv").is_file())
src = (root / "verilator/tb_memory_path.sv").read_text()
src = src.split("task automatic write32")[0]
src = src.replace("module tb_memory_path #(", "module refill_platform #(", 1)
src = src.replace(
    "parameter integer REGISTERED_LINE_HIT = 0\n);",
    """parameter integer REGISTERED_LINE_HIT = 0
) (
    output reg clk_sys = 0, output reg clk_ram = 0,
    input nreset, input init,
    input t_req, input t_write, input [1:0] t_size,
    input [31:0] t_addr, input [31:0] t_wdata,
    output t_ack, output [31:0] t_rdata,
    output sdr_busy, output line_valid, output [26:4] line_tag,
    output [127:0] line_data, output line_pending
);""",
    1,
)
for line in (
    "reg clk_ram = 0;\n", "reg clk_sys = 0;\n",
    "reg nreset = 0;\n", "reg init = 1;\n",
    "reg t_req = 0;\n", "reg t_write = 0;\n",
    "reg [1:0] t_size = 2'd2;\n", "reg [31:0] t_addr = 0;\n",
    "reg [31:0] t_wdata = 0;\n", "wire t_ack;\n",
    "wire [31:0] t_rdata;\n", "wire sdr_busy;\n",
    "wire line_valid;\n", "wire [26:4] line_tag;\n",
    "wire [127:0] line_data;\n", "wire line_pending;\n",
):
    assert line in src, line
    src = src.replace(line, "", 1)
src += "\nendmodule\n"
out = Path(sys.argv[1]) if len(sys.argv) > 1 else script.parent / "refill_platform.sv"
out.write_text(src)
