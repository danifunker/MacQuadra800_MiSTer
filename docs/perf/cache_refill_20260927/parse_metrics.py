from pathlib import Path
import csv
import re
import sys

path = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).with_name("integrated_run.log")
cases = {}
for line in path.read_text().splitlines():
    if line.startswith("CASE "):
        fields = dict(re.findall(r"(\w+)=([^ ]+)", line))
        cases[int(fields["id"])] = {
            "id": fields["id"], "sideband": fields["sideband"],
            "instr": fields["instr"], "address": fields["addr"],
            "start_word": str((int(fields["addr"], 16) >> 2) & 3),
            "span": str(int((int(fields["addr"], 16) & 3) != 0)),
        }
    elif line.startswith("EVENT "):
        fields = dict(re.findall(r"(\w+)=([^ ]+)", line))
        row = cases[int(fields["case"])]
        event = fields["kind"]
        if event == "fill_step":
            row[f"fill{fields['count']}"] = fields["rel"]
            row[f"source{fields['count']}"] = line.split("source=", 1)[1].strip()
        elif event == "fill_enter":
            row["way"] = fields["way"]
        elif event in ("sdr_ack", "bus_ack", "line_valid", "critical_ack", "tag_commit"):
            row[event] = fields["rel"]

columns = [
    "id", "sideband", "instr", "address", "start_word", "span", "way",
    "sdr_ack", "bus_ack", "line_valid", "fill0", "fill1", "fill2", "fill3",
    "source0", "source1", "source2", "source3", "critical_ack", "tag_commit",
]
out = path.with_suffix(".csv")
with out.open("w", newline="") as f:
    writer = csv.DictWriter(f, fieldnames=columns)
    writer.writeheader()
    writer.writerows(cases[i] for i in sorted(cases))
print(out)
