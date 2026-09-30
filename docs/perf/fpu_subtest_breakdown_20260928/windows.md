### Whetstone

Window: segments 95..138, monitor cycles [18,751,498, 27,298,914), opened by `Microseconds` at PC 007597F6. **8,547,416 clocks** = 0.2598 s of guest VIA time.

| quantity | clocks / count | % of window |
|---|---:|---:|
| total clocks | 8,547,416 | 100.00% |
| FPU FSM not idle (fst != F_IDLE) | 1,266,996 | 14.82% |
| &nbsp;&nbsp;F_SRC | 78,186 | 0.91% |
| &nbsp;&nbsp;F_NORM | 7,983 | 0.09% |
| &nbsp;&nbsp;F_EXEC | 117,425 | 1.37% |
| &nbsp;&nbsp;F_WB | 258,832 | 3.03% |
| &nbsp;&nbsp;F_SHR | 56,789 | 0.66% |
| &nbsp;&nbsp;F_PACKI | 3,489 | 0.04% |
| &nbsp;&nbsp;F_BIN | 174,259 | 2.04% |
| &nbsp;&nbsp;F_ADDX | 82,096 | 0.96% |
| &nbsp;&nbsp;F_MULT | 127,442 | 1.49% |
| &nbsp;&nbsp;F_DIVL | 53,040 | 0.62% |
| &nbsp;&nbsp;F_SQRTL | 21,390 | 0.25% |
| &nbsp;&nbsp;F_NORM2 | 23,749 | 0.28% |
| &nbsp;&nbsp;F_ROUND | 258,827 | 3.03% |
| &nbsp;&nbsp;F_STDONE | 3,489 | 0.04% |
| S_FPU_DEC total | 877,585 | 10.27% |
| &nbsp;&nbsp;S_FPU_DEC waiting on fpu_bg (previous FP op not retired) | 487,215 | 5.70% |
| FBcc/FScc waiting on fpu_bg | 0 | 0.00% |
| exception entry waiting on fpu_bg | 71 | 0.00% |
| fpu_bg set (FP op running in background) | 825,375 | 9.66% |
| FPU busy with CPU not released (foreground: fst!=IDLE and !fpu_bg) | 700,452 | 8.19% |
| FP operand read: S_FPU_RD + S_FPU_RD2 | 123,057 | 1.44% |
| FP operand read: S_MRD with return S_FPU_RD/RD2 | 673,204 | 7.88% |
| FP operand EA/imm states (S_FPU_AN/EA/DREG/IMM) | 175,119 | 2.05% |
| S_FPU_GO (issue/wait for FPU accept or done) | 1,077,759 | 12.61% |
| FP store: S_FPU_WR | 154,623 | 1.81% |
| FP store: S_MWR with return S_FPU_WR | 156,600 | 1.83% |
| other FP core state S_FPU_CR | 70,840 | 0.83% |
| other FP core state S_FPU_CR2 | 20,240 | 0.24% |
| other FP core state S_FPU_MVM | 88,948 | 1.04% |
| other FP core state S_FPU_MVM2 | 229,960 | 2.69% |
| other FP core state S_FPU_CRD | 10,119 | 0.12% |
| other FP core state S_FPU_CRI | 15,180 | 0.18% |
| D-cache C_FILL clocks | 3,480 | 0.04% |
| I-cache C_FILL clocks | 6,673 | 0.08% |
| store buffer non-empty | 1,518,462 | 17.77% |
| store buffer push blocked (req && !push && !ack) | 0 | 0.00% |
| bus read issued behind a queued store | 356 | 0.00% |
| PC in ROM ($4xxxxxxx) | 4,987,016 | 58.35% |

Exclusive partition of the window by CPU core state (S_MRD/S_MWR charged to the state that issued them):

