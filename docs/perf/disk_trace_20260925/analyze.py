import csv,sys,statistics as st,collections
rows=[r for r in csv.DictReader(open(sys.argv[1])) if r['t_us']!='t_us']
for r in rows:
    for k in r: r[k]=int(r[k])
hd=[r for r in rows if r['slot'] in (0,1)]
if not hd: print('no hd rows'); sys.exit()
t0=hd[0]['t_us']; t1=hd[-1]['t_us']
print(f"{sys.argv[1]}: {len(rows)} requests ({len(hd)} hard disk), span {(t1-t0)/1e6:.2f} s")
def summ(name,sel):
    if not sel: return
    n=len(sel); by=sum(r['bytes'] for r in sel)
    def tot(k): return sum(max(r[k],0) for r in sel)/1e6
    def med(k):
        v=[r[k] for r in sel if r[k]>=0]; return st.median(v) if v else -1
    def p95(k):
        v=sorted(r[k] for r in sel if r[k]>=0); return v[int(len(v)*.95)] if v else -1
    bl=collections.Counter(r['blks'] for r in sel)
    print(f"  {name}: n={n} bytes={by/1e6:.2f}MB blks={dict(bl.most_common(4))}")
    print(f"     spi  tot {tot('spi_us'):.2f}s med {med('spi_us')}us  | file tot {tot('file_us'):.2f}s med {med('file_us')}us p95 {p95('file_us')}us | readahead tot {tot('ra_us'):.2f}s med {med('ra_us')}us | gap tot {tot('gap_us'):.2f}s med {med('gap_us')}us")
rd=[r for r in hd if r['op']==1]; wr=[r for r in hd if r['op']==2]
summ('reads',rd); summ('  read misses',[r for r in rd if r['miss']]); summ('  read hits',[r for r in rd if not r['miss']]); summ('writes',wr)
busy=sum(max(r['spi_us'],0)+max(r['file_us'],0)+max(r['ra_us'],0) for r in hd)/1e6
print(f"  Main busy in sector service: {busy:.2f}s of {(t1-t0)/1e6:.2f}s")
# sequentiality of writes
seq=sum(1 for a,b in zip(wr,wr[1:]) if b['lba']==a['lba']+a['blks'])
print(f"  writes continuing the previous write's LBA: {seq}/{max(len(wr)-1,0)}")
