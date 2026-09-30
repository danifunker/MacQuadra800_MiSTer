# Speedometer FPU subtests: cycle breakdown of the timed windows (2026-09-28)

This is a full-machine Verilator measurement of the **committed production RTL**,
commit `0b2d265` (branch `add-ethernet`). It is not the 6c FPU candidate or the
cache-v2 candidate. It measures each of the three Speedometer 4.02 FPU subtests
**only over the interval the benchmark itself times**. Earlier profiles used a
fixed 1.3 G-clock window after launch, which included setup and idle time
(`docs/FPU_PROFILE_20260927.md`). This is simulator evidence, not a hardware
measurement.

## Result validity

- The run exited 0. The final screen (`screenshot_f7382.png`) shows "The tests
  are done!" with one iteration of each test: **Whetstone 3849.262 KWhetstones/s
  (0.739), Matrix Mult 0.991 s (0.713), Fast Fourier 0.447 s (0.642), average
  0.698**. These are the established production baseline values: the 6c
  candidate scored 0.729. No timing is negative or near zero.
- The screenshot SHA256 (`c66734da…`) and the whole-bracket CPU-profile TSV
  SHA256 (`15012e02…`) are byte-identical to the archived baseline
  (`docs/perf/cache_refill_20260927/timed_profile_attempt2/`). The dispatch
  count (194,699,885) is identical too. The monitor is purely passive, so this
  run is cycle-identical to the earlier 0.698 baseline runs.
- The benchmark selection dialog (`screenshot_f4277.png`) shows all three FPU
  tests with 1 iteration.

## How the timed window was found and defined

The monitor ends a segment at every primary dispatch of the A-line traps
Microseconds `$A193`, TickCount `$A975`, InsTime `$A058`/`$A458`, PrimeTime
`$A05A` and RmvTime `$A059`, and also every 200,000 clocks. Each segment's
nonzero counters are dumped, so a window between two trap dispatches is
**exact**: the sum of its segments. `markers.txt` lists every
marker-to-marker interval that contains FP work.

**Speedometer times each FPU subtest with a pair of `_Microseconds` calls.**
The timed code runs between a call at one Speedometer site and the next call
at the following site. TickCount and Time Manager calls occur only outside the
timed intervals, except for a few OS calls at interrupt level.

**Window = [dispatch of the opening `_Microseconds` trap, dispatch of the
closing `_Microseconds` trap).** One clock is one `clk_sys` rising edge, and
`sim.v` ties the CPU CE high. The guest's VIA timer ticks every 42 clocks
(`iosb.sv` `E_HALF=21`), so 1 guest second is 783,360 × 42 = 32,901,120
clocks. The windows reproduce the displayed results exactly. This confirms
that they are the benchmark's own timed intervals:

| subtest | Microseconds call sites (PC) | timed runs | clocks per run | seconds (clocks / 32.90112 M) | displayed |
|---|---|---|---|---|---|
| Whetstone | `$007597F6` → `$0075981E` | 1 | 8,547,416 | 0.25979 | 3849.262 KWh/s = 1000 KWh / 0.25979 s |
| Matrix Multiply | `$00759980` → `$007599A8` | 3 (Speedometer repeats it) | 33,306,554 / 32,234,385 / 32,236,225 | 1.0123 / 0.9797 / 0.9798 | 0.991 s = mean |
| Fast Fourier | `$00759B3E` → `$00759B66` | 5 | 14,717,344 / 14,727,638 / 14,706,276 / 14,728,013 / 14,722,528 | 0.4473 / 0.4476 / 0.4470 / 0.4476 / 0.4475 | 0.447 s = mean |

The Matrix and FFT tables below aggregate all of their timed repetitions:
97,779,703 and 73,606,640 clocks respectively. The per-run numbers are in
`runs.json`.

The first Matrix run is 1.07 M clocks slower than runs 2 and 3. It has
60,495 D-cache fills against about 32,500, and 15,041 I-cache fills against
about 380. That is a cold-cache effect, and the displayed average includes
it.

## Summary table (all three windows)

