#!/usr/bin/env python3
"""Strict resource attribution report validation; never executes a model."""
from pathlib import Path
from collections import defaultdict
import re,json,sys
FIELDS={
 'ADDR':('addr','size','n','sum','max'),
 'EVENT':('addr','size','event','n'),'FAIL':('addr','size','mask','n'),
 'SECOND':('addr','size','mask','hit','n'),'INV':('mask','relation','n'),
 'PATH':('id','n'),
 'TOTAL':('starts','ends','active','touched','whole','sum','max','partial','partial_edges','active_edges','occupancy','unclassified'),
 'REST':('n','sum','max')}
META='RREAD_META format=native-resource-reads-v1 finish=BEFORE_ORIGINAL_DRAIN address=PHYSICAL_ORIGINAL size=B0_W1_L2 event=FAST0_IDLE_SECOND1_FIRST_HIT2_FIRST_PASS3_SECOND_HIT4_SECOND_FILL5_SECOND_PASS6 failmask=INV3_CURRENT_SNOOP2_LATCHED_SNOOP1_MISS0 invmask=SWEEP5_CI4_FERR3_LOST2_STORE1_SNOOP0 relation=FIRST0_NEXT1_OTHER2 path=OTHER0_FAST1_FIRST_PASS2_SECOND_HIT3_SECOND_FILL4_SECOND_PASS5_UNCLASSIFIED6'
def cross(addr,size):
 return (addr&12)==12 and ((size==2 and addr&3!=0) or (size==1 and addr&3==3))
