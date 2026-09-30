# Native FPMm integer-exact oracle

`oracle.py` reconstructs the native resource's FPMm selector from the archived
static disassembly in
`docs/perf/cache_refill_20260927/fpu_completion_eligibility/provenance/`.
It is independent of RTL and is not evidence that a simulator run captured or
matched these results.

The call graph and loop mechanics are in `FPMm.dis`: selector target 0x17a;
three arrays of 41 row pointers are allocated in loops at 0x186–0x1a2,
0x1a8–0x1c4, and 0x1ca–0x1e6. At 0x1ec, the seed is reset; `rInitmatrix` at
0x1f0 initializes the first matrix and the call at 0x1f8 initializes the
second matrix after the same seed reset. Each initializer covers row and
column indices 1..40 (`rInitmatrix.dis` 0x7a–0xd0). The four passes at
0x1ec–0x24c each reset the seed and reinitialize both input matrices before
recomputing the result; deterministic inputs make all four results identical.
Results are disposed at 0x250–0x288.

`LocalInitrand.dis` 0x26–0x2c sets the 16-bit seed to 0x2403. `LocalRand.dis`
0x44–0x56 implements `seed = (seed*0x051d + 0x3619) mod 65536`; only the
low word is consumed. `rInitmatrix.dis` 0x82–0xa6 interprets it as signed
16-bit, computes signed remainder by 120 (DIVS quotient truncates toward
zero), subtracts 60, then signed-divides by 3 with truncation toward zero.
The integer quotient is converted to FP and stored as binary32. The generated
values lie in [-59,19]. Each matrix initializes exactly 40×40=1,600 values;
row 0 is unused and consumes no random values. Each pass makes 3,200 random
calls total and leaves the seed at 0xd383.

The result loops in `FPMm.dis` 0x206–0x24c write result[row][column]. The
caller pushes the second table then the first table, and `rInnerproduct.dis`
receives A as its first table and B as its second (`FPMm.dis` 0x20a–0x22e).
The inner routine sums `A[row][k] * B[k][column]`, k=1..40: it loads
B[k][column] at 0x116–0x11a and A[row][k] at 0x120–0x132 using row D5 and
inner index D2. Its single-precision product and each
single-precision accumulated sum are exact: `abs(input)<=59`, each product
has magnitude <=3481, and even the conservative 40-term partial-sum bound
`40*59^2=139240` is below 2^24, the binary32 exact-integer limit. The result
is therefore a 40x40 matrix of exactly representable integer-valued floats.

Run `python3 scratch/native_fppm_oracle_20260928/oracle.py` for reproducible
big-endian row-major input/result hashes, known cells and ranges. The result
hash is over IEEE binary32 words in row-major 1-based order; each pass yields
the same matrix. This is a proposed independent comparison oracle only: no
existing native simulation result capture has been compared against it.
