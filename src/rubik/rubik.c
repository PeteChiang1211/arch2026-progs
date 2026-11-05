#include "rubik.h"
#include "rubik_tables.h"

int rubik_solve(const char *state, char *out, size_t cap)
{
    (void) out;
    (void) cap;

    /* The state must be exactly 14 characters long. */
    for (int i = 0; i < 14; i++) {
        if (state[i] == '\0')
            return -1;
    }
    if (state[14] != '\0')
        return -1;

    /* Cubies '1'..'7' without repeats, twists '1'..'3' summing to a
     * multiple of 3 (counted down by subtraction: no divide here).
     */
    int p[7], o[7];
    int seen[7] = {0};
    int sum = 0;
    for (int i = 0; i < 7; i++) {
        int c = state[i] - '1';
        int t = state[7 + i] - '1';
        if (c < 0 || c > 6)
            return -1;
        if (t < 0 || t > 2)
            return -1;
        if (seen[c] == 1)
            return -1;
        seen[c] = 1;
        sum = sum + t;
        p[i] = c;
        o[i] = t;
    }
    while (sum >= 3)
        sum = sum - 3;
    if (sum != 0)
        return -1;

    /* Permutation rank (Lehmer code): position i counts the smaller cubies
     * to its right, weighted by (6 - i)!.
     */
    static const int fact[7] = {720, 120, 24, 6, 2, 1, 1};
    int pr = 0;
    for (int i = 0; i < 7; i++) {
        int smaller = 0;
        for (int j = i + 1; j < 7; j++) {
            if (p[j] < p[i])
                smaller = smaller + 1;
        }
        pr = pr + smaller * fact[i];
    }

    /* Orientation rank: the first six twists as a base-3 number. */
    int orank = 0;
    for (int i = 0; i < 6; i++)
        orank = orank * 3 + o[i];

    /* Position * 4 + twist of cubies 0 and 1. */
    int s0 = 0, s1 = 0;
    for (int pos = 0; pos < 7; pos++) {
        if (p[pos] == 0)
            s0 = pos * 4 + o[pos];
        if (p[pos] == 1)
            s1 = pos * 4 + o[pos];
    }

    /* TODO: step 3, the search; step 4, the output. */
    (void) pr;
    (void) orank;
    (void) s0;
    (void) s1;
    return -1;
}
