#!/usr/bin/env python3
"""analyze.py arm.txt [cmdD_epoch] -- phases of a Finder duplicate / PR from the 0.26 s sampler."""
import sys, statistics as st
def load(fn):
    rows=[]
    for l in open(fn):
        if l.startswith('#') or not l.strip(): continue
        f=l.split()
        try: rows.append((float(f[0]),int(f[1]),int(f[2])))
        except: pass
    w=[]
    for (t0,r0,w0),(t1,r1,w1) in zip(rows,rows[1:]):
        w.append((t0,t1,r1-r0,w1-w0))
    return w
def runs(w,pred):
    out=[];cur=[]
    for x in w:
        if pred(x): cur.append(x)
        elif cur: out.append(cur);cur=[]
    if cur: out.append(cur)
    return out
MiB=1048576
def phase(ws,idx):
    b=sum(x[idx] for x in ws); dt=ws[-1][1]-ws[0][0]
    inner=[x[idx]/(x[1]-x[0]) for x in ws[1:-1]]
    return b,dt,(st.median(inner)/MiB if inner else float('nan')),(max(inner)/MiB if inner else float('nan'))
w=load(sys.argv[1]); t0=float(sys.argv[2]) if len(sys.argv)>2 else None
if t0: w=[x for x in w if x[1]>t0]
wr=runs(w,lambda x:x[3]>0)
big=max(wr,key=lambda r:sum(x[3] for x in r))
wb,wdt,wmed,wmax=phase(big,3)
rd=[x for x in w if x[1]<=big[0][0]+0.3 and x[2]>=65536]
first_rd=rd[0][0] if rd else big[0][0]
rdph=[x for x in w if x[0]>=first_rd and x[1]<=big[0][1]]
rb,rdt,rmed,rmax=phase(rdph,2)
end=(big[-1][0]+big[-1][1])/2
res=dict(read_KiB=rb//1024,read_s=round(rdt,2),read_MiBs=round(rb/MiB/rdt,2),read_inner_med=round(rmed,2),read_inner_max=round(rmax,2),
         write_KiB=wb//1024,write_s=round(wdt,2),write_MiBs=round(wb/MiB/wdt,2),write_inner_med=round(wmed,2),write_inner_max=round(wmax,2))
if t0: res['dur_s']=round(end-t0,2); res['kB_s']=round(3958171/1000/(end-t0))
print(' '.join(f'{k}={v}' for k,v in res.items()))
