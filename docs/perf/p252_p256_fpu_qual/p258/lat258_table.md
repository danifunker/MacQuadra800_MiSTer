| key | Row | lat3 0b2d265 | lat3 b2ed1b0 | lat3 ad7a0d4 | lat1 0b2d265 | lat1 b2ed1b0 | lat1 ad7a0d4 |
|---|---|---:|---:|---:|---:|---:|---:|
| fmove_i | FMOVE.X FPm,FPn indep | 5 | 3 | 3 | 5 | 3 | 3 |
| fmove_d | FMOVE.X FPm,FPn dep | 5 | 3 | 3 | 5 | 3 | 3 |
| faddeq_i | FADD.X equal exp indep | 6 | 4 | 4 | 6 | 4 | 4 |
| faddeq_d | FADD.X equal exp dep | 6 | 4 | 4 | 6 | 4 | 4 |
| fadd5_i | FADD.X exp diff 5 indep | 7 | 4 | 4 | 7 | 4 | 4 |
| fadd5_d | FADD.X exp diff 5 dep | 7 | 4 | 4 | 7 | 4 | 4 |
| fadd40_i | FADD.X exp diff 40 indep | 7 | 4 | 4 | 7 | 4 | 4 |
| fadd40_d | FADD.X exp diff 40 dep | 7 | 4 | 4 | 7 | 4 | 4 |
| fsubc_i | FSUB.X cancel/FADD d60 pairs indep | 7 | 4.5 | 4.5 | 7 | 4.5 | 4.5 |
| fsubc_d | FSUB.X cancel/FADD d60 pairs dep | 7 | 4.5 | 4.5 | 7 | 4.5 | 4.5 |
| fsubn_i | FSUB.X no cancel indep | 8 | 5 | 5 | 8 | 5 | 5 |
| fsubn_d | FSUB.X no cancel dep | 8 | 5 | 5 | 8 | 5 | 5 |
| fmul_i | FMUL.X FPm,FPn indep | 7 | 4 | 4 | 7 | 4 | 4 |
| fmul_d | FMUL.X FPm,FPn dep | 7 | 4 | 4 | 7 | 4 | 4 |
| fmul2_i | FMUL.X by 2.0 (fast path) indep | 5 | 4 | 4 | 5 | 4 | 4 |
| fdiv_i | FDIV.X FPm,FPn indep | 29 | 27 | 27 | 29 | 27 | 27 |
| fdiv_d | FDIV.X FPm,FPn dep | 29 | 27 | 27 | 29 | 27 | 27 |
| fsqrt_i | FSQRT.X FPm,FPn indep | 29 | 27 | 27 | 29 | 27 | 27 |
| fsqrt_d | FSQRT.X FPn dep | 29 | 27 | 27 | 29 | 27 | 27 |
| fmulmx_i | FMUL.X (A0),FPn indep | 11 | 8 | 8 | 11 | 8 | 8 |
| fmulmx_d | FMUL.X (A0),FPn dep | 11 | 8 | 8 | 11 | 8 | 8 |
| fmulmd_i | FMUL.D (A0),FPn indep | 12 | 7 | 7 | 12 | 7 | 7 |
| fmulmd_d | FMUL.D (A0),FPn dep | 12 | 7 | 7 | 12 | 7 | 7 |
| fmulms_i | FMUL.S (A0),FPn indep | 11 | 6 | 6 | 11 | 6 | 6 |
| fmulms_d | FMUL.S (A0),FPn dep | 11 | 6 | 6 | 11 | 6 | 6 |
| faddpi_i | FADD.D (A0)+,FPn indep | 12 | 7 | 7 | 12 | 7 | 7 |
| faddpi_d | FADD.D (A0)+,FPn dep | 12 | 7 | 7 | 12 | 7 | 7 |
| fstx_i | FMOVE.X FPn,(A0) indep | 18 | 18 | 18 | 12 | 12 | 12 |
| fstx_d | FADD.X + FMOVE.X of its result (pair) | 18 | 18 | 18 | 16 | 13 | 13 |
| fstd_i | FMOVE.D FPn,(A0) indep | 12 | 12 | 12 | 9 | 8 | 8 |
| fstd_d | FADD.X + FMOVE.D of its result (pair) | 16 | 12 | 12 | 16 | 11 | 11 |
| fsts_i | FMOVE.S FPn,(A0) indep | 7.06 | 6 | 6 | 7.06 | 5.06 | 5.06 |
| fsts_d | FADD.X + FMOVE.S of its result (pair) | 14 | 9 | 9 | 14 | 9 | 9 |
| fstl_i | FMOVE.L FPn,(A0) indep | 9 | 9 | 9 | 9 | 9 | 9 |
| fstl_d | FADD.X + FMOVE.L of its result (pair) | 16 | 13 | 13 | 16 | 13 | 13 |
| fld_i | FMOVE.D (A0),FPn different dest | 9 | 6 | 6 | 9 | 6 | 6 |
| fld_d | FMOVE.D (A0),FP0 same dest | 8.97 | 5.94 | 5.94 | 8.97 | 5.94 | 5.94 |
| fcmp_i | FCMP.X FPm,FPn | 5 | 4 | 4 | 5 | 4 | 4 |
| fcmpb_d | FCMP.X + FBEQ.W not taken (pair) | 7 | 6 | 6 | 7 | 6 | 6 |
| fbnt | FBEQ.W not taken | 2.28 | 2.28 | 2.28 | 2.28 | 2.28 | 2.28 |
| fbt | FBNE.W taken (to next insn) | 2.22 | 2.22 | 2.22 | 2.22 | 2.22 | 2.22 |
| add_i | ADD.L D0,Dn (integer only) | 1 | 1 | 1 | 1 | 1 | 1 |
| mulint1 | FMUL.X FP7,FPn + 1 ADD.L (pair) | 7 | 6 | 6 | 7 | 6 | 6 |
| mulint1d | FMUL.X FP7,FP0 dep + 1 ADD.L (pair) | 7 | 6 | 6 | 7 | 6 | 6 |
| mulint4 | FMUL.X FP7,FPn + 4 ADD.L (group) | 9 | 9 | 9 | 9 | 9 | 9 |
| mulint8 | FMUL.X FP7,FPn + 8 ADD.L (group) | 12.94 | 12.94 | 12.94 | 12.94 | 12.94 | 12.94 |
| divint8 | FDIV.X FP7,FPn + 8 ADD.L (group) | 29 | 27 | 27 | 29 | 27 | 27 |
| divint24 | FDIV.X FP7,FPn + 24 ADD.L (group) | 29.09 | 29.09 | 29.09 | 29.09 | 29.09 | 29.09 |
| flds16_i | FMOVE.S d16(A0),FPn | 12 | 5 | 5 | 12 | 5 | 5 |
| fldsx_i | FMOVE.S d8(A0,D0.L),FPn | 12 | 5 | 5 | 12 | 5 | 5 |
| flds0_i | FMOVE.S (A0),FPn | 8 | 5 | 5 | 8 | 5 | 5 |
| fsts16_i | FMOVE.S FPn,d16(A0) | 11 | 6 | 6 | 11 | 5 | 5 |
| ldmul | FMOVE.S d16(A0),FP0 ; FMUL.X FP0,FP1 (pair) | 19 | 9 | 9 | 19 | 9 | 9 |
| mulst | FMUL.X FP1,FP2 ; FMOVE.S FP2,d16(A0) (pair) | 18.06 | 9.06 | 9.06 | 18.06 | 9.06 | 9.06 |
| matrix | Matrix: FMOVE.S 0(A0,D0.L),FP0; FMUL.X FP1,FP0; FADD.X FP0,F | 26 | 15 | 15 | 26 | 15 | 15 |
| fft | FFT: 2x FMOVE.S d16(A0),FPn; FSUB.X; FMUL.X; FADD.X; 2x FMOV | 65 | 32.94 | 32.94 | 65 | 32.94 | 32.94 |
| fldd16_i | FMOVE.D d16(A0),FPn | 13 | 6 | 6 | 13 | 6 | 6 |
| fstd16_i | FMOVE.D FPn,d16(A0) | 13.06 | 12 | 12 | 13.06 | 8 | 8 |
| fsnull | FSAVE -(A7) ; FRESTORE (A7)+, NULL frame (pair) | 11 | 11 | 10 | 11 | 11 | 10 |
| fsidle | FSAVE -(A7) ; FRESTORE (A7)+, IDLE frame after FMOVE (pair) | 11 | 11 | 10 | 11 | 11 | 10 |
| fintrz_rte | FINTRZ.X FP1,FP0 -> vec 11, handler RTE | 65.22 | 65.22 | 56.22 | 65.22 | 65.22 | 56.22 |
| fintrz_fs | FINTRZ.X FP1,FP0 -> vec 11, handler FSAVE/FRESTORE/RTE 2 | 167.28 | 167.28 | 141.28 | 163.28 | 163.28 | 125.28 |
| fmovecr_rte | FMOVECR #0,FP0 -> vec 11, handler RTE | 65.22 | 65.22 | 56.22 | 65.22 | 65.22 | 56.22 |
| fmovecr_fs | FMOVECR #0,FP0 -> vec 11, handler FSAVE/FRESTORE/RTE 2 | 167.28 | 167.28 | 141.28 | 163.28 | 163.28 | 125.28 |
| trap | TRAP #0 -> handler RTE | 58 | 58 | 49 | 58 | 58 | 49 |
| aline | A-line $A000 -> handler ADDQ.L #2,2(SP); RTE | 63 | 63 | 54 | 63 | 63 | 54 |
| nop_rte | handler-only reference: BSR to RTS (not a trap) | 9 | 9 | 9 | 9 | 9 | 9 |
