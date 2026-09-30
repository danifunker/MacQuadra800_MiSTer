from pathlib import Path
import re
r=Path(__file__).parent/'baseline_sim/verilator'
for stem,expected_clocks,expected_d0 in [('fixture',79,1),('fixture_earlybranch',79,2)]:
 log=(r/(stem+'_observer.log')).read_text()
 tsv=(r/(stem+'_timed.tsv')).read_text()
 run=(r/(stem+'_run.log')).read_text()
 assert f'FIXTURE_CHECK PASS selector0=0004 selector1=0042 magic=600d0042 D0={expected_d0:08x} SP=00200000' in run
 assert 'FPU_SUMMARY starts=1 stops=1 callbacks=1 returns=1 aborts=0 unmatched=0' in log
 assert f'TOTAL\t1\ttimer\tcomplete\t{expected_clocks}\t' in tsv
 assert 'TOTAL\t1\tcallback\tcomplete\t39\t' in tsv
 assert 'SPAN\t1\ttimer\tstarts=1\tcomplete=1\taborted=0\topen=0' in tsv
 if stem=='fixture_earlybranch':
  assert 'IR_MISMATCH cycle=471 pc=40805106 ir=6032 fetched=3f3c state=3 before_state=190 pipe_admit=0' in log
  assert 'LIVE cycle=479 kind=FPU_TimerStart' in log
  assert 'primary_mismatch_skipped=1' in log
 print(f'PASS {stem}: independently checked guest signature/registers, one timer79/callback39, no aborted/unmatched span')
log=(r/'smoke_observer.log').read_text()
row=[x for x in log.splitlines() if x.startswith('ADAPTER')][-1]
for key in ['instruction_acks','fetched_bytes','known_dispatches','secondary_skipped']:
 assert int(re.search(fr'\b{key}=(\d+)',row).group(1))>0
print('PASS normal-ROM boot: nonzero fetched instructions, known dispatches and secondary admission coverage')
