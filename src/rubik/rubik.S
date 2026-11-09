# rubik_solve_asm: optimal 2x2x2 solver, hand-written RV32I.
#
# int rubik_solve_asm(const char *state, char *out, size_t cap)
#     a0 = state, a1 = out, a2 = cap; returns the length, -1 or -2 in a0.
#
# The same iterative deepening search as rubik.c, rearranged so that a
# node costs few instructions:
#
# * Corners 0 and 1 are one coordinate, the address of a 20-byte record
#   in rubik_pairs (see mytests/rubik_tables.c). A record holds the
#   addresses of its rows of the two distance tables and of the records
#   after a quarter turn of each face, so a turn of the pair is one load
#   and the two table rows need no multiply.
# * The distance tables are stored transposed (rubik_pdist_t,
#   rubik_odist_t): the row comes from the record, the column is the plain
#   permutation or orientation rank.
# * A child is tested before it is entered: a pruned child, the common
#   case, costs no stores; only a child that passes is pushed.
# * The recursion is a loop over 32-byte frames in .bss, one per depth:
#     0 P, 4 O, 8 R   the state at this depth (ranks and pair record)
#     12 M            the move being tried, face * 3 + turn
#     16, 20          the perm_move and orient_move rows of the face
#     24 F            the offset of the face in a pair record (8, 12, 16)
#     28 T            turns of this face still to try
#
# Registers in the search:
#   s0 frame of the current depth    s1, s2, s3 P, O, R of this depth
#   s4 moves left at this depth      s5 M     s6, s7 perm, orient rows
#   s8 F    s9, s10, s11 the child: P, O, R after the latest turn
#   a3, a4 perm_move, orient_move    a5 frame 0    a6 F of the previous
#   move (-1 at depth 0)    a7 turns left    t4 = 20 (past the last face)
#   t5 the move limit    t6 = 10080 (one face of perm_move)
#   t0, t1, t2 scratch
#
# RV32I only: no multiply, divide or CSR, no call. Tests: tests/trubik.c.

    .equ    PERM_ROW, 10080         # 5040 halfwords per face
    .equ    ORIENT_ROW, 1458        # 729 halfwords per face
    .equ    FRAME, 32

    .text
    .globl  rubik_solve_asm
    .type   rubik_solve_asm, @function
    .align  2
rubik_solve_asm:
    addi    sp, sp, -80
    sw      s0, 0(sp)
    sw      s1, 4(sp)
    sw      s2, 8(sp)
    sw      s3, 12(sp)
    sw      s4, 16(sp)
    sw      s5, 20(sp)
    sw      s6, 24(sp)
    sw      s7, 28(sp)
    sw      s8, 32(sp)
    sw      s9, 36(sp)
    sw      s10, 40(sp)
    sw      s11, 44(sp)
    sw      a1, 48(sp)              # out
    sw      a2, 52(sp)              # cap
                                    # p[7] at 56(sp), o[7] at 64(sp)

    # The state must be exactly 14 characters long.
    li      t0, 0
    li      t1, 14
len_loop:
    add     t2, a0, t0
    lbu     t3, 0(t2)
    beqz    t3, invalid
    addi    t0, t0, 1
    bne     t0, t1, len_loop
    lbu     t3, 14(a0)
    bnez    t3, invalid

    # Corners '1'..'7' without repeats, twists '1'..'3'. Unsigned compares
    # also reject a character below '1'.
    li      t0, 0                   # i
    li      t4, 0                   # mask of the corners seen
    li      t5, 0                   # sum of the twists
    li      t6, 7
    li      a3, 3
digit_loop:
    add     t2, a0, t0
    lbu     t1, 0(t2)
    addi    t1, t1, -49             # corner c = ch - '1'
    bgeu    t1, t6, invalid
    lbu     t3, 7(t2)
    addi    t3, t3, -49             # twist t
    bgeu    t3, a3, invalid
    li      a4, 1
    sll     a4, a4, t1
    and     a5, t4, a4
    bnez    a5, invalid             # c seen before
    or      t4, t4, a4
    add     t5, t5, t3
    add     a5, sp, t0
    sb      t1, 56(a5)
    sb      t3, 64(a5)
    addi    t0, t0, 1
    bne     t0, t6, digit_loop
sum_loop:                           # the sum modulo 3, by subtraction
    blt     t5, a3, sum_done
    addi    t5, t5, -3
    j       sum_loop
sum_done:
    bnez    t5, invalid

    # Permutation rank: each position counts the smaller corners to its
    # right, weighted by (6 - i)!; the weight is added that many times.
    li      s1, 0
    li      t0, 0
    la      a3, rubik_fact
