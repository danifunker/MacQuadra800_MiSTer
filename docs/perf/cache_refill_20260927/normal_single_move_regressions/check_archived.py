#!/usr/bin/env python3
from pathlib import Path
import hashlib,json,re
D=Path(__file__).resolve().parent
for line in (D/'archive.sha256').read_text().splitlines():
 h,n=line.split('  ',1);assert hashlib.sha256((D/n).read_bytes()).hexdigest()==h,n
result=json.loads((D/'result.json').read_text());assert result['simulation_status']=='PASS' and result['runner_exit_status']==1
for label,targets in result['targets'].items():
 assert len(targets)==6
 for target,record in targets.items():
  f=D/label/(target+'.log');t=f.read_text();assert hashlib.sha256(f.read_bytes()).hexdigest()==record['log_sha256']
  assert 'ALL TESTS PASSED' in t and not re.search(r'FATAL|TEST FAILED|FAIL:',t)
  if target!='fpu_normalize':assert re.findall(r'phase (\d) passed',t)==['0','1','2']
print('PASS12terminal existingcore/FPU regressions; originalrunner outputhash bookkeepingfailure documented')
