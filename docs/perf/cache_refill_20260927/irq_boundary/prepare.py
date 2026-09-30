"""Generate direct test-only retained-line ports for the AP040 CPU bench."""
from pathlib import Path

here = Path(__file__).resolve().parent
repo = next(p for p in here.parents if (p / 'MacQuadra800.qsf').is_file())
wrapper = (repo / 'rtl/ap68040/rtl/ap040_tg68k_compat.v').read_text()
bench = (repo / 'rtl/ap68040/tb/tb_ap040_program.v').read_text()

old = '\tinput         berr,\n'
new = old + '\tinput         retained_line_valid,\n\tinput [31:4]  retained_line_tag,\n\tinput [127:0] retained_line_data,\n'
assert wrapper.count(old) == 1
wrapper = wrapper.replace(old, new, 1)
old = ".m_line_valid(1'b0),\n\t\t.m_line_tag(28'd0),\n\t\t.m_line_data(128'd0),"
new = '.m_line_valid(retained_line_valid),\n\t\t.m_line_tag(retained_line_tag),\n\t\t.m_line_data(retained_line_data),'
assert wrapper.count(old) == 1
wrapper = wrapper.replace(old, new, 1)

old = '\t.berr(berr),\n'
new = old + '\t.retained_line_valid(tb_line_valid_to_cache),\n\t.retained_line_tag(tb_line_tag),\n\t.retained_line_data(tb_line_data),\n'
assert bench.count(old) == 1
bench = bench.replace(old, new, 1)
old = 'reg clk = 0;\n'
new = old + '''reg tb_line_valid = 0;
reg [31:4] tb_line_tag = 0;
reg [127:0] tb_line_data = 0;
wire tb_line_valid_to_cache = nreset && tb_line_valid &&
    !(busstate == 2'b11) && !(walker_req && walker_we) &&
    !dut.g_cache.cache.m_write;
'''
assert bench.count(old) == 1
bench = bench.replace(old, new, 1)
assert bench.rstrip().endswith('endmodule')
bench = bench.rstrip()[:-len('endmodule')] + (here / 'retained_stim.sv').read_text() + '\nendmodule\n'
(here / 'ap040_tg68k_retained.v').write_text(wrapper)
(here / 'tb_ap040_program_retained.v').write_text(bench)
