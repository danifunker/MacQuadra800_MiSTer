#!/usr/bin/env python3
"""Fail-closed inventory and identity checker for the compact native result."""
from pathlib import Path
import hashlib,json,re
D=Path(__file__).resolve().parent
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
rows={}
for line in (D/'SHA256SUMS.txt').read_text().splitlines():
 h,n=line.split('  ',1);assert re.fullmatch(r'[0-9a-f]{64}',h) and n not in rows;rows[n]=h
expected={p.relative_to(D).as_posix() for p in D.rglob('*') if p.is_file() and p.name!='SHA256SUMS.txt'}
assert set(rows)==expected, f'inventory differs: missing={expected-set(rows)} extra={set(rows)-expected}'
for n,h in rows.items():assert sha(D/n)==h,n
assert not any(p.name in {'__pycache__','obj','Vtb_platform_whet'} or p.suffix in {'.o','.vvp','.so','.a'} for p in D.rglob('*'))
ref=json.loads((D/'baseline_reference.json').read_text())
comparison=json.loads((D/'comparison.json').read_text())
runmeta=json.loads((D/'candidate_supervisor.json').read_text())
bid=json.loads((D/'reference/run_identity.json').read_text())
cid=json.loads((D/'candidate_run_identity.json').read_text())
assert runmeta['status']=='QUALIFIED_CANDIDATE' and runmeta['exit_status']==0 and runmeta['runner_exit_status']==0
assert runmeta['profile_check']=='PASS' and runmeta['runtime_abi_check']=='PASS' and runmeta['postrun_source_manifest']=='PASS'
assert runmeta['source_manifest_count']==128 and runmeta['source_manifest_sha256']==comparison['candidate_source_manifest_sha256']
assert sha(D/'candidate_source_manifest.sha256')==runmeta['source_manifest_sha256']
assert (D/'candidate_postrun_source_manifest.sha256').read_bytes()==(D/'candidate_source_manifest.sha256').read_bytes()
assert sha(D/'candidate_run.log')==comparison['candidate_run_log_sha256'] and sha(D/'reference/run.log')==ref['run_log_sha256']==comparison['baseline_run_log_sha256']
assert sha(D/'candidate_compile.log')==comparison['candidate_compile_log_sha256']
assert bid['image_sha256']==ref['image_sha256'] and bid['rom_sha256']==ref['rom_sha256'] and bid['romlat']==ref['romlat']==6
assert cid['image_sha256']==ref['image_sha256'] and cid['rom_sha256']==ref['rom_sha256'] and cid['romlat']==6
assert cid['sources'][next(k for k in cid['sources'] if k.endswith('/ap040_cache.v'))]=='9e8c0582db1b0bb88428e56fec63e99029b61faffac62c6f3dda9326b5191481'
assert cid['sources'][next(k for k in cid['sources'] if k.endswith('/ap040_fpu.v'))]=='6c157b3bc045e74a90416f4764f35cf65024e77577019a100b8aa9b5bdd9ce9b'
assert re.search(r'WHETSTONE_LOOP cycles=8724166', (D/'reference/run.log').read_text())
assert re.search(r'WHETSTONE_LOOP cycles=8541493', (D/'candidate_run.log').read_text())
for name,h in ref['captures'].items():
 assert sha(D/'reference/captures'/name)==h
 assert (D/'reference/captures'/name).read_bytes()==(D/'candidate_captures'/name).read_bytes(),name
manifest={}
for line in (D/'candidate_source_manifest.sha256').read_text().splitlines():
 h,n=line.split('  ',1);manifest[n]=h
for archived,source_rel in [('source/supervise_candidate.py','supervise_candidate.py'),('source/run_platform_whet.py','run_platform_whet.py'),('source/check_result.py','check_result.py'),('source/check_profile.py','check_profile.py'),('source/tb_platform_whet.sv','tb_platform_whet.sv'),('source/next_monitor.svh','next_monitor.svh'),('source/candidate_ap040_cache.v','tree/rtl/ap68040/rtl/ap040_cache.v'),('source/assets/tb_sdram.sv','assets/tb_sdram.sv'),('source/assets/altddio_out_stub.v','assets/altddio_out_stub.v')]:
 assert manifest[source_rel]==sha(D/archived), archived
assert comparison['final_memory_captures']=='BYTE_EXACT' and comparison['candidate_wrapper_exit_status']==0
assert comparison['delta_cycles']==-182673 and abs(comparison['delta_percent']-(-2.093873500343758))<1e-12
assert comparison['candidate_NATIVE_CACHE']['6']==630743 and comparison['candidate_NATIVE_CACHE']['4']==8300
assert comparison['candidate_EXT_read_bus32_n_sum']==[0,0]
print(f"PASS native cache-v2 archive: {len(rows)} archived files; candidate exit0; source and baseline identities pinned; four captures byte-exact")
print(f"Native cycles {comparison['baseline_loop_cycles']} -> {comparison['candidate_loop_cycles']} ({comparison['delta_percent']:.5f}%); aggregate-only attribution")
