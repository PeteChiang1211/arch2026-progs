# Assignment 2: Complete Applications

contributed by < [`PeteChiang1211`](https://github.com/PeteChiang1211) >

Repository: [PeteChiang1211/arch2026-progs](https://github.com/PeteChiang1211/arch2026-progs)

## Progress log

| Date | Program | What changed | Effect | Commit |
|---|---|---|---|---|
| 2026-10-31 | setup | Forked the framework, installed the xPack toolchain, built rv32emu | `make toolchain` passes, skeleton scores 0 | — |
| 2026-10-31 | gcd | C version of the binary GCD | all C tests pass, worst call 399 instructions at `-O2` (budget 4,000) | [`bd483ec`](https://github.com/PeteChiang1211/arch2026-progs/commit/bd483ec137608a109433bb72df4aaee5836a89f6) |
| 2026-10-31 | gcd | RV32I assembly version | 84.4 instructions per call, 1.17x the best C build; gcd passes, total 25/100 | [`5b823a4`](https://github.com/PeteChiang1211/arch2026-progs/commit/5b823a401464e32a6507b22279481cbbee1ada75) |
| | fixed | | | |
| | bf16 | | | |
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

> TODO

## bf16: BFloat16

> TODO

## rubik

> TODO
