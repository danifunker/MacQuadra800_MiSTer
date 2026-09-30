#!/usr/bin/env python3
from pathlib import Path
import hashlib,json,re,subprocess,sys
P=Path(__file__).resolve().parent
for row in (P/'archive_manifest.sha256').read_text().splitlines():
 h,n=row.split('  ',1);assert hashlib.sha256((P/n).read_bytes()).hexdigest()==h,n
execution=json.loads((P/'execution.json').read_text());assert execution['status']=='QUALIFIED_PAIR' and execution['pair_check_exit_status']==0
assert execution['source_manifest_sha256']=='e5393d16e3281cef14d365fd7a421db1e27e358aa47782d51d42a4f1dcde9d9a'
assert hashlib.sha256((P/'source_manifest.sha256').read_bytes()).hexdigest()==execution['source_manifest_sha256']
logs=[]
for v in ['uninstrumented','profile']:
 d=P/v;m=json.loads((d/'supervisor.json').read_text());assert m['status']=='QUALIFIED_NATIVE_RUNTIME' and m['exit_status']==0 and m['runner_terminal'] and m['postrun_source_manifest']=='PASS'
 assert m['candidate_fpu']=='6c157b3bc045e74a90416f4764f35cf65024e77577019a100b8aa9b5bdd9ce9b'
 subprocess.run([sys.executable,str(d/'check_result.py')],check=True)
 logs.append((d/'run/run.log').read_text())
assert all(re.search(r'WHETSTONE_LOOP cycles=(\d+)',x)[1]=='8724166' for x in logs)
for f in ['native_abi.hex','native_code.hex','native_globals.hex','native_stack.hex']:
 assert (P/'uninstrumented/run'/f).read_bytes()==(P/'profile/run'/f).read_bytes(),f
keep=('WHETSTONE','BUS32','SDRAM','BERR','CORE_LAT','EXT','WALKER','STOREBUF','BRIDGE','FPU_ELIG','NATIVE')
assert [x for x in logs[0].splitlines() if x.startswith(keep)]==[x for x in logs[1].splitlines() if x.startswith(keep)]
subprocess.run([sys.executable,str(P/'check_profile.py'),str(P/'profile/run/run.log')],check=True)
subprocess.run([sys.executable,str(P/'test_checker.py')],check=True)
from check_profile import parse
rows=parse(logs[1]);s=json.loads((P/'result_summary.json').read_text())
assert s['loop_cycles_each']==8724166
assert sum(x['sum']-x['n'] for x in rows['GROUP'] if x['plane']==1)==s['translated_total_excess_over_one']==810867
assert sum(x['sum']-x['n'] for x in rows['GROUP'] if x['plane']==1 and x['addr_region']==0)==s['translated_ROM_excess_over_one']==172693
print('PASS compact6c native Whetstone joint-profile archive; matched runtime/captures/reports, valid exclusive/episode counters; numerical oracle NONE')
