#!/usr/bin/env python3
"""Prepared fail-closed runner for paired six-target core FPU regressions."""
from pathlib import Path
import argparse, hashlib, json, os, re, shutil, signal, subprocess, sys, time

ROOT = Path(__file__).resolve().parent
INPUTS = ROOT / 'inputs'
OUT = ROOT / 'outputs'
MANIFEST = ROOT / 'input_manifest.sha256'
PROFILE = ROOT / 'profile.json'
PREPARED = ROOT / 'prepared_identity.json'
TARGETS = ['fpu', 'fpu_frames', 'fpu_resume', 'mmu', 'exceptions', 'fpu_normalize']
UNITS = [
    'ap040_tg68k_compat', 'ap040_core', 'ap040_bus16_adapter', 'ap040_bus_timeout',
    'ap040_regfile', 'ap040_alu', 'ap040_muldiv', 'ap040_mmu', 'ap040_cache',
    'ap040_walker_cdc', 'primitives/dpram',
]
BASELINE_FPU = INPUTS / 'baseline_ap040_fpu.v'
CANDIDATE_FPU = INPUTS / 'ap68040/rtl/ap040_fpu.v'
ASSEMBLER = Path('/home/alans/mister/MacQuadra800_fixtures/wombat-vasm/vasmm68k_mot')
CANDIDATE_SHA = '6c157b3bc045e74a90416f4764f35cf65024e77577019a100b8aa9b5bdd9ce9b'
BASELINE_SHA = '2d53db3ae4a04310add04eeb7919f0219197a98827ed92e410e6d4a4a90f5465'
PROGRAM_TARGETS = [t for t in TARGETS if t != 'fpu_normalize']
COMMAND_TIMEOUT = 240
TOTAL_TIMEOUT = 3600


