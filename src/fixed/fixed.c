#include "fixed.h"

/* Dummies: every function returns 0. Replace with the real routines. */
uint32_t op1(uint32_t a, uint32_t b, int *n)
{
    int count = 0;
    while (b != 0) {
        uint32_t c = (a & b) << 1;
        a = a ^ b;
        b = c;
        count = count + 1;
    }
    *n = count;
    return a;
}

uint32_t op2(uint32_t a, uint32_t b)
{
    a = a - b;
    return a;
}

uint32_t op3(uint32_t a, uint32_t b)
{
    return (a >> 1) + (b >> 1) + (a & b & 1);
}

int32_t q_mul(int32_t a, int32_t b)
{
    /* The product is negative when exactly one operand is. */
    int negative = (a < 0) != (b < 0);

    /* Magnitudes as unsigned values; INT32_MIN maps to 2^31. */
    uint32_t ua = (a < 0) ? 0u - (uint32_t) a : (uint32_t) a;
    uint32_t ub = (b < 0) ? 0u - (uint32_t) b : (uint32_t) b;

    /* Split each magnitude into 16-bit halves. */
    uint32_t ah = ua >> 16;
    uint32_t al = ua & 0xFFFF;
    uint32_t bh = ub >> 16;
    uint32_t bl = ub & 0xFFFF;

    /* Four 16 x 16 products fit in 32 bits; combine them in 64 bits so
     * that no 64-bit multiply (and no __muldi3) is needed.
     */
    uint64_t p = ((uint64_t) (ah * bh) << 32) + ((uint64_t) (ah * bl) << 16) +
                 ((uint64_t) (al * bh) << 16) + (uint64_t) (al * bl);

    /* At most 2^62, so the signed value cannot overflow. */
    int64_t prod = negative ? -(int64_t) p : (int64_t) p;

    /* Add half a unit, then shift right arithmetically by Q. */
    return (int32_t) ((prod + (1 << (Q - 1))) >> Q);
}
