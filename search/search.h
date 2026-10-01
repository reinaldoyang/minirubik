#ifndef SEARCH_H
#define SEARCH_H

#include "cube.h"

#include <stdint.h>

typedef struct {
    uint8_t solution_length;
    uint8_t maximum_stack_depth;
    uint64_t nodes_expanded;
    uint64_t children_generated;
    uint64_t search_iterations;
    uint64_t pdb_lookups;
    double host_seconds;
    uint32_t static_table_bytes;
} search_metrics_t;

int iddfs_solve(cube_state_t start, uint8_t solution[CUBE_DIAMETER],
                search_metrics_t *metrics);
int idastar_solve(cube_state_t start, uint8_t solution[CUBE_DIAMETER],
                  search_metrics_t *metrics);

void idastar_build_pdbs(void);
uint8_t idastar_permutation_distance(uint16_t rank);
uint8_t idastar_orientation_distance(uint16_t rank);

#endif
