#include "cube.h"
#include "search.h"

#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static uint16_t permutation_moves[CUBE_MOVES][CUBE_PERMUTATIONS];
static uint16_t orientation_moves[CUBE_MOVES][CUBE_ORIENTATIONS];

static void build_transitions(void)
{
    uint16_t rank;
    for (rank = 0; rank < CUBE_PERMUTATIONS; ++rank) {
        cube_state_t state;
        uint8_t face;
        cube_unrank_permutation(rank, &state);
        for (face = 0; face < CUBE_FACES; ++face) {
            cube_state_t next = state;
            uint8_t turn;
            for (turn = 0; turn < 3; ++turn) {
                next = cube_quarter_turn(next, face);
                permutation_moves[face * 3U + turn][rank] =
                    cube_rank_permutation(&next);
            }
        }
    }
    for (rank = 0; rank < CUBE_ORIENTATIONS; ++rank) {
        cube_state_t state;
        uint8_t face;
        cube_unrank_orientation(rank, &state);
        for (face = 0; face < CUBE_FACES; ++face) {
            cube_state_t next = state;
            uint8_t turn;
            for (turn = 0; turn < 3; ++turn) {
                next = cube_quarter_turn(next, face);
                orientation_moves[face * 3U + turn][rank] =
                    cube_rank_orientation(&next);
            }
        }
    }
}

static uint8_t *build_exact_distances(void)
{
    uint8_t *distance = malloc(CUBE_STATES);
    uint32_t *queue = malloc((size_t) CUBE_STATES * sizeof *queue);
    uint32_t head = 0, tail = 1;
    if (!distance || !queue) {
        free(distance);
        free(queue);
        return NULL;
    }
    memset(distance, UCHAR_MAX, CUBE_STATES);
    distance[0] = 0;
    queue[0] = 0;
    while (head < tail) {
        uint32_t here = queue[head++];
        uint16_t p = (uint16_t) (here / CUBE_ORIENTATIONS);
        uint16_t o = (uint16_t) (here % CUBE_ORIENTATIONS);
        uint8_t move;
        for (move = 0; move < CUBE_MOVES; ++move) {
            uint32_t there =
                (uint32_t) permutation_moves[move][p] * CUBE_ORIENTATIONS +
                orientation_moves[move][o];
            if (distance[there] == UCHAR_MAX) {
                distance[there] = (uint8_t) (distance[here] + 1U);
                queue[tail++] = there;
            }
        }
    }
    free(queue);
    if (tail != CUBE_STATES) {
        free(distance);
        return NULL;
    }
    return distance;
}

int main(void)
{
    uint8_t *exact;
    uint32_t rank;
    build_transitions();
    exact = build_exact_distances();
    if (!exact) {
        fputs("could not build exact BFS oracle\n", stderr);
        return 1;
    }
    idastar_build_pdbs();
    for (rank = 0; rank < CUBE_STATES; ++rank) {
        uint16_t p = (uint16_t) (rank / CUBE_ORIENTATIONS);
        uint16_t o = (uint16_t) (rank % CUBE_ORIENTATIONS);
        uint8_t hp = idastar_permutation_distance(p);
        uint8_t ho = idastar_orientation_distance(o);
        uint8_t h = hp > ho ? hp : ho;
        if (h > exact[rank]) {
            fprintf(stderr,
                    "inadmissible heuristic at rank %lu: h=%u, exact=%u\n",
                    (unsigned long) rank, h, exact[rank]);
            free(exact);
            return 1;
        }
    }
    free(exact);
    printf("PDB heuristic admissible for all %d states\n", CUBE_STATES);
    return 0;
}