| core activity | clocks | % |
|---|---:|---:|
| integer execute | 2,036,990 | 23.83% |
| fetch/decode/ext words | 1,281,424 | 14.99% |
| FP issue/wait (S_FPU_GO) | 1,077,759 | 12.61% |
| FP dispatch (S_FPU_DEC) | 877,585 | 10.27% |
| FP operand EA/read [mem read] | 673,204 | 7.88% |
| integer memory read | 562,664 | 6.58% |
| FP control/FMOVEM | 435,287 | 5.09% |
| FP operand EA/read | 298,176 | 3.49% |
| integer memory write | 220,331 | 2.58% |
| FP control/FMOVEM [mem write] | 171,429 | 2.01% |
| FP control/FMOVEM [mem read] | 159,042 | 1.86% |
| FP store (S_FPU_WR) [mem write] | 156,600 | 1.83% |
| FP store (S_FPU_WR) | 154,623 | 1.81% |
| FP branch/FSAVE/FRESTORE | 141,680 | 1.66% |
| FP branch/FSAVE/FRESTORE [mem write] | 131,573 | 1.54% |
| exception entry/RTE | 69,145 | 0.81% |
| exception entry/RTE [mem read] | 52,690 | 0.62% |
| exception entry/RTE [mem write] | 47,214 | 0.55% |

Dispatches 1,377,173; FP instructions (S_FPU_DEC entries) 390,370 (cpGEN opcode dispatches 390,370); FBcc 0, FScc/FDBcc 0, FSAVE 10,120, FRESTORE 0. FP instructions that found the previous op still running: 230,837. D-cache fills 351, I-cache fills 662.

Exceptions (entry = first exception-processing state; duration to the RTE that pops the same frame, nested time included):

| vector | count | RTE-matched | entry→RTE clocks | % of window | mean |
|---|---:|---:|---:|---:|---:|
| 10 A-line | 5 | 0 | 0 | 0.00% | 0 |
| 11 F-line / FP unimplemented instr. | 5,060 | 5,060 | 4,999,384 | 58.49% | 988 |
| 25 autovector L1 (VIA1) | 228 | 228 | 189,338 | 2.22% | 830 |
| 26 autovector L2 (VIA2/slot) | 21 | 21 | 34,963 | 0.41% | 1,665 |

Exception detail (vector 11 by emulated opmode; A-line by trap word):

| kind | count | RTE-matched | entry→RTE clocks | mean |
|---|---:|---:|---:|---:|
| vec11 FCOS FPm,FPn | 1,920 | 1,920 | 1,927,805 | 1,004 |
| vec11 FETOX FPm,FPn | 930 | 930 | 907,206 | 975 |
| vec11 FLOGN FPm,FPn | 930 | 930 | 971,672 | 1,045 |
| vec11 FATAN FPm,FPn | 640 | 640 | 570,803 | 892 |
| vec11 FSIN FPm,FPn | 640 | 640 | 621,898 | 972 |
| vec25 | 228 | 228 | 189,338 | 830 |
| vec26 | 21 | 21 | 34,963 | 1,665 |
| A-line A055 | 1 | 0 | 0 | 0 |
| A-line A193 | 1 | 0 | 0 | 0 |
| A-line A829 | 1 | 0 | 0 | 0 |
| A-line A851 | 1 | 0 | 0 | 0 |
| A-line A924 | 1 | 0 | 0 | 0 |

Top FP instruction forms (count; clocks from S_FPU_DEC entry to the next dispatch or exception):

| # | form | count | CPU clocks | clocks/instr |
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

### MatrixMultiply (3 timed runs)

Window: segments 156..654, monitor cycles [30,150,647, 127,930,350), opened by `Microseconds` at PC 00759980. **97,779,703 clocks** = 2.9719 s of guest VIA time.

