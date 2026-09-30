#!/usr/bin/env python3
from pathlib import Path
import json,re
D=Path(__file__).resolve().parent;t=(D/'run/run.log').read_text();m=json.loads((D/'measurement.json').read_text());assert m['loop_cycles']==8726508
rows=[tuple(int(v,16) if i==2 else int(v) for i,v in enumerate(z)) for z in re.findall(r'FPU_SOURCE_SHAPE class=(\d+) field_fmt=(\d+) op=([0-9a-f]+) raw_branch_edges=(\d+) first_branch_per_req_episode=(\d+)',t)]
crows=[tuple(int(v,16) if i==3 else int(v) for i,v in enumerate(z)) for z in re.findall(r'FPU_SOURCE_CONTEXT context=(\d+) class=(\d+) field_fmt=(\d+) op=([0-9a-f]+) first_branch_per_req_episode=(\d+)',t)]
s=dict((k,int(v)) for k,v in re.findall(r'(\w+)=(\d+)',re.search(r'FPU_SOURCE_TOTAL (.*)',t)[1]));o=dict((k,int(v)) for k,v in re.findall(r'(\w+)=(\d+)',re.search(r'FPU_SOURCE_OPPORTUNITY (.*)',t)[1]))
assert sum(z[3] for z in rows)==s['raw_branch_edges'] and sum(z[4] for z in rows)==s['first_branch_per_req_episode']
assert sum(z[4] for z in crows)==s['first_branch_per_req_episode']
assert s['raw_branch_edges']==s['first_branch_per_req_episode']+s['held_reexecution_edges']
assert len({z[:3] for z in rows})==len(rows) and len({z[:4] for z in crows})==len(crows)
for c,f,op,raw,unique in rows:
 assert 0<=c<8 and 0<=f<8 and 0<=op<128 and 0<=unique<=raw
 assert sum(z[4] for z in crows if z[1:4]==(c,f,op))==unique
for c in ['single','extended']:
 assert 0<=o[c+'_unique']<=o[c+'_raw']<=s['raw_branch_edges']
 assert o[c+'_unique']<=s['first_branch_per_req_episode']
result={'scope':'baseline native Whet source-format pre-edge branch/request-episode counts, no architectural instruction or saved-cycle claim','totals':s,'opportunities':o,'shape_rows':rows,'context_rows':crows,'context_legend':['resource','ROM','other_validated_PC','unknown_PC']}
(D/'source_formats.json').write_text(json.dumps(result,indent=2)+'\n');print('PASS source-format sums/opportunities; loop8726508 unchanged')
