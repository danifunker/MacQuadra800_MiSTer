#!/usr/bin/env python3
from pathlib import Path
import argparse,subprocess,hashlib,json,os,datetime,signal,sys
D=Path(__file__).resolve().parent;p=argparse.ArgumentParser();p.add_argument('--variant',choices=['baseline','candidate'],required=True);a=p.parse_args();out=D/a.variant;sha=lambda f:hashlib.sha256(f.read_bytes()).hexdigest()
identity=json.loads((out/'inputs.json').read_text());assert set(f.name for f in out.iterdir())=={'Vemu','control.txt','run.hda','rom.hex','inputs.json'},'fresh output paths required'
for name,h in identity['prelaunch_files'].items():assert sha(out/name)==h,name
cmd=[str(out/'Vemu'),'--headless','--no-cpu-trace','--disk','run.hda','+rom=rom.hex','+ram=0','--control','control.txt','--cpu-profile','refill.tsv','--max-cycles','20000000000','+ram_line_model','+ram_first_latency=4','+ram_line_publish_delay=2']
meta={'status':'STARTING','variant':a.variant,'supervisor_pid':os.getpid(),'started_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'argv':cmd,'input_identity_sha256':sha(out/'inputs.json'),'supervisor_sha256':sha(D/'run_mix.py'),'binary_sha256':sha(out/'Vemu'),'guest_measurement':'all10/1iteration setup+done/result screens required; not accepted byfixedwindow counters'}
def save():(out/'run.meta.json').write_text(json.dumps(meta,indent=2)+'\n')
save();child=None

def stop(signum,frame):
 if child is not None and child.poll() is None:os.killpg(child.pid,signal.SIGTERM)
 meta['status']='INTERRUPTED';meta['signal']=signum;save();sys.exit(128+signum)
signal.signal(signal.SIGTERM,stop);signal.signal(signal.SIGINT,stop)
with (out/'run.log').open('w') as log:
 child=subprocess.Popen(cmd,cwd=out,stdout=log,stderr=subprocess.STDOUT,start_new_session=True);meta['child_pid']=child.pid;meta['status']='RUNNING';save();rc=child.wait()
meta['exit_status']=rc;meta['finished_utc']=datetime.datetime.now(datetime.timezone.utc).isoformat();meta['status']='SIM_EXIT0_PENDING_SCREENSHOT_REVIEW' if rc==0 else 'FAILED';save();(out/'exit_status.txt').write_text(str(rc)+'\n')
if rc:raise SystemExit(rc)
with (out/'refill_check.log').open('w') as log:check=subprocess.run([sys.executable,str(D/'check_refill_report.py'),str(out/'refill.tsv')],stdout=log,stderr=subprocess.STDOUT)
meta['refill_check_exit_status']=check.returncode;meta['status']='EXIT0_REFILL_PASS_PENDING_SCREENSHOT_REVIEW' if check.returncode==0 else 'REFILL_CHECK_FAILED';save();raise SystemExit(check.returncode)
