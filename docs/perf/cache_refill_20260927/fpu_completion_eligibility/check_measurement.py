from pathlib import Path
import re,json,hashlib,argparse
r=Path(__file__).parent
log=(r/'run/run.log').read_text();stdout=(r/'stdout.log').read_text()
fields=lambda line:{k:int(v) for k,v in re.findall(r'(\w+)=(\d+)',line)}
line=lambda prefix:next(x for x in log.splitlines() if x.startswith(prefix))
window=fields(line('FPU_ELIG_WINDOW '));rd=fields(line('FPU_ELIG_ROUND '));std=fields(line('FPU_ELIG_STDONE '))
fst={int(x):int(y) for x,y in re.findall(r'FPU_ELIG_FST id=(\d+) samples=(\d+)',log)}
ops={x:{'samples':int(y),'eligible':int(z)} for x,y,z in re.findall(r'FPU_ELIG_ROUND_OP op=([0-9a-f]+) samples=(\d+) eligible=(\d+)',log)}
reject={int(x):int(y) for x,y in re.findall(r'FPU_ELIG_ROUND_REJECT reason=(\d+) samples=(\d+)',log)}
assert window['clocks']==17641650==sum(fst.values())
assert rd['samples']==fst[14]==sum(x['samples'] for x in ops.values())
assert rd['eligible']==sum(x['eligible'] for x in ops.values())
assert rd['decode_wait']<=rd['bg']<=rd['eligible']<=rd['samples']
assert std['samples']==fst[17] and std['enables_zero']+std['enabled']==std['samples']
assert std['eligible']<=std['enables_zero']
assert 'WHETSTONE RETURNED cycles=17642118 loop=17641650' in log
assert 'SDRAM_PROTOCOL_ERRORS 0' in log and re.search(r'BERR 0\s+IPL_ASSERTED_CYCLES 0',log)
assert stdout.count('MEMCHECK whet_')==3 and stdout.count(': match')==3
p=argparse.ArgumentParser();p.add_argument('--check-sources',action='store_true');args=p.parse_args()
for name in ['whet_globals.hex','whet_code.hex','whet_stack.hex']:
 normalize=lambda path:[x.lower() for x in path.read_text().split() if not x.startswith('//')]
 assert normalize(r/'run'/name)==normalize(r/'oracle'/name),name
if args.check_sources:
 for name,sha in json.loads((r/'run/identity.json').read_text())['sources'].items():
  assert hashlib.sha256(Path(name).read_bytes()).hexdigest()==sha,name
result={'qualified':True,'loop_clocks':17641650,'returned_clocks':17642118,'guest_600D':'TB accepts only600D beforefinish','memory_oracles':'all3byteexactmatch','chip_errors':0,'bus_errors':0,'IRQ_samples':0,'window':window,'round':rd,'round_by_op':ops,'round_rejection_counts_independent':reject,'fst_samples':fst,'stdone_edge_observation_NOT_prior_conversion_exit_eligibility':std}
assert json.loads((r/'measurement.json').read_text())==json.loads(json.dumps(result))
print('PASS archive: prior baseline clocks,3byteexact archived memory oracles, FST/window/ROUND/STDONE totals; source-file checks optional --check-sources')
