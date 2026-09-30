#!/usr/bin/env python3
from pathlib import Path
import argparse
p=argparse.ArgumentParser();p.add_argument('report',type=Path);p.add_argument('--allow-empty',action='store_true');a=p.parse_args();rows=[x.split('\t') for x in a.report.read_text().splitlines()]
meta={r[1]:r[2] for r in rows if r[0]=='FPU_GUARD_META'};assert meta['format']=='fpu-guard-profile-v1'
summary=[r for r in rows if r[0]=='SUMMARY' and len(r)>1 and r[1].isdigit()];assert len(summary)==1
s=[r for r in rows if r[0]=='FPU_GUARD_SUMMARY' and len(r)>1 and r[1].isdigit()];assert len(s)==1
edge,raw,restore,pending,unexpected,enable_reject,dropped,rounds,mismatch,reconciles=map(int,s[0][1:]);assert edge==int(summary[0][1]);assert raw+restore+pending<=edge and unexpected==mismatch==0 and reconciles==1
b=[list(map(int,r[1:])) for r in rows if r[0]=='FPU_GUARD_BUCKET' and r[1].isdigit()]
assert len({(r[0],r[1]) for r in b})==len(b)
for precision,enables,br,bs,bzero,bnormal,bff,old,new in b:
 assert 0<=precision<4 and 0<=enables<256 and br>=bs==bzero+bnormal+bff
 assert 0<=old<=new<=bnormal and (precision==0 or old==0) and (enables==0 or new==0)
assert sum(r[2] for r in b)==raw and sum(r[8] for r in b)==rounds
assert sum(r[5] for r in b if r[1])==enable_reject
contexts=[r for r in rows if r[0]=='FPU_GUARD_CONTEXT' and r[1].isdigit()];normal=sum(r[5] for r in b);assert len(contexts)==min(normal,64) and len(contexts)+dropped==normal
assert len([r for r in rows if r[0]=='FPU_GUARD_REJECT_SIDE'])==8
if not a.allow_empty:assert rounds>0,'no eligible normal-single branch observed'
print('PASS observer report edges',edge,'raw',raw,'normal',normal,'old',sum(r[7] for r in b),'new',rounds,'post_mismatch',mismatch)
