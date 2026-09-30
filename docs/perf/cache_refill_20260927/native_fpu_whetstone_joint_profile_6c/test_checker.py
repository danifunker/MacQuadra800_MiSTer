#!/usr/bin/env python3
from check_profile import validate
# Independently written sparse valid record: one immediate request, one70-cycle
# overflow request, and one boundary partial2-edge request per observation plane.
base='''NEXT_META format=native-whet-joint-v1 finish=BEFORE_ORIGINAL_DRAIN
NEXT_JOINT pc=0 cpu=0 fst=0 n=72
NEXT_JOINT pc=1 cpu=2 fst=14 n=1
NEXT_OP pc=1 cpu=2 op=00 n=1
NEXT_MARGIN id=0 pc=72 cpu=72
NEXT_MARGIN id=1 pc=1 cpu=0
NEXT_MARGIN id=2 pc=0 cpu=1
NEXT_MARGIN id=3 pc=0 cpu=0
NEXT_BG pc=1 cpu=2 n=1
NEXT_TOTAL edges=73 joint=73 busy_op=1
'''
plane='''NEXT_WAIT plane=P pc=0 cpu=0 fst=0 n=72
NEXT_WAIT plane=P pc=1 cpu=2 fst=14 n=1
NEXT_LAT plane=P pc=0 addr_region=0 kind=0 policy=0 bin=0 n=1
NEXT_LAT plane=P pc=0 addr_region=0 kind=0 policy=0 bin=64 n=1
NEXT_GROUP plane=P pc=0 addr_region=0 kind=0 policy=0 n=2 sum=71 max=70
NEXT_PLANE id=P starts=3 ends=3 active=0 touched=3 whole=2 latency_sum=71 max=70 partial=1 partial_edges=2 active_edges=0 occupancy=73 faults=0 diag=3 dropped=0
NEXT_EVER plane=P busy_dec_mask=0 n=2
NEXT_BYPASS plane=P bit=0 n=2
NEXT_EP plane=P pc=40800000 addr=40801000 instr=1 write=0 size=2 fc=6 policy=0 bypass=0 latency=1 window=1 first_window=1
NEXT_EP plane=P pc=40800000 addr=40801004 instr=1 write=0 size=2 fc=6 policy=0 bypass=0 latency=70 window=70 first_window=1
NEXT_EP plane=P pc=40800000 addr=40801008 instr=1 write=0 size=2 fc=6 policy=0 bypass=0 latency=4 window=2 first_window=0
'''
# Replace token placeholders without corrupting NEXT_EP / NEXT_PLANE names.
text=base+plane.replace('=P','=0')+plane.replace('=P','=1')
assert validate(text)['edges']==73
mutations=[('joint=73','joint=74'),('sum=71','sum=70'),('max=70','max=64'),('occupancy=73','occupancy=74'),('faults=0','faults=1'),('diag=3','diag=2'),('fst=14','fst=32'),('policy=0','policy=4'),('bin=64','bin=65'),('starts=3','starts=4'),('partial_edges=2','partial_edges=3'),('first_window=0','first_window=2')]
for a,b in mutations:
 try:validate(text.replace(a,b,1))
 except (AssertionError,ValueError):pass
 else:raise AssertionError(('accepted corrupt fixture',a,b))
try:validate(text+'NEXT_JOINT pc=0 cpu=0 fst=0 n=72\n')
except AssertionError:pass
else:raise AssertionError('accepted duplicate')
active=text.replace('fst=0 n=72','fst=0 n=73').replace('id=0 pc=72 cpu=72','id=0 pc=73 cpu=73').replace('edges=73 joint=73','edges=74 joint=74').replace('starts=3 ends=3 active=0 touched=3','starts=4 ends=3 active=1 touched=4').replace('active_edges=0 occupancy=73','active_edges=1 occupancy=74')
assert validate(active)['edges']==74
for bad in [text.replace('max=70','max=71'),text+'WHETSTONE_LOOP cycles=74 platform=sdram romlat=6\n']:
 try:validate(bad)
 except AssertionError:pass
 else:raise AssertionError('accepted overstated max or wrong loop')
assert validate(text+'WHETSTONE_LOOP cycles=73 platform=sdram romlat=6\n')['edges']==73
print('PASS passive checker: sparse valid immediate/overflow/partial+finish-active fixtures and15corruptions rejected; no RTL/model run')
