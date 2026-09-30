# Integrated AP040 cache refill baseline, 2026-09-27

tb_refill_path.sv connects the production ap040_cache.v to a RAM-only
service path mechanically extracted by make_platform.py from
verilator/tb_memory_path.sv. The service path uses the same parameters as
tb_memory_path_registered_first_miss: FAST_BYPASS=1,
DIRECT_FIRST_MISS=1, REGISTERED_FIRST_MISS=1, ADAPTER_LINE_HIT=1,
DIRECT_MEM_ACK=0, REGISTERED_LINE_HIT=1. The actual wombat_bus32,
sdram_beat32, sdram, and SDRAM chip model are included. The cache is
compiled at its production SETW=7 (8 KB per bank) with the release
AP040_EXPERIMENTAL_XSTORE macro. The other QSF AP040 macros apply to the
CPU and do not alter this cache module. Clock periods are 30.3 ns CPU and
10.1 ns SDRAM.

The standalone service-path control test in baseline_run.log passes
64 sequential reads and 2048 mixed accesses, reporting 304 ns per line
averaged over the stream. That figure excludes cache lookup and tag commit.
The integrated trace and exact metrics are in integrated_run.log and
integrated_run.csv. All timings below are CPU clocks from the request set
at a falling clock edge to a rising-edge observation of the event.

For a representative warm-row aligned read at word 0:

| Event | Sideband off | Sideband on |
|---|---:|---:|
| First SDRAM acknowledgement | 7 | 7 |
| Registered first-word bus acknowledgement / fill count 0 | 8 | 8 |
| Retained 16-byte line valid | 9 | 9 |
| Critical-word cache acknowledgement | 9 | 9 |
| Fill count 1 | 10 (bus) | 9 (sideband) |
| Fill count 2 | 12 (bus) | 10 (sideband) |
| Fill count 3 | 14 (bus) | 11 (sideband) |
| Tag commit | 15 | 12 |

The sideband saves three clocks of tail installation but no critical-word
latency in this case. It is available immediately after the first bus
acknowledgement. Thus a one-clock bulk installation of all remaining words
at fill_line_match could plausibly move tag commit from clock 12 to clock
10, while leaving the first-word acknowledgement unchanged. The candidate
measurement below confirms that estimate.

The integrated bench covers four requested start-word rotations for both
data and instruction lines, with the retained-line cache sideband on and off.
It also covers a data longword starting at byte offset 5, which needs two
fill words. For every case, it checks the returned value and then reads all
four line words as hits without a new memory request. All 18 rotation/span cases pass and
the chip model reports zero protocol errors. In the warm-row spanning case,
the cache acknowledgement moves from clock 11 to clock 10 with the sideband.
Cold first-word service varies by SDRAM row state (for example, case 17
took four more clocks in the earlier no-macro run); compare tail timings
relative to bus_ack when assessing the cache optimization.

The release-macro run adds twenty same-set cases: four successive fills
occupy ways 0, 1, 2 and 3, and a fifth replaces way 0. This sequence is
repeated for data and instruction banks, with the sideband off and on.
Before checking each filled instruction line, the bench reads a separately
warmed instruction line at address 0x46A0 to displace the private instruction
line buffer. All 38 integrated cases pass for both the production cache and
the bulk-fill candidate; after each fill, all four line words hit without
a bus request. The candidate's sideband-on tag commit
is two clocks after the first registered bus ack, versus four for baseline;
critical-word timing relative to that ack is unchanged. Sideband-off timing
is unchanged (tag commit at bus ack +7). Both sources also pass the existing
cache snoop bench with AP040_EXPERIMENTAL_XSTORE, including its retained-line
T10 case, T2 swept fill/snoop collisions, and T5/T6 fill errors.
boundary_stim.sv adds the exact conjunction: same-row snoop on the local
sideband edge and the tag edge, error on the bulk eligibility edge, delayed
sideband while a bus beat is outstanding, and a free-running snoop while CE
is frozen. It verifies that changed backing memory is refetched and the
previously valid victim is not revived. Both sources pass; the candidate
logs six actual fill_line_bulk clocks, including the error exclusion check.
The candidate has not been fitted or tested on hardware. The integrated bench leaves the
MMU hint-match flags low, so the mirror-bank one-clock hint path is not
exercised.

Disabling the sideband here gates only m_line_valid at the cache port.
The service path's own retained-line hit remains enabled, so its later
bus acknowledgements are registered retained-line hits, as in production.
The extracted service path covers RAM reads and writes, but omits the full
quadra800 arbitration, MMU, store buffer, CPU instruction sequencing,
DMA, ROM and I/O. No full-machine timing or FPU score is inferred from
these measurements.

run_integrated.sh [cache_source] [tag] rebuilds the integrated bench with
the given cache source and writes separate build/run/CSV/hash artifacts for
that tag. Defaults are the production cache and integrated. The script
does not edit tracked RTL. release_xstore_manifest.sha256 freezes both cache
sources, the bench inputs, binaries, logs and CSVs. The earlier no-macro
integrated evidence is saved as nomacro_baseline_run.* and
nomacro_candidate_run.*; its original hash manifests were copied alongside
those files. baseline_build.log and baseline_run.log freeze the service-path
control run.

From the repository root, rebuild the candidate and run the archived benches:

```bash
mkdir -p scratch/fpu_bulk_line_candidate_20260927
patch -o scratch/fpu_bulk_line_candidate_20260927/ap040_cache.v \
  rtl/ap68040/rtl/ap040_cache.v \
  < docs/perf/cache_refill_20260927/bulk_candidate.diff
bash docs/perf/cache_refill_20260927/run_integrated.sh \
  rtl/ap68040/rtl/ap040_cache.v integrated
bash docs/perf/cache_refill_20260927/run_integrated.sh \
  scratch/fpu_bulk_line_candidate_20260927/ap040_cache.v candidate
bash docs/perf/cache_refill_20260927/run_boundary.sh \
  rtl/ap68040/rtl/ap040_cache.v boundary_baseline
bash docs/perf/cache_refill_20260927/run_boundary.sh \
  scratch/fpu_bulk_line_candidate_20260927/ap040_cache.v boundary_candidate candidate
```

All generated build files and new logs go under scratch/fpu_refill_path_20260927.
The archived release_xstore_manifest.sha256 records source and result hashes.
