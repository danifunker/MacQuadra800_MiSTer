#!/usr/bin/env python3
from pathlib import Path
import hashlib,json,subprocess,sys
D=Path(__file__).resolve().parent
for row in (D/'archive_manifest.sha256').read_text().splitlines():
 h,n=row.split('  ',1);assert hashlib.sha256((D/n).read_bytes()).hexdigest()==h,n
c=json.loads((D/'comparison.json').read_text());m=json.loads((D/'candidate/run.meta.json').read_text());assert m['exit_status']==m['refill_check_exit_status']==0
assert c['baseline']['aggregate']==c['candidate']['aggregate']==0.698 and c['iterations']==[1,1,1] and c['tests_done']
assert c['baseline']['ratings']==c['candidate']['ratings']==[0.739,0.713,0.642]
for n in ['control.txt','screenshot_f4277.png']:assert (D/'baseline'/n).read_bytes()==(D/'candidate'/n).read_bytes(),n
assert m['golden_input_disk_sha256']=='80d8479430a66edae161c2bac6a9563dbb4f6bd0f564ee7849a555c447df8888'
assert m['binary_sha256']==json.loads((D/'completed_build_identity.json').read_text())['binary_sha256']
for v in ['baseline','candidate']:subprocess.run([sys.executable,str(D/'check_refill_report.py'),str(D/v/'refill.tsv')],check=True)
print('PASS archived full OS FPU source/screen/profile identities; aggregate0.698 unchanged')
