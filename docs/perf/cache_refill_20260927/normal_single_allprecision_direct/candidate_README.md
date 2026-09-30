# Normal FMOVE.S conversion at all FPCR precision settings

Isolated source only; production RTL and prior candidate remain unchanged.
This removes only fpcr[7:6]==00 from the previous normal-single shortcut.
Enabled exceptions must still be zero; all normal-value/opcode/sideport guards
and the existing F_ROUND/F_WB pipeline are retained.

Primary source proof: normal binary32 exponent1..254 expands to16257..16510,
and its24-bit significand expands with40zero low bits. F_SRC conversion and
FMOVE F_EXEC setup do not depend on FPCR precision. The retained F_ROUND handles
all precision modes: single discards40 alreadyzero bits with exactly this
normal exponent range; double discards11 alreadyzero bits and has a wider
range; extended discards only zeroGRS. All rounding modes leave this value
unchanged. Reservedprecision11 uses double per existing prec_of(). Preserve
FPCR, exception/status/condition flags, FPIAR, shadows, physical banks and
accepted/done behavior. No NaN/zero/subnormal/otheropcode shortcut is added.

The unchanged fullguest score of the previous candidate motivates reviewing
eligibility, but actual guest FPCR is not yet measured. Do not claim this
revision fixes the OS mismatch until runtime evidence establishes it.

Next: expand independent real-port tests to all4precision x4rounding modes,
all254normal exponents/both signs/8mantissa boundaries, CE/request/reset cases,
both physical replicas/dependent read and FPCR retention. Move three old
precision-exclusion cases into positive coverage; retain all other exclusion
signatures and all six existing regressions. Native/fullguest performance,
actual OS guard/FPCR observation and FPGA fit remain unqualified.