Percentages are of each window's clocks. The rows are overlapping views and
do not add up to 100%. The exclusive partition by CPU core state is given for
each subtest further down.

| clocks | Whetstone | Matrix Multiply (3 runs) | Fast Fourier (5 runs) |
|---|---:|---:|---:|
| Window clocks | 8,547,416 (100%) | 97,779,703 (100%) | 73,606,640 (100%) |
| FPU FSM not idle (`fst != F_IDLE`) | 1,266,996 (14.8%) | 23,020,908 (23.5%) | 18,821,425 (25.6%) |
| &nbsp;&nbsp;FPU busy while the CPU is released (`fpu_bg`) | 566,544 (6.6%) | 6,690,504 (6.8%) | 5,402,095 (7.3%) |
| &nbsp;&nbsp;FPU busy while the CPU is held (foreground) | 700,452 (8.2%) | 16,330,404 (16.7%) | 13,419,330 (18.2%) |
| `S_FPU_DEC` total | 877,585 (10.3%) | 12,142,616 (12.4%) | 9,292,177 (12.6%) |
| &nbsp;&nbsp;`S_FPU_DEC` waiting because `fpu_bg` is set (previous FP op not retired) | 487,215 (5.7%) | 5,921,816 (6.1%) | 4,164,397 (5.7%) |
| `S_FPU_GO` (issue, wait for accept or done) | 1,077,759 (12.6%) | 24,157,428 (24.7%) | 19,910,515 (27.0%) |
| FP operand read (`S_FPU_RD`/`RD2` + `S_MRD` returning to them) | 796,261 (9.3%) | 8,872,283 (9.1%) | 5,494,705 (7.5%) |
| FP EA/immediate states (`S_FPU_AN`/`EA`/`DREG`/`IMM`) | 175,119 (2.0%) | 3,916,800 (4.0%) | 3,826,815 (5.2%) |
| FP store (`S_FPU_WR` + `S_MWR` returning to it) | 311,223 (3.6%) | 3,974,005 (4.1%) | 2,590,044 (3.5%) |
| FP instruction clocks (`S_FPU_DEC` entry to the next dispatch) | 4,571,816 (53.5%) | 64,710,069 (66.2%) | 52,563,292 (71.4%) |
| vector 11 handlers, entry to RTE (FPSP emulation) | 4,999,384 (58.5%) | 0 | 132,227 (0.2%) |
| interrupts (vectors 25 and 26), entry to RTE | 224,301 (2.6%) | 2,806,883 (2.9%) | 2,023,562 (2.7%) |
| D-cache `C_FILL` (`r_bank=0`) | 3,480 (0.04%) | 1,256,728 (1.3%) | 144,036 (0.2%) |
| I-cache `C_FILL` (`r_bank=1`) | 6,673 (0.08%) | 161,555 (0.2%) | 31,889 (0.04%) |
| CPU in `S_MRD` while the cache is in `C_FILL` | 5,079 (0.06%) | 1,047,999 (1.1%) | 126,243 (0.2%) |
| store buffer non-empty | 1,518,462 (17.8%) | 8,683,478 (8.9%) | 7,895,976 (10.7%) |
| store-buffer push blocked (`buffer_req && !push && !accept_ack`) | 0 | 0 | 0 |
| PC in ROM (`$4xxxxxxx`) | 4,987,016 (58.3%) | 3,402,643 (3.5%) | 1,686,875 (2.3%) |

| counts | Whetstone | Matrix (3 runs) | FFT (5 runs) |
|---|---:|---:|---:|
| FP instructions (`S_FPU_DEC` entries) | 390,370 | 6,220,800 | 5,127,780 |
| cpGEN opcode dispatches (cross-check) | 390,370 | 6,220,800 | 5,127,780 |
| FP instructions that found the previous op still running | 230,837 | 3,846,085 | 2,526,277 |
| all opcode dispatches | 1,377,173 | 22,835,687 | 17,794,902 |
| D-cache / I-cache line fills | 351 / 662 | 125,644 / 15,863 | 14,447 / 3,150 |
| FSAVE | 10,120 | 0 | 250 |
| vector 11 (FP unimplemented instruction) | 5,060 | 0 | 125 |
| vector 55 (FP unsupported data type) | 0 | 0 | 0 |
| vector 10 (A-line) | 5 | 802 | 89 |
| vectors 25 / 26 (interrupts) | 228 / 21 | 2,616 / 233 | 1,972 / 175 |
| RTEs / RTEs without a matching frame | 5,309 / 0 | 2,849 / 0 | 2,272 / 0 |

