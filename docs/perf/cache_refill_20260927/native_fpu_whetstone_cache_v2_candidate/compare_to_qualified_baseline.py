#!/usr/bin/env python3
"""Post-run invariant capture checks and aggregate Whetstone counter summary."""
from pathlib import Path
import hashlib,json,re
ROOT=Path(__file__).resolve().parent
C=ROOT/'candidate'; B=ROOT.parent.parent/'docs/perf/cache_refill_20260927/native_fpu_whetstone_joint_profile_6c/profile/run'
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
assert json.loads((C/'supervisor.json').read_text())['status']=='QUALIFIED_CANDIDATE'
assert (C/'postrun_source_manifest.sha256').read_bytes()==(C/'source_manifest.sha256').read_bytes()
meta=json.loads((C/'supervisor.json').read_text()); assert meta['status']=='QUALIFIED_CANDIDATE' and meta['exit_status']==0 and meta['postrun_source_manifest']=='PASS'
for n in ('native_abi.hex','native_code.hex','native_globals.hex','native_stack.hex'):
 assert (B/n).read_bytes()==(C/'run'/n).read_bytes(),f'qualified baseline capture differs: {n}'
base=(B/'run.log').read_text(); cand=(C/'run/run.log').read_text()
def loop(t):
 m=re.search(r'WHETSTONE_LOOP cycles=(\d+)',t);assert m;return int(m[1])
def keyed(t,pattern,group):
 out={}
 for m in re.finditer(pattern,t,re.M):out[','.join(m.group(i) for i in group[:-1]) or 'all']=int(m.group(group[-1]))
 return out
bc=keyed(base,r'NATIVE_CACHE state=(\d+) samples=(\d+)',(1,2));cc=keyed(cand,r'NATIVE_CACHE state=(\d+) samples=(\d+)',(1,2))
shape=keyed(base,r'BUS32_SHAPE class=(\d+) size=(\d+) addr\[3:0\]=([0-9a-f]+) n=(\d+)',(1,2,3,4))
cshape=keyed(cand,r'BUS32_SHAPE class=(\d+) size=(\d+) addr\[3:0\]=([0-9a-f]+) n=(\d+)',(1,2,3,4))
region=keyed(base,r'BUS32_REGION class=(\d+) addr=([0-9a-f]+) n=(\d+)',(1,2,3));cregion=keyed(cand,r'BUS32_REGION class=(\d+) addr=([0-9a-f]+) n=(\d+)',(1,2,3))
read_bus=lambda t:tuple(map(int,re.search(r'EXT read_bus32 n=(\d+) sum=(\d+)',t).groups()))
summary={'baseline_loop_cycles':loop(base),'candidate_loop_cycles':loop(cand),'candidate_wrapper_start_local':meta['started_local'],'candidate_wrapper_finish_local':meta['finished_local'],'candidate_wrapper_exit_status':meta['exit_status'],'exec_session_id':92103,'runner_pid_namespace':meta['runner_pid'],'native_pid_namespace':meta['native_pid'],'native_executable_sha256':meta['native_exe_sha256'],'candidate_compile_jobs':meta['compile_jobs'],'candidate_supervisor_cap_seconds':meta['supervisor_timeout_seconds'],'candidate_source_manifest_sha256':meta['source_manifest_sha256'],'candidate_source_manifest_count':meta['source_manifest_count'],'candidate_postrun_source_manifest':'PASS','candidate_run_log_sha256':sha(C/'run/run.log'),'baseline_run_log_sha256':sha(B/'run.log'),'candidate_compile_log_sha256':sha(C/'run/compile.log'),'candidate_compile_wall_seconds':31.155,'delta_cycles':loop(cand)-loop(base),'delta_percent':100*(loop(cand)-loop(base))/loop(base),'baseline_NATIVE_CACHE':bc,'candidate_NATIVE_CACHE':cc,'baseline_EXT_read_bus32_n_sum':read_bus(base),'candidate_EXT_read_bus32_n_sum':read_bus(cand),'baseline_BUS32_SHAPE_class2_size2_offsetE':shape.get('2,2,e',0),'candidate_BUS32_SHAPE_class2_size2_offsetE':cshape.get('2,2,e',0),'baseline_BUS32_REGION_class2_0600000':region.get('2,0600000',0),'candidate_BUS32_REGION_class2_0600000':cregion.get('2,0600000',0),'final_memory_captures':'BYTE_EXACT','scope':'single native selector1 Whetstone fixture; aggregate attribution only; not an exact EAE/path identity, numerical oracle, fullguest result, FPGA timing or hardware result'}
(ROOT/'comparison.json').write_text(json.dumps(summary,indent=2)+'\n')
print(json.dumps(summary,indent=2));print('PASS candidate runtime profile and final captures compare against qualified baseline')
