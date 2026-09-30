#!/usr/bin/env python3
from pathlib import Path
import subprocess,os,json,hashlib,datetime,sys,signal
E=Path(__file__).resolve().parent;P=E.parent/'native_whet_next_measurement_20260928'
meta={'status':'STARTING','launcher_pid':os.getpid(),'started_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'source_manifest_sha256':hashlib.sha256((P/'source_manifest.sha256').read_bytes()).hexdigest(),'stages':[]}
assert meta['source_manifest_sha256']=='e5393d16e3281cef14d365fd7a421db1e27e358aa47782d51d42a4f1dcde9d9a'
assert not (E/'execution.json').exists()
def save():(E/'execution.json').write_text(json.dumps(meta,indent=2)+'\n')
child=None
def interrupted(signum,frame):raise InterruptedError(f'launcher signal{signum}')
signal.signal(signal.SIGTERM,interrupted);signal.signal(signal.SIGINT,interrupted);save()
try:
 for variant in ['uninstrumented','profile']:
  meta['status']='RUNNING_'+variant.upper();save()
  child=subprocess.Popen([sys.executable,str(P/variant/'supervise.py')],cwd=P/variant)
  meta['stages'].append({'variant':variant,'supervisor_pid':child.pid});save()
  rc=child.wait(timeout=800);meta['stages'][-1]['exit_status']=rc;save();assert rc==0,(variant,rc)
  m=json.loads((P/variant/'supervisor.json').read_text());assert m['status']=='QUALIFIED_NATIVE_RUNTIME'
  meta['stages'][-1].update(runner_pid=m['runner_pid'],native_pid=m['native_pid'],native_exe_sha256=m['native_exe_sha256']);save()
  child=None
 meta['status']='CHECKING_PAIR';save()
 with (E/'pair_check.log').open('x') as log:
  rc=subprocess.run([sys.executable,str(P/'check_pair.py')],stdout=log,stderr=subprocess.STDOUT,timeout=120).returncode
 meta['pair_check_exit_status']=rc;assert rc==0
 meta['status']='QUALIFIED_PAIR'
except BaseException as exc:
 meta['status']='FAILED';meta['error']=repr(exc)
 if child is not None and child.poll() is None:
  child.terminate()
  try:child.wait(timeout=20)
  except subprocess.TimeoutExpired:child.kill();child.wait()
 raise
finally:
 meta['finished_utc']=datetime.datetime.now(datetime.timezone.utc).isoformat();save()