## Whetstone (8,547,416 clocks, 1 run)

FPU FSM occupancy: F_WB 258,832; F_ROUND 258,827; F_BIN 174,259; F_MULT
127,442; F_EXEC 117,425; F_ADDX 82,096; F_SRC 78,186; F_SHR 56,789; F_DIVL
53,040; F_NORM2 23,749; F_SQRTL 21,390; F_NORM 7,983; F_PACKI 3,489;
F_STDONE 3,489. The total is 1,266,996 (14.8%).

Exceptions. Entry is the first exception-processing state. The duration runs
to the RTE that pops the same stack frame, and nested interrupts are included.

| vector / emulated op | count | entry→RTE clocks | % of window | mean clocks |
|---|---:|---:|---:|---:|
| 11 FCOS | 1,920 | 1,927,805 | 22.6% | 1,004 |
| 11 FETOX | 930 | 907,206 | 10.6% | 976 |
| 11 FLOGN | 930 | 971,672 | 11.4% | 1,045 |
| 11 FATAN | 640 | 570,803 | 6.7% | 892 |
| 11 FSIN | 640 | 621,898 | 7.3% | 972 |
| **11 total** | **5,060** | **4,999,384** | **58.5%** | 988 |
| 25 VIA1 interrupt | 228 | 189,338 | 2.2% | 830 |
| 26 VIA2 interrupt | 21 | 34,963 | 0.4% | 1,665 |
| 10 A-line | 5 | (no RTE: the trap dispatcher returns without one) | | |

Top 10 FP instruction forms. These include the FP instructions that FPSP
itself executes: FMOVEM, FMOVE to/from control registers and extended moves.
"Clocks" runs from `S_FPU_DEC` entry to the next dispatch. It includes waiting
for a previous background operation, the EA, the operand read and the issue.
It excludes the opcode/command-word fetch and any background execution after
release.

| # | form | count | clocks | clocks/instr |
|---:|---|---:|---:|---:|
| 1 | `FMOVE FPm,FPn` | 41,798 | 226,038 | 5.4 |
| 2 | `FMUL FPm,FPn` | 39,601 | 242,160 | 6.1 |
| 3 | `FADD FPm,FPn` | 38,599 | 225,581 | 5.8 |
| 4 | `FMOVE.X FPn,-(An)` | 26,970 | 242,742 | 9.0 |
| 5 | `FMUL.X d16(An),FPn` | 25,949 | 408,011 | 15.7 |
| 6 | `FMOVE.X d16(An),FPn` | 23,070 | 325,603 | 14.1 |
| 7 | `FMOVE.X FPn,d16(An)` | 19,518 | 282,879 | 14.5 |
| 8 | `FMOVE(M) #imm,FPcr` | 15,180 | 45,592 | 3.0 |
| 9 | `FADD.D d16(PC),FPn` | 13,897 | 255,084 | 18.4 |
| 10 | `FADD.X d16(An),FPn` | 11,490 | 167,677 | 14.6 |

By opmode: FMOVE 83,613; FMUL 76,189; FADD 75,092; FMOVE out 54,177; FMOVE to
control registers 25,299; FMOVEM out 20,971; FMOVEM in 15,911; FDIV 11,200;
FSUB 10,848; FMOVE from control registers 10,120; FCOS 1,920; FNEG 960;
FSQRT, FETOX and FLOGN 930 each; FATAN and FSIN 640 each. FSQRT runs in
hardware (F_SQRTL).

By source: register 128,838; X 92,297; control/multiple 72,301; X store
50,688; D 25,360; S 11,337; W 4,200; L store 3,489; L 1,860.