lehmer_i:
    add     t2, sp, t0
    lbu     t1, 56(t2)              # p[i]
    addi    t3, t0, 1
    li      t4, 0                   # smaller
lehmer_j:
    bge     t3, t6, lehmer_add
    add     t2, sp, t3
    lbu     t5, 56(t2)
    sltu    t5, t5, t1
    add     t4, t4, t5
    addi    t3, t3, 1
    j       lehmer_j
lehmer_add:
    slli    t2, t0, 1
    add     t2, a3, t2
    lhu     t2, 0(t2)               # (6 - i)!
lehmer_mul:
    beqz    t4, lehmer_next
    add     s1, s1, t2
    addi    t4, t4, -1
    j       lehmer_mul
lehmer_next:
    addi    t0, t0, 1
    bne     t0, t6, lehmer_i

    # Orientation rank: the first six twists in base 3.
    li      s2, 0
    li      t0, 0
    li      t1, 6
orient_loop:
    add     t2, sp, t0
    lbu     t3, 64(t2)
    slli    t4, s2, 1
    add     s2, s2, t4
    add     s2, s2, t3
    addi    t0, t0, 1
    bne     t0, t1, orient_loop

    # Positions q0, q1 and twists of corners 0 and 1 (a3, a4 and a5, a6).
    li      t0, 0
    li      t5, 1
corner_loop:
    add     t2, sp, t0
    lbu     t1, 56(t2)
    lbu     t3, 64(t2)
    bnez    t1, corner_one
    mv      a3, t0
    mv      a4, t3
corner_one:
    bne     t1, t5, corner_next
    mv      a5, t0
    mv      a6, t3
corner_next:
    addi    t0, t0, 1
    bne     t0, t6, corner_loop
    # Record id = (q0 * 7 + q1) * 9 + t0 * 3 + t1, at rubik_pairs + 20 id.
    slli    t0, a3, 3
    sub     t0, t0, a3
    add     t0, t0, a5
    slli    t1, t0, 3
    add     t0, t1, t0
    slli    t1, a4, 1
    add     t1, t1, a4
    add     t0, t0, t1
    add     t0, t0, a6
    slli    t1, t0, 4
    slli    t0, t0, 2
    add     t0, t0, t1
    la      s3, rubik_pairs
    add     s3, s3, t0

    la      a5, rubik_frames
    # The solved state needs no search.
    lw      t1, 0(s3)
    add     t1, t1, s1
    lbu     t1, 0(t1)
    lw      t2, 4(s3)
    add     t2, t2, s2
    lbu     t2, 0(t2)
    bgeu    t1, t2, root_h
    mv      t1, t2
root_h:
    li      t0, 0                   # length 0
    beqz    t1, output
    mv      t5, t1                  # first move limit: the root bound

    la      a3, rubik_perm_move
    la      a4, rubik_orient_move
    li      t4, 20
    li      t6, PERM_ROW

bound_loop:                         # one pass with move limit t5
    mv      s0, a5
    sw      s1, 0(s0)
    sw      s2, 4(s0)
    sw      s3, 8(s0)
    mv      s4, t5
    li      a6, -1
level_start:                        # first face of a new depth
    li      s5, 0
    mv      s6, a3
    mv      s7, a4
    li      s8, 8
face_loop:
    beq     s8, a6, skip_face       # never turn the previous face again
    mv      s9, s1
    mv      s10, s2
    mv      s11, s3
    li      a7, 3
turn_loop:                          # one more quarter turn of this face
    slli    t0, s9, 1
    add     t0, t0, s6
    lhu     s9, 0(t0)
    slli    t0, s10, 1
    add     t0, t0, s7
    lhu     s10, 0(t0)
    add     t0, s11, s8
    lw      s11, 0(t0)
    lw      t1, 0(s11)              # h = max of the two lower bounds
    add     t1, t1, s9
    lbu     t1, 0(t1)
    lw      t2, 4(s11)
    add     t2, t2, s10
    lbu     t2, 0(t2)
    bgeu    t1, t2, turn_h
    mv      t1, t2
turn_h:
    beqz    t1, found               # the child is solved
    blt     t1, s4, descend         # it can be solved within the limit
next_turn:
    addi    s5, s5, 1
    addi    a7, a7, -1
    bnez    a7, turn_loop
    j       next_face
skip_face:
    addi    s5, s5, 3
