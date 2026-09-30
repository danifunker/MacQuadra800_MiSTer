; Differential FSAVE/FRESTORE frame dump (2026-09-29, FSAVE/FRESTORE
; compaction).  Not self-checking: every FSAVE frame, the FPSR/FPCR and all
; eight FP registers are written a word at a time to the bench's $F108
; stamp port, and run_diff.sh compares the tag stream of two RTL trees.
; Cases: unimplemented instructions (vector 11) from every operand class,
; unsupported data types (vector 55) including packed and the opclass 011
; stores, every deferred arithmetic class (SNAN/OPERR/DZ e1, OVFL/UNFL/INEX
; e1 and e3) through a pre-instruction trap and through a direct FSAVE,
; FRESTORE+FSAVE round trips of each frame (in the handler), a CU_SAVEPC=$fe
; resume, and FRESTORE over a pending frame.  "run_diff.sh <tree> <label>
; berr" builds a bench variant whose one-shot data bus error sits at $5040,
; armed by a BERRCTL write; cases 90-91 put a UNIMP frame across it.
STAMP   equ     $F108
BERRCTL equ     $F142
RESUME  equ     $3F00
FBUF    equ     $4000
FBUF2   equ     $4100
REGBUF  equ     $4200
SAVED   equ     $4300           ; a saved BUSY frame for the resume case
FAULT   equ     $5040           ; the one-shot faulting read address (bench variant)

T       macro
        bsr     clean
        move.w  #\1,(STAMP).l
        move.l  #res\1,(RESUME).l
        endm
E       macro
res\1:
        bsr     regs
        endm
SV      macro
        lea     (FBUF).l,a0
        fsave   (a0)
        bsr     dumpframe
        endm
LDX     macro                   ; LDX label,fpn
        fmove.x (\1).l,\2
        endm

        org     0
        dc.l    $e000,start
        rept    254
        dc.l    handler
        endr

start:
        move.w  #$2700,sr
        lea     ($e000).l,sp

;--------------------------------------------------- unimplemented (vec 11)
        T       1
        LDX     x_half,fp1
        fsin.x  fp1,fp0
        E       1
        T       2
        fsin.s  (s_quarter).l,fp0
        E       2
        T       3
        fetox.d (d_pi).l,fp2
        E       3
        T       4
        LDX     x_one,fp3
        fsin.x  (x_half).l,fp3
        E       4
        T       5
        LDX     x_one,fp4
        fmovecr.x #$0f,fp4
        E       5
        T       6
        fsin.p  (p_one).l,fp5
        E       6
        T       7
        LDX     x_half,fp1
        LDX     x_big,fp2
        fscale.x fp1,fp2
        E       7
        T       8
        LDX     x_pi,fp1
        LDX     x_big,fp2
        fmod.x  fp1,fp2
        E       8
        T       9
        LDX     x_pi,fp1
        fgetexp.x fp1,fp6
        E       9
        T       10
        LDX     x_pi,fp1
        fintrz.x fp1,fp6
        E       10