Exclusive partition by core state. `S_MRD`/`S_MWR` clocks are charged to the
state that issued them.

| core activity | clocks | % |
|---|---:|---:|
| integer execute (incl. FPSP integer code) | 2,036,990 | 23.8% |
| fetch/decode/extension words | 1,281,424 | 15.0% |
| `S_FPU_GO` | 1,077,759 | 12.6% |
| `S_FPU_DEC` | 877,585 | 10.3% |
| FP operand EA/read, including memory reads | 971,380 | 11.4% |
| integer memory read/write | 782,995 | 9.2% |
| FP control/FMOVEM, including memory | 765,758 | 9.0% |
| FP store, including memory writes | 311,223 | 3.6% |
| FSAVE/FRESTORE/FBcc, including memory | 273,253 | 3.2% |
| exception entry/RTE, including memory | 169,049 | 2.0% |

**Reading:** 58.5% of the timed Whetstone is spent inside the FPSP
unimplemented-instruction handler in ROM. There are 5,060 emulated
transcendentals (FCOS, FSIN, FATAN, FETOX, FLOGN), each costing about 1,000
clocks from exception entry to RTE, including the FSAVE, FMOVEM and control
register traffic. A real MC68040 also traps these instructions to the FPSP,
so this cost is architectural: it can only be reduced by making the handler's
own code run faster (integer, FMOVEM and extended loads and stores). The
remaining ~3.5 M clocks are ordinary arithmetic. The FPU FSM is busy for only
14.8% of the window. Extended-precision memory operand forms cost 14–18 CPU
clocks each, against about 5–6 for register-register forms. Cache refill is
negligible (under 0.1%).

## Matrix Multiply (97,779,703 clocks, 3 timed runs)

FPU FSM occupancy: F_SRC 4,684,800; F_WB 4,646,400; F_ROUND 4,614,504;
F_EXEC 3,157,572; F_STDONE 1,574,400; F_BIN 1,536,000; F_MULT 1,093,464;
F_ADDX 716,916; F_SHR 692,832; F_NORM2 265,620; F_NORM 38,400. The total is
23,020,908 (23.5%).

By FPU op (the `r_op` split): each `FMOVE.S` load occupies exactly 4 FSM
clocks (F_SRC, F_EXEC, F_WB, F_ROUND). Each `FMOVE.S` store occupies exactly
2 (F_SRC and F_STDONE, with `r_op=$7F`). FADD takes about 4.8 FSM clocks
(BIN, ADDX, SHR, NORM2, ROUND, WB) and FMUL about 4.4 (BIN, MULT, ROUND,
WB).

Exceptions: no vector 11 or 55. Interrupts 2,616 + 233 take 2,806,883 clocks
(2.9%), and there are 802 A-line traps from OS/interrupt-level code.

All FP instruction forms. There are only seven, so these are the top 10:

| # | form | count | clocks | clocks/instr |
|---:|---|---:|---:|---:|
| 1 | `FMOVE.S FPn,d16(An)` | 1,574,400 | 21,765,319 | 13.8 |
| 2 | `FMOVE.S d8(An,Xn),FPn` | 1,536,000 | 18,372,354 | 12.0 |
| 3 | `FADD FPm,FPn` | 768,000 | 4,565,663 | 5.9 |
| 4 | `FMUL FPm,FPn` | 768,000 | 3,888,098 | 5.1 |
| 5 | `FMOVE.S (An),FPn` | 768,000 | 7,399,425 | 9.6 |
| 6 | `FMOVE.S d16(An),FPn` | 768,000 | 8,450,383 | 11.0 |
| 7 | `FMOVE.W Dn,FPn` | 38,400 | 268,827 | 7.0 |

By source: S 3,072,000; S store 1,574,400; register 1,536,000; W 38,400.

Exclusive partition by core state:

