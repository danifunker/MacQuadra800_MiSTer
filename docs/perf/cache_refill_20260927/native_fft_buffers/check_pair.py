#!/usr/bin/env python3
from pathlib import Path
import subprocess,sys,json,hashlib,re
D=Path(__file__).resolve().parent
for name in ['baseline','candidate']:subprocess.run([sys.executable,str(D/name/'check_result.py')],check=True)
a=json.loads((D/'baseline/measurement.json').read_text());b=json.loads((D/'candidate/measurement.json').read_text());assert a['allocations']==b['allocations']
blocks=[]
for x,n in enumerate([2056,2056,1040]):
 read=lambda v:bytes(int(z,16) for z in (D/v/'run'/f'fft_payload_{x}.hex').read_text().split())
 before,after=read('baseline'),read('candidate');assert len(before)==len(after)==n
 assert before==after,f'FFT payload{x} mismatch'
 row={'id':x,'pointer':a['allocations']['pointers'][x],'bytes':n,'full_sha256':hashlib.sha256(before).hexdigest(),'equality':'PASS'}
 if x<2:row['complex_active_bytes']=2048;row['complex_active_sha256']=hashlib.sha256(before[8:]).hexdigest()
 blocks.append(row)
result={'scope':'native FFT matched baseline/candidate payload regression, NOT independent numerical FFT oracle','baseline_loop':a['loop_cycles'],'candidate_loop':b['loop_cycles'],'capture':'validated firstfree600e00 primary dispatch, natural-drain guard, no time advance','blocks':blocks,'total_bytes_compared':5152}
(D/'pair_result.json').write_text(json.dumps(result,indent=2)+'\n');print('PASS all5152 FFT payload bytes identical; no independent FFT oracle')
