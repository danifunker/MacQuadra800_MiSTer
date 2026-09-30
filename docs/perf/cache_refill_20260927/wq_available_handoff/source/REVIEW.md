# Queue availability handoff review — 2026-09-28

Purpose: remove the four-bit queue comparison from the failing RAM half-cycle
request-capture path in 6c seed31. This is a timing experiment, not a claimed
throughput improvement. Production RTL remains unchanged.

Baseline bridge SHA256: 6b49355a45b6e3d81d603d0542139a45854223c71c295ac8515c26cf5f9937ba
Candidate SHA256: 5f24b115c01105d376a763c5eee84a45728587eab9a146072b97fc4d364f2ddf

## Equivalence argument

Previously the falling RAM edge sampled wp; the following rising RAM edge
compared that sample to rp. Now the falling edge samples wp != rp. The only
assignment to rp after declaration is an increment at a rising RAM edge after
the second write half completes. There is no rp assignment between the falling
edge and the following rising-edge decision. Nonblocking updates at that
rising edge do not affect the decision. Thus both decisions use the same wp
and rp values. Initial wp/rp are zero and the candidate availability bit is
initialized zero, matching the old empty decision before the first handoff.
The data memory, pointer increments, ordering priorities, and init behavior are
unchanged. Four-bit comparison retains the wrap bit; it is not a low-index
empty check. Queue data is still consumed at exactly the same capture edge.

The PLL clocks are related. This is not a design for arbitrary asynchronous
clocks; moving comparison logic creates a new system-to-RAM-falling-edge
path that must meet timing. Both input paths to the availability register and
its outgoing half-cycle capture path require STA. Existing MLAB publication
and read-address settling requirements remain. The other seed31 failing path,
a_ram[13] to SDRAM command[0] (-0.040 ns), is not directly addressed.

## Required evidence

Paired physical SDRAM protocol, production memory-path and DMA tests; queue
ordering, wrap/full, init and read-after-write cases; actual altdpram primitive
coverage, with limitations stated; edge-level decision comparison. If these
pass, root reviews evidence before approving a new isolated FPGA fit containing
the qualified 6c FPU plus this bridge. Existing full-guest runs use a simplified
RAM model and do not test this bridge. No timing or hardware claim yet.