| core activity | clocks | % |
|---|---:|---:|
| integer execute | 27,234,177 | 27.9% |
| `S_FPU_GO` | 24,157,428 | 24.7% |
| `S_FPU_DEC` | 12,142,616 | 12.4% |
| FP operand EA/read, including memory reads | 12,789,083 | 13.1% |
| fetch/decode/extension words | 8,570,272 | 8.8% |
| integer memory read/write | 8,815,886 | 9.0% |
| FP store, including memory writes | 3,974,005 | 4.1% |
| exception entry/RTE | 96,236 | 0.1% |

The partition charges the integer EA states (`S_EA_DISP`, `S_EA_EXTW2`,
`S_EA_D16`) and extension-word fetches (`S_IMMF`) to integer and fetch, even
when an FP instruction uses them. The "FP instruction clocks" row above
avoids that problem.

**Reading:** the loop is single-precision load/store bound. There are
2,073,600 FP instructions per run, and two thirds of all window clocks
(66.2%) are spent from `S_FPU_DEC` entry to the next dispatch of an FP
instruction. The `FMOVE.S` loads and stores are 74% of the FP instructions
(4.65 M of 6.22 M) and account for 87% of those FP clocks (56.0 M of
64.7 M), at 9.6–13.8 clocks each. The FSM itself needs only 4 clocks per
single-precision load and 2 per store. The rest is the CPU in `S_FPU_GO`, in `S_FPU_DEC`
waiting on the previous background op (6.1% of the window; 3.85 M of the
6.22 M FP instructions had to wait), EA calculation and the operand read.
The arithmetic FSM states (F_BIN, F_MULT, F_ADDX, F_NORM2) total only 3.7%.
D-cache refill is 1.3% of the window, and the CPU waits in `S_MRD` on a
filling cache for 1.1%. The integer loop overhead (address arithmetic) is
about 28%.

## Fast Fourier (73,606,640 clocks, 5 timed runs)

FPU FSM occupancy: F_WB 3,837,955; F_SRC 3,809,845; F_ROUND 3,760,965;
F_EXEC 2,602,625; F_BIN 1,293,320; F_STDONE 1,285,205; F_ADDX 746,310;
F_SHR 587,575; F_MULT 523,950; F_NORM2 367,870; F_DIVL 3,000; F_NORM 2,680;
F_PACKI 125. The total is 18,821,425 (25.6%).

Exceptions: 125 vector-11 FCOS emulations (132,227 clocks, 0.2%, mean 1,058),
none of them vector 55. Interrupts 1,972 + 175 take 2,023,562 clocks (2.7%).
There are 89 A-line traps.

Top 10 FP instruction forms:

| # | form | count | clocks | clocks/instr |
|---:|---|---:|---:|---:|
| 1 | `FMOVE.S d8(An,Xn),FPn` | 1,692,120 | 19,053,923 | 11.3 |
| 2 | `FMOVE.S FPn,d16(An)` | 1,285,080 | 16,976,405 | 13.2 |
| 3 | `FMOVE.S d16(An),FPn` | 820,460 | 9,027,945 | 11.0 |
| 4 | `FSUB FPm,FPn` | 512,000 | 2,959,316 | 5.8 |
| 5 | `FMUL FPm,FPn` | 461,925 | 2,387,042 | 5.2 |
| 6 | `FADD FPm,FPn` | 308,710 | 1,782,357 | 5.8 |
| 7 | `FNEG FPm,FPn` | 25,600 | 128,034 | 5.0 |
| 8 | `FMOVE.D #imm,FPn` | 2,790 | 28,051 | 10.1 |
| 9 | `FMOVE.X FPn,(An)` | 2,685 | 25,913 | 9.7 |
| 10 | `FMUL.X d16(An),FPn` | 2,685 | 35,210 | 13.1 |

By opmode: FMOVE 2,519,035; FMOVE out 1,288,240; FSUB 514,810; FMUL 466,120;
FADD 309,580; FNEG 25,600; FDIV 2,810; FCOS 125; control/FMOVEM 1,460.

By source: S 2,512,945; register 1,309,235; S store 1,285,080; D 8,785;
X 4,555; X store 3,035; W 2,560.

Exclusive partition by core state:

