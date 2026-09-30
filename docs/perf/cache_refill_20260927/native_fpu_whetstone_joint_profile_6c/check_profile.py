#!/usr/bin/env python3
"""Strict sparse passive monitor reconciliation; no model execution."""
from pathlib import Path
from collections import defaultdict
import re,json,sys
FIELDS={
 'JOINT':('pc','cpu','fst','n'),'OP':('pc','cpu','op','n'),'BG':('pc','cpu','n'),
 'WAIT':('plane','pc','cpu','fst','n'),'LAT':('plane','pc','addr_region','kind','policy','bin','n'),
 'GROUP':('plane','pc','addr_region','kind','policy','n','sum','max'),
 'MARGIN':('id','pc','cpu'),'EVER':('plane','busy_dec_mask','n'),'BYPASS':('plane','bit','n'),
 'PLANE':('id','starts','ends','active','touched','whole','latency_sum','max','partial','partial_edges','active_edges','occupancy','faults','diag','dropped'),
 'TOTAL':('edges','joint','busy_op'),
 'EP':('plane','pc','addr','instr','write','size','fc','policy','bypass','latency','window','first_window')}
LIMITS={'plane':2,'cpu':4,'fst':32,'op':128,'addr_region':5,'kind':3,'policy':4,'bin':65,'busy_dec_mask':4,'bit':2}
def parse(text):
 rows=defaultdict(list);meta=0
 for line in text.splitlines():
  if not line.startswith('NEXT_'):continue
  name,_,body=line.partition(' ');name=name[5:]
  if name=='META':
   assert 'format=native-whet-joint-v1' in body and 'finish=BEFORE_ORIGINAL_DRAIN' in body;meta+=1;continue
  assert name in FIELDS,name
  pairs=body.split();keys=[x.split('=',1)[0] for x in pairs];assert tuple(keys)==FIELDS[name],(name,keys)
  row={k:int(v,16 if k=='op' or (name=='EP' and k in ['pc','addr']) else 10) for k,v in (x.split('=',1) for x in pairs)}
  assert all(v>=0 for v in row.values())
  for k,n in LIMITS.items():
   if k in row and name!='MARGIN':assert row[k]<n,(name,k)
  if 'pc' in row and name not in ['EP','MARGIN']:assert row['pc']<4
  if name=='EP':assert row['latency']>=1 and row['window']<=row['latency'] and row['instr']+row['write']<=1 and row['size']<4 and row['fc']<8 and row['first_window']<2 and row['bypass']<2
  rows[name].append(row)
 assert meta==1 and len(rows['TOTAL'])==1 and len(rows['PLANE'])==2 and len(rows['MARGIN'])==4
 for name in FIELDS:
  if name in ['EP','TOTAL']:continue
  key=FIELDS[name][:-1] if name not in ['GROUP','PLANE','MARGIN'] else (FIELDS[name][:5] if name=='GROUP' else ('id',))
  vals=[tuple(x[k] for k in key) for x in rows[name]];assert len(vals)==len(set(vals)),('duplicate',name)
 return rows
def validate(text):
 rows=parse(text);t=rows['TOTAL'][0];assert t['edges']>0 and t['joint']==t['edges']
 loops=re.findall(r'WHETSTONE_LOOP cycles=(\d+)',text)
 if loops:assert len(loops)==1 and int(loops[0])==t['edges']
 joints=rows['JOINT'];assert sum(x['n'] for x in joints)==t['edges']
 idle=sum(x['n'] for x in joints if x['fst']==0)
 assert sum(x['n'] for x in rows['OP'])==t['busy_op']==t['edges']-idle
 for a in range(4):
  for b in range(4):
   assert sum(x['n'] for x in rows['OP'] if (x['pc'],x['cpu'])==(a,b))==sum(x['n'] for x in joints if (x['pc'],x['cpu'])==(a,b) and x['fst']!=0)
 for m in rows['MARGIN']:
  assert m['id']<4 and m['pc']==sum(x['n'] for x in joints if x['pc']==m['id']) and m['cpu']==sum(x['n'] for x in joints if x['cpu']==m['id'])
 for bg in rows['BG']:assert bg['n']<=sum(x['n'] for x in joints if (x['pc'],x['cpu'])==(bg['pc'],bg['cpu']))
 for p in rows['PLANE']:
  i=p['id'];assert i<2 and p['active']<2 and p['faults']==0 and p['diag']<=64
  assert p['starts']==p['ends']+p['active']
  assert p['touched']==p['whole']+p['partial']+int(p['active_edges']>0)
  assert p['occupancy']==p['latency_sum']+p['partial_edges']+p['active_edges']
  assert p['diag']+p['dropped']==p['whole']+p['partial']
  assert len([x for x in rows['EP'] if x['plane']==i])==p['diag']
  assert sum(x['n'] for x in rows['WAIT'] if x['plane']==i)==p['occupancy']
  for w in rows['WAIT']:
   if w['plane']==i:assert w['n']<=sum(x['n'] for x in joints if (x['pc'],x['cpu'],x['fst'])==(w['pc'],w['cpu'],w['fst']))
  groups=[x for x in rows['GROUP'] if x['plane']==i];hist=[x for x in rows['LAT'] if x['plane']==i]
  assert sum(x['n'] for x in groups)==p['whole']==sum(x['n'] for x in hist)
  assert sum(x['sum'] for x in groups)==p['latency_sum'] and max([x['max'] for x in groups],default=0)==p['max']
  assert sum(x['n'] for x in rows['EVER'] if x['plane']==i)==sum(x['n'] for x in rows['BYPASS'] if x['plane']==i)==p['whole']
  for g in groups:
   h=[x for x in hist if all(x[k]==g[k] for k in ['plane','pc','addr_region','kind','policy'])]
   assert g['n']>0 and sum(x['n'] for x in h)==g['n'] and g['n']<=g['sum']<=g['n']*g['max']
   exact=sum(x['n']*(x['bin']+1) for x in h if x['bin']<64);over=sum(x['n'] for x in h if x['bin']==64)
   assert exact+65*over<=g['sum']<=exact+g['max']*over
   if over:
    remaining=g['sum']-exact
    assert max(65,(remaining+over-1)//over)<=g['max']<=remaining-65*(over-1)
   else:assert g['max']==max([x['bin']+1 for x in h if x['n']>0],default=0)
   assert all((x['bin']+1<=g['max']) if x['bin']<64 else g['max']>=65 for x in h)
 return {'edges':t['edges'],'busy_op_samples':t['busy_op'],'planes':rows['PLANE'],'scope':'native joint occupancy and per-plane episodes; no additive stall total or numerical oracle'}
if __name__=='__main__':
 text=Path(sys.argv[1]).read_text();print(json.dumps(validate(text),indent=2));print('PASS passive native profile reconciliation')
