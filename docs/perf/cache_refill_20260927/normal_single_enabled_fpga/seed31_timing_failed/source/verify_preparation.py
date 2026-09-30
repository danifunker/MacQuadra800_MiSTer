#!/usr/bin/env python3
"""Fail-closed check for the seed-31 candidate preparation; never runs Quartus."""
from pathlib import Path
import hashlib, sys
root=Path(__file__).resolve().parent; tree=root/'tree'
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
base=Path(__file__).resolve().parents[1]/'fpu_normal_single_enabled_quartus_20260928_seed28'
base_tree=base/'tree'
manifest=root/'seed31_candidate_6c_manifest.sha256'
rows=[line.split('  ',1) for line in manifest.read_text().splitlines()]
if len(rows)!=1892: raise SystemExit(f'expected 1892 manifest rows, got {len(rows)}')
for digest,rel in rows:
 p=tree/rel
 if not p.is_file() or sha(p)!=digest: raise SystemExit(f'manifest mismatch: {rel}')
changed=[]
for line in (base/'seed28_candidate_6c_manifest.sha256').read_text().splitlines():
 digest,rel=line.split('  ',1)
 if sha(tree/rel)!=digest: changed.append(rel)
if changed!=['MacQuadra800.qsf']: raise SystemExit(f'only QSF may change; changed={changed}')
q28=(base_tree/'MacQuadra800.qsf').read_text(); q31=(tree/'MacQuadra800.qsf').read_text()
if q28.replace('set_global_assignment -name SEED 28','set_global_assignment -name SEED 31')!=q31: raise SystemExit('QSF has changes beyond seed 28->31')
if sha(tree/'rtl/ap68040/rtl/ap040_fpu.v')!='6c157b3bc045e74a90416f4764f35cf65024e77577019a100b8aa9b5bdd9ce9b': raise SystemExit('candidate FPU hash mismatch')
if sha(tree/'MacQuadra800.sdc')!='b2f5bd18b52d7897f711b7b1c465c6a5bd1fffa344275557761aba8f40929062': raise SystemExit('SDC hash mismatch')
if sha(tree/'rtl/ap68040/rtl/ap040_cache.v')!='7cba7f73f6f7f16fa7a45d439af6a786bd55c3ef2a3f8c876b400e10d4fb7747': raise SystemExit('cache hash mismatch')
if (tree/'scripts/local.env').stat().st_mode & 0o777 != 0o600: raise SystemExit('local.env must be mode 0600')
for name in ('db','incremental_db','output_files'):
 if (tree/name).exists(): raise SystemExit(f'generated directory already exists: {name}')
print('PASS: 1892 manifest entries; only seed assignment changed; FPU/SDC/cache intact; local.env mode 0600; generated dirs absent')