| core activity | clocks | % |
|---|---:|---:|
| integer execute | 22,416,973 | 30.5% |
| `S_FPU_GO` | 19,910,515 | 27.0% |
| `S_FPU_DEC` | 9,292,177 | 12.6% |
| FP operand EA/read, including memory reads | 9,321,520 | 12.7% |
| fetch/decode/extension words | 6,294,747 | 8.6% |
| integer memory read/write | 3,693,338 | 5.0% |
| FP store, including memory writes | 2,590,044 | 3.5% |
| other (exception entry/RTE, FMOVEM, FSAVE) | 87,326 | 0.1% |

**Reading:** FFT has the same profile as Matrix. 71.4% of the window is FP
instruction time. The three `FMOVE.S` forms (3.80 M of the 5.13 M FP
instructions) account for 45.1 M of those 52.6 M clocks, at 11–13 clocks
each. Register arithmetic costs about 5–6 clocks. There is almost no
cache-fill cost (0.2%) and only 125 FPSP traps.

## Where the clocks go

- **Matrix and FFT (two of the three ratings averaged into the FPU
  score):** single-precision `FMOVE.S` loads and stores dominate. Each costs
  10–14 CPU clocks, while the FPU FSM does only 4 clocks of work for a load
  and 2 for a store. Most of the cost is CPU-side handshaking: `S_FPU_GO`, which is 25–27%
  of all clocks; `S_FPU_DEC` waiting for the previous background op to
  retire, about 6%; and EA plus operand read, about 9–13%. The arithmetic
  datapath (BIN/MULT/ADDX/NORM2) is under 4%. Cache refills are 0.2–1.3%.
  **The earlier 41% `C_FILL` figure does not apply to the timed intervals.**
- **Whetstone:** almost 60% of the timed clocks are spent in the ROM FPSP
  emulating FCOS, FSIN, FATAN, FETOX and FLOGN, at about 1,000 clocks per
  call. Speeding up that path means making FSAVE/FRESTORE, FMOVEM,
  extended-precision loads and stores, and the ROM integer code faster. The
  exception entry itself is small (about 2%).
- Interrupt handling costs about 2.7% in every window and is the same on real
  hardware.

## What the simulation models and does not model

- **RAM:** `sim.v` with `+ram_line_model +ram_first_latency=4
  +ram_line_publish_delay=2`, the calibrated retained-line model. A RAM read
  is acknowledged 4 `clk_sys` edges after acceptance. The whole 16-byte line
  is published to the cache's retained-line sideband (`mem_line_*`, which is
  **connected** in this `sim.v`, SHA `372f1a19…`) 2 edges later. Writes
  complete one edge after acceptance. Posted writes (`mem_wp_*`) land
  immediately and invalidate the retained line.
- **Not modelled:** the posted-write queue is never full (`mem_wq_room` is
  tied to 1). There is no SDRAM refresh, bank/row timing or 33↔99 MHz
  crossing. It is an abstract fixed-latency model, not cycle-accurate SDRAM.
  The store-buffer "push blocked" counter is therefore 0 by construction of
  the model, not a hardware measurement.
- **ROM:** the retained one-edge response. A ROM read is acknowledged on the
  next edge, and the whole ROM line is exposed through `mem_rom_line_*`.
  There is no ROM latency calibration. (The "ROM latency 6" in the handoff
  belongs to the native fixtures, not to this full-machine run.) ROM code,
  including FPSP, is cached. I-cache fills in Whetstone total only 6,673
  clocks.
- The `emu` top level (`MacQuadra800.sv`) is not simulated. The absolute
  score 0.698 agrees with hardware 0.690 only in aggregate.

## Monitor definitions and caveats

- The samples are taken after each rising-edge eval, as for the existing
  `--cpu-profile` bracket. Counters: core `state`; FPU `fst` and `r_op`; cache
  `cst`, with `r_bank` recording which cache is refilling; core `r_m_ret` (the
  state that `S_MRD`/`S_MWR` returns to); `fpu_bg`/`fpu_done`; store buffer
  `count`/`buffer_req`/`push`/`accept_ack`; and `pc_i`, `ir`, `imm`
  (the FP command word) and `debug_a7`.
