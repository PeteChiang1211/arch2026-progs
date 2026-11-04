/* Host generator of the rubik search tables (Homework 1, ida.c).
 *
 * Build and run from the repository root:
 *   cc -O2 -o build/rubik_tables mytests/rubik_tables.c
 *   build/rubik_tables
 *   clang-format-20 -i src/rubik/rubik_tables.h
 * It writes src/rubik/rubik_tables.h (C arrays for rubik.c) and
 * src/rubik/rubik_tables.S (the same data for the assembly).
 *
 * Tables, with p the Lehmer rank of the permutation of cubies 0..6 (5,040) and
 * o the base-3 rank of the orientations of positions 0..5 (729):
 *   perm_move[f][p]   rank after a quarter turn of face f (R, B, D)
 *   orient_move[f][o] the same for the orientations
 *   cubie_move[f][c]  coordinate pos * 4 + twist of one cubie after a turn
 *   pattern_dist[p * 9 + t0 * 3 + t1]
 *                     moves needed to solve the permutation together with the
 *                     twists t0, t1 of cubies 0 and 1: the minimum distance of
 *                     the 3,674,160 states that share them
 *   orient_pos_dist[o * 49 + q0 * 7 + q1]
 *                     moves needed to solve the orientations together with
 *                     the positions q0, q1 of cubies 0 and 1, built the same
 *                     way. Homework 1 used the orientations alone; telling the
 *                     two cubies apart raises the bound and cuts the nodes of
 *                     the hardest state from 157,239 to 88,899, and since it
 *                     is never below the orientation-only distance, that
 *                     table is no longer needed.
 * Both distances are lower bounds of the true distance, so IDA* with their
 * maximum as the heuristic finds shortest solutions. The full distance table
 * is needed only here, on the host, to build the two; it is freed and never
 * reaches the target.
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

enum { CUBIES = 7, PERMS = 5040, ORIENTS = 729, STATES = PERMS * ORIENTS };

typedef struct {
    uint8_t p[CUBIES], o[CUBIES];
} state_t;

static const uint8_t source[3][CUBIES] = {
    {1, 4, 2, 0, 3, 5, 6},
    {0, 1, 2, 4, 5, 6, 3},
    {0, 2, 5, 3, 1, 4, 6},
};
static const uint8_t twist[3][CUBIES] = {
    {1, 2, 0, 2, 1, 0, 0},
    {0, 0, 0, 1, 2, 1, 2},
    {0, 0, 0, 0, 0, 0, 0},
};

static state_t quarter_turn(state_t s, int face)
{
    state_t r;
    for (int i = 0; i < CUBIES; i++) {
        int from = source[face][i];
        r.p[i] = s.p[from];
        r.o[i] = (uint8_t) ((s.o[from] + twist[face][i]) % 3);
    }
    return r;
}

static uint32_t rank_state(const state_t *s)
{
    uint32_t p = 0, o = 0;
    for (int i = 0; i < CUBIES; i++) {
        int smaller = 0;
        for (int j = i + 1; j < CUBIES; j++)
            smaller += s->p[j] < s->p[i];
        p = p * (CUBIES - i) + smaller;
    }
    for (int i = 0; i < 6; i++)
        o = o * 3 + s->o[i];
    return p * ORIENTS + o;
}

static void unrank_state(uint32_t rank, state_t *s)
{
    uint8_t avail[CUBIES] = {0, 1, 2, 3, 4, 5, 6};
    uint32_t p = rank / ORIENTS, o = rank % ORIENTS, f = 720;
    int sum = 0;
    for (int i = 0; i < CUBIES; i++) {
        int q = (int) (p / f);
        p %= f;
        s->p[i] = avail[q];
        for (int j = q; j + 1 < CUBIES - i; j++)
            avail[j] = avail[j + 1];
        if (i < 5)
            f /= 6 - i;
    }
    for (int i = 6; i-- > 0;) {
        s->o[i] = (uint8_t) (o % 3);
        sum += s->o[i];
        o /= 3;
    }
    s->o[6] = (uint8_t) ((3 - sum % 3) % 3);
}

static uint8_t cubie_coord(const state_t *s, int cubie)
{
    int pos = 0;
    while (s->p[pos] != cubie)
        pos++;
    return (uint8_t) (pos * 4 + s->o[pos]);
}

static uint16_t perm_move[3][PERMS], orient_move[3][ORIENTS];
static uint8_t cubie_move[3][28], orient_dist[ORIENTS];
static uint8_t pattern_dist[PERMS * 9], orient_pos_dist[ORIENTS * 49];

static void build(void)
{
    state_t s;
    for (int r = 0; r < PERMS; r++) {
        unrank_state((uint32_t) r * ORIENTS, &s);
        for (int f = 0; f < 3; f++) {
            state_t n = quarter_turn(s, f);
            perm_move[f][r] = (uint16_t) (rank_state(&n) / ORIENTS);
        }
    }
    for (int r = 0; r < ORIENTS; r++) {
        unrank_state((uint32_t) r, &s);
        for (int f = 0; f < 3; f++) {
            state_t n = quarter_turn(s, f);
            orient_move[f][r] = (uint16_t) (rank_state(&n) % ORIENTS);
        }
    }
    for (int f = 0; f < 3; f++)
        for (int pos = 0; pos < CUBIES; pos++)
            for (int ori = 0; ori < 3; ori++) {
                int to = 0;
                while (source[f][to] != pos)
                    to++;
                cubie_move[f][pos * 4 + ori] =
                    (uint8_t) (to * 4 + (ori + twist[f][to]) % 3);
            }

    /* Orientation distances by breadth-first search. */
    uint16_t queue[ORIENTS];
    int head = 0, tail = 1;
    memset(orient_dist, 0xFF, sizeof orient_dist);
    orient_dist[0] = 0;
    queue[0] = 0;
    while (head < tail) {
        int here = queue[head++];
        for (int f = 0; f < 3; f++) {
            int next = here;
            for (int t = 0; t < 3; t++) {
                next = orient_move[f][next];
                if (orient_dist[next] == 0xFF) {
                    orient_dist[next] = (uint8_t) (orient_dist[here] + 1);
                    queue[tail++] = (uint16_t) next;
                }
            }
        }
    }

    /* Exact distances of every state, on the host only. */
    uint8_t *exact = malloc(STATES);
    uint32_t *q = malloc((size_t) STATES * sizeof *q);
    if (!exact || !q)
        exit(1);
    memset(exact, 0xFF, STATES);
    exact[0] = 0;
    q[0] = 0;
    uint32_t h = 0, t = 1;
    while (h < t) {
        uint32_t here = q[h++];
        int p = (int) (here / ORIENTS), o = (int) (here % ORIENTS);
        for (int f = 0; f < 3; f++) {
            int np = p, no = o;
            for (int k = 0; k < 3; k++) {
                np = perm_move[f][np];
                no = orient_move[f][no];
                uint32_t there = (uint32_t) np * ORIENTS + (uint32_t) no;
                if (exact[there] == 0xFF) {
                    exact[there] = (uint8_t) (exact[here] + 1);
                    q[t++] = there;
                }
            }
        }
    }
    if (t != STATES)
        exit(1);

    memset(pattern_dist, 0xFF, sizeof pattern_dist);
    memset(orient_pos_dist, 0xFF, sizeof orient_pos_dist);
    for (uint32_t r = 0; r < STATES; r++) {
        unrank_state(r, &s);
        int c0 = cubie_coord(&s, 0), c1 = cubie_coord(&s, 1);
        uint32_t cell =
            (r / ORIENTS) * 9 + (uint32_t) ((c0 & 3) * 3 + (c1 & 3));
        if (exact[r] < pattern_dist[cell])
            pattern_dist[cell] = exact[r];
        cell = (r % ORIENTS) * 49 + (uint32_t) ((c0 >> 2) * 7 + (c1 >> 2));
        if (exact[r] < orient_pos_dist[cell])
            orient_pos_dist[cell] = exact[r];
    }
    for (int o = 0; o < ORIENTS; o++)
        for (int c = 0; c < 49; c++)
            if (orient_pos_dist[o * 49 + c] < orient_dist[o])
                exit(1); /* must never be below the orientation distance */
    free(q);
    free(exact);
}