next_face:
    addi    s8, s8, 4
    beq     s8, t4, pop
    add     s6, s6, t6
    addi    s7, s7, ORIENT_ROW
    j       face_loop

descend:                            # save this depth, enter the child
    sw      s5, 12(s0)
    sw      s6, 16(s0)
    sw      s7, 20(s0)
    sw      s8, 24(s0)
    sw      a7, 28(s0)
    addi    s0, s0, FRAME
    mv      s1, s9
    mv      s2, s10
    mv      s3, s11
    sw      s1, 0(s0)
    sw      s2, 4(s0)
    sw      s3, 8(s0)
    addi    s4, s4, -1
    mv      a6, s8
    j       level_start

pop:                                # every move at this depth is tried
    beq     s0, a5, bound_fail
    lw      s9, 0(s0)               # the child state to turn further
    lw      s10, 4(s0)
    lw      s11, 8(s0)
    addi    s0, s0, -FRAME
    lw      s1, 0(s0)
    lw      s2, 4(s0)
    lw      s3, 8(s0)
    lw      s5, 12(s0)
    lw      s6, 16(s0)
    lw      s7, 20(s0)
    lw      s8, 24(s0)
    lw      a7, 28(s0)
    addi    s4, s4, 1
    li      a6, -1
    beq     s0, a5, next_turn
    lw      a6, -FRAME + 24(s0)     # face of the previous depth
    j       next_turn

bound_fail:                         # no solution within t5 moves
    addi    t5, t5, 1
    j       bound_loop

found:                              # moves 0..depth are in the frames
    sw      s5, 12(s0)
    sub     t0, s0, a5
    srli    t0, t0, 5
    addi    t0, t0, 1               # length

output:                             # t0 = length, moves at 12 + 32 i
    lw      a1, 48(sp)
    lw      a2, 52(sp)
    slli    a3, t0, 5
    add     a3, a5, a3              # past the last frame
    la      t3, rubik_name_len
    li      t1, 1                   # the terminating null
    mv      t2, a5
need_loop:
    beq     t2, a3, need_done
    lw      a4, 12(t2)
    add     a4, t3, a4
    lbu     a4, 0(a4)
    add     t1, t1, a4
    addi    t1, t1, 1               # a space after each move ...
    addi    t2, t2, FRAME
    j       need_loop
need_done:
    beqz    t0, need_check
    addi    t1, t1, -1              # ... but not after the last one
need_check:
    bgtu    t1, a2, too_small

    la      t3, rubik_names
    mv      a4, a1
    mv      t2, a5
    li      a7, ' '
write_loop:
    beq     t2, a3, write_done
    beq     t2, a5, write_name      # no space before the first move
    sb      a7, 0(a4)
    addi    a4, a4, 1
write_name:
    lw      a6, 12(t2)
    slli    a6, a6, 1
    add     a6, t3, a6
    lbu     t1, 0(a6)
    sb      t1, 0(a4)
    addi    a4, a4, 1
    lbu     t1, 1(a6)
    beqz    t1, write_next
    sb      t1, 0(a4)
    addi    a4, a4, 1
write_next:
    addi    t2, t2, FRAME
    j       write_loop
write_done:
    sb      zero, 0(a4)
    mv      a0, t0
    j       epilogue

too_small:                          # leave an empty string if there is room
    beqz    a2, too_small_ret
    sb      zero, 0(a1)
too_small_ret:
    li      a0, -2
    j       epilogue

invalid:
    li      a0, -1
epilogue:
    lw      s0, 0(sp)
    lw      s1, 4(sp)
    lw      s2, 8(sp)
    lw      s3, 12(sp)
    lw      s4, 16(sp)
    lw      s5, 20(sp)
    lw      s6, 24(sp)
    lw      s7, 28(sp)
    lw      s8, 32(sp)
    lw      s9, 36(sp)
    lw      s10, 40(sp)
    lw      s11, 44(sp)
    addi    sp, sp, 80
    ret
    .size   rubik_solve_asm, .-rubik_solve_asm

    .section .rodata
    .align  1
rubik_fact:
    .hword  720, 120, 24, 6, 2, 1, 1
rubik_name_len:                     # characters of move face * 3 + turn
    .byte   1, 2, 2, 1, 2, 2, 1, 2, 2
rubik_names:                        # two bytes per move, 0 when unused
    .byte   'R', 0, 'R', '2', 'R', 39, 'B', 0, 'B', '2', 'B', 39
    .byte   'D', 0, 'D', '2', 'D', 39

    .bss
    .align  2
rubik_frames:                       # one frame per depth, at most 12 deep
    .space  13 * FRAME