| quantity | clocks / count | % of window |
|---|---:|---:|
| total clocks | 97,779,703 | 100.00% |
| FPU FSM not idle (fst != F_IDLE) | 23,020,908 | 23.54% |
| &nbsp;&nbsp;F_SRC | 4,684,800 | 4.79% |
| &nbsp;&nbsp;F_NORM | 38,400 | 0.04% |
| &nbsp;&nbsp;F_EXEC | 3,157,572 | 3.23% |
| &nbsp;&nbsp;F_WB | 4,646,400 | 4.75% |
| &nbsp;&nbsp;F_SHR | 692,832 | 0.71% |
| &nbsp;&nbsp;F_BIN | 1,536,000 | 1.57% |
| &nbsp;&nbsp;F_ADDX | 716,916 | 0.73% |
| &nbsp;&nbsp;F_MULT | 1,093,464 | 1.12% |
| &nbsp;&nbsp;F_NORM2 | 265,620 | 0.27% |
| &nbsp;&nbsp;F_ROUND | 4,614,504 | 4.72% |
| &nbsp;&nbsp;F_STDONE | 1,574,400 | 1.61% |
| S_FPU_DEC total | 12,142,616 | 12.42% |
| &nbsp;&nbsp;S_FPU_DEC waiting on fpu_bg (previous FP op not retired) | 5,921,816 | 6.06% |
| FBcc/FScc waiting on fpu_bg | 0 | 0.00% |
| exception entry waiting on fpu_bg | 813 | 0.00% |
| fpu_bg set (FP op running in background) | 11,305,080 | 11.56% |
| FPU busy with CPU not released (foreground: fst!=IDLE and !fpu_bg) | 16,330,404 | 16.70% |
| FP operand read: S_FPU_RD + S_FPU_RD2 | 3,072,000 | 3.14% |
| FP operand read: S_MRD with return S_FPU_RD/RD2 | 5,800,283 | 5.93% |
| FP operand EA/imm states (S_FPU_AN/EA/DREG/IMM) | 3,916,800 | 4.01% |
| S_FPU_GO (issue/wait for FPU accept or done) | 24,157,428 | 24.71% |
| FP store: S_FPU_WR | 1,574,400 | 1.61% |
| FP store: S_MWR with return S_FPU_WR | 2,399,605 | 2.45% |
| D-cache C_FILL clocks | 1,256,728 | 1.29% |
| I-cache C_FILL clocks | 161,555 | 0.17% |
| store buffer non-empty | 8,683,478 | 8.88% |
| store buffer push blocked (req && !push && !ack) | 0 | 0.00% |
| bus read issued behind a queued store | 7,060 | 0.01% |
| PC in ROM ($4xxxxxxx) | 3,402,643 | 3.48% |

Exclusive partition of the window by CPU core state (S_MRD/S_MWR charged to the state that issued them):

| core activity | clocks | % |
|---|---:|---:|
| integer execute | 27,234,177 | 27.85% |
| FP issue/wait (S_FPU_GO) | 24,157,428 | 24.71% |
| FP dispatch (S_FPU_DEC) | 12,142,616 | 12.42% |
| fetch/decode/ext words | 8,570,272 | 8.76% |
| FP operand EA/read | 6,988,800 | 7.15% |
| integer memory read | 6,268,566 | 6.41% |
| FP operand EA/read [mem read] | 5,800,283 | 5.93% |
| integer memory write | 2,547,320 | 2.61% |
| FP store (S_FPU_WR) [mem write] | 2,399,605 | 2.45% |
| FP store (S_FPU_WR) | 1,574,400 | 1.61% |
| exception entry/RTE | 43,491 | 0.04% |
| exception entry/RTE [mem read] | 27,709 | 0.03% |
| exception entry/RTE [mem write] | 25,036 | 0.03% |

Dispatches 22,835,687; FP instructions (S_FPU_DEC entries) 6,220,800 (cpGEN opcode dispatches 6,220,800); FBcc 0, FScc/FDBcc 0, FSAVE 0, FRESTORE 0. FP instructions that found the previous op still running: 3,846,085. D-cache fills 125,644, I-cache fills 15,863.

Exceptions (entry = first exception-processing state; duration to the RTE that pops the same frame, nested time included):

| vector | count | RTE-matched | entry→RTE clocks | % of window | mean |
|---|---:|---:|---:|---:|---:|
| 10 A-line | 802 | 0 | 0 | 0.00% | 0 |
| 25 autovector L1 (VIA1) | 2,616 | 2,616 | 2,375,573 | 2.43% | 908 |
| 26 autovector L2 (VIA2/slot) | 233 | 233 | 431,310 | 0.44% | 1,851 |

Exception detail (vector 11 by emulated opmode; A-line by trap word):

| kind | count | RTE-matched | entry→RTE clocks | mean |
|---|---:|---:|---:|---:|
| vec25 | 2,616 | 2,616 | 2,375,573 | 908 |
| A-line A31E | 369 | 0 | 0 | 0 |
| A-line A01F | 369 | 0 | 0 | 0 |
| vec26 | 233 | 233 | 431,310 | 1,851 |
| A-line A829 | 17 | 0 | 0 | 0 |
| A-line A851 | 17 | 0 | 0 | 0 |
| A-line A924 | 17 | 0 | 0 | 0 |
| A-line A193 | 5 | 0 | 0 | 0 |
| A-line A055 | 3 | 0 | 0 | 0 |
| A-line A05A | 3 | 0 | 0 | 0 |
| A-line A975 | 2 | 0 | 0 | 0 |

