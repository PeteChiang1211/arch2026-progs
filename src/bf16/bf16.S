# BFloat16 routines: hand-written RV32I.
#
# uint16_t bf16_from_f32_asm(uint32_t f32bits)   a0 -> a0
# uint16_t bf16_mul_asm(uint16_t a, uint16_t b)  a0, a1 -> a0
# uint16_t bf16_sqrt_asm(uint16_t a)             a0 -> a0
#
# RV32I and Zicsr only: no mul, div, rem, no floating point, no compressed
# instructions. Tests: tests/tbf16.c.
#
# The two 16-bit arguments arrive zero-extended (unsigned narrow types in
# the RISC-V calling convention), so bit 15 is the sign and a << 17 keeps
# exactly the exponent and fraction fields.

    .text

# bf16_from_f32: round a binary32 pattern to nearest, ties to even.
# Registers: a0 = pattern, t0 = exponent field, t1 = scratch, t2 = mask.
    .globl  bf16_from_f32_asm
    .type   bf16_from_f32_asm, @function
    .align  2
bf16_from_f32_asm:
    lui     t2, 0x7F800             # exponent mask 0x7F800000
    and     t0, a0, t2
    beq     t0, t2, f32_top         # Inf and NaN: no rounding
    srli    t1, a0, 16              # lowest kept bit decides the tie
    andi    t1, t1, 1
    add     a0, a0, t1
    lui     t1, 0x8                 # + 0x8000 - 1 = + 0x7FFF
    add     a0, a0, t1
    addi    a0, a0, -1
f32_top:
    srli    a0, a0, 16
    ret
    .size   bf16_from_f32_asm, .-bf16_from_f32_asm

# bf16_mul: the contract of bf16.h, with the 8-bit by 8-bit significand
# product taken from a quarter-square table instead of a multiply:
#   x * y = q(x + y) - q(x - y),  q(n) = floor(n * n / 4).
# For x, y in [128, 255] the sum and the difference have the same parity, so
# the two floors drop the same quarter and the identity is exact.
# Registers: t0 = exponent of a, then of the result; t1 = exponent of b;
# t2, t3 = significands; t4, t5 = scratch; t6 = sign of the result.
    .globl  bf16_mul_asm
    .type   bf16_mul_asm, @function
    .align  2
bf16_mul_asm:
    xor     t6, a0, a1              # sign = (a ^ b) & 0x8000
    srli    t6, t6, 15
    slli    t6, t6, 15
    srli    t0, a0, 7
    andi    t0, t0, 0xFF
    srli    t1, a1, 7
    andi    t1, t1, 0xFF
    andi    t2, a0, 0x7F
    andi    t3, a1, 0x7F
    li      t4, 0xFF
    beq     t0, t4, mul_a_special
    beq     t1, t4, mul_b_special
    slli    t4, a0, 17              # a is a zero of either sign
    beqz    t4, mul_ret_sign
    slli    t4, a1, 17
    beqz    t4, mul_ret_sign

    # Restore the hidden one; a denormal is shifted up until it has one,
    # each shift taking one off the exponent (which starts at 1).
    beqz    t0, mul_a_denormal
    ori     t2, t2, 0x80
mul_a_ready:
    beqz    t1, mul_b_denormal
    ori     t3, t3, 0x80
mul_b_ready:
    add     t0, t0, t1              # biased exponents add less one bias
    addi    t0, t0, -127

    # Significand product from the quarter-square table (halfwords).
    la      t5, mul_qsq
    add     t4, t2, t3              # sum in [256, 510]
    slli    t4, t4, 1
    add     t4, t5, t4
    lhu     t4, 0(t4)
    sub     t1, t2, t3              # |difference| in [0, 127]
    srai    a1, t1, 31
    xor     t1, t1, a1
    sub     t1, t1, a1
    slli    t1, t1, 1
    add     t1, t5, t1
    lhu     t1, 0(t1)
    sub     t4, t4, t1              # product in [16384, 65025]

    # Renormalize by one bit at bit 15; the fraction is truncated.
    srli    t1, t4, 15
    add     t0, t0, t1
    addi    t1, t1, 7
    srl     t4, t4, t1
    andi    t4, t4, 0x7F

    li      t1, 0xFF
    bge     t0, t1, mul_ret_inf
    blez    t0, mul_small
    slli    t0, t0, 7
    or      a0, t6, t0
    or      a0, a0, t4
    ret

mul_small:                          # exponent <= 0: denormal or zero
    li      t1, -6
    blt     t0, t1, mul_ret_sign
    li      t1, 1
    sub     t1, t1, t0              # shift right by 1 - exponent
    srl     t4, t4, t1
    or      a0, t6, t4
    ret

mul_a_denormal:
    li      t0, 1
1:  slli    t2, t2, 1
    addi    t0, t0, -1
    andi    t4, t2, 0x80
    beqz    t4, 1b
    j       mul_a_ready

mul_b_denormal:
    li      t1, 1
1:  slli    t3, t3, 1
    addi    t1, t1, -1
    andi    t4, t3, 0x80
    beqz    t4, 1b
    j       mul_b_ready

mul_a_special:                      # a is Inf or NaN
    bnez    t2, mul_ret             # NaN a: unchanged
    slli    t4, a1, 17
    beqz    t4, mul_ret_nan         # Inf times zero
    j       mul_ret_inf             # Inf, whatever b is
