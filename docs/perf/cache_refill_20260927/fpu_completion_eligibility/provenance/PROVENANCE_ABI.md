# Native Speedometer FPU resource: static provenance and ABI

This is static evidence, not an execution or numerical qualification.
`provenance.json` pins the raw resource fork, its byte-exact payload in the
82-byte external envelope, CODE3, and tEsT12000. Resource tEsT12000 is 3,784
bytes, SHA25634ee511807b66d2360c505b352d0946c01730d764843ed815cfd49bab2fa8aa0.
Its resource metadata name is `\0FPUTests.rsrc`.

## Callback mapping

`CODE3_resource_setup.dis` shows GetResource(`tEsT`,12000), HLock(A2), and
A4=*(handle A2). Thus each JSR(A4) enters the same resource, not CODE3 WStone.

| Observer site | CODE3 call / preceding push | Main selector target | Embedded Pascal name |
| --- | --- | --- | --- |
|0|4f80 / WORD1 at4f7c|29a|FPUWStone (name6a2)|
|1|510a / WORD3 at5106|17a|FPMm (name292)|
|2|52c8 / WORD2 at52c4|c84|FPUFFT (namee12)|

`CODE3_site*.dis`, `main.dis`, and the respective kernel disassemblies provide
both sides of this mapping. Names are resource bytes, not inferred UI order.

## Entry and return ABI

Resource0 BRA→c JMP→main e5e. Caller pushes one WORD selector, then JSR;
main LINK A6,#0 reads selector at8(A6). Main does not pop the argument; each
CODE3 caller ADDQ.W#2,A7 after return. No other explicit kernel parameter is
read by main. Selector1/2/3 dispatch as above; others return without a kernel.

Main saves D3 and A4 (old A4 kept in saved D3), calls helper10 to install local
A4, and restores both at exit. Helper computes resource_base+c+8e94 =
resource_base+8ea0 in D0, executes original A055, then EXG D0,A4. The resource
must execute that trap through the existing ROM; this audit does not replace
or assume its implementation. Main's final EXG restores caller A4 and leaves
D0 containing the post-A055 resource-local A4. D0 is not a benchmark score.
All paths return with RTS, preserving caller stack except its still-pushed
selector. A6 is restored by UNLK. Kernel/helper prologues preserve used
D3-D7/A2-A3 and FP4-FP7; scratch D0-D2/A0-A1/FP0-FP3 and CCR/FPSR are not
preserved. There is no explicit FPCR save, initialization or restore. No
A5 access occurs in the decoded native function bodies; A5-dependent timer,
UI/result and HLock wrappers are in CODE3, outside the native callback.
ROM traps/FPSP remain external dependencies and must preserve their own ABI.

All direct native A4 displacements decode to resource offsets ea0 (Pascal
memory-error text), eae..ec5 (two extended constants), ec6..ec7 (RNG seed).
All fit inside the3,784-byte resource endingec8. A4 itself is base+8ea0;
the reused private arena/page map must also make that pointer representable.
Decoded branches/JSRs and entry addressing are PC-relative; no XREF/absolute
external call patching was found in these bodies. Copy the complete resource,
including its mutable tail, rather than only kernel code.

## Per-kernel dependencies and outputs

* Selector1 FPUWStone: LINK#-44; D3-D7 and FP4-FP7 saved. Internal helpers
  sp3(6ae) and spa(700); initializes both A4 extended constants; loop scale
  D4=10 is internal. No allocation or A-line trap in this body. Native
  FCOS/FSIN/FATAN/FLOGN/FETOX at4e2/4e6/51e/67e/686 require the 68040 software
  operation route; these are excluded by rtl/ap68040/rtl/ap040_fpu.v:372
  op_in_hw and captured at951. Local stack and constants are modified; no
  numerical result is exported through a documented caller pointer.
* Selector3 FPMm: LINK#-1ec,123 A31E allocations of a4bytes, three41-row
  pointer matrices; four passes of40x40 native single-precision products,
  local RNG initialized to2403 each pass;123 A01F disposals. Local helpers
  LocalInitrand22, LocalRand40, rInitmatrix6e, rInnerproducte8. Result matrices
  are computed in allocated blocks and then disposed; no scalar score return.
  A31E/A01F require the existing Memory Manager. Allocation failure is not
  checked in this body, so a future fixture must observe allocations/errors.
* Selector2 FPUFFT: LINK#-1e; three A11E allocations808/808/410bytes;256-point
  arrays,20 FFft passes, local FExptab824, FUniform117de and FFft9de. FExptab
  uses FCOS requiring software-operation service. Success disposes all three
  pointers viaA01F; allocation failure invokes A98B/A985/A9F4 and cleanup.
  Outputs are internal arrays subsequently disposed; no scalar score return.

Neither an RTS nor byte-exact baseline memory proves numerical correctness.
Initial baseline scope can establish return, ABI, native-PC/FPSP coverage and
absence of bus/protocol errors; future optimization needs baseline comparison
plus independent ISA/arithmetic regressions.

## Existing fixture runtime and proposed narrow experiment

scripts/cpu/build_whetstone_image.py retains the original32MB snapshot except
private600000..63ffff and reset vectors. The current image's low-memory vector11
is4088d9fe; vectors48/51/52/53/54/55 are4088d252/4088d856/4088d28c/4088d544/
4088d68e/4088dab0. The shipped ROM is the platform runner's existing input.
docs/quadra800-rom-disassembly.asm:121639 shows vector11's ROM entry performing
LINK/FSAVE/frame handling. Existing runtime availability is concrete; its
correct execution with this native callback has not yet been tested.

A separate image can reuse that frozen snapshot/ROM, place complete tEsT at
600000, enter with A4=600000, push selector1, JSR(A4), clean2bytes, and assert
stack/A4/callee-save sentinels on return. Native globals occupy600ea0..600ec7
and local A4 is608ea0, inside the already identity-mapped private arena.
Retain original MMU/ROM/runtime settings and all release macros; bound the
run and count native-body and ROM vector11 PCs plus FPU states/opcodes. Do
not reuse the old code/globals/stack numerical oracle as a native oracle.
Selector1 is the first experiment; Matrix/FFT allocation paths need separate
qualification. No native fixture was implemented or run for this report.

## Disassembly method

Files here are generated by disassemble.cpp linked to the existing Musashi
m68kdasm.o/m68k_dasm_stubs.o in frozen attempt2. Formatter names can truncate
an FP immediate; the driver corrects f23c class2 operand length using the
encoded source format and emits the complete raw bytes. Native code ranges
exclude embedded Pascal names; this avoids linear decoding through metadata.
Binary inputs/executable stay in scratch; the archive contains text only.
