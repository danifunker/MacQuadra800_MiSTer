#!/usr/bin/env python3
"""Bounded paired existing AP040 program regressions; no retries."""
from pathlib import Path
import argparse, concurrent.futures, hashlib, json, os, re, shutil, signal, subprocess, sys, threading, time

ROOT = Path(__file__).resolve().parent
INPUTS, OUT = ROOT / 'inputs', ROOT / 'outputs'
MANIFEST, PROFILE, PREPARED = ROOT / 'input_manifest.sha256', ROOT / 'profile.json', ROOT / 'prepared_identity.json'
TARGETS = ['fpu', 'fpu_frames', 'fpu_resume', 'mmu', 'exceptions']
EXPECTED_FLAGS = ['-g2012','-DAP040_EXPERIMENTAL_LEA=1','-DAP040_EXPERIMENTAL_PIPELINE=1',
    '-DAP040_EXPERIMENTAL_PIPELINE_LOADS=1','-DAP040_EXPERIMENTAL_PIPELINE_P6=1',
    '-DAP040_EXPERIMENTAL_PIPELINE_PEA=1','-DAP040_EXPERIMENTAL_PIPELINE_STORES=1',
    '-DAP040_EXPERIMENTAL_XSTORE=1','-DAP040_PIPELINE_COMPARE=1','-DAP040_PIPELINE_EARLY_DRAIN=1',
    '-DAP040_PIPELINE_MEMORY_ENTRY=1','-DCACHE_CD_OFF=1','-DCACHE_SMALL=1','-DSIMULATION=1']
EXPECTED_SIM_FLAGS = EXPECTED_FLAGS[1:]
UNITS = [
    'ap040_tg68k_compat', 'ap040_core', 'ap040_bus16_adapter', 'ap040_bus_timeout',
    'ap040_regfile', 'ap040_alu', 'ap040_muldiv', 'ap040_mmu', 'ap040_walker_cdc',
    'primitives/dpram',
]
FPU_FILES = {'baseline': INPUTS / 'baseline_ap040_fpu.v', 'candidate': INPUTS / 'ap68040/rtl/ap040_fpu.v'}
CACHE_FILES = {'baseline': INPUTS / 'ap68040/rtl/ap040_cache.v', 'candidate': INPUTS / 'candidate_ap040_cache.v'}
EXPECTED_FPU_SHA = '6c157b3bc045e74a90416f4764f35cf65024e77577019a100b8aa9b5bdd9ce9b'
EXPECTED_CACHE_SHA = {'baseline': '7cba7f73f6f7f16fa7a45d439af6a786bd55c3ef2a3f8c876b400e10d4fb7747',
                      'candidate': '9e8c0582db1b0bb88428e56fec63e99029b61faffac62c6f3dda9326b5191481'}
ASSEMBLER = Path('/home/alans/mister/MacQuadra800_fixtures/wombat-vasm/vasmm68k_mot')
COMMAND_TIMEOUT, TOTAL_TIMEOUT, MAX_WORKERS = 240, 3600, 2
LOCK = threading.RLock()

