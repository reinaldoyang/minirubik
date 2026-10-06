#ifndef IDASTAR_TABLES_H
#define IDASTAR_TABLES_H

#include "cube.h"

#include <stdint.h>

extern const uint8_t idastar_permutation_pdb[CUBE_PERMUTATIONS];
extern const uint8_t idastar_orientation_pdb[CUBE_ORIENTATIONS];

extern const uint16_t idastar_permutation_turn_r[CUBE_PERMUTATIONS];
extern const uint16_t idastar_permutation_turn_b[CUBE_PERMUTATIONS];
extern const uint16_t idastar_permutation_turn_d[CUBE_PERMUTATIONS];

extern const uint16_t idastar_orientation_turn_r[CUBE_ORIENTATIONS];
extern const uint16_t idastar_orientation_turn_b[CUBE_ORIENTATIONS];
extern const uint16_t idastar_orientation_turn_d[CUBE_ORIENTATIONS];

#endif
