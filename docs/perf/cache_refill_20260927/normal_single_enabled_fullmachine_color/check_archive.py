#!/usr/bin/env python3
from pathlib import Path
import hashlib,json,subprocess,sys
P=Path(__file__).resolve().parent
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
for row in (P/'archive_manifest.sha256').read_text().splitlines():
 h,n=row.split('  ',1);assert sha(P/n)==h,n
m=json.loads((P/'candidate/run.meta.json').read_text());review=json.loads((P/'candidate/manual_review.json').read_text())
assert m['exit_status']==0 and m['child_terminal'] and m['postrun_source_manifest']=='PASS'
assert m['refill_check_exit_status']==m['observer_check_exit_status']==0
assert m['binary_sha256']==m['running_exe_sha256']=='2f16b5f63372788b8dc1b63ae8d657cdaad67c3e5232524e9be1edb0d14e6ebf'
assert sha(P/'source_manifest.sha256')==m['source_manifest_sha256']
assert review['guest_seconds']==review['baseline_seconds']==9.878 and review['rating']==1.072 and review['iterations']==1
for n in ['screenshot_f4277.png','screenshot_f5525.png']:
 assert (P/'candidate'/n).read_bytes()==(P/'baseline'/n).read_bytes()
 assert sha(P/'candidate'/n)==m['screens'][n]==review['screens'][n]
assert (P/'candidate/control.txt').read_bytes()==(P/'baseline/control.txt').read_bytes()
clean=''.join(x+'\n' for x in (P/'candidate/refill.tsv').read_text().splitlines() if not x.startswith('FPU_GUARD_')).encode()
assert clean==(P/'baseline/refill.tsv').read_bytes()
subprocess.run([sys.executable,str(P/'check_refill_report.py'),str(P/'candidate/refill.tsv')],check=True)
subprocess.run([sys.executable,str(P/'check_guard_report.py'),str(P/'candidate/refill.tsv'),'--allow-empty'],check=True)
print('PASS Color8 archive: displayed9.878s unchanged; exact screens/standard profile, terminal/source/binary/report evidence')
