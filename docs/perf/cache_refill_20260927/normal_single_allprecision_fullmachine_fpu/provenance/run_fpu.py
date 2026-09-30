#!/usr/bin/env python3
from pathlib import Path
import argparse,subprocess,hashlib,json,os,datetime,signal,sys
S=Path(__file__).resolve().parent;D=S.parent/'fpu_normal_single_allprecision_fullmachine_20260928';out=D/'fpu_run'
p=argparse.ArgumentParser();p.add_argument('--launch',action='store_true',required=True);a=p.parse_args()
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def verify():
 assert sha(D/'source_manifest.sha256')=='cd794af982858ddbb3f116345bf9dd301111897c73c575a343f6283ccc58ab0f'
 for row in (D/'source_manifest.sha256').read_text().splitlines():
  h,n=row.split('  ',1);assert sha(Path(n))==h,n
verify();build=json.loads((S/'completed_build_identity.json').read_text());assert build['status']=='PASS'
assert build['candidate_sha256']=='55ff9b3cd1d59069ec0b94ca17e4dc3a8c87ac031317902285444d92643724a2'
binary=D/'verilator/obj_dir/Vemu';assert sha(binary)==build['binary_sha256']
assert sha(out/'run.hda')=='80d8479430a66edae161c2bac6a9563dbb4f6bd0f564ee7849a555c447df8888'
assert sha(out/'control.txt')=='33108dcd7af064820bb59ae89f72c77a2f8a62b74bbee73f86bd912c244253e4'
assert sha(D/'verilator/quadra800-fastboot.rom.hex')=='045c02746b5f15f83132d33c5414f806e7b049f3bfe53a7bd0ecacb8e072d673'
assert {p.name for p in out.iterdir()}=={'run.hda','control.txt'},'fresh outputs required; no overwrite'
cmd=[str(binary),'--headless','--no-cpu-trace','--disk','run.hda','+rom=../verilator/quadra800-fastboot.rom.hex','+ram=0','--control','control.txt','--cpu-profile','refill.tsv','--max-cycles','20000000000','+ram_line_model','+ram_first_latency=4','+ram_line_publish_delay=2']
assert len('../verilator/quadra800-fastboot.rom.hex')<=128
meta={'status':'STARTING','supervisor_pid':os.getpid(),'started_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'argv':cmd,'wall_timeout_seconds':10800,'source_manifest_sha256':sha(D/'source_manifest.sha256'),'binary_sha256':sha(binary),'build_identity_sha256':sha(S/'completed_build_identity.json'),'supervisor_sha256':sha(Path(__file__)),'observer_checker_sha256':sha(S/'check_guard_report.py'),'golden_input_disk_sha256':sha(out/'run.hda'),'control_sha256':sha(out/'control.txt')}
def save():(out/'run.meta.json').write_text(json.dumps(meta,indent=2)+'\n')
child=None
class Interrupted(Exception):pass
def stop(signum,frame):meta['signal']=signum;raise Interrupted()
signal.signal(signal.SIGTERM,stop);signal.signal(signal.SIGINT,stop)
save()
try:
 with (out/'run.log').open('w') as log:
  child=subprocess.Popen(cmd,cwd=out,stdout=log,stderr=subprocess.STDOUT,start_new_session=True);meta['child_pid']=child.pid;meta['running_exe_sha256']=sha(Path('/proc')/str(child.pid)/'exe');assert meta['running_exe_sha256']==meta['binary_sha256'];meta['status']='RUNNING';save();print('FPU_CHILD',child.pid,'SUPERVISOR',os.getpid(),meta['binary_sha256'],flush=True)
  rc=child.wait(timeout=10800);meta['exit_status']=rc;assert rc==0,rc
 assert 'file not found' not in (out/'run.log').read_text(errors='replace').lower(),'memory image load failure'
 verify();meta['postrun_source_manifest']='PASS'
 for name,cmdcheck in [('refill',[sys.executable,str(D/'verilator/tests/check_refill_report.py'),str(out/'refill.tsv')]),('observer',[sys.executable,str(S/'check_guard_report.py'),str(out/'refill.tsv')])]:
  with (out/(name+'_check.log')).open('w') as log:check=subprocess.run(cmdcheck,stdout=log,stderr=subprocess.STDOUT,timeout=60)
  meta[name+'_check_exit_status']=check.returncode;save();assert check.returncode==0,name
 meta['status']='EXIT0_REFILL_OBSERVER_PASS_PENDING_SCREENSHOT_REVIEW'
except BaseException as exc:
 meta['status']='FAILED';meta['error']=repr(exc)
 if child is not None and child.poll() is None:
  os.killpg(child.pid,signal.SIGTERM)
  try:child.wait(timeout=10)
  except subprocess.TimeoutExpired:os.killpg(child.pid,signal.SIGKILL);child.wait()
 if child is not None:meta['exit_status']=child.returncode
 raise
finally:
 meta['finished_utc']=datetime.datetime.now(datetime.timezone.utc).isoformat();meta['child_terminal']=child is None or child.poll() is not None;save()
 if 'exit_status' in meta:(out/'exit_status.txt').write_text(str(meta['exit_status'])+'\n')
