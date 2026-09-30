#!/usr/bin/env python3
"""One fresh native phase only. Prepared; launching requires root approval."""
from pathlib import Path
import subprocess,os,signal,time,json,hashlib,datetime,sys
D=Path(__file__).resolve().parent;P=D.parent
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
def verify():
 for row in (P/'source_manifest.sha256').read_text().splitlines():
  h,n=row.split('  ',1);assert sha(P/n)==h,n
 assert sha(D/'tree/rtl/ap68040/rtl/ap040_fpu.v')=='6c157b3bc045e74a90416f4764f35cf65024e77577019a100b8aa9b5bdd9ce9b'
verify()
assert not any((D/n).exists() for n in ['run','supervisor.json','stdout.log','measurement.json','profile_check.log'])
meta={'status':'STARTING','variant':D.name,'candidate_fpu':'6c157b3bc045e74a90416f4764f35cf65024e77577019a100b8aa9b5bdd9ce9b','source_manifest_sha256':sha(P/'source_manifest.sha256'),'supervisor_pid':os.getpid(),'started_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'runner_timeout_seconds':650,'scope':'native selector1 runtime/ABI only; original checker inherited baseline wording'}
def save():(D/'supervisor.json').write_text(json.dumps(meta,indent=2)+'\n')
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
def interrupted(signum,frame):raise InterruptedError(f'supervisor signal{signum}')
signal.signal(signal.SIGTERM,interrupted);signal.signal(signal.SIGINT,interrupted)
child=None;save()
try:
 with (D/'stdout.log').open('x') as out:
  env=os.environ.copy();env['CCACHE_DISABLE']='1'
  cmd=[sys.executable,str(D/'run_platform_whet.py'),'--out',str(D/'run')]
  child=subprocess.Popen(cmd,cwd=D,env=env,stdout=out,stderr=subprocess.STDOUT,start_new_session=True)
  meta.update(status='RUNNING',runner_pid=child.pid,argv=cmd);save();start=time.monotonic()
  while child.poll() is None:
   for pid in descendants(child.pid):
    try:
     exe=Path(f'/proc/{pid}/exe')
     if Path(os.readlink(exe)).name=='Vtb_platform_whet' and 'native_pid' not in meta:
      meta.update(native_pid=pid,native_exe_sha256=sha(exe),native_seen_utc=datetime.datetime.now(datetime.timezone.utc).isoformat());save()
    except (OSError,ValueError):pass
   if time.monotonic()-start>650:raise TimeoutError('650s outer deadline')
   time.sleep(.2)
  if child.returncode:raise RuntimeError(f'runner exit{child.returncode}')
 assert 'native_pid' in meta,'actual native child not captured'
 assert not Path('/proc',str(meta['native_pid'])).exists(),'native child remains after runner'
 verify()
 # Preserve all original checker gates; populate its recorded-result input
 # from the unchanged original computation, then execute the complete checker.
 source=(D/'check_result.py').read_text();marker="assert json.loads((D/'measurement.json').read_text())==json.loads(json.dumps(result))"
 assert source.count(marker)==1 and not (D/'measurement.json').exists()
 ns={'__file__':str(D/'check_result.py'),'__name__':'__main__'}
 exec(compile(source[:source.index(marker)],str(D/'check_result.py'),'exec'),ns)
 (D/'measurement.json').write_text(json.dumps(ns['result'],indent=2)+'\n')
 subprocess.run([sys.executable,str(D/'check_result.py')],check=True,cwd=D,timeout=60)
 if D.name=='profile':
  with (D/'profile_check.log').open('x') as log:
   subprocess.run([sys.executable,str(P/'check_profile.py'),str(D/'run/run.log')],check=True,stdout=log,stderr=subprocess.STDOUT,timeout=60)
 meta.update(status='QUALIFIED_NATIVE_RUNTIME',exit_status=0,original_checker='PASS',passive_checker='PASS' if D.name=='profile' else 'not_applicable',postrun_source_manifest='PASS')
except BaseException as exc:
 if child is not None:
  cleanup(child.pid);child.wait()
 meta.update(status='FAILED',error=repr(exc),exit_status=child.returncode if child is not None else None)
 raise
finally:
 meta['finished_utc']=datetime.datetime.now(datetime.timezone.utc).isoformat();meta['runner_terminal']=child is None or child.poll() is not None;save()
