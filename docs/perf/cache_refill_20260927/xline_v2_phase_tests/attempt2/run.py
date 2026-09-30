#!/usr/bin/env python3
"""One serial bounded phase pair; launch only after parent source approval."""
from pathlib import Path
import datetime, hashlib, json, os, signal, subprocess, sys
P = Path(__file__).resolve().parent
R = P.parent
O = P / 'outputs'
CACHE = {'baseline': '7cba7f73f6f7f16fa7a45d439af6a786bd55c3ef2a3f8c876b400e10d4fb7747',
         'candidate': '9e8c0582db1b0bb88428e56fec63e99029b61faffac62c6f3dda9326b5191481'}
sha = lambda f: hashlib.sha256(f.read_bytes()).hexdigest()
def verify():
    for row in (P / 'source_manifest.sha256').read_text().splitlines():
        h, name = row.split('  ', 1)
        assert sha(R / name) == h, name
    for variant, expected in CACHE.items():
        assert sha(R / 'inputs' / variant / 'rtl/ap68040/rtl/ap040_cache.v') == expected

verify()
assert not O.exists(), 'preserve existing outputs; no automatic retry'
O.mkdir()
meta = {'status': 'RUNNING', 'runner_pid': os.getpid(),
        'started_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'source_manifest_sha256': sha(P / 'source_manifest.sha256'),
        'cache_sha256': CACHE, 'flags': ['-g2012', '-DAP040_EXPERIMENTAL_XSTORE'],
        'candidate_observer_define': 'TEST_XFIRST',
        'scope': 'direct cache ports; independent byte oracle; no CPU/MMU/SDRAM timing claim',
        'per_step_timeout_seconds': 90, 'steps': []}
child = None
def save():
    (O / 'metadata.json').write_text(json.dumps(meta, indent=2) + '\n')
def cleanup():
    if child is not None and child.poll() is None:
        os.killpg(child.pid, signal.SIGKILL)
        child.wait()
def stop(signum, frame):
    cleanup()
    raise RuntimeError('signal ' + str(signum))
signal.signal(signal.SIGTERM, stop)
signal.signal(signal.SIGINT, stop)
try:
    save()
    for variant in ['baseline', 'candidate']:
        rtl = R / 'inputs' / variant / 'rtl/ap68040/rtl'
        exe = O / (variant + '.vvp')
        defines = ['-DTEST_XFIRST'] if variant == 'candidate' else []
        commands = [('build', ['iverilog', '-g2012', '-DAP040_EXPERIMENTAL_XSTORE',
                             *defines, '-I', str(rtl), '-s', 'tb_xfirst_sideband',
                             '-o', str(exe), str(P / 'tb_xfirst_sideband.sv'),
                             str(rtl / 'ap040_cache.v'), str(rtl / 'primitives/dpram.v')]),
                    ('run', ['vvp', str(exe)])]
        for stage, argv in commands:
            step = {'name': variant + '_' + stage, 'argv': argv}
            meta['steps'].append(step)
            with (O / (step['name'] + '.log')).open('x') as log:
                child = subprocess.Popen(argv, cwd=O, stdout=log, stderr=subprocess.STDOUT,
                                         start_new_session=True)
                step['pid'] = child.pid
                save()
                try:
                    child.wait(timeout=90)
                except BaseException:
                    cleanup()
                    raise
            step.update(exit_status=child.returncode, terminal=True)
            save()
            assert child.returncode == 0, step['name']
    with (O / 'check_results.log').open('x') as log:
        subprocess.run([sys.executable, str(P / 'check_results.py'), str(O)],
                       stdout=log, stderr=subprocess.STDOUT, timeout=30, check=True)
    verify()
    meta.update(status='PASS_XFIRST_PHASE_PAIR', postrun_source='PASS')
except BaseException as exc:
    cleanup()
    meta.update(status='FAILED', error=repr(exc))
    raise
finally:
    meta['finished_utc'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
    save()
