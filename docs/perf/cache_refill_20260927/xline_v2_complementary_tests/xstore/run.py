#!/usr/bin/env python3
"""One serial paired run of complementary cache benches, posted hints explicitly tied."""
from pathlib import Path
import subprocess,hashlib,os,signal,time,json,shutil,datetime
P=Path(__file__).resolve().parent;R=P.parent;O=P/'outputs'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def verify():
 for row in (P/'input_manifest.sha256').read_text().splitlines():
  h,n=row.split('  ',1);assert sha(R/n)==h,n
 for v,h in [('baseline','7cba7f73f6f7f16fa7a45d439af6a786bd55c3ef2a3f8c876b400e10d4fb7747'),('candidate','9e8c0582db1b0bb88428e56fec63e99029b61faffac62c6f3dda9326b5191481')]:
  assert sha(R/'inputs'/v/'rtl/ap68040/rtl/ap040_cache.v')==h
verify();assert not O.exists(),'fresh outputs required';O.mkdir()
meta={'status':'RUNNING','started_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'runner_pid':os.getpid(),'input_manifest_sha256':sha(P/'input_manifest.sha256'),'flags':['-g2012','-DAP040_EXPERIMENTAL_XSTORE'],'tools':{n:{'path':shutil.which(n),'sha256':sha(Path(shutil.which(n)).resolve())} for n in ['iverilog','vvp']},'steps':[],'scope':'direct-port cache units with XSTORE; XSTORE bench unmodified, posted bench pin-only adapter; other CPU macros not consumed; behavioral dual-port RAM'}
def save():(O/'metadata.json').write_text(json.dumps(meta,indent=2)+'\n')
def run(cmd,name):
 step={'name':name,'argv':[str(x) for x in cmd]};meta['steps'].append(step);save()
 with (O/(name+'.log')).open('x') as out:
  c=subprocess.Popen([str(x) for x in cmd],cwd=O,stdout=out,stderr=subprocess.STDOUT,start_new_session=True)
  step['child_pid']=c.pid;save()
  try:c.wait(timeout=90)
  except BaseException:
   try:os.killpg(c.pid,signal.SIGKILL)
   except ProcessLookupError:pass
   c.wait();raise
 step['exit_status']=c.returncode;step['terminal']=True;save();assert c.returncode==0,name
 return (O/(name+'.log')).read_text()
save()
try:
 for v in ['baseline','candidate']:
  rtl=R/'inputs'/v/'rtl/ap68040/rtl'
  for name,tb,top,expected in [('xstore','tb_ap040_cache_xstore.sv','tb_ap040_cache_xstore','XSTORE PASS'),('posted','tb_cache_posted_read_matrix.sv','tb_posted_read_matrix','POSTED_MATRIX PASS')]:
   prefix=v+'_'+name;exe=O/(prefix+'.vvp')
   run(['iverilog','-g2012','-DAP040_EXPERIMENTAL_XSTORE','-I',rtl,'-s',top,'-o',exe,R/'inputs/common'/tb,rtl/'ap040_cache.v',rtl/'primitives/dpram.v'],prefix+'_build')
   text=run(['vvp',exe],prefix+'_run');assert expected in text,(prefix,text[-1000:]);assert 'FAIL' not in text
 verify();meta.update(status='QUALIFIED_COMPLEMENTARY_PAIR',postrun_input_manifest='PASS')
except BaseException as exc:meta.update(status='FAILED',error=repr(exc));raise
finally:meta['finished_utc']=datetime.datetime.now(datetime.timezone.utc).isoformat();save()
