#!/usr/bin/env python3
"""Require matched native outcomes after two separately authorized phases."""
from pathlib import Path
import json,re,hashlib,subprocess,sys
P=Path(__file__).resolve().parent
for row in (P/'source_manifest.sha256').read_text().splitlines():
 h,n=row.split('  ',1);assert hashlib.sha256((P/n).read_bytes()).hexdigest()==h,n
logs=[]
for name in ['uninstrumented','profile']:
 d=P/name;m=json.loads((d/'supervisor.json').read_text());assert m['status']=='QUALIFIED_NATIVE_RUNTIME' and m['exit_status']==0 and m['runner_terminal']
 assert m['candidate_fpu']=='6c157b3bc045e74a90416f4764f35cf65024e77577019a100b8aa9b5bdd9ce9b' and m['postrun_source_manifest']=='PASS'
 subprocess.run([sys.executable,str(d/'check_result.py')],check=True)
 logs.append((d/'run/run.log').read_text())
assert re.search(r'WHETSTONE_LOOP cycles=(\d+)',logs[0])[1]==re.search(r'WHETSTONE_LOOP cycles=(\d+)',logs[1])[1]
for file in ['native_abi.hex','native_code.hex','native_globals.hex','native_stack.hex']:
 assert (P/'uninstrumented/run'/file).read_bytes()==(P/'profile/run'/file).read_bytes(),file
# Added passive diagnostics alone may differ; existing measured reports match.
keep=('WHETSTONE','BUS32','SDRAM','BERR','CORE_LAT','EXT','WALKER','STOREBUF','BRIDGE','FPU_ELIG','NATIVE')
old=lambda log:[x for x in log.splitlines() if x.startswith(keep)]
assert old(logs[0])==old(logs[1]),'passive instrumentation changed original reports'
subprocess.run([sys.executable,str(P/'check_profile.py'),str(P/'profile/run/run.log')],check=True)
print('PASS matched6c native runtime/gates/memory/reports; passive-only difference; numerical oracle NONE')
