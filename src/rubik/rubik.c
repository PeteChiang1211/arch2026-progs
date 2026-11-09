#include "rubik.h"
#include "rubik_tables.h"

/* path[g] = face * 3 + turn of move g (turn 0, 1, 2: a quarter, a half and
 * an inverse turn), the index of the move name R R2 R' B B2 B' D D2 D'.
 */
static int path[12];

/* Depth-first search with a move limit (IDA*): returns 1 when the state
 * (pr, orank, s0, s1) is solved within bound - g more moves, with the moves
 * in path[g..]. last is the face of the previous move, -1 for none.
 */
static int dfs(int g, int bound, int pr, int orank, int s0, int s1, int last)
{
    /* At least h more moves: the larger of two lower bounds. */
    int h = pattern_dist[pr * 9 + (s0 & 3) * 3 + (s1 & 3)];
    int h2 = orient_pos_dist[orank * 49 + (s0 >> 2) * 7 + (s1 >> 2)];
    if (h2 > h)
        h = h2;
    if (g + h > bound)
        return 0;
    if (h == 0)
        return 1;

    for (int face = 0; face < 3; face++) {
        /* Two turns of one face in a row are never shortest. */
        if (face == last)
            continue;
        int np = pr, no = orank, n0 = s0, n1 = s1;
        for (int turn = 0; turn < 3; turn++) {
            /* One more quarter turn of this face, by table lookup. */
            np = perm_move[face][np];
            no = orient_move[face][no];
            n0 = cubie_move[face][n0];
            n1 = cubie_move[face][n1];
            path[g] = face * 3 + turn;
            if (dfs(g + 1, bound, np, no, n0, n1, face))
                return 1;
        }
    }
    return 0;
}

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

    /* Raise the move limit one at a time: the first limit that succeeds
     * is the length of a shortest solution.
     */
    int len = 0;
    while (!dfs(0, len, pr, orank, s0, s1, -1))
        len = len + 1;

    /* TODO: step 4, the output. */
    return -1;
}
