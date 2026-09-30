#!/usr/bin/env python3
from pathlib import Path
import hashlib, json, re, sys
R=Path(sys.argv[1] if len(sys.argv)>1 else '.')
def need(ok,msg):
    if not ok: raise SystemExit('FAIL: '+msg)
def sha(p): return hashlib.sha256((R/p).read_bytes()).hexdigest()
def j(p): return json.loads((R/p).read_text())
entries={}
for line in (R/'SHA256SUMS').read_text().splitlines():
    h,n=line.split('  ',1); need(re.fullmatch(r'[0-9a-f]{64}',h)!=None,'bad archive digest')
    need(n not in entries,'duplicate path'); entries[n]=h
actual={p.relative_to(R).as_posix() for p in R.rglob('*') if p.is_file() and p.name!='SHA256SUMS'}
need(actual==set(entries),'archive inventory mismatch')
for n,h in entries.items(): need(sha(n)==h,'archive file hash: '+n)
def manifest(p):
    out={}
    for line in (R/p).read_text().splitlines():
        h,n=line.split('  ',1); need(re.fullmatch(r'[0-9a-f]{64}',h)!=None,'source hash format')
        need(n not in out,'duplicate source'); out[n]=h
    return out
b=manifest('run/base_manifest.sha256'); c=manifest('run/candidate_manifest.sha256')
need(len(b)==len(c)==1892 and set(b)==set(c),'manifest inventory')
delta=[p for p in b if b[p]!=c[p]]
need(delta==['rtl/sdram_beat32.sv'],'sole bridge RTL delta')
need(sha('source/candidate_sdram_beat32.sv')==c[delta[0]],'candidate bridge source hash')
prep=j('run/preparation_identity.json')
need(prep['candidate_manifest_sha256']==hashlib.sha256((R/'run/candidate_manifest.sha256').read_bytes()).hexdigest(),'preparation candidate manifest identity')
need(prep['base_manifest_sha256']==hashlib.sha256((R/'run/base_manifest.sha256').read_bytes()).hexdigest(),'preparation base manifest identity')
need(prep['changed_manifest_paths']==delta,'preparation delta')
need(prep['base_bridge_sha256']==b[delta[0]] and prep['candidate_bridge_sha256']==c[delta[0]],'bridge source identities')
post=j('run/source_postrun_check.json')
need(post['result']=='PASS' and post['entries']==post['verified']==1892 and post['mismatches']==[],'source postrun')
fc=j('run/full_compile_identity.json')
need(fc['status']=='terminal' and fc['wrapper_exit_status']==1 and fc['quartus_flow_errors']==0,'terminal build state')
need((R/'run/full_exit_status.txt').read_text().strip()=='1','wrapper exit record')
arts=j('run/final_artifact_identities.json')
need(arts['full_compile']['timing_gate']=='FAIL' and arts['full_compile']['quartus_flow_errors']==0,'artifact build status')
need(arts['setup_slack_ns']=={'cpu':-0.033,'hdmi':-0.119,'ram_falling_to_rising':0.528},'setup slacks')
need(arts['artifacts']['rbf']=={'path':'tree/output_files/MacQuadra800.rbf','bytes':4456988,'sha256':'8f875a50d9d03b4cc40eeab0a7a857ab3038d625d4232c2d0dc1a33d70837a30'},'RBF identity')
need(arts['artifacts']['sof']=={'path':'tree/output_files/MacQuadra800.sof','bytes':6690368,'sha256':'07343ae95a79cd909826b42825eae03bf493d0fefea387777252a9e59621aa27'},'SOF identity')
need(arts['cpu_paths']['summary_paths']==12 and arts['cpu_paths']['worst_slack_ns']==-0.033 and arts['cpu_paths']['tns_ns']==-0.033,'CPU paths metadata')
need(arts['cross_paths']['all_12_positive'] is True and arts['cross_paths']['queue_input_path_slack_ns']==1.739,'cross paths metadata')
need(arts['ram_paths']['all_12_positive'] is True and arts['ram_paths']['queue_output_slack_ns']==0.528,'RAM paths metadata')
sta=(R/'reports/sta.summary').read_text(); fit=(R/'reports/fit.summary').read_text()
for v in ('Slack : -0.033','Slack : -0.119','Slack : 0.528','Slack : 0.213'):
    need(v in sta,'STA summary '+v)
for v in ('38,741 / 41,910','Total registers : 24624','468 / 553','3,389,411','Total DSP Blocks : 36'):
    need(v in fit,'fit summary '+v)
need('Flow Status                     ; Successful' in (R/'reports/flow.rpt').read_text(),'Quartus flow report')
for fn in ('cross_sys2ram.txt','cross_ram2sys.txt'):
    need((R/'reports'/fn).is_file(),'cross report missing')
need('1.739' in (R/'reports/cross_sys2ram.txt').read_text(),'sys-to-RAM crossing')
need('0.899' in (R/'reports/cross_ram2sys.txt').read_text(),'RAM-to-sys crossing')
need('0.528' in (R/'reports/ram_worst_paths.txt').read_text(),'RAM path report')
need('-0.033' in (R/'reports/cpu_worst_paths.txt').read_text(),'CPU path report')
for p in R.rglob('*'):
    if not p.is_file(): continue
    rel='/'+p.relative_to(R).as_posix().lower()
    need(p.name.lower() not in {'macquadra800.rbf','macquadra800.sof','local.env'},'payload/private file included')
    need('/db/' not in rel and '/incremental_db/' not in rel,'Quartus database included')
print(f'PASS archive={len(entries)} source_inputs=1892 sole_delta=rtl/sdram_beat32.sv Quartus_flow=0 wrapper=1 CPU=-0.033 HDMI=-0.119 RAM_halfcycle=+0.528 cross=12_positive')
