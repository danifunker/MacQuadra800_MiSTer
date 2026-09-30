#!/usr/bin/env python3
from pathlib import Path
import hashlib,json,re
D=Path(__file__).resolve().parent
for line in (D/'archive.sha256').read_text().splitlines():
 h,n=line.split('  ',1);assert hashlib.sha256((D/n).read_bytes()).hexdigest()==h,n
q=json.loads((D/'qualification.json').read_text());assert q['status']=='PASS' and q['excluded_and_restore_signatures']==43
logs=[(D/(x+'.run.log')).read_text() for x in ['baseline','candidate']]
for t in logs:assert 'PASS normal_single checks=16301' in t and not re.search(r'FATAL|TEST FAILED',t)
assert [x for x in logs[0].splitlines() if x.startswith('SIG')]==[x for x in logs[1].splitlines() if x.startswith('SIG')]
assert 'fast=0 slow=16298' in logs[0] and 'fast=16256 slow=42' in logs[1]
print('PASS archive hashes;16301 checks each;16256 eligible;43 excluded/restore signatures match')
