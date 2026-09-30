#!/usr/bin/env python3
from pathlib import Path
import argparse,subprocess,hashlib,json,os,datetime,signal,sys
D=Path(__file__).resolve().parent
p=argparse.ArgumentParser();p.add_argument('--kind',choices=['fpu','color8'],required=True);a=p.parse_args();out=D/(a.kind+'_run')
def sha(f):return hashlib.sha256(f.read_bytes()).hexdigest()
pre=json.loads((D/'preflight.json').read_text());build=json.loads((D/'completed_build_identity.json').read_text())
assert build['status']=='PASS'
for line in (D/'source_manifest.sha256').read_text().splitlines():
 h,n=line.split('  ',1);assert sha(Path(n))==h,n
assert sha(D/'verilator/obj_dir/Vemu')==build['binary_sha256']
assert sha(out/'run.hda')==pre['golden_disk_sha256']
assert sha(out/'control.txt')==pre['controls'][a.kind]
assert sha(D/'verilator/quadra800-fastboot.rom.hex')=='045c02746b5f15f83132d33c5414f806e7b049f3bfe53a7bd0ecacb8e072d673'
assert set(f.name for f in out.iterdir())=={'run.hda','control.txt'},'outputdirectory must be fresh'
cmd=[str(D/'verilator/obj_dir/Vemu'),'--headless','--no-cpu-trace','--disk','run.hda','+rom='+str(D/'verilator/quadra800-fastboot.rom.hex'),'+ram=0','--control','control.txt','--cpu-profile','refill.tsv','--max-cycles','20000000000','+ram_line_model','+ram_first_latency=4','+ram_line_publish_delay=2']
meta={'status':'STARTING','supervisor_pid':os.getpid(),'started_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'argv':cmd,'binary_sha256':build['binary_sha256'],'build_identity_sha256':sha(D/'completed_build_identity.json'),'golden_input_disk_sha256':sha(out/'run.hda'),'control_sha256':sha(out/'control.txt'),'source_manifest_sha256':sha(D/'source_manifest.sha256')}
def save(): (out/'run.meta.json').write_text(json.dumps(meta,indent=2)+'\n')
save();child=None
# If this supervisor is stopped, stop the actual child group and record failure.
def stop(signum,frame):
 if child is not None and child.poll() is None:os.killpg(child.pid,signal.SIGTERM)
 meta['status']='INTERRUPTED';meta['signal']=signum;save();sys.exit(128+signum)
signal.signal(signal.SIGTERM,stop);signal.signal(signal.SIGINT,stop)
with (out/'run.log').open('w') as log:
 child=subprocess.Popen(cmd,cwd=out,stdout=log,stderr=subprocess.STDOUT,start_new_session=True)
 meta['child_pid']=child.pid;meta['status']='RUNNING';save();rc=child.wait()
meta['exit_status']=rc;meta['finished_utc']=datetime.datetime.now(datetime.timezone.utc).isoformat();meta['status']='SIM_EXIT0_PENDING_SCREENSHOT_REVIEW' if rc==0 else 'FAILED';save()
(out/'exit_status.txt').write_text(str(rc)+'\n')
if rc:raise SystemExit(rc)
with (out/'refill_check.log').open('w') as log:
 check=subprocess.run([sys.executable,str(D/'verilator/tests/check_refill_report.py'),str(out/'refill.tsv')],stdout=log,stderr=subprocess.STDOUT)
meta['refill_check_exit_status']=check.returncode;meta['status']='EXIT0_REFILL_PASS_PENDING_SCREENSHOT_REVIEW' if check.returncode==0 else 'REFILL_CHECK_FAILED';save();raise SystemExit(check.returncode)
