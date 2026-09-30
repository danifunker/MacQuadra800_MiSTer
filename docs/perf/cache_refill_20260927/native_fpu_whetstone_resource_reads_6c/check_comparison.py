#!/usr/bin/env python3
"""Require passive probe to preserve completed 6c reports and four captures."""
from pathlib import Path
import hashlib,sys,json
P=Path(__file__).resolve().parent
KEEP=('WHETSTONE','BUS32','SDRAM','BERR','CORE_LAT','EXT','WALKER','STOREBUF','BRIDGE','FPU_ELIG','NATIVE')
CAPTURES=('native_abi.hex','native_code.hex','native_globals.hex','native_stack.hex')
def validate(text,captures):
 r=P/'reference';identity=json.loads((r/'identity.json').read_text())
 assert identity['loop_cycles']==8724166 and identity['candidate_fpu_sha256']=='6c157b3bc045e74a90416f4764f35cf65024e77577019a100b8aa9b5bdd9ce9b'
 for n,h in identity['copied_files'].items():assert hashlib.sha256((r/n).read_bytes()).hexdigest()==h,n
 original='\n'.join(x for x in text.splitlines() if x.startswith(KEEP))+'\n'
 joint='\n'.join(x for x in text.splitlines() if x.startswith('NEXT_'))+'\n'
 assert original==(r/'original_reports.txt').read_text(),'changed original report'
 assert joint==(r/'joint_reports.txt').read_text(),'changed original NEXT report'
 for n in CAPTURES:assert (Path(captures)/n).read_bytes()==(r/n).read_bytes(),n
 return {'original_reports':'byte-exact','joint_reports':'byte-exact','four_captures':'byte-exact','reference_log_sha256':identity['completed_log_sha256']}
if __name__=='__main__':
 for row in (P/'source_manifest.sha256').read_text().splitlines():
  h,n=row.split('  ',1);assert hashlib.sha256((P/n).read_bytes()).hexdigest()==h,n
 log=Path(sys.argv[1]);print(json.dumps(validate(log.read_text(),log.parent),indent=2));print('PASS unchanged completed6c reports and four captures')
