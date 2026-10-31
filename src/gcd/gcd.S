# gcd_u32_asm: binary GCD, hand-written RV32I.
#
# uint32_t gcd_u32_asm(uint32_t a, uint32_t b)   a in a0, b in a1, result in a0
#
# Registers: a0 and a1 hold the two operands, t0 = shift (the common power
# of two), t1 and t2 are scratch. Leaf function, no stack.
#
# The subtract loop exists in two copies that differ only in which register
# holds the smaller odd value: copy A keeps it in a0 and reduces a1, copy B
# keeps it in a1 and reduces a0. When the reduced value drops below the odd
# one, control moves to the other copy instead of swapping registers, which
# saves the three moves of a swap and the jumps of a top-tested loop.
#
# RV32I and Zicsr only: no mul, div, rem, no floating point, no compressed
# instructions. Tests: tests/tgcd.c.

    .text

    .globl  gcd_u32_asm
    .type   gcd_u32_asm, @function
    .align  2
gcd_u32_asm:
    beqz    a0, ret_b               # gcd(0, b) = b
    beqz    a1, done                # gcd(a, 0) = a

    # shift = trailing zeros of (a | b), the common factors of two.
    li      t0, 0
    or      t2, a0, a1
    andi    t1, t2, 1
    bnez    t1, strip_a             # usual case: no common factor of two
count_shift:
    srli    t2, t2, 1
    addi    t0, t0, 1
    andi    t1, t2, 1
    beqz    t1, count_shift
    srl     a0, a0, t0
    srl     a1, a1, t0

    # Make both operands odd; the remaining factors of two are not shared.
strip_a:
    andi    t1, a0, 1
    bnez    t1, strip_b
strip_a_loop:
    srli    a0, a0, 1
    andi    t1, a0, 1
    beqz    t1, strip_a_loop
strip_b:
    andi    t1, a1, 1
    bnez    t1, enter
strip_b_loop:
    srli    a1, a1, 1
    andi    t1, a1, 1
    beqz    t1, strip_b_loop

    # Both odd. gcd(a, b) = gcd(min, max - min), and max - min is even.
enter:
    bltu    a1, a0, to_b            # a > b: reduce a0 in copy B
    sub     a1, a1, a0
    beqz    a1, finish_a

    # Copy A: a0 odd and smallest, a1 even and nonzero.
loop_a:
    srli    a1, a1, 1               # halve until odd
    andi    t1, a1, 1
    beqz    t1, loop_a
    bltu    a1, a0, to_b            # the odd value moved to a1
    sub     a1, a1, a0
    bnez    a1, loop_a
finish_a:
    sll     a0, a0, t0              # put the common factors of two back
done:
    ret

to_b:
    sub     a0, a0, a1              # a0 = a0 - a1, even and nonzero
    # Copy B: a1 odd and smallest, a0 even and nonzero.
loop_b:
    srli    a0, a0, 1
    andi    t1, a0, 1
    beqz    t1, loop_b
    bltu    a0, a1, to_a            # the odd value moved back to a0
    sub     a0, a0, a1
    bnez    a0, loop_b
    sll     a0, a1, t0              # the result is in a1
    ret

to_a:
    sub     a1, a1, a0              # a1 = a1 - a0, even and nonzero
    j       loop_a

ret_b:
    mv      a0, a1
    ret
    .size   gcd_u32_asm, .-gcd_u32_asm
