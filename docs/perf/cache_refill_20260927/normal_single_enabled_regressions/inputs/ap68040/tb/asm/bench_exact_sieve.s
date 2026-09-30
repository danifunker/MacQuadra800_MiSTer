; Exact Speedometer 4.02 CODE 3 Sieve computational loop.
; Build from the verified original resource via prepare_exact_sieve.py.
; Measured interval is the decode boundary at $2000 to that at $2050.
; No stopwatch, allocator, checking, or wrapper instructions are timed.

ARRAY equ $4000
GUARD_START equ $3FE0
GUARD_END equ $6020
DONEREG equ $F102
FAILREG equ $F100

 org 0
 dc.l $3400
 dc.l start
 rept 254
 dc.l unexpected
 endr

 org $400
start:
 move.w #$2700,sr
 ; Cache-disabled setup: sentinel fills array, padding, and both guards.
 moveq #0,d0
 movec d0,cacr
 lea (GUARD_START).l,a0
 move.w #(GUARD_END-GUARD_START)/4-1,d1
fill:
 move.l #$A55AA55A,(a0)+
 dbra d1,fill
 move.l #$80008000,d0
 movec d0,cacr
 cinva ic
 cinva dc
 lea (ARRAY).l,a2
 moveq #0,d2
again:
 jsr (kernel).l
 addq.w #1,d2
 cmpi.w #2,d2
 blt.s again
 move.w #$600D,(DONEREG).l
 stop #$2700
unexpected:
 move.w #$99,(FAILREG).l
 move.w #$BAD0,(DONEREG).l
 bra.s unexpected

 org $2000
kernel:
 incbin "build/exact_sieve.bin"
kernel_exit:
 nop
 rts
