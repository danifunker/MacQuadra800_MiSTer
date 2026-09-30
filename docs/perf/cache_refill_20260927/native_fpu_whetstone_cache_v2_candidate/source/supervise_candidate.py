#!/usr/bin/env python3
"""Single reviewed native cache-v2 candidate run; no automatic retry."""
from pathlib import Path
import datetime, hashlib, json, os, signal, subprocess, sys, time
D=Path(__file__).resolve().parent
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
def verify_inputs():
 for row in (D/'source_manifest.sha256').read_text().splitlines():
  h,n=row.split('  ',1); p=D/n
  if not p.is_file() or sha(p)!=h: raise RuntimeError(f'input mismatch: {n}')
 if sha(D/'tree/rtl/ap68040/rtl/ap040_cache.v')!='9e8c0582db1b0bb88428e56fec63e99029b61faffac62c6f3dda9326b5191481': raise RuntimeError('candidate cache identity mismatch')
 if sha(D/'tree/rtl/ap68040/rtl/ap040_fpu.v')!='6c157b3bc045e74a90416f4764f35cf65024e77577019a100b8aa9b5bdd9ce9b': raise RuntimeError('FPU identity mismatch')
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
verify_inputs()
assert not any((D/n).exists() for n in ('run','supervisor.json','stdout.log','measurement.json','profile_check.log')),'outputs must be fresh'
meta={'status':'STARTING','started_local':datetime.datetime.now().astimezone().isoformat(),'source_manifest_sha256':sha(D/'source_manifest.sha256'),'source_manifest_count':len((D/'source_manifest.sha256').read_text().splitlines()),'cache_sha256':sha(D/'tree/rtl/ap68040/rtl/ap040_cache.v'),'fpu_sha256':sha(D/'tree/rtl/ap68040/rtl/ap040_fpu.v'),'compile_jobs':2,'compile_and_run_command_timeout_seconds':300,'supervisor_timeout_seconds':650,'romlat':6,'retry_count':0,'scope':'one native tEsT12000 selector1 Whetstone cache-v2 candidate; no independent numerical oracle'}
def save(): (D/'supervisor.json').write_text(json.dumps(meta,indent=2)+'\n')
child=None; save()
try:
 with (D/'stdout.log').open('x') as out:
  env=os.environ.copy();env['CCACHE_DISABLE']='1'
  cmd=[sys.executable,str(D/'run_platform_whet.py'),'--out',str(D/'run'),'--image',str(D/'ram.bin'),'--rom',str(D/'assets/quadra800.rom'),'--romlat','6']
  child=subprocess.Popen(cmd,cwd=D,env=env,stdout=out,stderr=subprocess.STDOUT,start_new_session=True)
  meta.update(status='RUNNING',runner_pid=child.pid,argv=cmd);save();start=time.monotonic()
  while child.poll() is None:
   for pid in descendants(child.pid):
    try:
     exe=Path(f'/proc/{pid}/exe')
     if Path(os.readlink(exe)).name=='Vtb_platform_whet' and 'native_pid' not in meta:
      meta.update(native_pid=pid,native_exe_sha256=sha(exe),native_seen_local=datetime.datetime.now().astimezone().isoformat());save()
    except (OSError,ValueError):pass
   if time.monotonic()-start>650:raise TimeoutError('candidate runner exceeded 650s')
   time.sleep(.2)
  if child.returncode:raise RuntimeError(f'runner exit {child.returncode}')
 if 'native_pid' not in meta:raise RuntimeError('native executable PID not observed')
 if Path('/proc',str(meta['native_pid'])).exists():raise RuntimeError('native executable remains after runner')
 verify_inputs()
 (D/'postrun_source_manifest.sha256').write_text((D/'source_manifest.sha256').read_text())
 # Recompute original runtime/ABI/code/stack and all passive profile totals.
 check=(D/'check_result.py').read_text(); marker="assert json.loads((D/'measurement.json').read_text())==json.loads(json.dumps(result))"
 if check.count(marker)!=1 or (D/'measurement.json').exists():raise RuntimeError('result checker/output not fresh')
 ns={'__file__':str(D/'check_result.py'),'__name__':'__main__'}
 exec(compile(check[:check.index(marker)],str(D/'check_result.py'),'exec'),ns)
 (D/'measurement.json').write_text(json.dumps(ns['result'],indent=2)+'\n')
 with (D/'profile_check.log').open('x') as log:
  subprocess.run([sys.executable,str(D/'check_profile.py'),str(D/'run/run.log')],check=True,cwd=D,stdout=log,stderr=subprocess.STDOUT,timeout=60)
 subprocess.run([sys.executable,str(D/'check_result.py')],check=True,cwd=D,timeout=60)
 meta.update(status='QUALIFIED_CANDIDATE',exit_status=0,runner_exit_status=0,profile_check='PASS',runtime_abi_check='PASS',postrun_source_manifest='PASS')
except BaseException as exc:
 if child is not None:
  cleanup(child.pid);child.wait()
 meta.update(status='FAILED',error=repr(exc),exit_status=child.returncode if child is not None else None)
 raise
finally:
 meta['finished_local']=datetime.datetime.now().astimezone().isoformat();meta['runner_terminal']=child is None or child.poll() is not None;save()
