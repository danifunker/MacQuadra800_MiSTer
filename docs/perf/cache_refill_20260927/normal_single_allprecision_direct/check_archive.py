#!/usr/bin/env python3
from pathlib import Path
import hashlib,json,re
D=Path(__file__).resolve().parent
for row in (D/'archive_manifest.sha256').read_text().splitlines():
 h,n=row.split('  ',1);assert hashlib.sha256((D/n).read_bytes()).hexdigest()==h,n
q=json.loads((D/'qualification.json').read_text());assert q['status']=='PASS' and q['excluded_and_restore_signatures']==40
assert q['baseline']=='PASS normal_single checks=65069 fast=0 slow=65066'
assert q['candidate']=='PASS normal_single checks=65069 fast=65027 slow=39'
a=(D/'baseline.run.log').read_text();b=(D/'candidate.run.log').read_text()
assert q['baseline'] in a and q['candidate'] in b
sa=[x for x in a.splitlines() if x.startswith('SIG')];sb=[x for x in b.splitlines() if x.startswith('SIG')];assert len(sa)==40 and sa==sb
identity=json.loads((D/'identity.json').read_text())
for name in ['prepare.py','tests.inc','run.py','tb_normal_single_move.sv']:
 rows=[h for p,h in identity['sources'].items() if Path(p).name==name];assert rows==[hashlib.sha256((D/name).read_bytes()).hexdigest()],name
ci=json.loads((D/'candidate_identity.json').read_text());assert ci['candidate_fpu']=='55ff9b3cd1d59069ec0b94ca17e4dc3a8c87ac031317902285444d92643724a2'
assert ci['baseline_fpu']=='2d53db3ae4a04310add04eeb7919f0219197a98827ed92e410e6d4a4a90f5465'
assert ci['candidate_fpu'] in identity['sources'].values() and ci['baseline_fpu'] in identity['sources'].values()
print('PASS allprecision direct unit65,069 checks each/40 matched signatures;55ff candidate')