mul_b_special:                      # b is Inf or NaN, a is finite
    bnez    t3, mul_ret_b           # NaN b: unchanged
    slli    t4, a0, 17
    beqz    t4, mul_ret_nan
mul_ret_inf:
    li      a0, 0x7F80
    or      a0, a0, t6
    ret
mul_ret_nan:
    li      a0, 0x7FC0
    ret
mul_ret_b:
    mv      a0, a1
mul_ret:
    ret
mul_ret_sign:
    mv      a0, t6
    ret
    .size   bf16_mul_asm, .-bf16_mul_asm

# bf16_sqrt: the contract of bf16.h. For a positive normal input the
# result exponent is (exp + 127) >> 1 for both parities of exp, and the
# result fraction depends only on the input fraction and the parity, so it
# comes from a 256-byte table: entry frac | (exp even) << 7 holds the low 7
# bits of isqrt(128 * (m + 1) - 1), the largest mid with mid * mid / 128 <= m,
# where m = 128 + frac (exp odd) or 2 * (128 + frac) (exp even). That root
# always lies in [128, 255], so no renormalization is needed, and the
# exponent stays in [64, 190], so neither overflow nor underflow occurs.
# The table is generated and checked against the binary search of the
# contract by mytests/bf16_sqrt_table.py.
# Registers: t0 = exponent, t1 = fraction, t2, t3 = scratch.
    .globl  bf16_sqrt_asm
    .type   bf16_sqrt_asm, @function
    .align  2
bf16_sqrt_asm:
    srli    t0, a0, 7
    andi    t0, t0, 0xFF
    andi    t1, a0, 0x7F
    li      t2, 0xFF
    beq     t0, t2, sqrt_special
    slli    t2, a0, 17              # either zero gives +0
    beqz    t2, sqrt_zero
    srli    t2, a0, 15              # negative nonzero gives NaN
    bnez    t2, sqrt_nan
    beqz    t0, sqrt_zero           # denormals give +0

    andi    t2, t0, 1               # table index: frac | (exp even) << 7
    xori    t2, t2, 1
    slli    t2, t2, 7
    or      t2, t2, t1
    la      t3, sqrt_frac
    add     t3, t3, t2
    lbu     t1, 0(t3)
    addi    t0, t0, 127             # result exponent (exp + 127) >> 1
    srli    t0, t0, 1
    slli    t0, t0, 7
    or      a0, t0, t1
    ret

sqrt_special:                       # NaN and +Inf unchanged, -Inf is NaN
    bnez    t1, sqrt_ret
    srli    t2, a0, 15
    beqz    t2, sqrt_ret
sqrt_nan:
    li      a0, 0x7FC0
sqrt_ret:
    ret
sqrt_zero:
    li      a0, 0
    ret
    .size   bf16_sqrt_asm, .-bf16_sqrt_asm

    .section .rodata
    .align  1
# q(n) = floor(n * n / 4) for n in [0, 510], built by the assembler.
mul_qsq:
    .set    n, 0
    .rept   511
    .hword  (n * n) / 4
    .set    n, n + 1
    .endr

# Square root fractions, see bf16_sqrt_asm.
sqrt_frac:
    .byte     0,   0,   1,   1,   2,   2,   3,   3,   4,   4,   5,   5,   6,   6,   7,   7
    .byte     8,   8,   9,   9,  10,  10,  11,  11,  11,  12,  12,  13,  13,  14,  14,  15
    .byte    15,  15,  16,  16,  17,  17,  18,  18,  19,  19,  19,  20,  20,  21,  21,  22
    .byte    22,  22,  23,  23,  24,  24,  25,  25,  25,  26,  26,  27,  27,  27,  28,  28
    .byte    29,  29,  29,  30,  30,  31,  31,  31,  32,  32,  33,  33,  33,  34,  34,  35
    .byte    35,  35,  36,  36,  37,  37,  37,  38,  38,  39,  39,  39,  40,  40,  40,  41
    .byte    41,  42,  42,  42,  43,  43,  43,  44,  44,  45,  45,  45,  46,  46,  46,  47
    .byte    47,  47,  48,  48,  49,  49,  49,  50,  50,  50,  51,  51,  51,  52,  52,  53
    .byte    53,  54,  54,  55,  56,  56,  57,  58,  58,  59,  60,  60,  61,  62,  62,  63
    .byte    64,  64,  65,  66,  66,  67,  68,  68,  69,  70,  70,  71,  72,  72,  73,  74
    .byte    74,  75,  75,  76,  77,  77,  78,  79,  79,  80,  80,  81,  82,  82,  83,  83
    .byte    84,  85,  85,  86,  86,  87,  88,  88,  89,  89,  90,  91,  91,  92,  92,  93
    .byte    93,  94,  95,  95,  96,  96,  97,  97,  98,  99,  99, 100, 100, 101, 101, 102
    .byte   103, 103, 104, 104, 105, 105, 106, 106, 107, 107, 108, 109, 109, 110, 110, 111
    .byte   111, 112, 112, 113, 113, 114, 114, 115, 115, 116, 117, 117, 118, 118, 119, 119
    .byte   120, 120, 121, 121, 122, 122, 123, 123, 124, 124, 125, 125, 126, 126, 127, 127
