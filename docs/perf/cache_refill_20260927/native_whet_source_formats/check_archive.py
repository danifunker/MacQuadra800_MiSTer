#!/usr/bin/env python3
from pathlib import Path
import hashlib,subprocess,sys,json
D=Path(__file__).resolve().parent;rows=(D/'archive_manifest.sha256').read_text().splitlines()
def verify():
 for row in rows:
  h,n=row.split('  ',1);assert hashlib.sha256((D/n).read_bytes()).hexdigest()==h,n
verify()
for name in ['check_result.py','check_format.py']:subprocess.run([sys.executable,str(D/name)],check=True)
r=json.loads((D/'source_formats.json').read_text());assert r['totals']['raw_branch_edges']==r['totals']['first_branch_per_req_episode']==318069
assert r['opportunities']['single_unique']==930 and r['opportunities']['extended_unique']==29058
assert json.loads((D/'supervisor.json').read_text())['status']=='QUALIFIED_RUNTIME'
verify();print('PASS archived native Whet source-format evidence; opportunities only')