- **FP instruction** means an entry into `S_FPU_DEC`. The key is the opcode
  word plus the command word, decoded offline into class, opmode, format and
  EA mode. That count equals the number of cpGEN (`$F2xx`) opcode dispatches
  in every window.
- **Exceptions** are counted on entry to `S_EXC_VEC`, using `exc_vec`. The
  frame SP is recorded on entry to `S_EXC_JMP`. An RTE, detected on entry to
  `S_RTE_SR`, pops the most recent record with the same SP, and records at
  lower SPs are discarded as abandoned. Every RTE in all three windows
  matched a frame. A-line frames never meet an RTE, because the Mac trap
  dispatcher returns without one. They are counted but get no duration.
  Their stale records overflowed the 4,096-entry cap: 7, 748 and 50 of the
  oldest records were dropped in the three windows. No RTE went unmatched.
- Durations are inclusive: an interrupt nested inside an FPSP handler counts
  in both the vector 11 total and its own total.
- The per-form clocks attribute the clocks from `S_FPU_DEC` entry up to the
  next opcode-dispatch toggle. That toggle can also be a secondary-pipeline
  admission. The per-form clocks include waiting for the previous background
  op, and exclude the fetch before `S_FPU_DEC` and background execution after
  release.
- Segment boundaries are exact cycles, so window totals are exact. The only
  approximations are the rare attributions that straddle a boundary: an
  exception duration or form clocks are charged to the segment where they
  close.
- The dispatch and opcode counts follow the existing profiler's toggle
  semantics, in which secondary-pipeline admissions also count.

## Files

This directory holds:

- `README.md` (this file)
- `windows.md` and `windows.json`: the full generated tables, including the
  core-state top 20, the `S_MRD` split by return state, the cache state by
  bank, fills by core state, the top PC buckets and the A-line list
- `runs.json`: the per-repetition windows
- `markers.txt`: every Microseconds/TickCount interval that contains FP work
- `fwm_timed_segments_95_1056.txt.gz`: the raw segment counters for all three
  windows. `analyze.py` reproduces `windows.md` from it byte for byte:
  ```
  python3 analyze.py <(zcat fwm_timed_segments_95_1056.txt.gz) \
    --window "Whetstone:95:139" \
    --window "MatrixMultiply (3 timed runs):156:655" \
    --window "FastFourier (5 timed runs):673:1056"
  ```
- `fpu_window_monitor.h`: the monitor
- `sim_main.cpp.diff` and `Makefile.diff`: the hooks, and the release CPU
  macros plus `SCSI_CACHE_OFF`, against commit `0b2d265`
- `control.txt`: the original FPU control, SHA `33108dcd…`
- `run_fullguest.sh` and `rerun.sh`: `rerun.sh` rebuilds from
  `git archive 0b2d265`, verifies `rtl_0b2d265_sha256.txt` and the absence of
  P250, patches, builds, runs and analyses
- `run.meta.txt`, `run_milestones.txt`, `exit_status.txt` and both
  screenshots

**Source identity:** commit `0b2d26559e60ece94aca3eead0f882f93b51a537`. All
113 files under `rtl/` were hashed against `git ls-tree 0b2d265` and match;
per-file SHA256 values are in `rtl_0b2d265_sha256.txt`. `ap040_core.v` is
`82601eae…` and contains no "P250". The scratch copy was taken at 09:38 EDT,
before the working-tree P250 edit. Verilator is 5.050 with
`--unroll-count 256`. Vemu SHA256 is `45f7b372…`, ROM
`quadra800-fastboot.rom.hex` is `045c0274…`, and the golden disk
`MacQuadra800-Speedometer402-profile.hda` is `80d84794…`.

The working tree is `scratch/fpu_subtest_breakdown_20260928/`, which also
holds the full 100 MB `fwm.txt` and the run log (both gzipped). The run was
systemd unit `fpu-subtest-breakdown-20260928`, invocation
`b4a2ddbf7f6d4c9bbe3c5b0f263b66ab`. It started at 13:45:58 UTC and ran for
about 1 h 45 m.