def sha256(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as f:
        for block in iter(lambda: f.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def manifest_rows():
    rows = {}
    for n, line in enumerate(MANIFEST.read_text().splitlines(), 1):
        parts = line.split('  ', 1)
        if len(parts) != 2 or len(parts[0]) != 64 or parts[1] in rows:
            raise RuntimeError(f'malformed immutable input manifest row {n}')
        rel = Path(parts[1])
        if rel.is_absolute() or '..' in rel.parts:
            raise RuntimeError(f'unsafe input path on row {n}')
        rows[parts[1]] = parts[0]
    if not rows:
        raise RuntimeError('empty immutable input manifest')
    return rows


def validate_immutable_inputs():
    rows = manifest_rows()
    expected = {p.relative_to(ROOT).as_posix() for p in INPUTS.rglob('*') if p.is_file()}
    expected |= {
        'profile.json', 'source_comparison.json', 'README.md',
        'candidate_vs_baseline_fpu.diff', 'candidate_vs_previous_55ff.diff',
        'previous_55ff_vs_baseline_fpu.diff', 'previous_55ff_vs_73bc_fpu.diff', 'run.py',
    }
    if set(rows) != expected:
        raise RuntimeError(f'input set differs from frozen manifest: missing={sorted(expected-set(rows))[:8]} extra={sorted(set(rows)-expected)[:8]}')
    for rel, digest in rows.items():
        path = ROOT / rel
        if not path.is_file() or sha256(path) != digest:
            raise RuntimeError(f'immutable input hash mismatch: {rel}')
    profile = json.loads(PROFILE.read_text())
    if sha256(BASELINE_FPU) != BASELINE_SHA or profile['baseline_fpu_sha256'] != BASELINE_SHA:
        raise RuntimeError('baseline FPU identity mismatch')
    if sha256(CANDIDATE_FPU) != CANDIDATE_SHA or profile['candidate_fpu_sha256'] != CANDIDATE_SHA:
        raise RuntimeError('candidate FPU identity mismatch')
    if profile['targets'] != TARGETS or not profile['sim_flags']:
        raise RuntimeError('unexpected regression target/flag profile')
    if len(profile['sim_flags']) != 13:
        raise RuntimeError('expected exact reviewed 13 simulation flag set')
    return rows, profile


def tool_identities():
    result = {}
    for name in ('iverilog', 'vvp'):
        found = shutil.which(name)
        if not found:
            raise RuntimeError(f'required tool not found on PATH: {name}')
        p = Path(found).resolve()
        result[name] = {'path': str(p), 'sha256': sha256(p)}
    if not ASSEMBLER.is_file() or not (ASSEMBLER.stat().st_mode & 0o111):
        raise RuntimeError(f'required assembler missing/not executable: {ASSEMBLER}')
    result['assembler'] = {'path': str(ASSEMBLER.resolve()), 'sha256': sha256(ASSEMBLER)}
    return result


def output_freshness():
    if not OUT.exists():
        return
    allowed = {'run_meta'}
    unexpected = {p.name for p in OUT.iterdir()} - allowed
    if unexpected:
        raise RuntimeError(f'output directory is not fresh: {sorted(unexpected)}')
    meta = OUT / 'run_meta'
    if meta.exists():
        unexpected_meta = {p.name for p in meta.iterdir()} - {'preflight_identity.json'}
        if unexpected_meta:
            raise RuntimeError(f'run metadata is not fresh: {sorted(unexpected_meta)}')
    for label in ('baseline', 'candidate'):
        d = OUT / label
        if d.exists() and any(d.iterdir()):
            raise RuntimeError(f'{label} output directory is not fresh')


def preflight(rows, profile):
    output_freshness()
    tools = tool_identities()
    prepared = json.loads(PREPARED.read_text())
    if tools != prepared['tools']:
        raise RuntimeError('tool binary path/hash differs from prepared identity')
    qsf_sha = sha256(INPUTS / 'reference/MacQuadra800.qsf')
    if qsf_sha != profile['qsf_reference_sha256'] or qsf_sha != prepared['qsf_reference_sha256']:
        raise RuntimeError('pinned QSF source identity mismatch')
    if profile['flags'] != prepared['flags'] or profile['sim_flags'] != prepared['sim_flags']:
        raise RuntimeError('reviewed flags differ from prepared identity')
    meta = OUT / 'run_meta'
    meta.mkdir(parents=True, exist_ok=True)
    record = {
        'status': 'PREFLIGHT_PASS_ONLY', 'immutable_input_count': len(rows),
        'immutable_input_manifest_sha256': sha256(MANIFEST),
        'baseline_fpu_sha256': BASELINE_SHA, 'candidate_fpu_sha256': CANDIDATE_SHA,
        'qsf_reference_sha256': qsf_sha, 'flags': profile['flags'],
        'sim_flags': profile['sim_flags'], 'targets': TARGETS, 'tools': tools,
        'outputs_hashed_as_inputs': False, 'no_compile_or_simulation': True,
    }
    (meta / 'preflight_identity.json').write_text(json.dumps(record, indent=2) + '\n')
    return record


def terminate_group(p):
    if p.poll() is not None:
        return
    try:
        os.killpg(p.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    try:
        p.wait(timeout=10)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(p.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        p.wait()


def run_command(cmd, log_path, deadline, cwd=None):
    remaining = deadline - time.monotonic()
    if remaining <= 0:
        raise TimeoutError('paired six-target suite exceeded global 3600-second wall cap')
    timeout = min(COMMAND_TIMEOUT, remaining)
    log_path.parent.mkdir(parents=True, exist_ok=True)
    with log_path.open('w') as log:
        p = subprocess.Popen([str(x) for x in cmd], stdout=log, stderr=subprocess.STDOUT, cwd=cwd, start_new_session=True)
        try:
            rc = p.wait(timeout=timeout)
        except subprocess.TimeoutExpired as exc:
            terminate_group(p)
            raise TimeoutError(f'command timeout after {timeout:.1f}s: {cmd[0]}') from exc
        except BaseException:
            terminate_group(p)
            raise
    text = log_path.read_text(errors='replace')
    if rc != 0:
        raise RuntimeError(f'command failed ({rc}): {cmd}\n{text[-2500:]}')
    return text


def require_pass(text, label):
    if 'ALL TESTS PASSED' not in text or re.search(r'FATAL|TEST FAILED|FAIL:|ERROR:', text):
        raise RuntimeError(f'terminal regression failure in {label}:\n{text[-2500:]}')


def run_suite(label, fpu, flags, deadline, result, progress_path):
    out = OUT / label
    out.mkdir(parents=True, exist_ok=False)
    rtl = INPUTS / 'ap68040/rtl'
    units = [rtl / (u + '.v') for u in UNITS]
    sources = [INPUTS / 'tb/tb_ap040_program.v', *units, fpu, INPUTS / 'ap68040/experimental/ap040_pipeline_integer.sv']
    run_command(['iverilog', *flags, '-I', rtl, '-s', 'tb_ap040_program', '-o', out / 'prog.vvp', *sources], out / 'compile.log', deadline)
    run_command(['iverilog', *flags, '-I', rtl, '-s', 'tb_ap040_fpu_normalize', '-o', out / 'normalize.vvp', INPUTS / 'tb/tb_ap040_fpu_normalize.v', fpu, rtl / 'ap040_regfile.v', rtl / 'primitives/dpram.v'], out / 'normalize_compile.log', deadline)
    target_results = {}
    for target in TARGETS:
        started = time.monotonic()
        if target == 'fpu_normalize':
            sim = out / 'normalize.vvp'
            text = run_command(['vvp', sim], out / f'{target}.log', deadline, cwd=out)
            require_pass(text, f'{label}/{target}')
            phases = re.findall(r'phase (\d) passed \((\d+) cycles\)', text)
            if phases:
                raise RuntimeError(f'unexpected bus phases in {label}/{target}: {phases}')
            artifacts = {'simulation_binary_sha256': sha256(sim)}
        else:
            binary, hexfile = out / f'{target}.bin', out / f'{target}.hex'
            run_command([ASSEMBLER, '-Fbin', '-m68040', '-no-opt', '-o', binary, INPUTS / 'tb/asm' / f't_{target}.s'], out / f'{target}_asm.log', deadline)
            run_command([sys.executable, INPUTS / 'tb/bin2hex.py', binary, hexfile], out / f'{target}_hex.log', deadline)
            if not binary.is_file() or not hexfile.is_file():
                raise RuntimeError(f'program image missing before vvp: {target}')
            plusarg = hexfile.name
            if len(plusarg.encode('ascii')) > 128:
                raise RuntimeError(f'program filename exceeds testbench 128-byte buffer: {plusarg!r}')
            sim = out / 'prog.vvp'
            text = run_command(['vvp', sim, '+prog=' + plusarg], out / f'{target}.log', deadline, cwd=out)
            require_pass(text, f'{label}/{target}')
            phases = re.findall(r'phase (\d) passed \((\d+) cycles\)', text)
            if [int(x[0]) for x in phases] != [0, 1, 2]:
                raise RuntimeError(f'missing three bus phases in {label}/{target}: {phases}')
            artifacts = {
                'simulation_binary_sha256': sha256(sim),
                'program_binary_sha256': sha256(binary),
                'program_hex_sha256': sha256(hexfile),
            }
        target_results[target] = {
            'status': 'PASS', 'bus_phase_cycles': {a: int(b) for a, b in phases},
            'log_sha256': sha256(out / f'{target}.log'), 'wall_seconds': round(time.monotonic() - started, 3),
            'artifacts': artifacts,
        }
        result['targets'][label] = target_results
        progress_path.write_text(json.dumps(result, indent=2) + '\n')
        print(f'{label} {target} PASS', flush=True)
    return target_results


def main():
    ap = argparse.ArgumentParser()
    mode = ap.add_mutually_exclusive_group(required=True)
    mode.add_argument('--preflight-only', action='store_true', help='check immutable inputs/tools; no compile or simulation')
    mode.add_argument('--launch-reviewed', action='store_true', help='launch paired regressions after explicit root authorization')
    args = ap.parse_args()
    rows, profile = validate_immutable_inputs()
    prepared = preflight(rows, profile)
    if args.preflight_only:
        print('PREFLIGHT PASS ONLY; no compile or simulation launched', flush=True)
        return 0
    def interrupt(signum, frame):
        raise KeyboardInterrupt(f'signal {signum}')
    signal.signal(signal.SIGTERM, interrupt)
    signal.signal(signal.SIGINT, interrupt)
    started = time.monotonic()
    deadline = started + TOTAL_TIMEOUT
    result = {
        'scope': profile['scope'], 'immutable_input_manifest_sha256': sha256(MANIFEST),
        'immutable_input_count': len(rows), 'source_flags': profile['flags'], 'sim_flags': profile['sim_flags'],
        'tools': prepared['tools'], 'targets': {}, 'simulation_status': 'RUNNING',
        'global_wall_cap_seconds': TOTAL_TIMEOUT, 'command_wall_cap_seconds': COMMAND_TIMEOUT,
    }
    progress = OUT / 'run_meta/progress.json'
    progress.write_text(json.dumps(result, indent=2) + '\n')
    try:
        run_suite('baseline', BASELINE_FPU, profile['flags'], deadline, result, progress)
        run_suite('candidate', CANDIDATE_FPU, profile['flags'], deadline, result, progress)
        after = manifest_rows()
        if after != rows:
            raise RuntimeError('immutable input manifest changed during regression run')
        for rel, digest in rows.items():
            if sha256(ROOT / rel) != digest:
                raise RuntimeError(f'immutable input changed during run: {rel}')
        result['simulation_status'] = 'PASS'
        result['immutable_inputs_revalidated'] = len(rows)
        result['wall_seconds'] = round(time.monotonic() - started, 3)
        (OUT / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
        progress.write_text(json.dumps(result, indent=2) + '\n')
        print('PASS paired six-target baseline/candidate regressions; immutable inputs revalidated', flush=True)
    except BaseException as exc:
        result['simulation_status'] = 'FAILED'
        result['failure'] = repr(exc)
        result['wall_seconds'] = round(time.monotonic() - started, 3)
        (OUT / 'failure.json').write_text(json.dumps(result, indent=2) + '\n')
        progress.write_text(json.dumps(result, indent=2) + '\n')
        raise
    return 0


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f'FAIL CLOSED: {exc}', file=sys.stderr, flush=True)
        raise SystemExit(1)
