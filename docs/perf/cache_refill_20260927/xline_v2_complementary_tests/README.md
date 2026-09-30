# Complementary cache test results for the v2 first-line-fill candidate

This archive contains two direct cache-unit regression pairs run against the
baseline and v2 candidate cache. Candidate cache SHA-256 is
`9e8c0582db1b0bb88428e56fec63e99029b61faffac62c6f3dda9326b5191481`; baseline
cache SHA-256 is
`7cba7f73f6f7f16fa7a45d439af6a786bd55c3ef2a3f8c876b400e10d4fb7747`. This is
the v2 source, not the earlier rejected `fb7e4e...` draft. Paired source
identity states that 113 RTL files were compared, only `ap68040/rtl/ap040_cache.v`
differs, FPU files match at 6c, and effective `SETW=7`. Only the cache is
compiled into these unit benches; this is not a CPU macro regression, full
system run, performance measurement, synthesis result, or hardware result.

The XSTORE pair ran 100 complementary posted/unposted cross-line store cases
per variant, covering residency, lanes, set wrap, CE pauses, snoops, and partial
write error handling. Both logs report `XSTORE PASS cases=100` and
`ALL TESTS PASSED`. Baseline output and its parent-run metadata are retained
under `xstore/`; the candidate’s isolated run metadata/logs are alongside them.

The corrected posted-read contract pair ran 216 cases per variant. Both runs
report `POSTED_MATRIX PASS cases=216 pending=816 prepared=816
early_disjoint_acks=30` and terminate normally. The TB captures an independent byte-oracle value at each
read acknowledgement and allows an early read acknowledgement only when its
word range is disjoint from the pending store. It retains final RAM, guard-byte,
and repeat-read checks. These are direct-port behavioral cache tests using the
testbench dual-port RAM model.

The initial v2 posted-matrix attempt is preserved separately in
`posted_failed_attempt/`. This is the pin-adapted v2 attempt: its stronger
original blanket rule (“no following read may acknowledge while the posted
store is pending”) fails on a legitimate disjoint read. The baseline run exited
1 at that assertion, before a candidate posted run; it is not counted as a
candidate regression. The corrected ACK-edge oracle and word-overlap rule are
the separately reviewed 216-case pair in `posted_corrected/`. An earlier,
separate `fb7e4e...` package failed its baseline warm-read case because hint
pins were floating; that is not this v2 result or failure and is not included
in this archive.

`provenance/original_input_manifest.sha256` and
`provenance/source_identity.json` are byte copies from the frozen scratch
package; the former records the original broad input snapshot but those full
RTL trees are intentionally not included here. The archive includes the small
cache-source delta, exact unit test sources, original runner scripts, build and
run logs, and original JSON run metadata. `COPY_MAP.tsv` maps copied evidence
to its scratch origin. No `.vvp`, full cache RTL file, generated code, or
compiler cache is included.

Verify this archive and its recorded outcomes from the repository root:

```sh
python3 docs/perf/cache_refill_20260927/xline_v2_complementary_tests/check_archive.py \
  docs/perf/cache_refill_20260927/xline_v2_complementary_tests
```

The checker validates every archived file against `SHA256SUMS`, verifies the
copy map and original corrected-test manifest, and applies the pass/fail gates
above. It does not re-run simulations or prove equivalence outside these
benches.