/* rows = 1 writes a flat array; rows = 3 writes one braced row per face. */
static void c_array(FILE *f,
                    const char *type,
                    const char *name,
                    const char *dims,
                    const void *data,
                    int n,
                    int wide,
                    int rows)
{
    int per = n / rows;
    fprintf(f, "static const %s %s%s = {", type, name, dims);
    for (int r = 0; r < rows; r++) {
        if (rows > 1)
            fprintf(f, "\n    {");
        for (int i = r * per; i < (r + 1) * per; i++) {
            unsigned v = wide ? ((const uint16_t *) data)[i]
                              : ((const uint8_t *) data)[i];
            fprintf(f, "%s%u,", (i - r * per) % 16 ? " " : "\n        ", v);
        }
        if (rows > 1)
            fprintf(f, "\n    },");
    }
    fprintf(f, "\n};\n\n");
}

static void s_array(FILE *f,
                    const char *name,
                    const void *data,
                    int n,
                    int wide)
{
    fprintf(f, "    .globl  %s\n    .align  %d\n%s:\n", name, wide ? 1 : 0,
            name);
    for (int i = 0; i < n; i++) {
        unsigned v =
            wide ? ((const uint16_t *) data)[i] : ((const uint8_t *) data)[i];
        if (i % 16 == 0)
            fprintf(f, "%s    %s   ", i ? "\n" : "",
                    wide ? ".hword" : ".byte ");
        fprintf(f, "%s%u", i % 16 ? ", " : " ", v);
    }
    fprintf(f, "\n\n");
}

