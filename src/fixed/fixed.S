# op1, op2, op3 and q_mul: hand-written RV32I.
#
# uint32_t op1_asm(uint32_t a, uint32_t b, int *n)   a0, a1, a2 -> a0
# uint32_t op2_asm(uint32_t a, uint32_t b)           a0, a1 -> a0
# uint32_t op3_asm(uint32_t a, uint32_t b)           a0, a1 -> a0
# int32_t  q_mul_asm(int32_t a, int32_t b)           a0, a1 -> a0
#
# RV32I and Zicsr only: no mul, div, rem, no floating point, no compressed
# instructions. q_mul forms a 64-bit product in a register pair. Tests:
# tests/tfixed.c.

    .text

# op1: a + b with AND, XOR and a shift. Each pass: carry = (a & b) << 1,
# a = a ^ b, b = carry, until the carry is zero. *n = number of passes.
# Registers: a0 = partial sum, a1 = carry word, a2 = n, t0 = pass count,
# t1 = scratch.
    .globl  op1_asm
    .type   op1_asm, @function
    .align  2
op1_asm:
    li      t0, 0
    beqz    a1, op1_store           # no carry: zero passes
op1_loop:
    and     t1, a0, a1              # positions that carry
    xor     a0, a0, a1              # sum without the carries
    slli    a1, t1, 1               # the carries move one bit up
    addi    t0, t0, 1
    bnez    a1, op1_loop
op1_store:
    sw      t0, 0(a2)
    ret
    .size   op1_asm, .-op1_asm

# op2: a - b modulo 2^32, one instruction.
    .globl  op2_asm
    .type   op2_asm, @function
    .align  2
op2_asm:
    sub     a0, a0, a1
    ret
    .size   op2_asm, .-op2_asm

# op3: floor((a + b) / 2) without overflow. a + b = 2 * (a & b) + (a ^ b),
# so the average is (a & b) + ((a ^ b) >> 1): the shared bits count in
# full, the differing bits count half, and the dropped bit is the one the
# floor discards. Four instructions instead of the five of the C form
# (a >> 1) + (b >> 1) + (a & b & 1).
    .globl  op3_asm
    .type   op3_asm, @function
    .align  2
op3_asm:
    and     t0, a0, a1
    xor     a0, a0, a1
    srli    a0, a0, 1
    add     a0, a0, t0
    ret
    .size   op3_asm, .-op3_asm

# q_mul: Q11.20 product, (a * b + 2^19) >> 20 on the 64-bit product,
# keeping the low 32 bits.
#
# RV32I has no multiply and the runtime has no __muldi3, so the product of
# the magnitudes is formed by shift-and-add: for each set bit of the
# multiplier, the multiplicand (a 64-bit value in t1:a0) is added to the
# accumulator t3:t2. The smaller magnitude is the multiplier and the loop
# stops when it runs out of bits, so small operands cost few passes.
#
# Registers: a0 = multiplicand low, t1 = multiplicand high, a1 = multiplier,
# t2:t3 = product low:high, t6 = sign of the result (bit 31), t0 = scratch.
    .globl  q_mul_asm
    .type   q_mul_asm, @function
    .align  2
q_mul_asm:
    xor     t6, a0, a1              # bit 31 set: the product is negative
    srai    t0, a0, 31              # |a| = (a ^ s) - s, s = a >> 31
    xor     a0, a0, t0
    sub     a0, a0, t0
    srai    t0, a1, 31              # |b|; |INT32_MIN| = 2^31 as unsigned
    xor     a1, a1, t0
    sub     a1, a1, t0
    bgeu    a0, a1, q_ordered       # make a1 the smaller magnitude
    mv      t0, a0
    mv      a0, a1
    mv      a1, t0
q_ordered:
    li      t1, 0
    li      t2, 0
    li      t3, 0
    beqz    a1, q_sign
q_loop:
    andi    t0, a1, 1
    beqz    t0, q_shift
    add     t2, t2, a0              # product += multiplicand, 64-bit
    sltu    t0, t2, a0              # carry out of the low word
    add     t3, t3, t1
    add     t3, t3, t0
q_shift:
    srli    t0, a0, 31              # multiplicand <<= 1, 64-bit
    slli    t1, t1, 1
    or      t1, t1, t0
    slli    a0, a0, 1
    srli    a1, a1, 1               # next multiplier bit
    bnez    a1, q_loop

q_sign:
    bgez    t6, q_round
    seqz    t0, t2                  # -x = ~x + 1 on the pair: the +1
    neg     t2, t2                  # reaches the high word only when the
    not     t3, t3                  # low word is zero
    add     t3, t3, t0
q_round:
    lui     t0, 0x80                # 2^19, half a unit
    add     t2, t2, t0
    sltu    t0, t2, t0
    add     t3, t3, t0
    srli    t2, t2, 20              # low 32 bits of the 64-bit value
    slli    t3, t3, 12              # shifted right by 20; an arithmetic
    or      a0, t2, t3              # shift gives the same low word
    ret
    .size   q_mul_asm, .-q_mul_asm
