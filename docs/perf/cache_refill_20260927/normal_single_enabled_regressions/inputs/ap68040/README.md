# AP68040

A from-scratch MC68040-compatible CPU core in Verilog, with MMU, FPU and
split instruction/data caches. Developed inside the
[Minimig-AGA_MiSTer](https://github.com/apolkosnik/Minimig-AGA_MiSTer) fork,
extracted here so it can be pulled into other projects as a submodule.

It boots NetBSD/amiga and AmigaOS 3.x on real hardware (DE10-Nano), runs the
Amiga demo and application software that exercises the 040's cache, MMU and
FPSP paths, and passes 3,776 of the 3,801 slices of the WinUAE `cputest`
68040 corpus. The remaining 25 are documented generator defects, not core
failures — the corpus records expectations no real MC68040 can satisfy; see
`doc/CPUTEST_UPSTREAM_REPORT.md`.

## What is here

```
rtl/                    the core, and nothing else
  ap040.qip             Quartus file list, in dependency order
  ap040_defs.svh        shared defines (every .v includes this)
  ap040_tg68k_compat.v  top level: TG68K-shaped port set
  ap040_core.v          sequencer, decode, EA engine, exception logic
  ap040_alu.v           ALU and shifter
  ap040_muldiv.v        multiply / divide
  ap040_regfile.v       register file
  ap040_fpu.v           FPU (extended precision, FPSP trap path)
  ap040_mmu.v           MMU: ATCs, TTRs, hardware table walker
  ap040_cache.v         4-way split I/D cache
  ap040_bus16_adapter.v 32-bit core to 16-bit host bus
  ap040_bus_timeout.v   bus watchdog
  ap040_walker_cdc.v    table-walk port clock crossing
  primitives/dpram.v    inferred true-dual-port RAM -- substitutable
tb/                     self-contained test suite (see Testing)
doc/
```

## Integrating it

Add `rtl/ap040.qip` to a Quartus project, or hand the eleven `rtl/*.v` files
plus `rtl/primitives/dpram.v` to any other flow — `ap040_defs.svh` must be on
the include path (`-I rtl` for iverilog).

The top level is `ap040_tg68k_compat`, which presents a TG68K-shaped port set
so it can drop into a host that already speaks that interface:

```verilog
ap040_tg68k_compat #(
    .AP040_HAS_MMU     (1),
    .AP040_HAS_FPU     (1),
    .AP040_ENABLE_CACHE(1)
) cpu (
    .clk        (clk),
    .nreset     (nreset),
    .clkena_in  (cpu_enable),      // stall the core by holding this low

    .data_in    (cpu_din),         // 16-bit host bus
    .data_write (cpu_dout),
    .addr_out   (cpu_addr),        // 32-bit
    .nwr (nwr), .nuds (nuds), .nlds (nlds),
    .busstate   (busstate),        // 0 fetch, 1 idle, 2 read, 3 write
    .longword   (longword),
    .fc         (fc),
    .ipl (ipl), .ipl_autovector (1'b1), .berr (berr),
    .nresetout  (nresetout),       // the RESET instruction
    ...
);
```

Three groups of ports are optional and can be tied off:

- **`walker_*`** — the hardware table walker's own memory port. Give it a
  path to RAM; a walk that never gets `walker_ack` is turned into a bus
  error by the watchdog rather than hanging.
- **`cache_snoop_stb` / `cache_snoop_addr`** — DMA write snoop, already in
  the core's clock domain. Without it the data cache cannot see writes made
  by other bus masters. The `cache_z2_*`/`cache_z3_*` inputs describe which
  physical windows are cacheable at all; `cache_allow_all` bypasses them for
  flat simulation environments.
- **`mmu_*`, `cacr_out`, `vbr_out`, `debug_*`** — observation only.

The data cache is write-through. An aligned cacheable store updates a matching
resident longword only after the external write is acknowledged, preserving
the other ways in that set. Cache-inhibited, misaligned, and line-crossing
stores retain the conservative set-invalidation path. CPU writes deliberately
do not snoop the instruction cache; self-modifying code must execute CINV, as
on the MC68040.

The instruction front end retains one 32-byte sector of completed fetch data.
On a control-flow redirect, four contiguous valid words at the target can seed
the execution prefetch queue without another cache/MMU handshake. This is most
useful for short backwards loops; normal forward filling resumes once the
seeded words drain. The sector is tagged by logical address and supervisor
context and is invalidated by every architectural prefetch flush, including
exceptions, CINV, PFLUSH, MOVEC, and context changes. Ordinary branches preserve
it deliberately.

Several common paths also avoid redundant sequencer states. Simple address-
register effective addresses are selected during decode, memory operands can
retire on their successful acknowledgement when no later architectural work is
required, prefetched DBcc loops skip a separate decrement state, and ordinary
non-crossing memory-to-register MOVE/MOVEA operations retire on the read
acknowledgement. The common `ADD.L Dn,Dn` form selects both register-file ports
in decode and skips its otherwise empty pipeline-setup state. Faults, page
crossings, trace/interrupt boundaries, and the generic pipeline retain their
conservative paths.

### Performance development

Performance changes are accepted one opcode family or transaction class at a
time. The host project runs this standalone suite, its full-machine Verilator
model, the first 100 differential SingleStepTests CPU rows, a timing-clean
Quartus fit, and the complete Speedometer 3.23 PR suite on a DE10-Nano. A
simulation-only cycle win is not sufficient: one broader register-register
retirement experiment passed simulation and timing but froze during Mac OS
startup, so it remains rejected.

The current front end retires a resident queued opcode directly into decode
and, when bus ownership is unambiguous, consumes resident immediate extension
words from decode without an otherwise empty `S_IMMF` cycle. The immediate
step is deliberately limited to `S_DECODE`, refuses an outstanding prefetch or
same-edge memory acknowledgement, and suppresses a new speculative fill while
it pops the queue. On Wombat33 it removes 6.79% from the focused loop and 0.285%
from the first 100 differential rows; the complete standalone suite and
hardware Speedometer run pass.

In the Wombat33 seed-27 fit at commit `2b3634d`, the complete CPU hierarchy
accounts for about 24,783 ALMs; `ap040_core` accounts for about 23,565, of
which about 15,947 are the core's own sequencer/decode logic. The complete
host design is already at 40,755/41,910 ALMs and 4,183/4,191 LABs. Reducing
the core's decode/state muxing is therefore a prerequisite for comfortable
routing and larger pipeline changes, even though an area reduction alone does
not make an instruction execute faster. The host project's
`CPU_PERFORMANCE_TASKS.md` is the authoritative queue and recovery record.

`dpram` is a plain inferred true-dual-port RAM. Replace it with a vendor
macro (altsyncram, XPM) if your flow needs one; the ports are
`clock, address_a, data_a, wren_a, q_a, address_b, data_b, wren_b, q_b` with
`AW`/`DW` parameters.

### One thing to get right

The core is a **restart-model** 68040: on a write fault the handler repairs
the mapping and the faulting instruction re-executes. It deliberately never
advertises a valid WB3 in its access-error frame. A host OS that completes
valid writeback slots itself — NetBSD's `trap.c` does — would otherwise
double-apply the store of an RMW instruction.

## Testing

```
cd tb && ./run_tests.sh          # needs iverilog and vasmm68k_mot (vbcc)
```

Everything under `tb/` runs against the core alone, with no host-project
sources, so a failure is the CPU's rather than an integration artifact. The
suite covers the integer ISA, the exception and trace model, the MMU
(translation, TTRs, page-table walks, access faults, 4K and 8K pages), the
caches, and the FPU.

The Minimig-AGA tree adds further benches that co-simulate the core against a
real Amiga chipset, an SDRAM controller and a DDR3 controller, and drives the
WinUAE corpus and per-instruction differentials against WinUAE's own softfloat
and `cpummu`. Those live there because they need those modules.

## Status and provenance

Developed against three references, in this order of authority: real hardware
first, then WinUAE as the executable oracle, then the Motorola manuals. Where
the manual and WinUAE disagree the reference wins — several documented
"deviations" in this core turned out to be manual misreadings, and the
comments record which oracle settled each one and where.

## License

GPL v2 or later — see [LICENSE](LICENSE). The core was written as part of
Minimig-AGA_MiSTer, which is distributed under the same terms.

Copyright © 2026 Adam Polkosnik
