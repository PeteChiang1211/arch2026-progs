#!/usr/bin/env python3
"""Generate the square root table of src/bf16/bf16.S.

Index i = frac | (exponent even) << 7. The significand is m = 128 + frac for
an odd biased exponent and m = 2 * (128 + frac) for an even one (the odd
unbiased exponent lends a factor of two). The entry is the fraction of the
largest mid with mid * mid / 128 <= m, which is isqrt(128 * (m + 1) - 1);
it lies in [128, 255] for every m, so only its low 7 bits are stored.
The script also checks the closed form against the binary search of the
contract.
"""
import math


def search(m):
    lo, hi, r = 90, 256, 128
    while lo <= hi:
        mid = (lo + hi) >> 1
        if mid * mid // 128 <= m:
            r, lo = mid, mid + 1
        else:
            hi = mid - 1
    return r


vals = []
for i in range(256):
    frac, even = i & 0x7F, i >> 7
    m = (128 + frac) << even
    r = math.isqrt(128 * (m + 1) - 1)
    assert r == search(m) and 128 <= r <= 255
    vals.append(r & 0x7F)

for row in range(0, 256, 16):
    print("    .byte   " + ", ".join(f"{v:3d}" for v in vals[row:row + 16]))