int main(void)
{
    build();

    FILE *h = fopen("src/rubik/rubik_tables.h", "w");
    if (!h)
        return 1;
    fprintf(h,
            "/* Generated by mytests/rubik_tables.c. Do not edit. */\n"
            "#pragma once\n\n#include <stdint.h>\n\n");
    c_array(h, "uint16_t", "perm_move", "[3][5040]", perm_move, 3 * PERMS, 1,
            3);
    c_array(h, "uint16_t", "orient_move", "[3][729]", orient_move, 3 * ORIENTS,
            1, 3);
    c_array(h, "uint8_t", "cubie_move", "[3][28]", cubie_move, 3 * 28, 0, 3);
    c_array(h, "uint8_t", "pattern_dist", "[5040 * 9]", pattern_dist, PERMS * 9,
            0, 1);
    c_array(h, "uint8_t", "orient_pos_dist", "[729 * 49]", orient_pos_dist,
            ORIENTS * 49, 0, 1);
    fclose(h);

    FILE *s = fopen("src/rubik/rubik_tables.S", "w");
    if (!s)
        return 1;
    fprintf(s,
            "# Generated by mytests/rubik_tables.c. Do not edit.\n"
            "# Search tables of rubik_solve_asm, see rubik.S.\n\n"
            "    .section .rodata\n\n");
    s_array(s, "rubik_perm_move", perm_move, 3 * PERMS, 1);
    s_array(s, "rubik_orient_move", orient_move, 3 * ORIENTS, 1);
    s_array(s, "rubik_cubie_move", cubie_move, 3 * 28, 0);
    s_array(s, "rubik_pattern_dist", pattern_dist, PERMS * 9, 0);
    s_array(s, "rubik_orient_pos_dist", orient_pos_dist, ORIENTS * 49, 0);
    fclose(s);
    return 0;
}
