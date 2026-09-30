#!/usr/bin/env python3
from pathlib import Path
import argparse,subprocess,hashlib,json,os,datetime,signal,sys
P=Path(__file__).resolve().parent;out=P/'run';sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
a=argparse.ArgumentParser();a.add_argument('--launch',action='store_true',required=True);args=a.parse_args()
identity=json.loads((P/'inputs.json').read_text());D=Path(identity['source_project']);binary=Path(identity['binary_path'])
def verify():
 for row in (P/'package_manifest.sha256').read_text().splitlines():
  h,n=row.split('  ',1);assert sha(Path(n))==h,n
 assert sha(D/'source_manifest.sha256')==identity['source_manifest_sha256']
 for row in (D/'source_manifest.sha256').read_text().splitlines():
  h,n=row.split('  ',1);assert sha(Path(n))==h,n
 assert sha(binary)==identity['binary_sha256']
 assert sha(D/'rtl/ap68040/rtl/ap040_fpu.v')==identity['candidate_fpu']
 assert sha(P/'completed_build_identity.json')==identity['build_identity_sha256']
 assert sha(P/'check_guard_report.py')==identity['checker_sha256']
 assert sha(P/'check_refill_report.py')==identity['refill_checker_sha256']
verify();assert {p.name for p in out.iterdir()}=={'control.txt','run.hda','rom.hex'},'fresh outputs required; no overwrite'
for n,h in identity['prelaunch_files'].items():assert sha(out/n)==h,n
assert len('rom.hex')<=128
cmd=[str(binary),'--headless','--no-cpu-trace','--disk','run.hda','+rom=rom.hex','+ram=0','--control','control.txt','--cpu-profile','refill.tsv','--max-cycles','20000000000','+ram_line_model','+ram_first_latency=4','+ram_line_publish_delay=2']
m={'status':'STARTING','kind':identity['kind'],'supervisor_pid':os.getpid(),'started_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'argv':cmd,'package_manifest_sha256':sha(P/'package_manifest.sha256'),'input_identity_sha256':sha(P/'inputs.json'),'supervisor_sha256':sha(Path(__file__)),'source_manifest_sha256':identity['source_manifest_sha256'],'binary_sha256':identity['binary_sha256'],'golden_input_disk_sha256':identity['prelaunch_files']['run.hda'],'control_sha256':identity['prelaunch_files']['control.txt'],'ROM_sha256':identity['prelaunch_files']['rom.hex'],'wall_timeout_seconds':10800,'observer_allow_empty':True,'guest_gate':identity['guest_gate']}
def save():(out/'run.meta.json').write_text(json.dumps(m,indent=2)+'\n')
c=None
class Interrupted(Exception):pass
def stop(signum,frame):m['signal']=signum;raise Interrupted()
signal.signal(signal.SIGTERM,stop);signal.signal(signal.SIGINT,stop);save()
try:
 with (out/'run.log').open('w') as log:
  c=subprocess.Popen(cmd,cwd=out,stdout=log,stderr=subprocess.STDOUT,start_new_session=True);m['child_pid']=c.pid;m['running_exe_sha256']=sha(Path('/proc')/str(c.pid)/'exe');assert m['running_exe_sha256']==m['binary_sha256'];m['status']='RUNNING';save();print('CHILD',c.pid,'SUPERVISOR',os.getpid(),m['binary_sha256'],flush=True);rc=c.wait(timeout=10800);m['exit_status']=rc;assert rc==0
 assert 'file not found' not in (out/'run.log').read_text(errors='replace').lower(),'memory image load failure'
 verify();m['postrun_source_manifest']='PASS'
 for name,argv in [('refill',[sys.executable,str(P/'check_refill_report.py'),str(out/'refill.tsv')]),('observer',[sys.executable,str(P/'check_guard_report.py'),str(out/'refill.tsv'),'--allow-empty'])]:
  with (out/(name+'_check.log')).open('w') as log:q=subprocess.run(argv,stdout=log,stderr=subprocess.STDOUT,timeout=60)
  m[name+'_check_exit_status']=q.returncode;save();assert q.returncode==0,name
 m['screens']={}
 for name in [identity['expected_setup_screen'],identity['expected_terminal_screen']]:
  assert (out/name).exists(),name;m['screens'][name]=sha(out/name)
 for name in ['rom.hex','control.txt']:assert sha(out/name)==identity['prelaunch_files'][name]
 m['status']='EXIT0_REFILL_OBSERVER_PASS_PENDING_SCREENSHOT_REVIEW'
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
 if 'exit_status' in m:(out/'exit_status.txt').write_text(str(m['exit_status'])+'\n')
