#!/usr/bin/env python3
# Run archived immutable bench against explicitly supplied baseline/candidate.
from pathlib import Path
import argparse,subprocess,json,hashlib,re
D=Path(__file__).resolve().parent
p=argparse.ArgumentParser();p.add_argument('--baseline',type=Path,required=True);p.add_argument('--candidate',type=Path,required=True);p.add_argument('--defs',type=Path,required=True);p.add_argument('--out',type=Path,required=True);a=p.parse_args()
id=json.loads((D/'identity.json').read_text());expected=list(id['sources'].values())
for f,h in [(a.baseline,expected[0]),(a.candidate,expected[1]),(a.defs,expected[-1])]:assert hashlib.sha256(f.read_bytes()).hexdigest()==h,str(f)
a.out.mkdir(exist_ok=False,parents=True)
for label,f in [('baseline',a.baseline),('candidate',a.candidate)]:
 cmd=['iverilog','-g2012',*id['flags'],*(['-DCAND=1'] if label=='candidate' else []),'-I',str(a.defs.resolve().parent),'-s','tb_normal_single_move','-o',str(a.out/(label+'.vvp')),str(D/'tb_normal_single_move.sv'),str(f.resolve())]
 with (a.out/(label+'.compile.log')).open('w') as log:subprocess.run(cmd,stdout=log,stderr=subprocess.STDOUT,check=True,timeout=60)
 with (a.out/(label+'.run.log')).open('w') as log:subprocess.run(['vvp',str(a.out/(label+'.vvp'))],stdout=log,stderr=subprocess.STDOUT,check=True,timeout=180)
logs=[(a.out/(l+'.run.log')).read_text() for l in ['baseline','candidate']]
assert all('PASS normal_single checks=16301' in x and not re.search(r'FATAL|TEST FAILED',x) for x in logs)
assert [x for x in logs[0].splitlines() if x.startswith('SIG')]==[x for x in logs[1].splitlines() if x.startswith('SIG')]
print('PASS matched directed qualification')
