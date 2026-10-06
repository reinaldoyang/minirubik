#include "cube.h"

#include <stddef.h>
#include <string.h>

const char *const cube_move_names[CUBE_MOVES] = {
    "R", "R2", "R'", "B", "B2", "B'", "D", "D2", "D'",
};

const cube_state_t cube_solved = {{0, 1, 2, 3, 4, 5, 6}, {0}};

/* Each destination takes a cubie from source[face][destination]. */
static const uint8_t source[CUBE_FACES][CUBE_CUBIES] = {
    {1, 4, 2, 0, 3, 5, 6},
    {0, 1, 2, 4, 5, 6, 3},
    {0, 2, 5, 3, 1, 4, 6},
};

static const uint8_t twist[CUBE_FACES][CUBE_CUBIES] = {
    {1, 2, 0, 2, 1, 0, 0},
    {0, 0, 0, 1, 2, 1, 2},
    {0, 0, 0, 0, 0, 0, 0},
};

cube_state_t cube_quarter_turn(cube_state_t state, uint8_t face)
{
    cube_state_t result;
    uint8_t i;
    for (i = 0; i < CUBE_CUBIES; ++i) {
        uint8_t from = source[face][i];
        result.p[i] = state.p[from];
        result.o[i] = (uint8_t) ((state.o[from] + twist[face][i]) % 3U);
    }
    return result;
}

cube_state_t cube_apply_move(cube_state_t state, uint8_t move)
{
    uint8_t turns = (uint8_t) (move % 3U + 1U);
    uint8_t i;
    for (i = 0; i < turns; ++i)
        state = cube_quarter_turn(state, (uint8_t) (move / 3U));
    return state;
}

static uint8_t smaller_cubies_after(const cube_state_t *state, uint8_t index)
{
    uint8_t smaller = 0;
    uint8_t j;
    for (j = (uint8_t) (index + 1U); j < CUBE_CUBIES; ++j)
        if (state->p[j] < state->p[index])
            ++smaller;
    return smaller;
}

uint16_t cube_rank_permutation(const cube_state_t *state)
{
    uint16_t s0 = smaller_cubies_after(state, 0);
    uint16_t s1 = smaller_cubies_after(state, 1);
    uint16_t s2 = smaller_cubies_after(state, 2);
    uint16_t s3 = smaller_cubies_after(state, 3);
    uint16_t s4 = smaller_cubies_after(state, 4);
    uint16_t s5 = smaller_cubies_after(state, 5);

    return (uint16_t) ((s0 << 9U) + (s0 << 7U) + (s0 << 6U) +
                       (s0 << 4U) + (s1 << 6U) + (s1 << 5U) +
                       (s1 << 4U) + (s1 << 3U) + (s2 << 4U) +
                       (s2 << 3U) + (s3 << 2U) + (s3 << 1U) +
                       (s4 << 1U) + s5);
}

uint16_t cube_rank_orientation(const cube_state_t *state)
{
    uint16_t rank = 0;
    uint8_t i;
    for (i = 0; i < CUBE_CUBIES - 1; ++i)
        rank = (uint16_t) ((rank << 1U) + rank + state->o[i]);
    return rank;
}

uint32_t cube_rank(const cube_state_t *state)
{
    return (uint32_t) cube_rank_permutation(state) * CUBE_ORIENTATIONS +
           cube_rank_orientation(state);
}

void cube_unrank_permutation(uint16_t rank, cube_state_t *state)
{
    uint8_t available[CUBE_CUBIES] = {0, 1, 2, 3, 4, 5, 6};
    uint16_t factor = 720;
    uint8_t i;
    *state = cube_solved;
    for (i = 0; i < CUBE_CUBIES; ++i) {
        uint8_t q = (uint8_t) (rank / factor);
        uint8_t j;
        rank = (uint16_t) (rank % factor);
        state->p[i] = available[q];
        for (j = q; j + 1 < CUBE_CUBIES - i; ++j)
            available[j] = available[j + 1U];
        if (i < 5)
            factor = (uint16_t) (factor / (6U - i));
    }
}

void cube_unrank_orientation(uint16_t rank, cube_state_t *state)
{
    uint8_t sum = 0;
    uint8_t i;
    *state = cube_solved;
    for (i = CUBE_CUBIES - 1; i-- > 0;) {
        state->o[i] = (uint8_t) (rank % 3U);
        sum = (uint8_t) (sum + state->o[i]);
        rank = (uint16_t) (rank / 3U);
    }
    state->o[CUBE_CUBIES - 1] = (uint8_t) ((3U - sum % 3U) % 3U);
}

void cube_unrank(uint32_t rank, cube_state_t *state)
{
    cube_state_t orientation;
    uint8_t i;
    cube_unrank_permutation((uint16_t) (rank / CUBE_ORIENTATIONS), state);
    cube_unrank_orientation((uint16_t) (rank % CUBE_ORIENTATIONS),
                            &orientation);
    for (i = 0; i < CUBE_CUBIES; ++i)
        state->o[i] = orientation.o[i];
}

static int cube_valid(const cube_state_t *state)
{
    uint8_t sum = 0;
    uint8_t i;
    for (i = 0; i < CUBE_CUBIES; ++i) {
        uint8_t j;
        if (state->p[i] >= CUBE_CUBIES || state->o[i] >= 3)
            return 0;
        for (j = 0; j < i; ++j)
            if (state->p[j] == state->p[i])
                return 0;
        sum = (uint8_t) (sum + state->o[i]);
    }
    return sum % 3U == 0;
}

int cube_parse(const char *input, cube_state_t *state)
{
    uint8_t i;
    if (strlen(input) != 2U * CUBE_CUBIES)
        return 0;
    for (i = 0; i < 2U * CUBE_CUBIES; ++i) {
        int limit = i < CUBE_CUBIES ? 7 : 3;
        if (input[i] < '1' || input[i] > '0' + limit)
            return 0;
        (i < CUBE_CUBIES ? state->p : state->o)[i % CUBE_CUBIES] =
            (uint8_t) (input[i] - '1');
    }
    return cube_valid(state);
}

int cube_is_solved(const cube_state_t *state)
{
    return cube_rank(state) == 0;
}

int cube_move_from_name(const char *name)
{
    uint8_t move;
    for (move = 0; move < CUBE_MOVES; ++move)
        if (!strcmp(name, cube_move_names[move]))
            return move;
    return -1;
}
