#!/usr/bin/env python3
from pathlib import Path
import hashlib, json, re, sys

ROOT = Path(sys.argv[1] if len(sys.argv) > 1 else '.')
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def read_json(p): return json.loads((ROOT/p).read_text())
def require(ok, message):
    if not ok: raise SystemExit('FAIL: ' + message)

# Every archived file except the manifest itself is listed exactly once.
manifest = ROOT/'SHA256SUMS'
entries = {}
for line in manifest.read_text().splitlines():
    h, name = line.split('  ', 1)
    require(re.fullmatch(r'[0-9a-f]{64}', h) is not None, 'bad digest syntax')
    require(name not in entries, 'duplicate manifest path: '+name)
    entries[name] = h
actual = {p.relative_to(ROOT).as_posix() for p in ROOT.rglob('*') if p.is_file() and p != manifest}
require(set(entries) == actual, 'manifest file set mismatch')
for name, digest in entries.items(): require(sha(ROOT/name) == digest, 'hash mismatch: '+name)

build = read_json('build/completed_build_identity.json')
bmeta = read_json('build/build.meta.json')
ready = read_json('build/launch_ready_identity.json')
smoke = read_json('smoke/meta.json')
require(build['status'] == bmeta['status'] == 'PASS', 'build did not pass')
require(build['build_log_sha256'] == sha(ROOT/'build/build.log'), 'build log identity')
require(bmeta['supervisor_sha256'] == sha(ROOT/'build/build.py'), 'build supervisor identity')
require(build['supervisor_sha256'] == bmeta['supervisor_sha256'], 'build supervisor mismatch')
require(bmeta.get('before_manifest') == bmeta.get('after_manifest') == 'PASS', 'build source checks')
require(all(x.get('exit_status') == 0 for x in bmeta['commands']), 'build child exit status')
require(build['candidate_sha256'] == ready['candidate_fpu'] == sha(ROOT/'source/candidate_ap040_fpu.v'), 'candidate FPU identity')
require(build['observer_sha256'] == sha(ROOT/'source/sim_fpu_guard_profile.h'), 'observer identity')
require(build['source_manifest_sha256'] == ready['source_manifest_sha256'] == sha(ROOT/'build/source_manifest.sha256'), 'project manifest identity')
require(build['binary_sha256'] == ready['binary_sha256'] == smoke['binary_sha256'], 'binary identity metadata')
require(smoke['status'] == 'PASS' and smoke['child_terminal'] is True and smoke['exit_status'] == 0, 'smoke terminal status')
require(smoke['supervisor_sha256'] == sha(ROOT/'smoke/smoke.py'), 'smoke supervisor identity')
require(ready['run_supervisor_sha256'] == sha(ROOT/'runner/run_fpu.py'), 'fullguest supervisor identity')
require(ready['observer_checker_sha256'] == sha(ROOT/'checker/check_guard_report.py'), 'observer checker identity')
require(smoke['check0'] == smoke['check1'] == 0 and smoke['source_manifest_postrun'] == 'PASS', 'smoke checker/source statuses')
require(smoke['ROM_sha256'] == ready['ROM_sha256'], 'ROM identity')
require('zero raw FP command-branch events' in (ROOT/'README.md').read_text(), 'README empty-event scope')
refill = (ROOT/'smoke/refill.tsv').read_text().splitlines()
summary = [line.split('\t') for line in refill if line.startswith('SUMMARY\t')]
require(len(summary) == 2 and summary[1][1] == '100002', 'smoke profile edge count')
observer = [line.split('\t') for line in refill if line.startswith('FPU_GUARD_SUMMARY\t')]
require(len(observer) == 2 and observer[1][1] == '100002' and observer[1][2] == '0' and observer[1][9] == '0', 'smoke must have zero raw and eligible FP events')
require(observer[0][1] == 'edges' and observer[0][-1] == 'reconciles', 'observer report header')
require('PASS v2 enabled observer report' in (ROOT/'smoke/check_observer.log').read_text(), 'observer checker log')
require('refill report reconciles:' in (ROOT/'smoke/check_refill.log').read_text(), 'refill checker log')
for p in ROOT.rglob('*'):
    if not p.is_file(): continue
    n=p.name.lower()
    require(n not in {'vemu','rom.hex','run.hda','local.env'}, 'forbidden payload: '+str(p.relative_to(ROOT)))
    require('fpu_run' not in str(p.relative_to(ROOT)), 'live fullguest output in archive')
    require('ccache' not in str(p.relative_to(ROOT)), 'cache in archive')
print('PASS archive files=%d build=PASS smoke=PASS edges=100002 raw_fp=0 eligible=0 binary_omitted=1 ROM_omitted=1' % len(entries))
