# Assignment 2: Complete Applications

contributed by < [`PeteChiang1211`](https://github.com/PeteChiang1211) >

Repository: [PeteChiang1211/arch2026-progs](https://github.com/PeteChiang1211/arch2026-progs)

## Progress log

| Date | Program | What changed | Effect | Commit |
|---|---|---|---|---|
| 2026-10-31 | setup | Forked the framework, installed the xPack toolchain, built rv32emu | `make toolchain` passes, skeleton scores 0 | — |
| 2026-10-31 | gcd | C version of the binary GCD | all C tests pass, worst call 399 instructions at `-O2` (budget 4,000) | [`bd483ec`](https://github.com/PeteChiang1211/arch2026-progs/commit/bd483ec137608a109433bb72df4aaee5836a89f6) |
| 2026-10-31 | gcd | RV32I assembly version | 84.4 instructions per call, 1.17x the best C build; gcd passes, total 25/100 | [`5b823a4`](https://github.com/PeteChiang1211/arch2026-progs/commit/5b823a401464e32a6507b22279481cbbee1ada75) |
| 2026-11-01 | fixed | C bitwise add (`op1`) and subtraction (`op2`) | tests pass, worst `op1` call 169 instructions (budget 1,500) | [`96805ab`](https://github.com/PeteChiang1211/arch2026-progs/commit/96805ab5b1138ea8f3411897b6a11b8e365d44f9) |
| 2026-11-01 | fixed | C overflow-free average (`op3`) | tests pass, 11 instructions (budget 150) | [`f2c469a`](https://github.com/PeteChiang1211/arch2026-progs/commit/f2c469a08ccbc3149ae1af5877026e2220b991ee) |
| 2026-11-01 | fixed | C Q11.20 multiply from 16-bit partial products | all C tests pass, worst call 525 instructions (budget 3,000) | [`38d99b6`](https://github.com/PeteChiang1211/arch2026-progs/commit/38d99b69a842d897cd087658d0a8c1e9d8601cd5) |
| 2026-11-01 | fixed | RV32I assembly of all four functions | `q_mul` 1.73x, `op3` 1.29x the best C build; fixed passes, total 50/100 | [`2b37892`](https://github.com/PeteChiang1211/arch2026-progs/commit/2b37892bfd17f9d11355b79d7571f58d3afb6fae) |
| 2026-11-01 | bf16 | C narrowing with round to nearest, ties to even | tests pass, 15 instructions (budget 150) | [`ed6e6f1`](https://github.com/PeteChiang1211/arch2026-progs/commit/ed6e6f12d7d947fef441d4a09342e9f6eb810e3d) |
| 2026-11-01 | bf16 | C multiply | tests pass, worst call 174 instructions (budget 1,000) | [`16f0557`](https://github.com/PeteChiang1211/arch2026-progs/commit/16f05576e431027ffc8f52b8082e4216149a89c0) |
| 2026-11-01 | bf16 | C square root by binary search | all C tests pass, worst call 631 instructions (budget 4,000) | [`4592e41`](https://github.com/PeteChiang1211/arch2026-progs/commit/4592e41d049f1d516afc66032aeca8382c539731) |
| 2026-11-01 | bf16 | RV32I assembly: quarter-square multiply, table square root | multiply 2.01x, square root 18x the best C build; bf16 passes, total 75/100 | [`d9aaf53`](https://github.com/PeteChiang1211/arch2026-progs/commit/d9aaf53c23655c1bd7ba6de7a3b4fd49df5252e6) |
| | rubik | | | |

## Environment

| Item | Value |
|---|---|
| Compiler | xPack `riscv-none-elf-gcc` 15.2.0 (binutils 2.45) |
| Flags | `-march=rv32i_zicsr -mabi=ilp32 -ffreestanding` |
| Emulator | rv32emu `158b57e`, system emulation, `ELF_LOADER`, interpreter, no M/A/F/C |
| Host | Ubuntu 24.04, x86_64 |

**Measurement limit.** rv32emu has no timing model: `cycle` and `instret` are one counter of executed guest instructions. Every "cycle" figure in this note is an instruction count; it says nothing about pipeline stalls, cache misses or multi-cycle instructions. Code size is reported separately with `size -A`.

**Method.** Each figure comes from `make cycles`: the C and assembly versions run on identical inputs in the same timed region, and the overhead of the same loop with the call replaced by a copy of its input is subtracted. The counts are deterministic, so one run suffices. The counters are read with `get_cycles()` / `get_instret()` from `common/perf.S`, which reread the high word to handle the carry from the low word.

---

## gcd: Binary GCD without a divider

Contract: [`src/gcd/gcd.h`](https://github.com/PeteChiang1211/arch2026-progs/blob/5b823a401464e32a6507b22279481cbbee1ada75/src/gcd/gcd.h). `gcd_u32(a, b)` returns the greatest common divisor of two unsigned 32-bit values, with gcd(x, 0) = gcd(0, x) = x. No `mul`, `div`, `rem`, libgcc call, or one-step-at-a-time subtraction loop.

### Principle

Euclid's algorithm needs a remainder, and RV32I has no divider: a software division would cost hundreds of instructions per step. The binary GCD (Stein's algorithm) uses only shifts, subtraction and comparison, which are all single RV32I instructions.

### Mathematical foundation

Four identities, for unsigned a and b:

1. gcd(a, 0) = a, because every integer divides 0.
2. If a and b are both even, gcd(a, b) = 2 · gcd(a/2, b/2): 2 is a common factor.
3. If a is odd and b is even, gcd(a, b) = gcd(a, b/2): 2 does not divide a, so it cannot be part of a common divisor.
4. If a and b are both odd and b ≥ a, gcd(a, b) = gcd(a, b − a): any d dividing a and b divides b − a, and conversely any d dividing a and b − a divides b. Moreover b − a is even, so identity 3 applies right after.

Identity 2 is applied k times, where k is the number of trailing zeros of (a | b); the result is shifted back left by k at the end. Each subtraction step (4 followed by at least one halving by 3) reduces max(a, b) by at least half, so the loop runs at most about 64 times for 32-bit operands.

### C version

[`src/gcd/gcd.c`](https://github.com/PeteChiang1211/arch2026-progs/blob/5b823a401464e32a6507b22279481cbbee1ada75/src/gcd/gcd.c)

```c
    while ((a & 1) == 0 && (b & 1) == 0) {
        a = a >> 1;
        b = b >> 1;
        shift = shift + 1;
    }
```

Identity 2: strip the common factors of two and count them in `shift`.

```c
    while (b != 0) {
        while ((b & 1) == 0) {
            b = b >> 1;
        }
        if (a > b) {
            uint32_t temp = a;
            a = b;
            b = temp;
        }
        b = b - a;
    }
```

`a` is made odd once before this loop and stays odd: it is always the smaller of two odd values. Each pass makes `b` odd (identity 3), orders the pair so the unsigned subtraction cannot wrap, and subtracts (identity 4).

### Assembly version

[`src/gcd/gcd.S`](https://github.com/PeteChiang1211/arch2026-progs/blob/5b823a401464e32a6507b22279481cbbee1ada75/src/gcd/gcd.S#L56-L92)

The first draft translated the C loop directly: top-tested `while` loops (a test, a body and a `j` back) and a three-instruction swap. It took **103** instructions per call, slower than the **99** of GCC at `-O1`.

Two changes:

1. **Bottom-tested halving loops.** After a subtraction `b` is even and nonzero, so it is halved at least once; the test moves after the shift and the `j` disappears: `srli`, `andi`, `beqz` per bit.
2. **Two copies of the subtract loop instead of a swap.** Copy A keeps the odd value in `a0` and reduces `a1`; copy B does the opposite. When the reduced value falls below the odd one, `bltu` branches into the other copy, which replaces the swap.

```asm
loop_a:
    srli    a1, a1, 1               # halve until odd
    andi    t1, a1, 1
    beqz    t1, loop_a
    bltu    a1, a0, to_b            # the odd value moved to a1
    sub     a1, a1, a0
    bnez    a1, loop_a
```

### Results

Instructions per call (`make cycles`, 16 benchmark inputs):

| -O1 | -O2 | -O3 | -Os | asm (first draft) | **asm** |
|---|---|---|---|---|---|
| 98.8 | 108.1 | 110.3 | 115.2 | 102.9 | **84.4** |

The assembly is **1.17x** faster than the best C build (`-O1`).

Worst call over the test inputs (budget: 4,000 for C, 1,500 for assembly):

| -O1 | -O2 | -O3 | -Os | asm |
|---|---|---|---|---|
| 365 | 399 | 399 | 479 | 298 |

Footprint (`size -A`, bytes; `.rodata`, `.data` and `.bss` are all 0):

| -O1 | -O2 | -O3 | -Os | asm |
|---|---|---|---|---|
| 160 | 160 | 160 | 120 | 184 |

The assembly is the fastest and the largest: the duplicated subtract loop trades 24 bytes over `-O2` for the removed swap.

> TODO: compare with the `-O1` / `-Os` listings (`make dump`) and explain why `-O1` beats `-O2` here.

### Verification

`tests/tgcd.c` runs both versions on directed cases, identities, all 65,536 pairs below 256, powers of two, shared factors of two, random operands and Fibonacci pairs (gcd(F(n), F(m)) = F(gcd(n, m))), and cross-checks the assembly against the C version. All 34 tests pass at `-O1`, `-O2`, `-O3` and `-Os`; the C version also passes on the host under AddressSanitizer and UndefinedBehaviorSanitizer.

### Real-world applications

> TODO: e.g. fraction reduction, RSA key checks, GCD in cryptographic libraries on cores without a divider.

---

## fixed: Bitwise adders and Q11.20 fixed-point multiply

Contract: [`src/fixed/fixed.h`](https://github.com/PeteChiang1211/arch2026-progs/blob/2b37892bfd17f9d11355b79d7571f58d3afb6fae/src/fixed/fixed.h). C version: [`src/fixed/fixed.c`](https://github.com/PeteChiang1211/arch2026-progs/blob/2b37892bfd17f9d11355b79d7571f58d3afb6fae/src/fixed/fixed.c). Assembly: [`src/fixed/fixed.S`](https://github.com/PeteChiang1211/arch2026-progs/blob/2b37892bfd17f9d11355b79d7571f58d3afb6fae/src/fixed/fixed.S).

### op1: addition from logic

Adding two bits gives a sum bit and a carry bit:

| x | y | sum | carry |
|---|---|---|---|
| 0 | 0 | 0 | 0 |
| 0 | 1 | 1 | 0 |
| 1 | 0 | 1 | 0 |
| 1 | 1 | 0 | 1 |

The sum column is XOR, the carry column is AND, and a carry belongs one position to the left. So a + b = (a ^ b) + ((a & b) << 1): one pass turns (a, b) into (partial sum, carries), and the loop repeats until no carry is left. This is how an adder is built from gates. Example, 5 + 3: (101, 011) → (110, 010) → (100, 100) → (000, 1000) → (1000, 0), four passes.

```c
    while (b != 0) {
        uint32_t c = (a & b) << 1;
        a = a ^ b;
        b = c;
        count = count + 1;
    }
```

### op2: subtraction

The quiz builds a − b from op1 as a + ~b + 1, but the budget of 40 instructions asks for the plain `sub`.

### op3: average without overflow

(a + b) / 2 overflows when a + b ≥ 2^32 even though the average fits. Halving first, a/2 + b/2 loses exactly 1 when both operands are odd (two discarded halves), so the C version is

```c
    return (a >> 1) + (b >> 1) + (a & b & 1);
```

The assembly uses the identity from op1 instead, a + b = 2(a & b) + (a ^ b), so floor((a + b) / 2) = (a & b) + ((a ^ b) >> 1): four instructions instead of five.

### q_mul: Q11.20 multiply

A stored value A represents A / 2^20. Multiplying two stored values scales the product by 2^40, one factor of 2^20 too many, so the product is shifted right by 20 after adding 2^19 (half a unit) to round, ties toward plus infinity.

The product needs 64 bits (2.0 × 2.0 is 2^21 × 2^21 = 2^42), and GCC lowers a 64-bit multiply to `__muldi3`, which the runtime does not supply. The C version takes the magnitudes, splits each into 16-bit halves and adds the four partial products with shifts, like long multiplication with two-digit groups: (ah·2^16 + al)(bh·2^16 + bl) = ah·bh·2^32 + (ah·bl + al·bh)·2^16 + al·bl. Each partial product fits in 32 bits.

The assembly replaces the four `__mulsi3` calls with one shift-and-add loop over the bits of the smaller magnitude, adding the 64-bit multiplicand (a register pair) to the 64-bit accumulator with an explicit carry (`sltu`). The loop stops when the multiplier has no set bits left.

### Results

Instructions per call (`make cycles`):

| Function | -O1 | -O2 | -O3 | -Os | asm | speedup |
|---|---|---|---|---|---|---|
| op1 | 24.8 | 22.1 | 24.2 | 24.7 | 22.1 | 1.00x |
| op2 | 4.0 | 4.0 | 5.9 | 4.0 | 4.0 | 1.00x |
| op3 | 9.0 | 9.0 | 10.9 | 9.0 | 7.0 | 1.29x |
| q_mul | 323.2 | 321.8 | 323.7 | 324.8 | 185.9 | 1.73x |

Worst calls (assembly / best C / assembly budget): op1 169 / 169 / 600, op3 9 / 11 / 40, q_mul 404 / 522 / 1,200.

Footprint `.text` (bytes): -O1 380, -O2 360, -O3 360, -Os 372, asm 224.

> TODO: why op1 and op2 cannot beat the compiler; error analysis of Q11.20 (resolution 2^-20, range [-2048, 2048)); real-world uses of fixed point.

## bf16: BFloat16

Contract: [`src/bf16/bf16.h`](https://github.com/PeteChiang1211/arch2026-progs/blob/d9aaf53c23655c1bd7ba6de7a3b4fd49df5252e6/src/bf16/bf16.h). C version: [`src/bf16/bf16.c`](https://github.com/PeteChiang1211/arch2026-progs/blob/d9aaf53c23655c1bd7ba6de7a3b4fd49df5252e6/src/bf16/bf16.c). Assembly: [`src/bf16/bf16.S`](https://github.com/PeteChiang1211/arch2026-progs/blob/d9aaf53c23655c1bd7ba6de7a3b4fd49df5252e6/src/bf16/bf16.S).

### Format

A floating-point number is binary scientific notation: (−1)^s × 1.f × 2^(e − 127).

| | sign | exponent (bias 127) | fraction |
|---|---|---|---|
| binary32 | 1 bit | 8 bits | 23 bits |
| bfloat16 | 1 bit | 8 bits | 7 bits |

bfloat16 is the top half of binary32: the same range (about 10^±38) with 8 bits of precision instead of 24, which is why machine learning hardware uses it. The leading 1 of a normal number is not stored (the hidden bit). Exponent 0xFF encodes infinity (fraction 0) and NaN (fraction nonzero); exponent 0 encodes zero and denormals.

### Narrowing

Taking the top 16 bits truncates. Adding half of the dropped unit first rounds to nearest; adding 0x7FFF plus the lowest kept bit instead of 0x8000 sends an exact tie to the even neighbor, so ties do not bias upward. Infinity and NaN skip the rounding, which could turn a NaN payload into a different value.

```c
    uint32_t bit16 = (f32bits >> 16) & 1;
    return (f32bits + 0x7FFF + bit16) >> 16;
```

### Multiply

Like (2 × 10^3)(3 × 10^4) = 6 × 10^7: the significands (with the hidden bit restored) multiply and the exponents add. The biased exponents each carry +127, so one bias is subtracted. The 8 × 8-bit product of two values in [128, 255] lies in [2^14, 2^16); when it reaches bit 15 it is shifted one more bit and the exponent grows by one, like 20 × 10^5 = 2 × 10^6. The contract truncates the fraction.

The assembly replaces the `__mulsi3` call with the quarter-square identity

x · y = q(x + y) − q(x − y),  q(n) = ⌊n² / 4⌋

which holds exactly for integers because x + y and x − y have the same parity, so both floors drop the same quarter. q(0) … q(510) is a 1,022-byte table that the assembler builds with `.rept`, and the product costs two loads and a subtraction.

### Square root

√(2^e · m) = 2^(e/2) · √m; an odd e lends a factor of two to m, like √(9 × 10^5) = √(90 × 10^4) = √90 × 10^2. The C version follows the contract: a binary search over [90, 256] for the largest mid with mid · mid / 128 ≤ m, eight passes with a multiply each.

The assembly observes that the answer depends only on the 7-bit fraction and the parity of the exponent, 256 cases, that it always lies in [128, 255] (so the renormalization never runs), and that it equals isqrt(128(m + 1) − 1). A 256-byte table holds every answer, and the result exponent is (exp + 127) >> 1 for both parities. [`mytests/bf16_sqrt_table.py`](https://github.com/PeteChiang1211/arch2026-progs/blob/d9aaf53c23655c1bd7ba6de7a3b4fd49df5252e6/mytests/bf16_sqrt_table.py) generates the table and checks each entry against the binary search.

### Results

Instructions per call (`make cycles`):

| Function | -O1 | -O2 | -O3 | -Os | asm | speedup |
|---|---|---|---|---|---|---|
| from_f32 | 11.1 | 12.2 | 13.8 | 12.2 | 11.2 | 0.98x |
| mul | 100.7 | 92.1 | 93.6 | 94.6 | 45.8 | 2.01x |
| sqrt | 327.6 | 326.1 | 327.6 | 336.3 | 18.1 | 18.06x |

Narrowing ties the compiler: both versions are the same eleven instructions, and the 0.1 difference comes from the caller. It is within the grader's margin of two instructions.

Worst calls (assembly / best C / assembly budget): from_f32 14 / 14 / 60, mul 114 / 174 / 400, sqrt 27 / 622 / 1,500. The worst multiply is a pair of denormals, whose normalization loops shift one bit at a time.

Footprint (bytes): C -O2 `.text` 828; assembly `.text` 508 plus `.rodata` 1,278 (the two tables). The tables trade space for time.

> TODO: error of the square root against a host reference (the contract states 0.3884% at worst); real-world uses of bfloat16.

## rubik

> TODO
