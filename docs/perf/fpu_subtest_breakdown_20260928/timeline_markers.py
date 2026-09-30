#!/usr/bin/env python3
"""List intervals between consecutive Microseconds/TickCount marker traps with FP work in them."""
import sys
segs=[];cur=None
for l in open(sys.argv[1] if len(sys.argv)>1 else 'fpu_run/fwm.txt'):
    if l.startswith('SEG'):
        p=l.rstrip('\n').split('\t'); cur=[int(p[1]),int(p[2]),int(p[3]),p[4],p[5],p[6],{}]
    elif l.startswith('END'): segs.append(cur); cur=None
    elif cur is not None and l.count('\t')==1:
        k,v=l.rstrip('\n').split('\t')
        if v: cur[6][k]=int(v)
marks=[s for s in segs if s[3]=='T' and s[4] in('A193','A975')]
for a,b in zip(marks,marks[1:]):
    f=sum(s[6].get('fp_entries',0) for s in segs if a[0]<=s[0]<b[0])
    if f or b[1]-a[1]>1000000:
        print(f"seg {a[0]:5d} @{a[1]:>11,} {a[4]} pc={a[5]} -> seg {b[0]:5d} {b[4]} pc={b[5]}  len={b[1]-a[1]:>11,}  ({(b[1]-a[1])/32901120:.4f} s)  fp_instr={f:,}")
