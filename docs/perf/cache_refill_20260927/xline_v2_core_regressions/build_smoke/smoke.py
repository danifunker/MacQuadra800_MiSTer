#!/usr/bin/env python3
from pathlib import Path
import subprocess,json,hashlib,os,datetime,signal,shutil
S=Path(__file__).resolve().parent;D=S.parent/'cache_xline_sideband_fullmachine_20260928';O=S/'smoke';sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
assert sha(D/'source_manifest.sha256')=='8c70ed5af366c6dd8b5507ac5a575d991042716b044bec406567db2fd1332137'
def verify():
 for row in (D/'source_manifest.sha256').read_text().splitlines():
  h,n=row.split('  ',1);assert sha(Path(n))==h,n
verify();assert sha(D/'rtl/ap68040/rtl/ap040_cache.v')=='9e8c0582db1b0bb88428e56fec63e99029b61faffac62c6f3dda9326b5191481';b=json.loads((S/'completed_build_identity.json').read_text());assert b['status']=='PASS' and b['candidate_sha256']=='6c157b3bc045e74a90416f4764f35cf65024e77577019a100b8aa9b5bdd9ce9b'
assert b['candidate_cache_sha256']=='9e8c0582db1b0bb88428e56fec63e99029b61faffac62c6f3dda9326b5191481'
binary=D/'verilator/obj_dir/Vemu';assert sha(binary)==b['binary_sha256'];assert not O.exists(),'fresh smoke outputs required'
rom=D/'verilator/quadra800-fastboot.rom.hex';assert sha(rom)=='045c02746b5f15f83132d33c5414f806e7b049f3bfe53a7bd0ecacb8e072d673'
O.mkdir();shutil.copy2(rom,O/'rom.hex');shutil.copy2(S/'smoke.control.txt',O/'control.txt');assert len('rom.hex')<=128
cmd=[str(binary),'--headless','--no-cpu-trace','+rom=rom.hex','+ram=0','--control','control.txt','--cpu-profile','refill.tsv','--max-cycles','200000','+ram_line_model','+ram_first_latency=4','+ram_line_publish_delay=2']
m={'status':'STARTING','scope':'short disk-free generated-host smoke, not benchmark or guard coverage','supervisor_pid':os.getpid(),'argv':cmd,'binary_sha256':sha(binary),'source_manifest_sha256':sha(D/'source_manifest.sha256'),'candidate_cache_sha256':sha(D/'rtl/ap68040/rtl/ap040_cache.v'),'supervisor_sha256':sha(Path(__file__)),'ROM_sha256':sha(O/'rom.hex'),'started_utc':datetime.datetime.now(datetime.timezone.utc).isoformat()}
def save():(O/'meta.json').write_text(json.dumps(m,indent=2)+'\n')
c=None;save()
class Interrupted(Exception):pass
def stop(signum,frame):m['signal']=signum;raise Interrupted()
signal.signal(signal.SIGTERM,stop);signal.signal(signal.SIGINT,stop)
try:
 with (O/'run.log').open('w') as log:
  c=subprocess.Popen(cmd,cwd=O,stdout=log,stderr=subprocess.STDOUT,start_new_session=True);m['child_pid']=c.pid;m['running_exe_sha256']=sha(Path('/proc')/str(c.pid)/'exe');assert m['running_exe_sha256']==m['binary_sha256'];m['status']='RUNNING';save();print('SMOKE_CHILD',c.pid,flush=True);rc=c.wait(timeout=120);m['exit_status']=rc;assert rc==0
 assert 'file not found' not in (O/'run.log').read_text().lower(),'memory image load failure'
 checks=[['python3',str(D/'verilator/tests/check_refill_report.py'),str(O/'refill.tsv'),'--allow-empty'],['python3',str(S/'check_guard_report.py'),str(O/'refill.tsv'),'--allow-empty']]
 for i,cmdcheck in enumerate(checks):
  with (O/('check'+str(i)+'.log')).open('w') as log:q=subprocess.run(cmdcheck,stdout=log,stderr=subprocess.STDOUT,timeout=30)
  m['check'+str(i)]=q.returncode;save();assert q.returncode==0
 verify();assert sha(O/'rom.hex')==m['ROM_sha256'];m['source_manifest_postrun']='PASS';m['status']='PASS'
except BaseException as exc:
 m['status']='FAILED';m['error']=repr(exc)
 if c is not None and c.poll() is None:
  os.killpg(c.pid,signal.SIGTERM)
  try:c.wait(timeout=10)
  except subprocess.TimeoutExpired:os.killpg(c.pid,signal.SIGKILL);c.wait()
 if c is not None:m['exit_status']=c.returncode
 raise
finally:
 m['finished_utc']=datetime.datetime.now(datetime.timezone.utc).isoformat();m['child_terminal']=c is None or c.poll() is not None;save()
print('PASS disk-free v2 smoke')
