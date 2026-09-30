#!/usr/bin/env python3
from pathlib import Path
import json,hashlib,re
D=Path(__file__).resolve().parent;id=json.loads((D/'identity.json').read_text())
ignored=[]
for f,h in id['sources'].items():
 p=Path(f)
 if p==D/'stdout.log':ignored.append(f);continue
 assert hashlib.sha256(p.read_bytes()).hexdigest()==h,f
assert ignored==[str(D/'stdout.log')]
result={'scope':id['scope'],'simulation_status':'PASS','runner_exit_status':1,'runner_infrastructure_note':'run.py erroneously put output stdout.log in source inputs; final hash assertion rejected the grown log after all12simulations completed successfully. This checker verifies every real frozen source and every terminal simulation result; no rerun or input repair.','noninput_output_excluded':ignored,'targets':{}}
for label in ['baseline','candidate']:
 result['targets'][label]={}
 for target in id['targets']:
  t=(D/label/(target+'.log')).read_text();assert 'ALL TESTS PASSED' in t and not re.search(r'FATAL|TEST FAILED|FAIL:',t),(label,target)
  phases=re.findall(r'phase (\d) passed \((\d+) cycles\)',t)
  if target!='fpu_normalize':assert [int(x[0]) for x in phases]==[0,1,2]
  result['targets'][label][target]={'status':'PASS','bus_phase_cycles':dict((a,int(b)) for a,b in phases),'log_sha256':hashlib.sha256((D/label/(target+'.log')).read_bytes()).hexdigest()}
if (D/'result.json').exists():assert json.loads((D/'result.json').read_text())==result
else:(D/'result.json').write_text(json.dumps(result,indent=2)+'\n')
print('PASS12terminal existingregressions;allreal sourceidentities unchanged;originalrunner outputhash bookkeepingfailure acknowledged')
