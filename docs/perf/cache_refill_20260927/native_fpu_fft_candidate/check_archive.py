#!/usr/bin/env python3
from pathlib import Path
import hashlib,subprocess,sys,json
D=Path(__file__).resolve().parent
for row in (D/'archive_manifest.sha256').read_text().splitlines():
 h,n=row.split('  ',1);assert hashlib.sha256((D/n).read_bytes()).hexdigest()==h,n
subprocess.run([sys.executable,str(D/'check_result.py')],check=True)
a=json.loads((D.parent/'native_fpu_fft/measurement.json').read_text());b=json.loads((D/'measurement.json').read_text());c=json.loads((D/'comparison.json').read_text())
assert a['loop_cycles']==c['baseline_loop']==14301941 and b['loop_cycles']==c['candidate_loop']==13358788
assert c['saved_clocks']==a['loop_cycles']-b['loop_cycles']==943153
fpu=[v for k,v in json.loads((D/'run/identity.json').read_text())['sources'].items() if k.endswith('/ap040_fpu.v')]
assert fpu==[c['candidate_fpu_sha256']]
for k in ['ABI','chip_bus_irq_errors','allocations','native_calls','starting_fpcr']:assert a[k]==b[k],k
print('PASS native FFT candidate archive/runtime comparison; numerical output unqualified')
