#!/usr/bin/env python3
from pathlib import Path
import hashlib,subprocess,sys
D=Path(__file__).resolve().parent
rows=(D/'archive_manifest.sha256').read_text().splitlines()
def verify():
 for row in rows:
  h,n=row.split('  ',1);assert hashlib.sha256((D/n).read_bytes()).hexdigest()==h,n
verify();subprocess.run([sys.executable,str(D/'check_pair.py')],check=True);verify()
print('PASS archived native FFT paired capture checksums; baseline regression only')
