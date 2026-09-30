#!/usr/bin/env python3
"""Apply exact attempt2 host delta to a cloned frozen attempt1 simulator tree."""
from pathlib import Path
import argparse,hashlib,json,subprocess
p=argparse.ArgumentParser();p.add_argument('--tree',type=Path,required=True);a=p.parse_args()
r=Path(__file__).resolve().parent
pins=json.loads((r/'attempt1_host_pins.json').read_text())
for name,want in pins.items():
 have=hashlib.sha256((a.tree/name).read_bytes()).hexdigest()
 if have!=want:raise SystemExit(f'Attempt1 input mismatch: {name}: {have}')
subprocess.run(['patch','-p1','-d',str(a.tree.resolve()),'--batch','--forward'],input=(r/'attempt1_to_attempt2.diff').read_bytes(),check=True)
print('Exact attempt2 host delta applied. Rebuild only sim_main.o against matching generated model.')
