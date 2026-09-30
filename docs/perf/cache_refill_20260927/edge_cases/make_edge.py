from pathlib import Path
import sys

script = Path(__file__).resolve()
root = next(p for p in script.parents if (p / 'rtl/ap68040/tb/tb_ap040_cache_snoop.v').is_file())
source = (root / 'rtl/ap68040/tb/tb_ap040_cache_snoop.v').read_text()
source = source.split('integer i, off;')[0]
source = source.replace('module tb_ap040_cache_snoop;', 'module tb_edge_cases;', 1)
source = source.replace('.m_line_data(m_line_data), .m_err(m_err),',
                        '.m_line_data(m_line_data), .m_err(m_err | inject_err),', 1)
source = source.replace('ap040_cache dut\n',
                        'wire c_line_stb;\nwire [31:4] c_line_tag;\nwire [127:0] c_line_data;\nap040_cache dut\n', 1)
source = source.replace('.c_ack(c_ack), .c_rdata(c_rdata),',
                        '.c_ack(c_ack), .c_rdata(c_rdata),\n'
                        '    .c_line_stb(c_line_stb), .c_line_tag(c_line_tag), .c_line_data(c_line_data),', 1)
source = source.replace(".c_fc(3'd5)", ".c_fc(c_instr ? 3'd6 : 3'd5)", 1)
source = source.replace('reg [31:0] mem [0:16383];',
                        'reg [31:0] mem [0:16383];\nreg [31:0] rom [0:16383];', 1)
source = source.replace('else m_rdata <= mem[m_addr[15:2]];',
                        "else m_rdata <= m_addr[31:28] == 4'h4 ? rom[m_addr[15:2]] : mem[m_addr[15:2]];", 1)
source += '\nreg inject_err = 0;\n'
source += (script.parent / 'edge_stim.sv').read_text()
out = Path(sys.argv[1]) if len(sys.argv) > 1 else script.parent / 'tb_edge_cases.sv'
out.write_text(source)
