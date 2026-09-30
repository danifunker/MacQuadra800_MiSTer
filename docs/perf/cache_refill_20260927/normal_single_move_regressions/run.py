#!/usr/bin/env python3
from pathlib import Path
import subprocess,hashlib,json,re,time
D=Path(__file__).resolve().parent;R=D.parents[1];rtl=D/'ap68040/rtl'
flags=json.loads((R/'scratch/fpu_normal_single_move_tests_20260928/identity.json').read_text())['flags']
inputs=[f for f in D.rglob('*') if f.is_file()];qsf=R/'MacQuadra800.qsf'
assert hashlib.sha256((rtl/'ap040_fpu.v').read_bytes()).hexdigest()=='73bc156d147e4f8b1c7ee08f0bb03c7f1cd720d4e78293d8252f63bf992f0b1f'
identity={'scope':'existing fullcore FPU/frames/FPSPpreparedresume/FPCR plus MMU/exceptions and normalization; CPU bus model, no fullmachine/OS/hardware','targets':['fpu','fpu_frames','fpu_resume','mmu','exceptions','fpu_normalize'],'flags':flags,'sources':{str(f):hashlib.sha256(f.read_bytes()).hexdigest() for f in inputs+[qsf]}}
(D/'identity.json').write_text(json.dumps(identity,indent=2)+'\n')
units=['ap040_tg68k_compat','ap040_core','ap040_bus16_adapter','ap040_bus_timeout','ap040_regfile','ap040_alu','ap040_muldiv','ap040_mmu','ap040_cache','ap040_walker_cdc','primitives/dpram']
def run(cmd,path,limit=180):
 with path.open('w') as f:p=subprocess.run(list(map(str,cmd)),stdout=f,stderr=subprocess.STDOUT,timeout=limit)
 t=path.read_text();assert p.returncode==0,(path,t[-2500:]);return t
results={}
for label,fpu in [('baseline',D/'baseline_ap040_fpu.v'),('candidate',rtl/'ap040_fpu.v')]:
 out=D/label;out.mkdir(exist_ok=False)
 sources=[D/'tb/tb_ap040_program.v',*(rtl/(u+'.v') for u in units),fpu,D/'ap68040/experimental/ap040_pipeline_integer.sv']
 run(['iverilog','-g2012',*flags,'-I',rtl,'-s','tb_ap040_program','-o',out/'prog.vvp',*sources],out/'compile.log')
 run(['iverilog','-g2012',*flags,'-I',rtl,'-s','tb_ap040_fpu_normalize','-o',out/'normalize.vvp',D/'tb/tb_ap040_fpu_normalize.v',fpu,rtl/'ap040_regfile.v',rtl/'primitives/dpram.v'],out/'normalize_compile.log')
 results[label]={}
 for target in identity['targets']:
  start=time.monotonic()
  if target=='fpu_normalize':cmd=['vvp',out/'normalize.vvp']
  else:
   run(['/home/alans/mister/MacQuadra800_fixtures/wombat-vasm/vasmm68k_mot','-Fbin','-m68040','-no-opt','-o',out/(target+'.bin'),D/'tb/asm'/('t_'+target+'.s')],out/(target+'_asm.log'))
   run(['python3',D/'tb/bin2hex.py',out/(target+'.bin'),out/(target+'.hex')],out/(target+'_hex.log'))
   cmd=['vvp',out/'prog.vvp','+prog='+str(out/(target+'.hex'))]
  text=run(cmd,out/(target+'.log'));assert 'ALL TESTS PASSED' in text and not re.search(r'FATAL|TEST FAILED',text),(target,text[-3000:])
  results[label][target]={'status':'PASS','wall_seconds':round(time.monotonic()-start,3)};print(label,target,'PASS',flush=True)
for f,h in identity['sources'].items():assert hashlib.sha256(Path(f).read_bytes()).hexdigest()==h,f
(D/'result.json').write_text(json.dumps(results,indent=2)+'\n')
print('PASS matched existing FPU core/MMU regression source identities unchanged',flush=True)