Top FP instruction forms (count; clocks from S_FPU_DEC entry to the next dispatch or exception):

| # | form | count | CPU clocks | clocks/instr |
|---:|---|---:|---:|---:|
| 1 | `FMOVE.S FPn,d16(An)` | 1,574,400 | 21,765,319 | 13.8 |
| 2 | `FMOVE.S d8(An,Xn),FPn` | 1,536,000 | 18,372,354 | 12.0 |
| 3 | `FADD FPm,FPn` | 768,000 | 4,565,663 | 5.9 |
| 4 | `FMUL FPm,FPn` | 768,000 | 3,888,098 | 5.1 |
| 5 | `FMOVE.S (An),FPn` | 768,000 | 7,399,425 | 9.6 |
| 6 | `FMOVE.S d16(An),FPn` | 768,000 | 8,450,383 | 11.0 |
| 7 | `FMOVE.W Dn,FPn` | 38,400 | 268,827 | 7.0 |

### FastFourier (5 timed runs)

Window: segments 673..1055, monitor cycles [129,943,460, 203,550,100), opened by `Microseconds` at PC 00759B3E. **73,606,640 clocks** = 2.2372 s of guest VIA time.

| quantity | clocks / count | % of window |
|---|---:|---:|
| total clocks | 73,606,640 | 100.00% |
| FPU FSM not idle (fst != F_IDLE) | 18,821,425 | 25.57% |
| &nbsp;&nbsp;F_SRC | 3,809,845 | 5.18% |
| &nbsp;&nbsp;F_NORM | 2,680 | 0.00% |
| &nbsp;&nbsp;F_EXEC | 2,602,625 | 3.54% |
| &nbsp;&nbsp;F_WB | 3,837,955 | 5.21% |
| &nbsp;&nbsp;F_SHR | 587,575 | 0.80% |
| &nbsp;&nbsp;F_PACKI | 125 | 0.00% |
| &nbsp;&nbsp;F_BIN | 1,293,320 | 1.76% |
| &nbsp;&nbsp;F_ADDX | 746,310 | 1.01% |
| &nbsp;&nbsp;F_MULT | 523,950 | 0.71% |
| &nbsp;&nbsp;F_DIVL | 3,000 | 0.00% |
| &nbsp;&nbsp;F_NORM2 | 367,870 | 0.50% |
| &nbsp;&nbsp;F_ROUND | 3,760,965 | 5.11% |
| &nbsp;&nbsp;F_STDONE | 1,285,205 | 1.75% |
| S_FPU_DEC total | 9,292,177 | 12.62% |
| &nbsp;&nbsp;S_FPU_DEC waiting on fpu_bg (previous FP op not retired) | 4,164,397 | 5.66% |
| FBcc/FScc waiting on fpu_bg | 0 | 0.00% |
| exception entry waiting on fpu_bg | 660 | 0.00% |
| fpu_bg set (FP op running in background) | 9,163,550 | 12.45% |
| FPU busy with CPU not released (foreground: fst!=IDLE and !fpu_bg) | 13,419,330 | 18.23% |
| FP operand read: S_FPU_RD + S_FPU_RD2 | 2,520,805 | 3.42% |
| FP operand read: S_MRD with return S_FPU_RD/RD2 | 2,973,900 | 4.04% |
| FP operand EA/imm states (S_FPU_AN/EA/DREG/IMM) | 3,826,815 | 5.20% |
| S_FPU_GO (issue/wait for FPU accept or done) | 19,910,515 | 27.05% |
| FP store: S_FPU_WR | 1,294,310 | 1.76% |
| FP store: S_MWR with return S_FPU_WR | 1,295,734 | 1.76% |
| other FP core state S_FPU_CR | 1,750 | 0.00% |
| other FP core state S_FPU_CR2 | 500 | 0.00% |
| other FP core state S_FPU_MVM | 1,345 | 0.00% |
| other FP core state S_FPU_MVM2 | 3,550 | 0.00% |
| other FP core state S_FPU_CRD | 250 | 0.00% |
| other FP core state S_FPU_CRI | 375 | 0.00% |
| D-cache C_FILL clocks | 144,036 | 0.20% |
| I-cache C_FILL clocks | 31,889 | 0.04% |
| store buffer non-empty | 7,895,976 | 10.73% |
| store buffer push blocked (req && !push && !ack) | 0 | 0.00% |
| bus read issued behind a queued store | 3,040 | 0.00% |
| PC in ROM ($4xxxxxxx) | 1,686,875 | 2.29% |

