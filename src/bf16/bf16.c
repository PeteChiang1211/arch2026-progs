#include "bf16.h"

/* Dummies: every function returns 0. Replace with the real routines. */
uint16_t bf16_from_f32(uint32_t f32bits)
{
    uint32_t exp = (f32bits >> 23) & 0xFF;
    if (exp == 0xFF) /* Inf and NaN: keep the top half, no rounding */
        return f32bits >> 16;

    /* Round to nearest, ties to even: 0x7FFF plus the lowest kept bit. */
    uint32_t bit16 = (f32bits >> 16) & 1;
    return (f32bits + 0x7FFF + bit16) >> 16;
}

uint16_t bf16_mul(uint16_t a, uint16_t b)
{
    (void) a;
    (void) b;
    return 0;
}

uint16_t bf16_sqrt(uint16_t a)
{
    (void) a;
    return 0;
}
