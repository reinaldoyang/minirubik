#include "exact_bfs.h"

#include "cube.h"

#include <limits.h>
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

static uint16_t permutation_moves[CUBE_MOVES][CUBE_PERMUTATIONS];
static uint16_t orientation_moves[CUBE_MOVES][CUBE_ORIENTATIONS];

static int build_abstract_transitions(void)
{
    uint16_t rank;
    for (rank = 0; rank < CUBE_PERMUTATIONS; ++rank) {
        cube_state_t state;
        uint8_t move;
        cube_unrank_permutation(rank, &state);
        for (move = 0; move < CUBE_MOVES; ++move) {
            cube_state_t next = cube_apply_move(state, move);
            uint16_t there = cube_rank_permutation(&next);
            if (there >= CUBE_PERMUTATIONS)
                return 0;
            permutation_moves[move][rank] = there;
        }
    }
    for (rank = 0; rank < CUBE_ORIENTATIONS; ++rank) {
        cube_state_t state;
        uint8_t move;
        cube_unrank_orientation(rank, &state);
        for (move = 0; move < CUBE_MOVES; ++move) {
            cube_state_t next = cube_apply_move(state, move);
            uint16_t there = cube_rank_orientation(&next);
            if (there >= CUBE_ORIENTATIONS)
                return 0;
            orientation_moves[move][rank] = there;
        }
    }
    return 1;
}

uint8_t *host_build_exact_bfs_distances(void)
{
    uint8_t *distance;
    uint32_t *queue;
    uint32_t head = 0, tail = 1;
    if ((uint32_t) CUBE_PERMUTATIONS * CUBE_ORIENTATIONS != CUBE_STATES ||
        !build_abstract_transitions())
        return NULL;

    distance = malloc(CUBE_STATES);
    queue = malloc((size_t) CUBE_STATES * sizeof *queue);
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
        uint16_t permutation =
            (uint16_t) (here / CUBE_ORIENTATIONS);
        uint16_t orientation =
            (uint16_t) (here % CUBE_ORIENTATIONS);
        uint8_t move;
        for (move = 0; move < CUBE_MOVES; ++move) {
            uint32_t there =
                (uint32_t) permutation_moves[move][permutation] *
                    CUBE_ORIENTATIONS +
                orientation_moves[move][orientation];
            if (there >= CUBE_STATES) {
                free(distance);
                free(queue);
                return NULL;
            }
            if (distance[there] == UCHAR_MAX) {
                if (tail >= CUBE_STATES) {
                    free(distance);
                    free(queue);
                    return NULL;
                }
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