def sha(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as f:
        for block in iter(lambda: f.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()

def manifest_rows():
    rows = {}
    for n, line in enumerate(MANIFEST.read_text().splitlines(), 1):
        parts = line.split('  ', 1)
        if len(parts) != 2 or not re.fullmatch(r'[0-9a-f]{64}', parts[0]) or parts[1] in rows:
            raise RuntimeError(f'malformed immutable input manifest row {n}')
        rel = Path(parts[1])
        if rel.is_absolute() or '..' in rel.parts:
            raise RuntimeError(f'unsafe input path on row {n}')
        rows[parts[1]] = parts[0]
    if not rows:
        raise RuntimeError('empty immutable input manifest')
    return rows

def expected_files():
    result = {p.relative_to(ROOT).as_posix() for p in INPUTS.rglob('*') if p.is_file()}
    result |= {'profile.json', 'source_comparison.json', 'command_plan.json', 'README.md', 'run_cache_pair.py', 'candidate_cache.diff'}
    return result

def validate_inputs():
    rows = manifest_rows()
    if set(rows) != expected_files():
        raise RuntimeError(f'input set differs from manifest: missing={sorted(expected_files()-set(rows))[:8]} extra={sorted(set(rows)-expected_files())[:8]}')
    for rel, digest in rows.items():
        path = ROOT / rel
        if not path.is_file() or sha(path) != digest:
            raise RuntimeError(f'input hash mismatch: {rel}')
    profile = json.loads(PROFILE.read_text())
    for label in ('baseline', 'candidate'):
        if sha(FPU_FILES[label]) != EXPECTED_FPU_SHA:
            raise RuntimeError(f'{label} FPU identity is not the frozen 6c source')
        if sha(CACHE_FILES[label]) != EXPECTED_CACHE_SHA[label]:
            raise RuntimeError(f'{label} cache identity mismatch')
    if profile['targets'] != TARGETS or profile['flags'] != EXPECTED_FLAGS or profile['sim_flags'] != EXPECTED_SIM_FLAGS:
        raise RuntimeError('unexpected targets or release flag count')
    if profile['fpu_sha256'] != EXPECTED_FPU_SHA or profile['cache_sha256'] != EXPECTED_CACHE_SHA:
        raise RuntimeError('profile source identities mismatch')
    return rows, profile

def tools_identity():
    result = {}
    for name in ('iverilog', 'vvp'):
        found = shutil.which(name)
        if not found:
            raise RuntimeError(f'required tool missing: {name}')
        path = Path(found).resolve()
        result[name] = {'path': str(path), 'sha256': sha(path)}
    if not ASSEMBLER.is_file() or not (ASSEMBLER.stat().st_mode & 0o111):
        raise RuntimeError(f'required assembler missing/not executable: {ASSEMBLER}')
    result['assembler'] = {'path': str(ASSEMBLER.resolve()), 'sha256': sha(ASSEMBLER)}
    return result

def output_freshness():
    if not OUT.exists():
        return
    unexpected = {p.name for p in OUT.iterdir()} - {'run_meta'}
    if unexpected:
        raise RuntimeError(f'output directory not fresh: {sorted(unexpected)}')
    meta = OUT / 'run_meta'
    if meta.exists() and {p.name for p in meta.iterdir()} - {'preflight_identity.json'}:
        raise RuntimeError('run metadata has outputs from a prior launch')
    for label in ('baseline', 'candidate'):
        d = OUT / label
        if d.exists() and any(d.iterdir()):
            raise RuntimeError(f'{label} output is not fresh')

def preflight(rows, profile):
    output_freshness()
    tools = tools_identity()
    prepared = json.loads(PREPARED.read_text())
    if tools != prepared['tools']:
        raise RuntimeError('tool binary identity differs from prepared identity')
    qsf = sha(INPUTS / 'reference/MacQuadra800.qsf')
    if qsf != profile['qsf_reference_sha256']:
        raise RuntimeError('pinned release QSF identity mismatch')
    record = {'status':'PREFLIGHT_PASS_ONLY', 'no_compile_or_simulation':True,
              'input_manifest_sha256':sha(MANIFEST), 'input_count':len(rows),
              'targets':TARGETS, 'flags':profile['flags'], 'sim_flags':profile['sim_flags'],
              'fpu_sha256':EXPECTED_FPU_SHA, 'cache_sha256':EXPECTED_CACHE_SHA,
              'qsf_reference_sha256':qsf, 'tools':tools, 'max_workers':MAX_WORKERS,
              'command_timeout_seconds':COMMAND_TIMEOUT, 'global_timeout_seconds':TOTAL_TIMEOUT}
    meta = OUT / 'run_meta'; meta.mkdir(parents=True, exist_ok=True)
    (meta / 'preflight_identity.json').write_text(json.dumps(record,indent=2)+'\n')
    return record

def kill_group(p):
    if p.poll() is not None: return
    try: os.killpg(p.pid, signal.SIGTERM)
    except ProcessLookupError: pass
    try: p.wait(timeout=10)
    except subprocess.TimeoutExpired:
        try: os.killpg(p.pid, signal.SIGKILL)
        except ProcessLookupError: pass
        p.wait()

def run_command(cmd, log_path, deadline, cwd=None):
    remaining = deadline - time.monotonic()
    if remaining <= 0: raise TimeoutError('paired run exceeded 3,600-second wall cap')
    timeout = min(COMMAND_TIMEOUT, remaining)
    log_path.parent.mkdir(parents=True, exist_ok=True)
    with log_path.open('w') as log:
        p = subprocess.Popen([str(x) for x in cmd], stdout=log, stderr=subprocess.STDOUT, cwd=cwd, start_new_session=True)
        try: rc = p.wait(timeout=timeout)
        except subprocess.TimeoutExpired as e:
            kill_group(p); raise TimeoutError(f'command timed out after {timeout:.1f}s: {cmd[0]}') from e
        except BaseException:
            kill_group(p); raise
    text = log_path.read_text(errors='replace')
    if rc: raise RuntimeError(f'command failed ({rc}): {cmd}\n{text[-2500:]}')
    return text

def require_pass(text, label):
    if 'ALL TESTS PASSED' not in text or re.search(r'FATAL|TEST FAILED|FAIL:|ERROR:', text):
        raise RuntimeError(f'terminal regression failure in {label}:\n{text[-2500:]}')

def write_progress(result):
    with LOCK:
        tmp = OUT / 'run_meta/progress.tmp'
        tmp.write_text(json.dumps(result,indent=2)+'\n')
        tmp.replace(OUT / 'run_meta/progress.json')

def run_suite(label, flags, deadline, result):
    out = OUT / label; out.mkdir(parents=True, exist_ok=False)
    rtl = INPUTS / 'ap68040/rtl'
    units = [rtl / (u + '.v') for u in UNITS]
    fpu, cache = FPU_FILES[label], CACHE_FILES[label]
    sources = [INPUTS / 'tb/tb_ap040_program.v', *units, fpu, cache,
               INPUTS / 'ap68040/experimental/ap040_pipeline_integer.sv']
    run_command(['iverilog', *flags, '-I', rtl, '-s', 'tb_ap040_program', '-o', out/'prog.vvp', *sources], out/'compile.log', deadline)
    target_results = {}
    for target in TARGETS:
        started = time.monotonic()
        binary, hexfile = out/f'{target}.bin', out/f'{target}.hex'
        run_command([ASSEMBLER,'-Fbin','-m68040','-no-opt','-o',binary,INPUTS/'tb/asm'/f't_{target}.s'], out/f'{target}_asm.log', deadline)
        run_command([sys.executable,INPUTS/'tb/bin2hex.py',binary,hexfile], out/f'{target}_hex.log', deadline)
        if not binary.is_file() or not hexfile.is_file(): raise RuntimeError(f'{target} image missing')
        if len(hexfile.name.encode('ascii')) > 128: raise RuntimeError(f'+prog filename too long: {hexfile.name}')
        text = run_command(['vvp',out/'prog.vvp','+prog='+hexfile.name],out/f'{target}.log',deadline,cwd=out)
        require_pass(text,f'{label}/{target}')
        phases = re.findall(r'phase (\d) passed \((\d+) cycles\)',text)
        if [int(x[0]) for x in phases] != [0,1,2]: raise RuntimeError(f'missing three bus phases in {label}/{target}: {phases}')
        target_results[target]={'status':'PASS','bus_phase_cycles':{a:int(b) for a,b in phases},
             'log_sha256':sha(out/f'{target}.log'),'wall_seconds':round(time.monotonic()-started,3),
             'simulation_binary_sha256':sha(out/'prog.vvp'),'program_binary_sha256':sha(binary),'program_hex_sha256':sha(hexfile)}
        with LOCK:
            result['targets'][label]=target_results.copy()
            write_progress(result)
        print(f'{label} {target} PASS',flush=True)
    return target_results

def main():
    ap=argparse.ArgumentParser()
    mode=ap.add_mutually_exclusive_group(required=True)
    mode.add_argument('--preflight-only',action='store_true')
    mode.add_argument('--launch-reviewed',action='store_true')
    args=ap.parse_args()
    rows,profile=validate_inputs(); prepared=preflight(rows,profile)
    if args.preflight_only:
        print('PREFLIGHT PASS ONLY; no compile or simulation launched',flush=True); return 0
    def interrupt(signum,frame): raise KeyboardInterrupt(f'signal {signum}')
    signal.signal(signal.SIGTERM,interrupt); signal.signal(signal.SIGINT,interrupt)
    start=time.monotonic(); deadline=start+TOTAL_TIMEOUT
    result={'simulation_status':'RUNNING','scope':profile['scope'],'input_manifest_sha256':sha(MANIFEST),
            'input_count':len(rows),'fpu_sha256':EXPECTED_FPU_SHA,'cache_sha256':EXPECTED_CACHE_SHA,
            'flags':profile['flags'],'sim_flags':profile['sim_flags'],'tools':prepared['tools'],
            'targets':{},'workers':MAX_WORKERS,'command_timeout_seconds':COMMAND_TIMEOUT,'global_timeout_seconds':TOTAL_TIMEOUT}
    progress=OUT/'run_meta/progress.json'; write_progress(result)
    try:
        with concurrent.futures.ThreadPoolExecutor(max_workers=MAX_WORKERS) as pool:
            futures={pool.submit(run_suite,label,profile['flags'],deadline,result):label for label in ('baseline','candidate')}
            for future in concurrent.futures.as_completed(futures): future.result()
        after=manifest_rows()
        if after!=rows: raise RuntimeError('immutable inputs changed during run')
        for rel,digest in rows.items():
            if sha(ROOT/rel)!=digest: raise RuntimeError(f'input changed during run: {rel}')
        result['simulation_status']='PASS'; result['immutable_inputs_revalidated']=len(rows)
        result['wall_seconds']=round(time.monotonic()-start,3)
        (OUT/'result.json').write_text(json.dumps(result,indent=2)+'\n'); write_progress(result)
        print('PASS paired cache-v2 core regressions; inputs revalidated',flush=True); return 0
    except BaseException as exc:
        result['simulation_status']='FAILED'; result['failure']=repr(exc)
        result['wall_seconds']=round(time.monotonic()-start,3)
        (OUT/'failure.json').write_text(json.dumps(result,indent=2)+'\n'); write_progress(result); raise

if __name__=='__main__':
    try: raise SystemExit(main())
    except Exception as exc:
        print(f'FAIL CLOSED: {exc}',file=sys.stderr,flush=True); raise SystemExit(1)
