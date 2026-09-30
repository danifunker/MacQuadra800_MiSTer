#!/usr/bin/env python3
"""One bounded authorized paired posted-contract screen; no retry."""
from pathlib import Path
import json,hashlib,os,signal,subprocess,datetime,re
P=Path(__file__).resolve().parent;R=P.parent.parent;O=P/'outputs'
sha=lambda f:hashlib.sha256(f.read_bytes()).hexdigest()
def verify():
 for row in (R/'existing/input_manifest.sha256').read_text().splitlines():
  h,n=row.split('  ',1);assert sha(R/n)==h,n
 for row in (P/'manifest.sha256').read_text().splitlines():
  h,n=row.split('  ',1);assert sha(P/n)==h,n
verify();assert not O.exists();O.mkdir()
m={'status':'RUNNING','runner_pid':os.getpid(),'started_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'recipe_sha256':sha(Path(__file__)),'reviewed_adapter_manifest_sha256':sha(P/'manifest.sha256'),'existing_RTL_manifest_sha256':sha(R/'existing/input_manifest.sha256'),'flags':['-g2012','-DAP040_EXPERIMENTAL_XSTORE'],'steps':[],'scope':'unit cache byte oracle at read ACK, disjoint posted hit permitted, final RAM/cache checks retained'}
def save():(O/'metadata.json').write_text(json.dumps(m,indent=2)+'\n')
try:
 for variant in ['baseline','candidate']:
  rtl=R/'inputs'/variant/'rtl/ap68040/rtl';exe=O/(variant+'.vvp')
  for stage,cmd in [('build',['iverilog','-g2012','-DAP040_EXPERIMENTAL_XSTORE','-I',rtl,'-s','tb_posted_read_matrix','-o',exe,P/'tb_cache_posted_read_matrix.sv',rtl/'ap040_cache.v',rtl/'primitives/dpram.v']),('run',['vvp',exe])]:
   name=variant+'_'+stage;step={'name':name,'argv':[str(x) for x in cmd]};m['steps'].append(step)
   with (O/(name+'.log')).open('x') as log:
    c=subprocess.Popen(step['argv'],cwd=O,stdout=log,stderr=subprocess.STDOUT,start_new_session=True);step['pid']=c.pid;save()
    try:c.wait(timeout=90)
    except BaseException:os.killpg(c.pid,signal.SIGKILL);c.wait();raise
   step.update(exit_status=c.returncode,terminal=True);save();assert c.returncode==0,name
  text=(O/(variant+'_run.log')).read_text();match=re.search(r'POSTED_MATRIX PASS cases=216 pending=(\d+) prepared=(\d+) early_disjoint_acks=(\d+)',text);assert match and all(int(v)>0 for v in match.groups()),text
  m[variant]={'pending':int(match[1]),'prepared':int(match[2]),'early_disjoint_acks':int(match[3]),'cases':216}
 verify();m.update(status='PASS_POSTED_CONTRACT_PAIR',postrun_sources='PASS')
except BaseException as exc:m.update(status='FAILED',error=repr(exc));raise
finally:m['finished_utc']=datetime.datetime.now(datetime.timezone.utc).isoformat();save()