;------------------------------------------------ unsupported data (vec 55)
        T       20
        fmovem.x (x_denorm).l,fp7
        LDX     x_one,fp0
        fadd.x  fp7,fp0
        E       20
        T       21
        fmovem.x (x_denorm).l,fp7
        fmove.x fp7,(REGBUF).l
        E       21
        T       22
        fmovem.x (x_denorm).l,fp7
        LDX     x_one,fp1
        fcmp.x  fp1,fp7
        E       22
        T       23
        LDX     x_pi,fp1
        fmove.p fp1,(REGBUF).l{#3}
        E       23
        T       24
        fmove.p (p_one).l,fp0
        E       24
        T       25
        fmove.s (s_denorm).l,fp0
        E       25
        T       26
        fmove.x (x_denorm).l,fp0
        E       26
        T       27
        LDX     x_one,fp2
        fadd.x  (x_denorm).l,fp2
        E       27

;------------------------------------------ deferred arithmetic exceptions
; each op runs twice: FNOP takes the pre-instruction trap (handler FSAVE),
; then again with a direct FSAVE that extracts the prepared frame
        T       40                      ; SNAN, fadd.s (fast F_BIN memory path)
        LDX     x_one,fp2
        fmove.l #$4000,fpcr
        fadd.s  (s_snan).l,fp2
        fnop
        E       40
        T       41
        LDX     x_one,fp2
        fmove.l #$4000,fpcr
        fadd.s  (s_snan).l,fp2
        SV
        E       41
        T       42                      ; OPERR, fsqrt(-1) (monadic arith5, e1)
        LDX     x_neg1,fp1
        fmove.l #$2000,fpcr
        fsqrt.x fp1,fp3
        fnop
        E       42
        T       43
        LDX     x_neg1,fp1
        fmove.l #$2000,fpcr
        fsqrt.x fp1,fp3
        SV
        E       43
        T       44                      ; OPERR, 0 * inf
        LDX     x_zero,fp1
        LDX     x_inf,fp2
        fmove.l #$2000,fpcr
        fmul.x  fp1,fp2
        fnop
        E       44
        T       45                      ; DZ
        LDX     x_zero,fp1
        LDX     x_pi,fp2
        fmove.l #$0400,fpcr
        fdiv.x  fp1,fp2
        fnop
        E       45
        T       46
        LDX     x_zero,fp1
        LDX     x_pi,fp2
        fmove.l #$0400,fpcr
        fdiv.x  fp1,fp2
        SV
        E       46
        T       47                      ; OVFL, fmul (dyadic e3 BUSY)
        LDX     x_big,fp1
        LDX     x_big,fp2
        fmove.l #$1000,fpcr
        fmul.x  fp1,fp2
        fnop
        E       47
        T       48
        LDX     x_big,fp1
        LDX     x_big,fp2
        fmove.l #$1000,fpcr
        fmul.x  fp1,fp2
        SV
        lea     (FBUF).l,a0             ; keep this BUSY frame for case 60
        lea     (SAVED).l,a1
        moveq   #24,d1
.cp:    move.l  (a0)+,(a1)+
        dbra    d1,.cp
        E       48
        T       49                      ; OVFL, fadd.x (fast F_BIN register path)
        LDX     x_big,fp1
        LDX     x_big,fp2
        fmove.l #$1000,fpcr
        fadd.x  fp1,fp2
        fnop
        E       49
        T       50                      ; OVFL, fmove.x reg at single precision (e1)
        LDX     x_big,fp1
        fmove.l #$1040,fpcr
        fmove.x fp1,fp0
        fnop
        E       50
        T       51                      ; OVFL, fmove.d memory (fast F_ROUND memory path)
        fmove.l #$1040,fpcr
        fmove.d (d_big).l,fp0
        SV
        E       51
        T       52                      ; UNFL, fdiv (dyadic e3)
        LDX     x_tiny,fp1
        LDX     x_big,fp2
        fmove.l #$0800,fpcr
        fdiv.x  fp2,fp1
        fnop
        E       52
        T       53
        LDX     x_tiny,fp1
        LDX     x_big,fp2
        fmove.l #$0800,fpcr
        fdiv.x  fp2,fp1
        SV
        E       53
        T       54                      ; INEX2, fadd (dyadic e3)
        LDX     x_one,fp1
        LDX     x_e70,fp2
        fmove.l #$0200,fpcr
        fadd.x  fp2,fp1
        fnop
        E       54
        T       55                      ; INEX2, fsqrt (monadic arith5 e3)
        LDX     x_two,fp1
        fmove.l #$0200,fpcr
        fsqrt.x fp1,fp4
        SV
        E       55
        T       56                      ; INEX2, fsglmul
        LDX     x_pi,fp1
        LDX     x_e70,fp2
        fmove.l #$0200,fpcr
        fsglmul.x fp1,fp2
        fnop
        E       56
        T       57                      ; INEX2, fmove.x at double precision (e1)
        LDX     x_e70p,fp1
        fmove.l #$0280,fpcr
        fmove.x fp1,fp5
        SV
        E       57
        T       58                      ; INEX2, fdiv.d memory (P221 F_BIN)
        LDX     x_one,fp6
        fmove.l #$0200,fpcr
        fdiv.d  (d_pi).l,fp6
        fnop
        E       58

;------------------------------------------------ FRESTORE-driven cases
        T       60                      ; CU_SAVEPC=$fe resume of case 48's frame
        move.b  #$fe,(SAVED+8).l
        lea     (SAVED).l,a0
        frestore (a0)+
        fnop
        E       60
        T       61                      ; same frame, CU_SAVEPC 0, enables on:
        clr.b   (SAVED+8).l             ; re-arms the E3 pend
        fmove.l #$1000,fpcr
        lea     (SAVED).l,a0
        frestore (a0)
        SV
        E       61
        T       62                      ; FRESTORE over a pending (unsaved) frame
        LDX     x_pi,fp1
        fsin.x  fp1,fp0                 ; vec 11; handler resumes at res62
        E       62
        T       63
        LDX     x_big,fp1
        LDX     x_big,fp2
        fmove.l #$1000,fpcr
        fmul.x  fp1,fp2
        lea     (SAVED).l,a0            ; the frame replaces the pending one
        frestore (a0)
        SV
        E       63

;------------------------------------ faulting FRESTORE (bench variant)
; The variant bench faults the first access to $5040 after BERRCTL arms it:
; a UNIMP frame at $5040-40 faults on its word 10 (ETEMP high).  On the
; normal bench these FRESTOREs complete.
        T       90                      ; no frame pending before the FRESTORE
        lea     (FAULT-40).l,a1
        bsr     mkunimp
        move.w  #1,(BERRCTL).l
        lea     (FAULT-40).l,a0
        frestore (a0)
        SV
        E       90
        T       91                      ; a prepared frame pending when it faults
        lea     (FAULT-40).l,a1
        bsr     mkunimp
        LDX     x_big,fp1
        LDX     x_big,fp2
        fmove.l #$1000,fpcr
        fmul.x  fp1,fp2                 ; deferred OVFL: e3 frame prepared
        move.w  #1,(BERRCTL).l
        lea     (FAULT-40).l,a0
        frestore (a0)
        SV
        E       91

        move.w  #$600d,($f102).l
        bra.s   *

;------------------------------------------------------------ subroutines
clean:
        fmove.l #0,fpcr
        frestore (idlef).l              ; drops any frame and pending exception
        fmove.l #0,fpsr
        rts

mkunimp:                                ; a1 = frame base: $41 UNIMP, FSIN of 0.5
        move.l  #$41300000,(a1)+
        move.l  #$00000000,(a1)+        ; CMDREG3B
        clr.l   (a1)+
        move.l  #$00000000,(a1)+        ; STAG/GRS
        move.l  #$000e0000,(a1)+        ; CMDREG1B: fsin
        clr.l   (a1)+
        clr.l   (a1)+
        clr.l   (a1)+                   ; FPTEMP
        clr.l   (a1)+
        clr.l   (a1)+
        move.l  #$3ffe0000,(a1)+        ; ETEMP (word 10, the faulting read)
        move.l  #$80000000,(a1)+
        clr.l   (a1)+
        rts

regs:
        fmovem.x fp0-fp7,(REGBUF).l
        lea     (REGBUF).l,a0
        moveq   #23,d1
.l:     move.l  (a0)+,d0
        bsr     dumpl
        dbra    d1,.l
        fmove.l fpsr,d0
        bsr     dumpl
        fmove.l fpiar,d0
        bsr     dumpl
        rts

dumpframe:                              ; a0 = frame: header + its payload
        move.l  (a0),d0
        bsr     dumpl
        move.l  (a0)+,d1
        swap    d1
        and.w   #$ff,d1
        lsr.w   #2,d1
        beq.s   .d
        subq.w  #1,d1
.l:     move.l  (a0)+,d0
        bsr     dumpl
        dbra    d1,.l
.d:     rts

dumpl:
        swap    d0
        move.w  d0,(STAMP).l
        swap    d0
        move.w  d0,(STAMP).l
        rts

handler:
        move.w  6(sp),d0                ; format/vector word
        move.w  d0,(STAMP).l
        move.l  2(sp),d0                ; stacked PC
        bsr     dumpl
        lea     ($e000).l,sp
        lea     (FBUF).l,a0
        fsave   (a0)
        bsr     dumpframe
        fmove.l fpsr,d0
        bsr     dumpl
        lea     (FBUF).l,a0             ; round trip: FRESTORE, FSAVE again
        frestore (a0)
        lea     (FBUF2).l,a0
        fsave   (a0)
        bsr     dumpframe
        move.l  (RESUME).l,a0
        jmp     (a0)

;------------------------------------------------------------------ data
        cnop    0,4
idlef:    dc.l  $41000000
x_one:    dc.l  $3fff0000,$80000000,$00000000
x_two:    dc.l  $40000000,$80000000,$00000000
x_half:   dc.l  $3ffe0000,$80000000,$00000000
x_neg1:   dc.l  $bfff0000,$80000000,$00000000
x_pi:     dc.l  $40000000,$c90fdaa2,$2168c235
x_big:    dc.l  $7ffe0000,$ffffffff,$ffffffff
x_tiny:   dc.l  $00010000,$80000000,$00000000
x_denorm: dc.l  $00000000,$40000000,$00000001
x_zero:   dc.l  $00000000,$00000000,$00000000
x_inf:    dc.l  $7fff0000,$00000000,$00000000
x_e70:    dc.l  $3fb90000,$80000000,$00000000
x_e70p:   dc.l  $3fff0000,$80000000,$00000401
s_quarter: dc.l $3e800000
s_snan:   dc.l  $7f800001
s_denorm: dc.l  $00000001
d_pi:     dc.l  $400921fb,$54442d18
d_big:    dc.l  $7fefffff,$ffffffff
p_one:    dc.l  $00000001,$00000000,$00000000
