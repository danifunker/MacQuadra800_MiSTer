#!/usr/bin/env python3
from pathlib import Path
import subprocess,hashlib,json,re,time
D=Path(__file__).resolve().parent;R=D.parents[1]
base=R/'scratch/fpu_refill_platform_workload_20260927/baseline/rtl/ap68040/rtl/ap040_fpu.v'
cand=R/'scratch/fpu_normal_single_move_candidate_20260928/ap040_fpu.v'
qsf=R/'MacQuadra800.qsf';flags=['-D'+x for x in sorted(set(re.findall(r'^set_global_assignment -name VERILOG_MACRO "((?:AP040_[A-Z0-9_]+|CACHE_CD_OFF|CACHE_SMALL)=1)"',qsf.read_text(),re.M)))]
flags+=['-DSIMULATION=1']
identity={'sources':{str(f):hashlib.sha256(f.read_bytes()).hexdigest() for f in [base,cand,qsf,D/'tb_normal_single_move.sv',D/'prepare.py',D/'tests.inc',D/'run.py',base.parent/'ap040_defs.svh']},'flags':flags,'independent_oracle':'normal IEEE single exact extended conversion +preserved status/quotient/CC/frame fields; excluded baseline signatures compared','tool':'iverilog -g2012/vvp','scope':'FPU unit realports; no CPU/workload/timing qualification'}
(D/'identity.json').write_text(json.dumps(identity,indent=2)+'\n')
for label,source in [('baseline',base),('candidate',cand)]:
 for ext in ['compile.log','run.log','vvp']:assert not (D/(label+'.'+ext)).exists(),'fresh evidence paths required'
 with (D/(label+'.compile.log')).open('w') as f:subprocess.run(['iverilog','-g2012',*flags,*(['-DCAND=1'] if label=='candidate' else []),'-I',str(base.parent),'-s','tb_normal_single_move','-o',str(D/(label+'.vvp')),str(D/'tb_normal_single_move.sv'),str(source)],stdout=f,stderr=subprocess.STDOUT,check=True,timeout=60)
 start=time.monotonic()
 with (D/(label+'.run.log')).open('w') as f:subprocess.run(['vvp',str(D/(label+'.vvp'))],stdout=f,stderr=subprocess.STDOUT,check=True,timeout=180)
 text=(D/(label+'.run.log')).read_text();assert 'PASS normal_single' in text
 print(label,re.search(r'PASS normal_single.*',text)[0],'wall',round(time.monotonic()-start,2))
a=[x for x in (D/'baseline.run.log').read_text().splitlines() if x.startswith('SIG')]
b=[x for x in (D/'candidate.run.log').read_text().splitlines() if x.startswith('SIG')]
assert a==b,'excluded/restore baseline vs candidate signature mismatch'
print('PASS excluded_and_restore_signatures',len(a))
for f,expected in identity['sources'].items():assert hashlib.sha256(Path(f).read_bytes()).hexdigest()==expected
(D/'qualification.json').write_text(json.dumps({'status':'PASS','excluded_and_restore_signatures':len(a),'baseline':re.search(r'PASS normal_single.*',(D/'baseline.run.log').read_text())[0],'candidate':re.search(r'PASS normal_single.*',(D/'candidate.run.log').read_text())[0]},indent=2)+'\n')
