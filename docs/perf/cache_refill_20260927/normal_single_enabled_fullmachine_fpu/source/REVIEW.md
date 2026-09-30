# Exact normal FMOVE.S with exception enables

Based on frozen all-precision candidate55ff. The only behavioral change removes
its blanket FPCR exception-enable guard. All normal-input, operation and side-port
guards remain; pending restored-frame and restore-resume branches retain priority.

F_IDLE clears the per-instruction status byte while retaining accrued flags and
captures the destination shadows. For a normal binary32 source, cv_s and F_EXEC
cannot set SNAN, OPERR or unsupported-type status. FMOVE does not inspect the old
destination as an arithmetic operand. The shortcut reproduces those source shadows.
The 24-bit significand is exact at every precision, and its exponent is within all
supported ranges. F_ROUND and F_WB remain unchanged, including enabled-exception
writeback suppression. No exception status or enable bit is disabled by this edit.

Qualification required: all-precision/all-rounding normal sweep with measured
FPCR enable0x20; representative inputs under all256 enable masks; stale FPSR status
clearing/accrual preservation; both register banks; dependent operation; CE/reset/
held request; all side ports; restored pending/resignal and resume priority; excluded
zeros/subnormals/NaNs/infinities and trapping cases compared with production2d53.
Then core regressions and a fresh fullguest run with updated observer semantics.
No performance, FPGA timing or hardware qualification yet. Production unchanged.
