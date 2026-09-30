#!/usr/bin/env python3
"""One authorized candidate XSTORE diagnostic, no failed-test retry."""
from pathlib import Path
import hashlib,json,subprocess,os,signal,datetime
P=Path(__file__).resolve().parent;R=P.parent;O=P/'candidate_xstore'
sha=lambda f:hashlib.sha256(f.read_bytes()).hexdigest()
for row in (P/'input_manifest.sha256').read_text().splitlines():
 h,n=row.split('  ',1);assert sha(R/n)==h,n
assert not O.exists();O.mkdir()
rtl=R/'inputs/candidate/rtl/ap68040/rtl';assert sha(rtl/'ap040_cache.v')=='9e8c0582db1b0bb88428e56fec63e99029b61faffac62c6f3dda9326b5191481'
m={'status':'RUNNING','runner_pid':os.getpid(),'started_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'recipe_sha256':sha(Path(__file__)),'existing_manifest_sha256':sha(P/'input_manifest.sha256'),'candidate_cache_sha256':sha(rtl/'ap040_cache.v'),'steps':[]}
def save():(O/'metadata.json').write_text(json.dumps(m,indent=2)+'\n')
try:
 for name,cmd in [('build',['iverilog','-g2012','-DAP040_EXPERIMENTAL_XSTORE','-I',rtl,'-s','tb_ap040_cache_xstore','-o',O/'tb.vvp',R/'inputs/common/tb_ap040_cache_xstore.sv',rtl/'ap040_cache.v',rtl/'primitives/dpram.v']),('run',['vvp',O/'tb.vvp'])]:
  step={'name':name,'argv':[str(x) for x in cmd]};m['steps'].append(step)
  with (O/(name+'.log')).open('x') as log:
   c=subprocess.Popen(step['argv'],cwd=O,stdout=log,stderr=subprocess.STDOUT,start_new_session=True);step['pid']=c.pid;save()
   try:c.wait(timeout=90)
   except BaseException:
    os.killpg(c.pid,signal.SIGKILL);c.wait();raise
  step.update(exit_status=c.returncode,terminal=True);save();assert c.returncode==0
 assert 'XSTORE PASS cases=100' in (O/'run.log').read_text()
 for row in (P/'input_manifest.sha256').read_text().splitlines():
  h,n=row.split('  ',1);assert sha(R/n)==h,n
 m.update(status='PASS_XSTORE_COMPLEMENTARY',postrun_source='PASS')
except BaseException as exc:m.update(status='FAILED',error=repr(exc));raise
finally:m['finished_utc']=datetime.datetime.now(datetime.timezone.utc).isoformat();save()
