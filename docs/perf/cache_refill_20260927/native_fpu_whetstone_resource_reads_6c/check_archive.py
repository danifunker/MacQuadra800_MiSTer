#!/usr/bin/env python3
"""Portable verification of the included text evidence, not a model launch."""
from pathlib import Path
import hashlib,json,sys
P=Path(__file__).resolve().parent;sys.path.insert(0,str(P))
import check_resource,check_profile,check_comparison
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
for row in (P/'archive_manifest.sha256').read_text().splitlines():
 h,n=row.split('  ',1);assert sha(P/n)==h,n
assert sha(P/'original_source_manifest.sha256')=='7082248bdd0ec877b3a673ffe1b8dd21c91789fdf0afefe0ecb7ce877590610e'
m=json.loads((P/'runtime/supervisor.json').read_text());assert m['status']=='QUALIFIED_NATIVE_RUNTIME' and m['exit_status']==0 and m['runner_terminal']
assert m['candidate_fpu']=='6c157b3bc045e74a90416f4764f35cf65024e77577019a100b8aa9b5bdd9ce9b'
assert all(m[k]=='PASS' for k in ['original_checker','passive_checker','postrun_source_manifest','reference_report_and_capture_comparison'])
assert m['native_pid']==2574362 and m['native_exe_sha256']=='7b1d12958db240a90085d02b46d0554e5316aee1472ea3834824aabbb6acb571'
text=(P/'runtime/run/run.log').read_text();r=check_resource.validate(text);check_profile.validate(text)
check_comparison.validate(text,P/'runtime/run')
s=json.loads((P/'execution/result_summary.json').read_text())
assert s['target']==r['target'] and s['saved_rest_resource']==r['saved_rest_resource'] and s['loop_clocks']==8724166
assert all(s['child_cleanup'][k] for k in ['supervisor2573599','runner2573601','native2574362'])
print('PASS archive hashes/runtime/target96271-331334/rest90990-311506/zero partials/original+NEXT+fourcaptures byte-exact; no numerical/hardware oracle')
