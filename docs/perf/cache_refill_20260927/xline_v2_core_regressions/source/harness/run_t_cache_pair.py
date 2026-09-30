#!/usr/bin/env python3
from pathlib import Path
import concurrent.futures, datetime, hashlib, json, os, subprocess, sys, time
ROOT=Path(__file__).resolve().parent
PAIR=ROOT.parent/'cache_v2_core_regressions_20260928'
ASM=Path('/home/alans/mister/MacQuadra800_fixtures/wombat-vasm/vasmm68k_mot')
SRC=ROOT/'t_cache.s'
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
LIMIT=240
meta={'status':'RUNNING','started_local':datetime.datetime.now().astimezone().isoformat(),'target':'t_cache only; reuses immutable baseline/candidate VVPs from completed five-target package','max_workers':2,'command_timeout_seconds':LIMIT,'source_sha256':sha(SRC),'assembler_sha256':sha(ASM),'variants':{}}
(ROOT/'metadata.json').write_text(json.dumps(meta,indent=2)+'\n')
def runvar(label):
 d=ROOT/label; d.mkdir(exist_ok=False)
 sim=PAIR/'outputs'/label/'prog.vvp'; assert sim.is_file()
 row={'vvp':str(sim),'vvp_sha256':sha(sim),'commands':[]}
 def command(argv,logname,cwd=None):
  start=datetime.datetime.now().astimezone().isoformat(); t=time.monotonic()
  with (d/logname).open('wb') as log:
   p=subprocess.Popen([str(x) for x in argv],cwd=cwd or d,stdout=log,stderr=subprocess.STDOUT,start_new_session=True)
   row['commands'].append({'argv':list(map(str,argv)),'pid':p.pid,'started_local':start})
   try: rc=p.wait(timeout=LIMIT)
   except subprocess.TimeoutExpired:
    os.killpg(p.pid,15)
    try:p.wait(timeout=5)
    except subprocess.TimeoutExpired:os.killpg(p.pid,9);p.wait()
    raise RuntimeError(f'{label} {logname}: timeout after {LIMIT}s pid {p.pid}')
  info=row['commands'][-1];info.update(exit_status=rc,finished_local=datetime.datetime.now().astimezone().isoformat(),wall_seconds=round(time.monotonic()-t,3),log_sha256=sha(d/logname))
  if rc:raise RuntimeError(f'{label} {logname} exit {rc}')
 command([ASM,'-Fbin','-m68040','-no-opt','-o',d/'t_cache.bin',SRC],'assemble.log')
 command([sys.executable,PAIR/'inputs/tb/bin2hex.py',d/'t_cache.bin',d/'t_cache.hex'],'hex.log')
 command(['vvp',sim,'+prog=t_cache.hex'],'run.log',d)
 text=(d/'run.log').read_text(errors='replace')
 if 'ALL TESTS PASSED' not in text or any(x in text for x in ('FATAL','TEST FAILED','FAIL:','ERROR:')):raise RuntimeError(f'{label} t_cache missing PASS or reports failure: {text[-2000:]}')
 import re
 phases=re.findall(r'phase (\d) passed \((\d+) cycles\)',text)
 if [int(x[0]) for x in phases]!=[0,1,2]:raise RuntimeError(f'{label} phase gate failed {phases}')
 row.update(status='PASS',bus_phase_cycles={a:int(b) for a,b in phases},bin_sha256=sha(d/'t_cache.bin'),hex_sha256=sha(d/'t_cache.hex'))
 return label,row
try:
 with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
  futs=[pool.submit(runvar,x) for x in ('baseline','candidate')]
  for f in concurrent.futures.as_completed(futs):
   label,row=f.result();meta['variants'][label]=row;meta['updated_local']=datetime.datetime.now().astimezone().isoformat();(ROOT/'metadata.json').write_text(json.dumps(meta,indent=2)+'\n')
 meta.update(status='PASS',finished_local=datetime.datetime.now().astimezone().isoformat())
except BaseException as e:
 meta.update(status='FAILED',failure=repr(e),finished_local=datetime.datetime.now().astimezone().isoformat());raise
finally:(ROOT/'metadata.json').write_text(json.dumps(meta,indent=2)+'\n')
print('PASS paired t_cache extra gate; original five-target outputs untouched')