Exclusive partition of the window by CPU core state (S_MRD/S_MWR charged to the state that issued them):

| core activity | clocks | % |
|---|---:|---:|
| integer execute | 22,416,973 | 30.46% |
| FP issue/wait (S_FPU_GO) | 19,910,515 | 27.05% |
| FP dispatch (S_FPU_DEC) | 9,292,177 | 12.62% |
| FP operand EA/read | 6,347,620 | 8.62% |
| fetch/decode/ext words | 6,294,747 | 8.55% |
| FP operand EA/read [mem read] | 2,973,900 | 4.04% |
| integer memory read | 2,157,454 | 2.93% |
| integer memory write | 1,535,884 | 2.09% |
| FP store (S_FPU_WR) [mem write] | 1,295,734 | 1.76% |
| FP store (S_FPU_WR) | 1,294,310 | 1.76% |
| exception entry/RTE | 30,947 | 0.04% |
| exception entry/RTE [mem read] | 21,167 | 0.03% |
| exception entry/RTE [mem write] | 14,437 | 0.02% |
| FP control/FMOVEM | 7,770 | 0.01% |
| FP branch/FSAVE/FRESTORE | 3,500 | 0.00% |
| FP branch/FSAVE/FRESTORE [mem write] | 3,315 | 0.00% |
| FP control/FMOVEM [mem write] | 3,169 | 0.00% |
| FP control/FMOVEM [mem read] | 3,021 | 0.00% |

Dispatches 17,794,902; FP instructions (S_FPU_DEC entries) 5,127,780 (cpGEN opcode dispatches 5,127,780); FBcc 0, FScc/FDBcc 0, FSAVE 250, FRESTORE 0. FP instructions that found the previous op still running: 2,526,277. D-cache fills 14,447, I-cache fills 3,150.

Exceptions (entry = first exception-processing state; duration to the RTE that pops the same frame, nested time included):

| vector | count | RTE-matched | entry→RTE clocks | % of window | mean |
|---|---:|---:|---:|---:|---:|
| 10 A-line | 89 | 0 | 0 | 0.00% | 0 |
| 11 F-line / FP unimplemented instr. | 125 | 125 | 132,227 | 0.18% | 1,058 |
| 25 autovector L1 (VIA1) | 1,972 | 1,972 | 1,728,230 | 2.35% | 876 |
| 26 autovector L2 (VIA2/slot) | 175 | 175 | 295,332 | 0.40% | 1,688 |

Exception detail (vector 11 by emulated opmode; A-line by trap word):

| kind | count | RTE-matched | entry→RTE clocks | mean |
|---|---:|---:|---:|---:|
| vec25 | 1,972 | 1,972 | 1,728,230 | 876 |
| vec26 | 175 | 175 | 295,332 | 1,688 |
| vec11 FCOS FPm,FPn | 125 | 125 | 132,227 | 1,058 |
| A-line A11E | 15 | 0 | 0 | 0 |
| A-line A01F | 15 | 0 | 0 | 0 |
| A-line A829 | 13 | 0 | 0 | 0 |
| A-line A851 | 13 | 0 | 0 | 0 |
| A-line A924 | 13 | 0 | 0 | 0 |
| A-line A193 | 9 | 0 | 0 | 0 |
| A-line A055 | 5 | 0 | 0 | 0 |
| A-line A975 | 4 | 0 | 0 | 0 |
| A-line A05A | 2 | 0 | 0 | 0 |

Top FP instruction forms (count; clocks from S_FPU_DEC entry to the next dispatch or exception):

| # | form | count | CPU clocks | clocks/instr |
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

