#!/usr/bin/env python3
from pathlib import Path
import hashlib,json,subprocess,sys
D=Path(__file__).resolve().parent
for row in (D/'archive_manifest.sha256').read_text().splitlines():
 h,n=row.split('  ',1);assert hashlib.sha256((D/n).read_bytes()).hexdigest()==h,n
c=json.loads((D/'comparison.json').read_text());assert c['baseline_aggregate']==c['candidate_aggregate']==1.798
assert c['setup_all10_checked'] and c['setup_all_iterations']==1 and c['tests_done_both'] and len(c['visible_raw_rows'])==10
assert (D/'baseline/control.txt').read_bytes()==(D/'candidate/control.txt').read_bytes()
assert (D/'baseline/screenshot_f4277.png').read_bytes()==(D/'candidate/screenshot_f4277.png').read_bytes()
for v in ['baseline','candidate']:
 m=json.loads((D/v/'run.meta.json').read_text());i=json.loads((D/v/'inputs.json').read_text())
 assert m['exit_status']==m['refill_check_exit_status']==0
 assert m['binary_sha256']==i['prelaunch_files']['Vemu']
 assert i['prelaunch_files']['run.hda']=='80d8479430a66edae161c2bac6a9563dbb4f6bd0f564ee7849a555c447df8888'
 assert hashlib.sha256((D/v/'control.txt').read_bytes()).hexdigest()==i['prelaunch_files']['control.txt']
 assert i['nonFPU_RTL_host_model_identical'] and i['RTL_differences']==['ap68040/rtl/ap040_fpu.v']
 subprocess.run([sys.executable,str(D/'check_refill_report.py'),str(D/v/'refill.tsv')],check=True)
print('PASS archived matched full Mix terminal/source/setup/profile evidence; aggregate1.798 unchanged')
