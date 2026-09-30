#!/usr/bin/env python3
"""Host-only saved-reference comparison tests; no model execution."""
from pathlib import Path
import tempfile,shutil
import check_comparison as c
r=c.P/'reference';text=(r/'original_reports.txt').read_text()+(r/'joint_reports.txt').read_text()+'RREAD_NEW arbitrary passive rows ignored here\n'
def bad(name,t,d):
 try:c.validate(t,d)
 except AssertionError:print('REJECT',name);return
 raise AssertionError('accepted '+name)
with tempfile.TemporaryDirectory() as temp:
 d=Path(temp)
 for n in c.CAPTURES:shutil.copy2(r/n,d/n)
 c.validate(text,d);print('PASS exact reports/NEXT/captures with new passive rows')
 bad('original report changed',text.replace('WHETSTONE_LOOP cycles=8724166','WHETSTONE_LOOP cycles=8724167'),d)
 bad('joint report changed',text.replace('NEXT_TOTAL edges=8724166','NEXT_TOTAL edges=8724167'),d)
 bad('joint row duplicated',text+'NEXT_TOTAL edges=8724166 joint=8724166 busy_op=1265136\n',d)
 (d/'native_globals.hex').write_bytes((d/'native_globals.hex').read_bytes()+b'00\n')
 bad('capture changed',text,d)
print('PASS comparison fixtures; no model executed')
