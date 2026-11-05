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
    }
    while (sum >= 3)
        sum = sum - 3;
    if (sum != 0)
        return -1;

    /* TODO: step 2, the ranks; step 3, the search; step 4, the output. */
    return -1;
}
