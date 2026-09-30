#!/usr/bin/env python3
"""Saved evidence integrity/report checks; guest timing verdict remains invalid."""
from pathlib import Path
import hashlib,json,subprocess,sys
P=Path(__file__).resolve().parent
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
for row in (P/'archive_manifest.sha256').read_text().splitlines():
    h,n=row.split('  ',1);assert sha(P/n)==h,n
for row in json.loads((P/'source_copy_map.json').read_text())['files']:
    f=P/row['archive_path'];assert sha(f)==row['sha256'] and f.stat().st_size==row['bytes']
result=json.loads((P/'guest_results.json').read_text())
assert result['goal']=='PAUSED' and result['overall_qualification']=='FAILED' and result['cause']=='UNPROVEN'
assert result['fpu']['verdict']=='INVALID_GUEST_TIMING' and result['fpu']['current']['fft_seconds']<0
assert result['mix']['verdict']=='INVALID_GUEST_TIMING' and result['mix']['clearly_visible_invalid_seconds']['Puzzle']==0
audit=json.loads((P/'final_verification.json').read_text());assert audit['source223_postcheck']=='PASS'
identity=json.loads((P/'completed_build_identity.json').read_text())
assert sha(P/'source_manifest.sha256')==identity['source_manifest_sha256']
for kind,terminal in [('fpu','screenshot_f7382.png'),('mix','screenshot_f7382.png'),('color8','screenshot_f5525.png')]:
    c=P/kind/'candidate';b=P/kind/'completed6c';m=json.loads((c/'run.meta.json').read_text())
    assert m['exit_status']==0 and m['child_terminal'] and m['postrun_source_manifest']=='PASS'
    assert m['binary_sha256']==m['running_exe_sha256']==identity['binary_sha256']
    assert m['refill_check_exit_status']==m['observer_check_exit_status']==0
    assert (c/'screenshot_f4277.png').read_bytes()==(b/'screenshot_f4277.png').read_bytes()
    assert (c/'control.txt').read_bytes()==(b/'control.txt').read_bytes()
    assert (c/terminal).read_bytes()!=(b/terminal).read_bytes()
    assert json.loads((c/'manual_review.json').read_text())['verdict']==result[kind]['verdict']
    for checker,extra in [('check_refill_report.py',[]),('check_guard_report.py',[] if kind=='fpu' else ['--allow-empty'])]:
        subprocess.run([sys.executable,str(P/'checkers'/checker),str(c/'refill.tsv'),*extra],check=True,timeout=60,stdout=subprocess.DEVNULL)
print('PASS archive integrity and automated reports; FPU/Mix guest timing INVALID, overall qualification FAILED, goal PAUSED')
