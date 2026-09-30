#!/usr/bin/env python3
from pathlib import Path
import subprocess,hashlib,json,datetime,os,signal,sys
S=Path(__file__).resolve().parent;D=S.parent/'fpu_normal_single_enabled_fullmachine_20260928';V=D/'verilator'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
assert sha(D/'source_manifest.sha256')=='6ce6d46953c97a8de7c4944d189ef5af62dcfcdb712a896f8164e99bb03c3094'
def verify():
 for row in (D/'source_manifest.sha256').read_text().splitlines():
  h,n=row.split('  ',1);assert sha(Path(n))==h,n
verify();assert sha(D/'rtl/ap68040/rtl/ap040_fpu.v')=='6c157b3bc045e74a90416f4764f35cf65024e77577019a100b8aa9b5bdd9ce9b';assert not (V/'obj_dir').exists()
for n in ['build.log','build.meta.json','completed_build_identity.json']:assert not (S/n).exists(),n
tool=Path('/home/alans/verilator5/bin/verilator');version=subprocess.check_output([str(tool),'--version'],text=True).strip();assert '5.050' in version
meta={'status':'STARTING','supervisor_pid':os.getpid(),'started_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'source_manifest_sha256':sha(D/'source_manifest.sha256'),'before_manifest':'PASS','tool_version':version,'tool_sha256':sha(tool),'supervisor_sha256':sha(Path(__file__)),'commands':[]}
def save():(S/'build.meta.json').write_text(json.dumps(meta,indent=2)+'\n')
save();env=os.environ.copy();env['PATH']=str(tool.parent)+':'+env['PATH'];env['CCACHE_DIR']=str(S/'ccache');child=None
try:
 with (S/'build.log').open('w') as log:
  for cmd in [['make','fastboot'],['make','-j2','V='+str(tool)]]:
   child=subprocess.Popen(cmd,cwd=V,env=env,stdout=log,stderr=subprocess.STDOUT,start_new_session=True);entry={'argv':cmd,'child_pid':child.pid};meta['commands'].append(entry);meta['status']='BUILDING';save();print('BUILD_CHILD',child.pid,cmd,flush=True)
   try:rc=child.wait(timeout=900)
   except subprocess.TimeoutExpired:
    os.killpg(child.pid,signal.SIGTERM)
    try:child.wait(timeout=10)
    except subprocess.TimeoutExpired:os.killpg(child.pid,signal.SIGKILL);child.wait()
    entry['timeout']=True;raise
   entry['exit_status']=rc;save();assert rc==0,cmd
 verify();meta['after_manifest']='PASS';assert sha(V/'quadra800-fastboot.rom.hex')=='045c02746b5f15f83132d33c5414f806e7b049f3bfe53a7bd0ecacb8e072d673'
 binary=V/'obj_dir/Vemu';assert binary.exists()
 identity={'status':'PASS','binary_sha256':sha(binary),'candidate_sha256':sha(D/'rtl/ap68040/rtl/ap040_fpu.v'),'source_manifest_sha256':sha(D/'source_manifest.sha256'),'sim_v_sha256':sha(V/'sim.v'),'sim_main_sha256':sha(V/'sim_main.cpp'),'observer_sha256':sha(V/'sim_fpu_guard_profile.h'),'ROM_sha256':sha(V/'quadra800-fastboot.rom.hex'),'tool_version':version,'generated_verFiles_sha256':sha(V/'obj_dir/Vemu__verFiles.dat'),'build_log_sha256':sha(S/'build.log'),'flags':'all10 releaseCPU plusSCSI_CACHE_OFF;unroll256;8+8cache;model4/2','supervisor_sha256':sha(Path(__file__))}
 (S/'completed_build_identity.json').write_text(json.dumps(identity,indent=2)+'\n');meta['status']='PASS'
except BaseException as exc:
 meta['status']='FAILED';meta['error']=repr(exc)
 if child is not None and child.poll() is None:os.killpg(child.pid,signal.SIGKILL);child.wait()
 try:verify();meta['after_manifest']='PASS'
 except BaseException as e:meta['after_manifest']=repr(e)
 raise
finally:
 meta['finished_utc']=datetime.datetime.now(datetime.timezone.utc).isoformat();save()
print('PASS BUILD',identity['binary_sha256'],flush=True)
