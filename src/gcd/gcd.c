#include "gcd.h"

uint32_t gcd_u32(uint32_t a, uint32_t b)
{
    /* gcd(x, 0) = gcd(0, x) = x */
    if (a == 0)
        return b;
    if (b == 0)
        return a;

    /* Both even: factor out the common power of two. */
    int shift = 0;

    while ((a & 1) == 0 && (b & 1) == 0) {
        a = a >> 1;
        b = b >> 1;
        shift = shift + 1;
    }
    /* Make a odd; it stays odd from here on. */
    while ((a & 1) == 0) {
        a = a >> 1;
    }
    /* Both odd: subtract the smaller from the larger until b is 0. */
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
    a = a << shift;
    return a;
}
