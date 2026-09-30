#!/usr/bin/env python3
from pathlib import Path
import hashlib,json,subprocess,sys
P=Path(__file__).resolve().parent;sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
for row in (P/'archive_manifest.sha256').read_text().splitlines():
 h,n=row.split('  ',1);assert sha(P/n)==h,n
m=json.loads((P/'candidate/run.meta.json').read_text());r=json.loads((P/'candidate/manual_review.json').read_text())
assert m['exit_status']==0 and m['child_terminal'] and m['postrun_source_manifest']=='PASS'
assert m['refill_check_exit_status']==m['observer_check_exit_status']==0
assert m['binary_sha256']==m['running_exe_sha256']=='2f16b5f63372788b8dc1b63ae8d657cdaad67c3e5232524e9be1edb0d14e6ebf'
assert sha(P/'source_manifest.sha256')==m['source_manifest_sha256']
assert r['tests_done'] and r['setup_all10_selected_iteration1'] and r['aggregate']==r['baseline_aggregate']==1.798
assert list(r['visible_absolute_values'].values())==[1762.139,17932.324,.479,.507,.602,.362,.756,.712,.495,.845]
for n,h in r['screens'].items():assert sha(P/'candidate'/n)==h==m['screens'][n]
assert (P/'candidate/screenshot_f4277.png').read_bytes()==(P/'baseline/screenshot_f4277.png').read_bytes()
assert (P/'candidate/screenshot_f7382.png').read_bytes()!=(P/'baseline/screenshot_f7382.png').read_bytes()
assert (P/'candidate/screenshot_f7382.png').read_bytes()==(P/'previous73bc/screenshot_f7382.png').read_bytes()
assert (P/'candidate/control.txt').read_bytes()==(P/'baseline/control.txt').read_bytes()
clean=''.join(x+'\n' for x in (P/'candidate/refill.tsv').read_text().splitlines() if not x.startswith('FPU_GUARD_')).encode()
assert clean==(P/'previous73bc/refill.tsv').read_bytes() and clean!=(P/'baseline/refill.tsv').read_bytes()
subprocess.run([sys.executable,str(P/'check_refill_report.py'),str(P/'candidate/refill.tsv')],check=True)
subprocess.run([sys.executable,str(P/'check_guard_report.py'),str(P/'candidate/refill.tsv'),'--allow-empty'],check=True)
print('PASS Mix archive: aggregate1.798 unchanged; exactprior73bc image/standardprofile, originalbaseline differences retained, terminal/source/reports')
