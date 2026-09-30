#!/usr/bin/env python3
"""Synthetic report fixtures only; not cache/model execution coverage."""
import copy
import check_resource as c
# Literal producer schema, rather than importing FIELDS/META when constructing.
meta='RREAD_META format=native-resource-reads-v1 finish=BEFORE_ORIGINAL_DRAIN address=PHYSICAL_ORIGINAL size=B0_W1_L2 event=FAST0_IDLE_SECOND1_FIRST_HIT2_FIRST_PASS3_SECOND_HIT4_SECOND_FILL5_SECOND_PASS6 failmask=INV3_CURRENT_SNOOP2_LATCHED_SNOOP1_MISS0 invmask=SWEEP5_CI4_FERR3_LOST2_STORE1_SNOOP0 relation=FIRST0_NEXT1_OTHER2 path=OTHER0_FAST1_FIRST_PASS2_SECOND_HIT3_SECOND_FILL4_SECOND_PASS5_UNCLASSIFIED6'
def fixture():
 lines=[meta];addr=0x60000e
 # Every first-failure mask, including overlapping miss/snoop/invalidation.
 lines += [f'RREAD_FAIL addr={addr:08x} size=2 mask={i} n=1' for i in range(1,16)]
 lines += [f'RREAD_INV mask=1 relation={i} n={n}' for i,n in [(0,3),(1,3),(2,2)]]
 lines += [f'RREAD_SECOND addr={addr:08x} size=2 mask=0 hit=1 n=1',f'RREAD_SECOND addr={addr:08x} size=2 mask=0 hit=0 n=1']
 lines += [f'RREAD_SECOND addr={addr:08x} size=2 mask={i} hit={i%2} n=1' for i in range(1,8)]
 # Direct first-edge fast hit, idle second-lookup shortcut, first hit chain.
 lines += [f'RREAD_EVENT addr={addr:08x} size=2 event={i} n={n}' for i,n in enumerate([1,1,8,15,1,1,7])]
 lines += [f'RREAD_ADDR addr={addr:08x} size=2 n=25 sum=121 max=9',
           'RREAD_ADDR addr=0060000f size=1 n=1 sum=9 max=9',
           'RREAD_EVENT addr=0060000f size=1 event=0 n=1',
           'RREAD_ADDR addr=0060000e size=1 n=1 sum=1 max=1']
 lines += [f'RREAD_PATH id={i} n={n}' for i,n in enumerate([1,2,15,1,1,7,0])]
 # One boundary-completed partial and one active finish intersection are
 # excluded from whole totals. A partial branch need not have a whole path.
 lines += ['RREAD_TOTAL starts=29 ends=28 active=1 touched=29 whole=27 sum=131 max=9 partial=1 partial_edges=2 active_edges=3 occupancy=136 unclassified=0',
           'RREAD_REST n=27 sum=131 max=9',
           'NEXT_GROUP plane=1 pc=2 addr_region=1 kind=1 policy=0 n=27 sum=131 max=9']
 return '\n'.join(lines)+'\n'
def bad(name,text):
 try:c.validate(text,False)
 except (AssertionError,ValueError,KeyError):print('REJECT',name);return
 raise AssertionError('accepted corrupt fixture '+name)
good=fixture();c.validate(good,False);print('PASS valid masks/shortcut/odd-size/immediate/partials fixture')
closed=good.replace('starts=29 ends=28 active=1 touched=29','starts=27 ends=27 active=0 touched=27').replace('partial=1 partial_edges=2 active_edges=3 occupancy=136','partial=0 partial_edges=0 active_edges=0 occupancy=131')
c.validate(closed,False);print('PASS whole-only per-address path/event fixture')
bad('orphan first pass plus matching mask',closed.replace('event=3 n=15','event=3 n=16').replace('mask=1 n=1','mask=1 n=2'))
bad('orphan fast event',closed.replace('event=0 n=1','event=0 n=2',1))
bad('orphan second event plus matching mask',closed.replace('event=4 n=1','event=4 n=2').replace('mask=0 hit=1 n=1','mask=0 hit=1 n=2'))
bad('duplicate',good+'RREAD_ADDR addr=0060000e size=2 n=25 sum=121 max=9\n')
bad('schema',good.replace('size=2 n=25','bytes=4 n=25'))
bad('out of bounds',good.replace('addr=0060000f','addr=00600ec8'))
bad('invalid size',good.replace('size=1','size=3'))
bad('noncross branch',good.replace('addr=0060000f size=1','addr=0060000e size=1'))
bad('missing first mask',good.replace('RREAD_FAIL addr=0060000e size=2 mask=1 n=1\n',''))
bad('zero first mask',good.replace('mask=1 n=1','mask=0 n=1'))
bad('second outcome',good.replace('mask=0 hit=1 n=1','mask=1 hit=1 n=1'))
bad('invalidation projection',good.replace('relation=2 n=2','relation=2 n=1'))
bad('missing path',good.replace('RREAD_PATH id=4 n=1\n',''))
bad('unclassified',good.replace('RREAD_PATH id=6 n=0','RREAD_PATH id=6 n=1').replace('unclassified=0','unclassified=1'))
bad('address sum',good.replace('n=25 sum=121','n=25 sum=122'))
bad('impossible max',good.replace('n=25 sum=121 max=9','n=25 sum=121 max=120'))
bad('active partial',good.replace('active=1 touched=29','active=0 touched=29'))
bad('partial projection',good.replace('partial_edges=2','partial_edges=3'))
bad('saved context',good.replace('NEXT_GROUP plane=1 pc=2','NEXT_GROUP plane=1 pc=1'))
bad('existing group sum',good.replace('policy=0 n=27 sum=131','policy=0 n=27 sum=130'))
try:c.validate(good,True)
except AssertionError:print('REJECT synthetic fixture as real qualification')
else:raise AssertionError('synthetic fixture passed real qualified totals')
print('PASS 2 valid / 21 negative report fixtures; no model executed')
