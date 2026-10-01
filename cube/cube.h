#ifndef CUBE_H
#define CUBE_H

#include <stdint.h>

enum {
    CUBE_CUBIES = 7,
    CUBE_PERMUTATIONS = 5040,
    CUBE_ORIENTATIONS = 729,
    CUBE_STATES = CUBE_PERMUTATIONS * CUBE_ORIENTATIONS,
    CUBE_FACES = 3,
    CUBE_MOVES = 9,
    CUBE_DIAMETER = 11
};

typedef struct {
    uint8_t p[CUBE_CUBIES];
    uint8_t o[CUBE_CUBIES];
} cube_state_t;

extern const char *const cube_move_names[CUBE_MOVES];
extern const cube_state_t cube_solved;

cube_state_t cube_quarter_turn(cube_state_t state, uint8_t face);
cube_state_t cube_apply_move(cube_state_t state, uint8_t move);
uint16_t cube_rank_permutation(const cube_state_t *state);
uint16_t cube_rank_orientation(const cube_state_t *state);
uint32_t cube_rank(const cube_state_t *state);
void cube_unrank_permutation(uint16_t rank, cube_state_t *state);
void cube_unrank_orientation(uint16_t rank, cube_state_t *state);
void cube_unrank(uint32_t rank, cube_state_t *state);
int cube_parse(const char *input, cube_state_t *state);
int cube_is_solved(const cube_state_t *state);
int cube_move_from_name(const char *name);

#endif
