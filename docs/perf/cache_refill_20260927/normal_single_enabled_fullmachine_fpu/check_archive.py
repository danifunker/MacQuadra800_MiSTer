#!/usr/bin/env python3
from pathlib import Path
import hashlib,json,subprocess,sys,math
P=Path(__file__).resolve().parent;sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
for row in (P/'archive_manifest.sha256').read_text().splitlines():
 h,n=row.split('  ',1);assert sha(P/n)==h,n
m=json.loads((P/'candidate/run.meta.json').read_text());x=json.loads((P/'comparison.json').read_text());review=json.loads((P/'candidate/manual_review.json').read_text())
assert m['exit_status']==0 and m['child_terminal'] and m['postrun_source_manifest']=='PASS'
assert m['refill_check_exit_status']==m['observer_check_exit_status']==0
assert m['binary_sha256']==m['running_exe_sha256']=='2f16b5f63372788b8dc1b63ae8d657cdaad67c3e5232524e9be1edb0d14e6ebf'
assert sha(P/'provenance/source_manifest.sha256')==m['source_manifest_sha256']
assert review['tests_done'] and review['iterations']==[1,1,1] and review['setup_all_three_selected']
assert [review[k] for k in ['aggregate_rating','whetstones_per_second','matrix_seconds','fft_seconds']]==[.729,3850.048,.928,.418]
for n,h in review['screens'].items():assert sha(P/'candidate'/n)==h
for variant in ['baseline','previous55ff']:
 assert (P/variant/'control.txt').read_bytes()==(P/'candidate/control.txt').read_bytes()
assert (P/'candidate/screenshot_f4277.png').read_bytes()==(P/'previous55ff/fpu_setup.png').read_bytes()
assert math.isclose(x['aggregate_rating_increase_percent'],100*(.729/.698-1))
assert math.isclose(x['matrix_throughput_increase_percent_from_rounded_times'],100*(.991/.928-1))
assert math.isclose(x['fft_throughput_increase_percent_from_rounded_times'],100*(.447/.418-1))
subprocess.run([sys.executable,str(P/'provenance/check_refill_report.py'),str(P/'candidate/refill.tsv')],check=True)
subprocess.run([sys.executable,str(P/'provenance/check_guard_report.py'),str(P/'candidate/refill.tsv')],check=True)
print('PASS enabled-single FPU archive: terminal/source/binary/checkers/guestreview; aggregate+4.441% below10% target')
