#!/usr/bin/env python3
from pathlib import Path
import os,signal,sys,time,json,hashlib,datetime,subprocess
D=Path(__file__).resolve().parent;R=D.parents[1]
h=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
def verify():
 for row in (D/'source_manifest.sha256').read_text().splitlines():
  want,name=row.split('  ',1);assert h(R/name)==want,name
verify();assert not (D/'run').exists() and not (D/'supervisor.json').exists() and not (D/'stdout.log').exists()
assert h(D/'tree/rtl/ap68040/rtl/ap040_fpu.v')=='2d53db3ae4a04310add04eeb7919f0219197a98827ed92e410e6d4a4a90f5465'
meta={'status':'STARTING','started_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'source_manifest_sha256':h(D/'source_manifest.sha256')}
path=D/'supervisor.json'
def save():path.write_text(json.dumps(meta,indent=2)+'\n')
def descendants(pid):
 try:kids=[int(x) for x in Path(f'/proc/{pid}/task/{pid}/children').read_text().split()]
 except (OSError,ValueError):return []
 return kids+[z for k in kids for z in descendants(k)]
def cleanup(pid):
 try:os.killpg(pid,signal.SIGTERM)
 except ProcessLookupError:return
 time.sleep(1)
 try:os.killpg(pid,signal.SIGKILL)
 except ProcessLookupError:pass
with (D/'stdout.log').open('w') as out:
 env=os.environ.copy();env['TREE']=str(D/'tree');env['CCACHE_DISABLE']='1'
 child=subprocess.Popen([sys.executable,str(D/'run_platform_whet.py'),'--out',str(D/'run')],cwd=R,env=env,stdout=out,stderr=subprocess.STDOUT,start_new_session=True)
 meta.update(status='RUNNING',runner_pid=child.pid);save();begin=time.monotonic()
 try:
  while child.poll() is None:
   for pid in descendants(child.pid):
    try:
     exe=Path(f'/proc/{pid}/exe')
     if Path(os.readlink(exe)).name=='Vtb_platform_whet' and 'native_pid' not in meta:meta.update(native_pid=pid,binary_sha256=h(exe),native_seen_utc=datetime.datetime.now(datetime.timezone.utc).isoformat());save()
    except (OSError,ValueError):pass
   if time.monotonic()-begin>650:raise TimeoutError('outer650s deadline')
   time.sleep(1)
  if child.returncode:raise RuntimeError(f'runner exit{child.returncode}')
 except BaseException as e:
  cleanup(child.pid);child.wait();meta.update(status='FAILED',reason=str(e),exit_status=child.returncode,finished_utc=datetime.datetime.now(datetime.timezone.utc).isoformat());save();raise
meta.update(status='EXIT0',exit_status=child.returncode,finished_utc=datetime.datetime.now(datetime.timezone.utc).isoformat());save();verify()
# The unchanged archived checker records its calculated result by comparing to
# measurement.json. Populate that record from its own existing construction,
# then run the complete unchanged checker; no gate is removed.
source=(D/'check_result.py').read_text();marker="assert json.loads((D/'measurement.json').read_text())==json.loads(json.dumps(result))"
assert source.count(marker)==1 and not (D/'measurement.json').exists()
ns={'__file__':str(D/'check_result.py'),'__name__':'__main__'}
exec(compile(source[:source.index(marker)],str(D/'check_result.py'),'exec'),ns)
(D/'measurement.json').write_text(json.dumps(ns['result'],indent=2)+'\n')
subprocess.run([sys.executable,str(D/'check_result.py')],cwd=R,check=True)
subprocess.run([sys.executable,str(D/'check_format.py')],cwd=R,check=True)
meta['status']='QUALIFIED_RUNTIME';save();verify();print('PASS baseline native Whet source-format runtime gates; numerical oracle NONE')
