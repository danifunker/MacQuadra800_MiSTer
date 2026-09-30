#!/usr/bin/env python3
from pathlib import Path
import hashlib, json, re, sys
ROOT=Path(sys.argv[1] if len(sys.argv)>1 else '.')
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def j(p): return json.loads((ROOT/p).read_text())
def need(v,m):
    if not v: raise SystemExit('FAIL: '+m)

# Verify exact archived file inventory and content hashes.
entries={}
for line in (ROOT/'SHA256SUMS').read_text().splitlines():
    h,n=line.split('  ',1); need(re.fullmatch('[0-9a-f]{64}',h) is not None,'bad digest'); need(n not in entries,'duplicate path'); entries[n]=h
actual={p.relative_to(ROOT).as_posix() for p in ROOT.rglob('*') if p.is_file() and p.name!='SHA256SUMS'}
need(set(entries)==actual,'SHA256SUMS inventory mismatch')
for n,h in entries.items(): need(sha(ROOT/n)==h,'archive hash mismatch: '+n)

# The two original source manifests must contain the same 1,892 paths and
# differ only at the FPU implementation.
def manifest(path):
    rows={}
    for line in (ROOT/path).read_text().splitlines():
        h,n=line.split('  ',1); need(re.fullmatch('[0-9a-f]{64}',h) is not None,'bad source hash')
        need(n not in rows,'duplicate source path'); rows[n]=h
    return rows
base=manifest('source/base_55ff_source_manifest.sha256')
cand=manifest('source/candidate_6c_source_manifest.sha256')
need(len(base)==len(cand)==1892 and set(base)==set(cand),'source manifest cardinality/path mismatch')
diff=[n for n in base if base[n]!=cand[n]]
need(diff==['rtl/ap68040/rtl/ap040_fpu.v'],'expected sole FPU source delta')
need(base[diff[0]]==sha(ROOT/'source/base_55ff_ap040_fpu.v'),'baseline FPU identity')
need(cand[diff[0]]==sha(ROOT/'source/candidate_ap040_fpu.v'),'candidate FPU identity')
need((ROOT/'source/candidate_vs_55ff.diff').stat().st_size>0,'diff missing')

fc=j('run/full_compile_identity.json'); post=j('run/source_postrun_check.json')
cd=j('run/cross_domain_identity.json'); cpu=j('run/cpu_worst_paths_identity.json')
need(fc['exit_status']==1 and (ROOT/'run/full_exit_status.txt').read_text().strip()=='1','wrapper exit should reflect timing guard')
need(fc['source_manifest_sha256']==sha(ROOT/'source/candidate_6c_source_manifest.sha256'),'compile source manifest')
need(post['status']=='PASS' and post['manifest_count']==1892 and post['source_mismatches']==[],'source postrun check')
need(cd['status']=='complete' and cd['exit_status']==0 and cd['reports']['sys_to_ram']['worst_slack_ns']==0.706 and cd['reports']['ram_to_sys']['worst_slack_ns']==0.112,'cross-domain result')
need(cd['reports']['sys_to_ram']['sha256']==sha(ROOT/'reports/cross_sys2ram.txt') and cd['reports']['ram_to_sys']['sha256']==sha(ROOT/'reports/cross_ram2sys.txt'),'cross-domain report hashes')
need(cpu['status']=='complete' and cpu['exit_status']==0 and cpu['worst_path']['slack_ns']==-0.449,'CPU path identity')
need('no FPU cell' in cpu['worst_path']['interpretation'],'path interpretation')
need('epf_data[2][10]' in (ROOT/'reports/cpu_worst_detail.txt').read_text(),'worst path endpoint report')
sta=(ROOT/'reports/sta.summary').read_text()
need(re.search(r"Setup .*?Slack : -0\.449",sta,re.S) is not None,'negative CPU setup slack absent')
need('TNS   : -3.294' in sta and 'Slack : 0.267' in sta and 'Slack : 0.443' in sta,'timing summary values')
need('Fitter Status : Successful' in (ROOT/'reports/fit.summary').read_text(),'fit did not succeed')
need('Analysis & Synthesis Status : Successful' in (ROOT/'reports/map.summary').read_text(),'map did not succeed')
art=j('run/artifact_hashes.json')
need(art['MacQuadra800.rbf']=={'size_bytes':4441088,'sha256':'5c0c19e72e7af9332e96dd58c73dd6075949b74b202d36967ad46eb17f9c106c','included':False},'RBF metadata')
need(art['MacQuadra800.sof']=={'size_bytes':6690368,'sha256':'d0a3951971a08fc2dcb7b5f5fc935c929c0d4714bbd9a9e4fb3c76c334b56db6','included':False},'SOF metadata')
for p in ROOT.rglob('*'):
    if not p.is_file(): continue
    n=p.name.lower(); rel=str(p.relative_to(ROOT)).lower()
    need(n not in {'macquadra800.rbf','macquadra800.sof','local.env'},'excluded artifact/private file included')
    need('/db/' not in '/'+rel and '/incremental_db/' not in '/'+rel,'Quartus database included')
print('PASS archive files=%d source_inputs=1892 sole_FPU_delta=1 Quartus_flow=success wrapper_exit=1 CPU_setup=-0.449ns cross_STA=PASS artifacts_omitted=1' % len(entries))
