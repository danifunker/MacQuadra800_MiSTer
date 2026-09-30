#!/usr/bin/env python3
from pathlib import Path
import hashlib, json, re, sys
ROOT=Path(sys.argv[1] if len(sys.argv)>1 else '.')
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def j(p): return json.loads((ROOT/p).read_text())
def need(v,m):
    if not v: raise SystemExit('FAIL: '+m)

# Archive inventory and byte integrity.
entries={}
for line in (ROOT/'SHA256SUMS').read_text().splitlines():
    h,n=line.split('  ',1); need(re.fullmatch('[0-9a-f]{64}',h) is not None,'bad archive digest')
    need(n not in entries,'duplicate manifest path'); entries[n]=h
actual={p.relative_to(ROOT).as_posix() for p in ROOT.rglob('*') if p.is_file() and p.name!='SHA256SUMS'}
need(set(entries)==actual,'SHA256SUMS inventory mismatch')
for n,h in entries.items(): need(sha(ROOT/n)==h,'archive hash mismatch: '+n)

# Frozen 1892-input manifests must differ only in the QSF seed.
def manifest(path):
    d={}
    for line in (ROOT/path).read_text().splitlines():
        h,n=line.split('  ',1); need(re.fullmatch('[0-9a-f]{64}',h) is not None,'bad source digest')
        need(n not in d,'duplicate source path'); d[n]=h
    return d
base=manifest('source/seed27_candidate_6c_manifest.sha256')
cand=manifest('source/seed28_candidate_6c_manifest.sha256')
need(len(base)==len(cand)==1892 and set(base)==set(cand),'source input inventory mismatch')
diff=[n for n in base if base[n]!=cand[n]]
need(diff==['MacQuadra800.qsf'],'expected sole QSF change')
need('SEED 27' in (ROOT/'source/qsf_seed27_to_seed28.diff').read_text() and 'SEED 28' in (ROOT/'source/qsf_seed27_to_seed28.diff').read_text(),'QSF diff contents')
need(sha(ROOT/'source/candidate_6c_ap040_fpu.v')==cand['rtl/ap68040/rtl/ap040_fpu.v'],'candidate FPU source hash')

fc=j('run/full_compile_identity.json'); post=j('run/source_postrun_check.json')
cd=j('run/cross_domain_identity.json'); cpu=j('run/cpu_worst_paths_identity.json')
need(fc['status']=='complete-timing-failed' and fc['quartus_full_flow_exit_status']==0 and fc['wrapper_exit_status']==1,'Quartus/wrapper terminal statuses')
need((ROOT/'run/full_exit_status.txt').read_text().strip()=='1','recorded wrapper exit')
need(fc['source_manifest_sha256']==sha(ROOT/'source/seed28_candidate_6c_manifest.sha256'),'compile manifest identity')
need(post['status']=='PASS' and post['passed_entries']==1892 and post['failed_paths']==[],'source postrun verification')
need(cd['status']=='complete-one-cross-domain-setup-violation' and cd['exit_status']==0,'cross tool completion/status')
need(cd['sys_to_ram']['worst_slack_ns']==0.731 and cd['sys_to_ram']['violated']==0,'sys-to-RAM report')
need(cd['ram_to_sys']['worst_slack_ns']==-0.203 and cd['ram_to_sys']['violated']==1,'RAM-to-sys violation')
need(cd['sys_to_ram']['report_sha256']==sha(ROOT/'reports/cross_sys2ram.txt'),'sys-to-RAM report hash')
need(cd['ram_to_sys']['report_sha256']==sha(ROOT/'reports/cross_ram2sys.txt'),'RAM-to-sys report hash')
need(cpu['status']=='complete' and cpu['exit_status']==0 and cpu['worst_path']['slack_ns']==-1.225,'CPU worst path metadata')
need('rf_written[6]' in cpu['worst_path']['startpoint'] and 'hq_ptag[19]' in cpu['worst_path']['endpoint'],'CPU path endpoints')
need(cpu['worst_path']['logic_levels']==24 and cpu['worst_path']['data_delay_ns']==30.871,'CPU path metrics')
need('no FPU cell' in cpu['worst_path']['interpretation'],'CPU path interpretation')
sta=(ROOT/'reports/sta.summary').read_text()
for value in ['Slack : -1.225','TNS   : -49.875','Slack : -0.710','TNS   : -3.828','Slack : 0.422']:
    need(value in sta,'STA summary missing '+value)
fit=(ROOT/'reports/fit.summary').read_text()
for value in ['38,650 / 41,910','Total registers : 24667','468 / 553','3,389,411','Total DSP Blocks : 36']:
    need(value in fit,'fit summary missing '+value)
need('Flow Status                     ; Successful' in (ROOT/'reports/flow.rpt').read_text(),'Quartus flow report')
arts=j('run/artifact_hashes.json')
need(arts['MacQuadra800.rbf']=={'size_bytes':4448892,'sha256':'366a7633d6737a47cca1a60f4a0aa6494792050fbcae52c7e062dd3f36d4e333','included':False},'RBF hash metadata')
need(arts['MacQuadra800.sof']=={'size_bytes':6690368,'sha256':'6c201428341a86f6bb8d84960b2aaff34fdd84eab55382490081583b9707be91','included':False},'SOF hash metadata')
for p in ROOT.rglob('*'):
    if not p.is_file(): continue
    name=p.name.lower(); rel=str(p.relative_to(ROOT)).lower()
    need(name not in {'macquadra800.rbf','macquadra800.sof','local.env'},'forbidden artifact/private file included')
    need('/db/' not in '/'+rel and '/incremental_db/' not in '/'+rel,'Quartus database included')
print('PASS archive files=%d source_inputs=1892 sole_QSF_delta=1 Quartus_flow=0 wrapper=1 CPU=-1.225ns HDMI=-0.710ns sys_to_RAM=+0.731ns RAM_to_sys=-0.203ns artifact_payloads_omitted=1' % len(entries))
