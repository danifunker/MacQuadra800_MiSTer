from pathlib import Path
import sys

script = Path(__file__).resolve()
root = next(p for p in script.parents if (p / "rtl/ap68040/tb/tb_ap040_cache_snoop.v").is_file())
source = (root / "rtl/ap68040/tb/tb_ap040_cache_snoop.v").read_text()
source = source.split("integer i, off;")[0]
source = source.replace("module tb_ap040_cache_snoop;", "module tb_bulk_boundary;", 1)
source = source.replace(".m_line_data(m_line_data), .m_err(m_err),",
                        ".m_line_data(m_line_data), .m_err(m_err | inject_err),", 1)
source += "\nreg inject_err = 0;\n"
source += (script.parent / "boundary_stim.sv").read_text()
out = Path(sys.argv[1]) if len(sys.argv) > 1 else script.parent / "tb_bulk_boundary.sv"
out.write_text(source)
