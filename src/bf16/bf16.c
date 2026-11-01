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
    uint16_t sign = (a ^ b) & 0x8000;
    int ea = (a >> 7) & 0xFF;
    int eb = (b >> 7) & 0xFF;
    uint32_t ma = a & 0x7F;
    uint32_t mb = b & 0x7F;

    /* Inf and NaN, a first: NaN unchanged, Inf times 0 is NaN. */
    if (ea == 0xFF) {
        if (ma != 0)
            return a;
        if (eb == 0 && mb == 0)
            return 0x7FC0;
        return sign | 0x7F80;
    }
    if (eb == 0xFF) {
        if (mb != 0)
            return b;
        if (ea == 0 && ma == 0)
            return 0x7FC0;
        return sign | 0x7F80;
    }
    /* Zero times a finite value is zero with the product sign. */
    if ((ea == 0 && ma == 0) || (eb == 0 && mb == 0))
        return sign;

    /* Restore the hidden one; shift a denormal up until it has one. */
    int adj = 0;
    if (ea == 0) {
        while ((ma & 0x80) == 0) {
            ma <<= 1;
            adj--;
        }
        ea = 1;
    } else {
        ma |= 0x80;
    }
    if (eb == 0) {
        while ((mb & 0x80) == 0) {
            mb <<= 1;
            adj--;
        }
        eb = 1;
    } else {
        mb |= 0x80;
    }

    /* Significands multiply, biased exponents add minus one bias. */
    uint32_t m = ma * mb;
    int e = ea + eb - 127 + adj;

    /* Renormalize by one bit when the product reaches bit 15; truncate. */
    if (m & 0x8000) {
        m = (m >> 8) & 0x7F;
        e = e + 1;
    } else {
        m = (m >> 7) & 0x7F;
    }

    if (e >= 0xFF)
        return sign | 0x7F80;
    if (e <= 0) {
        if (e < -6)
            return sign;
        m = m >> (1 - e);
        e = 0;
    }
    return sign | (e << 7) | m;
}

uint16_t bf16_sqrt(uint16_t a)
{
    int exp = (a >> 7) & 0xFF;
    uint32_t frac = a & 0x7F;

    /* NaN unchanged, -Inf gives NaN, +Inf unchanged. */
    if (exp == 0xFF) {
        if (frac != 0)
            return a;
        if (a & 0x8000)
            return 0x7FC0;
        return a;
    }
    if (exp == 0 && frac == 0) /* both zeros give +0 */
        return 0;
    if (a & 0x8000) /* negative nonzero */
        return 0x7FC0;
    if (exp == 0) /* denormals give +0 */
        return 0;

    /* sqrt(2^e * m) = 2^(e/2) * sqrt(m); an odd e lends a factor of two. */
    int e = exp - 127;
    uint32_t m = 0x80 | frac;
    if (e & 1) {
        m = m << 1;
        e = e - 1;
    }
    int new_exp = e / 2 + 127;

    /* Binary search for the largest mid with mid * mid / 128 <= m. */
    uint32_t low = 90, high = 256, result = 128;
    while (low <= high) {
        uint32_t mid = (low + high) >> 1;
        if ((mid * mid) / 128 <= m) {
            result = mid;
            low = mid + 1;
        } else {
            high = mid - 1;
        }
    }

    /* Bring the result back into [128, 256). */
    if (result >= 256) {
        result >>= 1;
        new_exp++;
    } else {
        while (result < 128 && new_exp > 1) {
            result <<= 1;
            new_exp--;
        }
    }
    if (new_exp >= 0xFF)
        return 0x7F80;
    if (new_exp <= 0)
        return 0;
    return (new_exp << 7) | (result & 0x7F);
}
