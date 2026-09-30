#!/usr/bin/env python3
from pathlib import Path
import hashlib, json, re, sys
ROOT=Path(sys.argv[1] if len(sys.argv)>1 else '.')
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def j(p): return json.loads((ROOT/p).read_text())
def need(v,m):
    if not v: raise SystemExit('FAIL: '+m)

entries={}
for line in (ROOT/'SHA256SUMS').read_text().splitlines():
    h,n=line.split('  ',1);need(re.fullmatch('[0-9a-f]{64}',h) is not None,'bad archive digest')
    need(n not in entries,'duplicate path');entries[n]=h
actual={p.relative_to(ROOT).as_posix() for p in ROOT.rglob('*') if p.is_file() and p.name!='SHA256SUMS'}
need(set(entries)==actual,'SHA256SUMS inventory mismatch')
for n,h in entries.items():need(sha(ROOT/n)==h,'archive hash mismatch: '+n)

def manifest(path):
    d={}
    for line in (ROOT/path).read_text().splitlines():
        h,n=line.split('  ',1);need(re.fullmatch('[0-9a-f]{64}',h) is not None,'bad source digest')
        need(n not in d,'duplicate source path');d[n]=h
    return d
base=manifest('source/seed28_candidate_6c_manifest.sha256')
cand=manifest('source/seed31_candidate_6c_manifest.sha256')
need(len(base)==len(cand)==1892 and set(base)==set(cand),'source manifest inventory')
diff=[n for n in base if base[n]!=cand[n]]
need(diff==['MacQuadra800.qsf'],'expected sole QSF change')
qdiff=(ROOT/'source/qsf_seed28_to_seed31.diff').read_text()
need('SEED 28' in qdiff and 'SEED 31' in qdiff,'QSF diff')
need(sha(ROOT/'source/candidate_6c_ap040_fpu.v')==cand['rtl/ap68040/rtl/ap040_fpu.v'],'candidate FPU hash')
fc=j('run/full_compile_identity.json');post=j('run/source_postrun_check.json')
cd=j('run/cross_domain_identity.json');ram=j('run/ram_worst_paths_identity.json')
need(fc['status']=='complete-timing-failed' and fc['quartus_full_flow_exit_status']==0 and fc['wrapper_exit_status']==1 and fc['systemd_main_exit_status']==1,'compile terminal statuses')
need((ROOT/'run/full_exit_status.txt').read_text().strip()=='1','exit status record')
need(fc['source_manifest_sha256']==sha(ROOT/'source/seed31_candidate_6c_manifest.sha256'),'compile manifest')
need(post['status']=='PASS' and post['passed_entries']==1892 and post['failed_paths']==[],'source postrun check')
need(cd['status']=='complete-crossing-checks-pass' and cd['exit_status']==0,'cross STA tool completion')
need(cd['sys_to_ram']['worst_slack_ns']==1.406 and cd['sys_to_ram']['violated']==0,'sys-to-RAM check')
need(cd['ram_to_sys']['worst_slack_ns']==0.348 and cd['ram_to_sys']['violated']==0,'RAM-to-sys check')
need(cd['sys_to_ram']['report_sha256']==sha(ROOT/'reports/cross_sys2ram.txt') and cd['ram_to_sys']['report_sha256']==sha(ROOT/'reports/cross_ram2sys.txt'),'cross-report hashes')
need(ram['status']=='complete-timing-violation-detailed' and ram['exit_status']==0,'RAM path report status')
need(ram['summary_path_count']==12 and ram['violated_paths_in_summary']==12,'RAM summary count')
need(ram['detailed_path_count']==3 and ram['violated_paths_in_detail']==3,'RAM detail count')
need(ram['worst_path']['slack_ns']==-0.103 and ram['worst_path']['logic_levels']==2,'worst RAM path metadata')
need('wq_wp_handoff[3]' in ram['worst_path']['startpoint'] and 'a_ram[24]' in ram['worst_path']['endpoint'],'worst RAM path endpoints')
fit=(ROOT/'reports/fit.summary').read_text();sta=(ROOT/'reports/sta.summary').read_text()
for v in ['38,667 / 41,910','Total registers : 24591','468 / 553','3,389,411','Total DSP Blocks : 36']:
    need(v in fit,'fit summary: '+v)
for v in ['Slack : 0.230','Slack : 0.085','Slack : -0.103','TNS   : -0.652','Slack : 0.229']:
    need(v in sta,'STA summary: '+v)
need('Flow Status                     ; Successful' in (ROOT/'reports/flow.rpt').read_text(),'Quartus flow report')
arts=j('run/artifact_hashes.json')
need(arts['MacQuadra800.rbf']=={'size_bytes':4497956,'sha256':'98f96258a59c6ce26ce7d4f4af11e6c2426cd2dc9fdddc5bea91605cb27ee6a3','included':False},'RBF metadata')
need(arts['MacQuadra800.sof']=={'size_bytes':6690368,'sha256':'930ab6b311536fb91cdb8d8cc1dbc3281eaed33c28471a6d90e0bad100057d42','included':False},'SOF metadata')
for p in ROOT.rglob('*'):
    if not p.is_file():continue
    n=p.name.lower();rel=str(p.relative_to(ROOT)).lower()
    need(n not in {'macquadra800.rbf','macquadra800.sof','local.env'},'excluded/private artifact included')
    need('/db/' not in '/'+rel and '/incremental_db/' not in '/'+rel,'Quartus database included')
print('PASS archive files=%d inputs=1892 sole_QSF_delta=1 Quartus_flow=0 wrapper=1 RAM_setup=-0.103ns crossing_checks=PASS RAM_violations=12 summary/3 detail artifact_payloads_omitted=1' % len(entries))
