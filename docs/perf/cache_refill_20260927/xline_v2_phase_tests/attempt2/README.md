Fresh attempt2 phase gate. Attempt1 is preserved in ../phase: baseline passed scenarios 0..4, then failed a bench assertion that checked err_hold on the same negedge as request withdrawal, before an enabled posedge could clear it. Candidate was never built/run. This attempt adds exactly one negedge wait (one intervening enabled posedge) before that assertion. No attempt2 HDL build or run has occurred at source freeze. Parent review and run authorization are required. The earlier rejected fb7 candidate is not consumed here.

`run.py` uses the frozen paired RTL in `../inputs/{baseline,candidate}/rtl`: baseline cache 7cba7f73 and sideband-only candidate 9e8c0582. The bench bytes are identical across variants. `TEST_XFIRST` only enables hierarchical candidate phase observation; it changes no cache feature. Both use the release cache-relevant `AP040_EXPERIMENTAL_XSTORE` and the actual SETW=7 / 8+8 KB geometry. The other nine CPU release macros have no consumer in this cache-only bench. All 113 RTL files per variant remain available in the input lineage; only cache/defs/behavioral dpram are compiled.

The 73 scenarios are recorded individually in `PHASE_CASE`, with phase-entry/local-word/publication/fallback/poison/error deltas. Sixteen `PHASE_COVERAGE` rows reconcile those records to terminal counters:

| ID | Cases | Scenario |
|---|---:|---|
| 0 | 32 | Four first/second residency combinations, LONG offsets D/E/F and WORD F including set/tag wrap, two hint modes |
| 1 | 4 | All replacement ways with live old tags and later byte checks |
| 2 | 4 | No sideband, or loss at each local tail slot; partial victim cleanup and fallback |
| 3 | 15 | First/next/unrelated-row snoop at FILL slots 0..3 and TAGW; CE stopped for slot 1 |
| 4 | 1 | Retained line arrives after physical critical beat issuance; issued beat must complete |
| 5 | 1 | Critical error, held request, no reissue, withdrawal/retry, old victim byte checks |
| 6 | 1 | Existing second-line critical error and held-request behavior |
| 7 | 7 | CI, disabled D-cache, instruction fill, byte, noncrossing word/long, in-line span exclusions |
| 8 | 1 | Prevalid matching sideband; no first critical request |
| 9 | 1 | Critical error with matching sideband arriving while issued |
| 10 | 1 | Existing second-line nonoperand tail error after operand ACK |
| 11 | 1 | Posted store before cross-line read and store after completion |
| 12 | 1 | CINV completion while crossing operand pending; bytes checked without assuming original publication survives |
| 13 | 1 | Reset during local fill, sweep, retry; baseline reset/read comparison |
| 14 | 1 | Wrong physical retained tag with poisoned data; fallback, no poison installation |
| 15 | 1 | Coincident m_err+m_ack with retained-line arrival; error priority and held-request retry |

The backing-memory byte oracle is independent of installed cache data. Every read is compared at its ACK; all installed words are read later, and selected installed-line checks require zero physical traffic. The provider latches one physical request and asserts stable request/address/size/write/data/FC until completion, including CE stalls. During actual candidate first phase, it asserts no operand ACK, unchanged original address/size, no owed CI/store invalidation, matching tag-mirror write controls, and no tag-port same-row collision. Every local-tail slot must have neither m_req nor r_issued. Physical first-phase requests must be the original requested aligned longword; other first-line words can only be local sideband. Lost sideband must use actual C_FERR victim-row invalidate before direct fallback.

Fault comparisons distinguish raw c_ack from qualified completion: baseline C_PASS directly forwards m_ack even on an m_err edge, so the oracle/counts qualify completion with !m_err as the CPU wrapper does. Four faulting operands hold c_req for eight further clocks with err_hold, no reissue or qualified ACK, then withdraw and retry. The coincident ACK/error test deliberately exercises both signals; the provider normally emits only one. One existing second-line trailing-beat error is checked after completion; this is not an assertion that artificial nonoperand faults should become new CPU exceptions.

Stimulus at candidate-specific phases necessarily occurs at different baseline times (baseline C_PASS), and second-line fault setup warms the baseline first line. This is byte/result and protocol qualification, not an assertion of identical memory traces or cycle counts. The model serves full byte-addressed operands; it does not instantiate the CPU, MMU, production bus adapter, store buffer, SDRAM bridge, Cyclone RAM primitive, or actual fault frame. It cannot qualify physical tag dual-port behavior; reachable no-collision assertions address the source invariant. The separately delegated full-CPU/MMU screens cover architectural integration; these phase scenarios do not replace them. No native timing, FPGA fit or hardware claim follows from this gate.

After approval, run `python3 scratch/cache_xline_sideband_validation_20260928/phase_attempt2/run.py` from the repository. It verifies every manifest row before/after, refuses existing outputs, compiles/runs variants serially with 90-second limits, saves exact commands/PIDs/exits and raw logs, checks all coverage, and stops on any failure without retry. `python3 phase_attempt2/check_results.py phase_attempt2/outputs` checks saved logs. Manifest paths are relative to `scratch/cache_xline_sideband_validation_20260928`, not the phase folder.