def validate(text,qualification=True):
 rows=defaultdict(list);metas=[]
 for line in text.splitlines():
  if not line.startswith('RREAD_'):continue
  if line.startswith('RREAD_META '):metas.append(line);continue
  name,_,body=line.partition(' ');name=name[6:];assert name in FIELDS,name
  pairs=[x.split('=',1) for x in body.split()];assert tuple(x[0] for x in pairs)==FIELDS[name],name
  r={k:int(v,16 if k=='addr' else 10) for k,v in pairs};assert all(v>=0 for v in r.values())
  if 'addr' in r:
   assert 0x600000<=r['addr']<0x600ec8 and r['size']<3
   if name!='ADDR':assert cross(r['addr'],r['size']),('noncross event',r)
  if name=='ADDR':assert 0<r['n']<=r['sum']<=r['n']*r['max'] and r['max']<=r['sum']-r['n']+1
  if name in ['EVENT','FAIL','SECOND','INV']:assert r['n']>0
  if name=='EVENT':assert r['event']<7
  if name=='FAIL':assert 0<r['mask']<16
  if name=='SECOND':assert r['mask']<8 and r['hit']<2
  if name=='INV':assert 0<r['mask']<64 and r['relation']<3
  if name=='PATH':assert r['id']<7
  rows[name].append(r)
 assert metas==[META] and len(rows['TOTAL'])==1 and len(rows['REST'])==1
 for name,fields in FIELDS.items():
  keys=fields[:-3] if name=='ADDR' else fields[:-1]
  if name in ['TOTAL','REST']:continue
  seen=[tuple(x[k] for k in keys) for x in rows[name]];assert len(seen)==len(set(seen)),('duplicate',name)
 paths={x['id']:x['n'] for x in rows['PATH']};assert set(paths)==set(range(7))
 t=rows['TOTAL'][0];rest=rows['REST'][0];assert t['active']<2 and t['unclassified']==paths[6]==0
 assert t['starts']==t['ends']+t['active'] and t['ends']>=t['whole']+t['partial']
 assert t['touched']==t['whole']+t['partial']+int(t['active_edges']>0)
 assert t['active_edges']==0 or t['active']==1
 assert t['occupancy']==t['sum']+t['partial_edges']+t['active_edges']
 assert (t['partial']==0)==(t['partial_edges']==0)
 assert t['partial_edges']>=t['partial']
 assert sum(x['n'] for x in rows['ADDR'])==t['whole']==sum(paths.values())
 assert sum(x['sum'] for x in rows['ADDR'])==t['sum']
 assert max([x['max'] for x in rows['ADDR']],default=0)==t['max']
 xn=sum(x['n'] for x in rows['ADDR'] if cross(x['addr'],x['size']))
 assert xn==sum(paths[i] for i in range(1,7)) and t['whole']-xn==paths[0]
 assert rest['n']<=t['whole'] and rest['sum']<=t['sum'] and rest['max']<=t['max']
 assert rest['n']<=rest['sum']<=rest['n']*rest['max']
 ev=defaultdict(int);fm=defaultdict(int);sec=defaultdict(int)
 for x in rows['EVENT']:ev[x['addr'],x['size'],x['event']]+=x['n']
 for x in rows['FAIL']:fm[x['addr'],x['size']]+=x['n']
 for x in rows['SECOND']:
  outcome=6 if x['mask'] else (4 if x['hit'] else 5)
  sec[x['addr'],x['size'],outcome]+=x['n']
 keys={(x['addr'],x['size']) for name in ['EVENT','FAIL','SECOND'] for x in rows[name]}
 for a,s in keys:
  assert fm[a,s]==ev[a,s,3]
  for out in [4,5,6]:assert sec[a,s,out]==ev[a,s,out]
 assert sum(x['n'] for x in rows['INV'])==sum(x['n'] for x in rows['FAIL'] if x['mask']&8)
 totals={i:sum(x['n'] for x in rows['EVENT'] if x['event']==i) for i in range(7)}
 assert paths[1]<=totals[0] and paths[2]<=totals[3]
 for path,event in [(3,4),(4,5),(5,6)]:assert paths[path]<=totals[event]
 assert paths[3]+paths[4]+paths[5]<=totals[1]+totals[2]
 # With no touched boundary partial/finish intersection, every measured
 # target event belongs to a whole episode. No orphan events are allowed.
 if t['partial']==0 and t['active_edges']==0:
  an={(x['addr'],x['size']):x['n'] for x in rows['ADDR']}
  for a,s in keys | {k for k in an if cross(*k)}:
   outcomes=sum(ev[a,s,i] for i in [4,5,6])
   assert an.get((a,s),0)==ev[a,s,0]+ev[a,s,3]+outcomes
   assert ev[a,s,1]+ev[a,s,2]==outcomes
  assert paths[1]==totals[0] and paths[2]==totals[3]
  for path,event in [(3,4),(4,5),(5,6)]:assert paths[path]==totals[event]
 # The original NEXT_GROUP report independently identifies all target and
 # saved rest-resource whole episodes. It is not reconstructed from RREAD.
 groups=[]
 for line in text.splitlines():
  if not line.startswith('NEXT_GROUP '):continue
  g={k:int(v) for k,v in (x.split('=') for x in line.split()[1:])}
  if (g['plane'],g['addr_region'],g['kind'],g['policy'])==(1,1,1,0):groups.append(g)
 assert len({g['pc'] for g in groups})==len(groups) and all(g['pc']<4 for g in groups)
 assert sum(g['n'] for g in groups)==t['whole'] and sum(g['sum'] for g in groups)==t['sum']
 assert max([g['max'] for g in groups],default=0)==t['max']
 rg=[g for g in groups if g['pc']==2]
 assert len(rg)==int(rest['n']>0)
 if rg:assert all(rg[0][k]==rest[k] for k in ['n','sum','max'])
 if qualification:
  assert (t['partial'],t['active_edges'],t['active'])==(0,0,0)
  assert (t['whole'],t['sum'],t['max'])==(96271,331334,25)
  assert (rest['n'],rest['sum'],rest['max'])==(90990,311506,25)
  loops=re.findall(r'WHETSTONE_LOOP cycles=(\d+)',text);assert loops==['8724166']
 return {'target':t,'saved_rest_resource':rest,'path_counts':paths,'branch_event_counts':totals,
         'scope':'translated enabled/cacheable resource data read episodes; no historical invalidation cause, numerical oracle or removable-cycle prediction'}
if __name__=='__main__':
 print(json.dumps(validate(Path(sys.argv[1]).read_text()),indent=2));print('PASS resource read attribution')
