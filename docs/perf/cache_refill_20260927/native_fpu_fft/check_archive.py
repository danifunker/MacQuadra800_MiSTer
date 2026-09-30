#!/usr/bin/env python3
from pathlib import Path
import hashlib,subprocess,sys
D=Path(__file__).resolve().parent
for row in (D/'archive_manifest.sha256').read_text().splitlines():
 h,n=row.split('  ',1);assert hashlib.sha256((D/n).read_bytes()).hexdigest()==h,n
subprocess.run([sys.executable,str(D/'check_result.py')],check=True)
print('PASS native FFT baseline archive checksums')
