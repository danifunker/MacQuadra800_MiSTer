from pathlib import Path
import subprocess,json,hashlib,os,datetime,signal
S=Path(__file__).resolve().parent;D=S.parent/'fpu_normal_single_allprecision_fullmachine_20260928';O=S/'smoke';sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
b=json.loads((S/'completed_build_identity.json').read_text());binary=D/'verilator/obj_dir/Vemu';assert sha(binary)==b['binary_sha256'];assert {p.name for p in O.iterdir()}=={'control.txt'}
cmd=[str(binary),'--headless','--no-cpu-trace','+rom='+str(D/'verilator/quadra800-fastboot.rom.hex'),'+ram=0','--control','control.txt','--cpu-profile','refill.tsv','--max-cycles','200000','+ram_line_model','+ram_first_latency=4','+ram_line_publish_delay=2']
m={'scope':'new generated model short disk-free smoke, not benchmark or guest guard coverage','supervisor_pid':os.getpid(),'argv':cmd,'binary_sha256':sha(binary),'started_utc':datetime.datetime.now(datetime.timezone.utc).isoformat()}
with (O/'run.log').open('w') as log:
 c=subprocess.Popen(cmd,cwd=O,stdout=log,stderr=subprocess.STDOUT,start_new_session=True);m['child_pid']=c.pid;m['running_exe_sha256']=sha(Path('/proc')/str(c.pid)/'exe');(O/'meta.json').write_text(json.dumps(m,indent=2)+'\n');print('SMOKE_CHILD',c.pid,flush=True)
 try:rc=c.wait(timeout=120)
 except subprocess.TimeoutExpired:os.killpg(c.pid,signal.SIGKILL);c.wait();raise
m['exit_status']=rc;m['finished_utc']=datetime.datetime.now(datetime.timezone.utc).isoformat();m['child_terminal']=c.poll() is not None;assert rc==0
checks=[['python3',str(D/'verilator/tests/check_refill_report.py'),str(O/'refill.tsv')],['python3',str(S/'check_guard_report.py'),str(O/'refill.tsv'),'--allow-empty']]
for i,cmdcheck in enumerate(checks):
 with (O/('check'+str(i)+'.log')).open('w') as log:q=subprocess.run(cmdcheck,stdout=log,stderr=subprocess.STDOUT,timeout=30)
 m['check'+str(i)]=q.returncode;assert q.returncode==0
for row in (D/'source_manifest.sha256').read_text().splitlines():
 h,n=row.split('  ',1);assert sha(Path(n))==h,n
m['source_manifest_postrun']='PASS';m['status']='PASS';(O/'meta.json').write_text(json.dumps(m,indent=2)+'\n');print('PASS disk-free smoke')
