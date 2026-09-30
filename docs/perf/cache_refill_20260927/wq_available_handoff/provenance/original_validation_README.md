# Queue availability handoff — paired digital qualification

All requested directed tests passed for baseline `6b49355a45b6e3d81d603d0542139a45854223c71c295ac8515c26cf5f9937ba` and candidate `5f24b115c01105d376a763c5eee84a45728587eab9a146072b97fc4d364f2ddf`. Shared bench/controller/adapter sources are identical across variants and match the production files copied at preparation. Only the bridge source differs. Production RTL and existing guest inputs were untouched.

| Test, each variant | Result |
|---|---|
| Production `tb_sdram` | 174 checks; zero failures and zero chip protocol errors |
| Production registered-first-miss `tb_memory_path` | 64 sequential reads plus 2,048 mixed posted-write/read operations; zero failures/protocol errors |
| Production `tb_line_dma`, default 4,000 rounds | 20,512 reads, 5,381 stores, 15,374 line acknowledgements, 11,423 DMA beats, 9,408 direct pushes, 1,434 spanning stores; zero errors |
| Passive decision/ownership supplement | 22,320 rising-edge comparisons; 373 pushes/consumes/pops; 46 slot wraps; occupancy reached 8; 150 sampled full cycles; zero mismatch/overwrite/payload errors |
| Actual Intel `altdpram` simulation model | Edge capture and 256 writes / 32 wraps passed; planted wrong-address mutation failed at first write, exit 1 |

Production timing metrics match exactly across variants: bridge cold/page/retained reads 6/4/1 system clocks, posted write acceptance 1 clock, 64-read/write streams 5,847/4,757 ns, integrated 64 reads 4,878 ns, and 4,096 DMA-bench back-to-back stores 9,712 clocks. These are unchanged digital timing measurements, not a speedup claim.

The supplementary bench preserves the current production stimulus, adds a passive shadow of the old falling-edge write-pointer capture, and checks at every rising RAM edge that `rp` has not changed since the falling edge and `(shadow_wp != rp)` equals the captured comparison. It separately checks the actual baseline handoff pointer or actual candidate availability bit. It counts 2,707 nonempty decisions and 373 queue consume starts. The reused historical ownership monitor checks exact 61-bit accepted payloads, slot reuse only after pop, and age before consumption; observed age was 10,102–515,102 ps, including its 2 ps observation delay. This is exercised equivalence, not a formal proof over all possible inputs.

Startup `init` was high for 11 monitored RAM rising edges with the queue empty; both SDRAM ranks completed mode initialization. Dynamic reinitialization during a queued write/read or a partially completed transaction was **not** exercised. The RTL change leaves init handling unchanged; the existing queue pointers are declaration-initialized and are not reset by init. No new abort/flush guarantee is claimed.

Verilator integration uses the bridge's synchronous-write/asynchronous-read behavioral queue branch. The standalone primitive tests use the actual Quartus Lite Intel `altera_mf.v` model and matching 61-bit × 8 Cyclone V MLAB parameters. They validate primitive write-edge/address/data retention and asynchronous reads, including a deliberately failing address mutation. They do not join the actual primitive to the full bridge/controller. No Quartus tool was launched for this evidence. Simulation cannot establish physical setup/hold margins, MLAB collision timing, clock uncertainty, or FPGA operation; both new comparison inputs and outgoing half-cycle path still require STA. Clocks tested are the production-related 1:3 clocks, not arbitrary asynchronous clocks.

`check_results.py` verifies saved exits, source hashes, exact counters, matched timing lines, no chip-error messages, and the expected negative result. Run it from any working directory:

```
python3 scratch/wq_available_validation_20260928/check_results.py
```

`run_production.py` and `run_supplement.py` record full argv/cwd/PID/start metadata, build/run logs and exits per target. They use Verilator 5.050, sequential builds with two workers, and a task-local writable CCACHE. The production memory-path parameters are exactly FAST_BYPASS=1, DIRECT_FIRST_MISS=1, REGISTERED_FIRST_MISS=1, ADAPTER_LINE_HIT=1, DIRECT_MEM_ACK=0, REGISTERED_LINE_HIT=1. These programs guard fresh output directories; reproduction requires a new isolated package/output tree, not overwriting this evidence.

Two failed preparation attempts are preserved under `baseline/invalid_tool_version_attempt` and `baseline/invalid_ccache_attempt`: the default Verilator 4.204 rejected `--binary`, then Verilator 5.050 compilation could not write the default CCACHE outside the permitted filesystem. Neither executed a simulator. Explicit tool selection and task-local CCACHE resolved those infrastructure failures; all subsequent builds and positive simulations completed once successfully.

`input_manifest.sha256` pins the paired bridge and original shared inputs; `supplement/inputs.sha256` additionally pins the supplemental/primitive benches and external Intel simulation model. `source_manifest.sha256` pins final scripts, sources and report; `evidence_manifest.sha256` pins the small text evidence, including failure logs. Generated models, binaries and cache remain scratch-only. No deployment or hardware qualification follows from these tests.
