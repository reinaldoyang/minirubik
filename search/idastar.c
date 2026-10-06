#include "search.h"
#include "idastar_tables.h"

#include <limits.h>
#include <string.h>

enum {
    IDASTAR_PDB_BYTES =
        sizeof idastar_permutation_pdb + sizeof idastar_orientation_pdb,
    IDASTAR_TRANSITION_BYTES =
        sizeof idastar_permutation_turn_r +
        sizeof idastar_permutation_turn_b +
        sizeof idastar_permutation_turn_d +
        sizeof idastar_orientation_turn_r +
        sizeof idastar_orientation_turn_b + sizeof idastar_orientation_turn_d
};

typedef struct {
    uint16_t permutation_rank;
    uint16_t orientation_rank;
    uint8_t next_face;
    uint8_t next_turn;
    uint8_t entered;
    uint8_t heuristic;
} idastar_frame_t;

void idastar_build_pdbs(void)
{
    /* The host generator has already built the const PDBs. */
}

size_t idastar_permutation_pdb_entries(void)
{
    return CUBE_PERMUTATIONS;
}

size_t idastar_orientation_pdb_entries(void)
{
    return CUBE_ORIENTATIONS;
}

uint8_t idastar_pdb_unvisited_value(void)
{
    return UCHAR_MAX;
}

uint8_t idastar_permutation_distance(uint16_t rank)
{
    return idastar_permutation_pdb[rank];
}

uint8_t idastar_orientation_distance(uint16_t rank)
{
    return idastar_orientation_pdb[rank];
}

static uint8_t heuristic(uint16_t permutation_rank, uint16_t orientation_rank,
                         search_metrics_t *metrics)
{
    uint8_t permutation = idastar_permutation_pdb[permutation_rank];
    uint8_t orientation = idastar_orientation_pdb[orientation_rank];
    metrics->pdb_lookups += 2;
    return permutation > orientation ? permutation : orientation;
}

static void select_turn_tables(uint8_t face,
                               const uint16_t **permutation_turn,
                               const uint16_t **orientation_turn)
{
    if (face == 0) {
        *permutation_turn = idastar_permutation_turn_r;
        *orientation_turn = idastar_orientation_turn_r;
    } else if (face == 1) {
        *permutation_turn = idastar_permutation_turn_b;
        *orientation_turn = idastar_orientation_turn_b;
    } else {
        *permutation_turn = idastar_permutation_turn_d;
        *orientation_turn = idastar_orientation_turn_d;
    }
}

int idastar_solve(cube_state_t start, uint8_t solution[CUBE_DIAMETER],
                  search_metrics_t *metrics)
{
    idastar_frame_t stack[CUBE_DIAMETER + 1];
    uint8_t path[CUBE_DIAMETER];
    uint8_t path_face[CUBE_DIAMETER];
    uint16_t root_permutation = cube_rank_permutation(&start);
    uint16_t root_orientation = cube_rank_orientation(&start);
    uint8_t root_heuristic;
    uint8_t threshold;

    memset(metrics, 0, sizeof *metrics);
    metrics->static_table_bytes =
        (uint32_t) (IDASTAR_PDB_BYTES + IDASTAR_TRANSITION_BYTES);
    root_heuristic = heuristic(root_permutation, root_orientation, metrics);
    threshold = root_heuristic;

    while (threshold <= CUBE_DIAMETER) {
        uint8_t depth = 0;
        uint8_t next_threshold = UCHAR_MAX;
        ++metrics->search_iterations;
        stack[0].permutation_rank = root_permutation;
        stack[0].orientation_rank = root_orientation;
        stack[0].heuristic = root_heuristic;
        stack[0].entered = 0;

        for (;;) {
            idastar_frame_t *frame = &stack[depth];
            if (!frame->entered) {
                uint8_t estimate = (uint8_t) (depth + frame->heuristic);
                frame->entered = 1;
                frame->next_face = 0;
                frame->next_turn = 0;
                if (depth > metrics->maximum_stack_depth)
                    metrics->maximum_stack_depth = depth;
                if (estimate > threshold) {
                    if (estimate < next_threshold)
                        next_threshold = estimate;
                    if (depth == 0)
                        break;
                    --depth;
                    continue;
                }
                if (frame->permutation_rank == 0 &&
                    frame->orientation_rank == 0) {
                    uint8_t i;
                    metrics->solution_length = depth;
                    for (i = 0; i < depth; ++i)
                        solution[i] = path[i];
                    return 1;
                }
                ++metrics->nodes_expanded;
            }

            if (depth > 0 && frame->next_face == path_face[depth - 1]) {
                ++frame->next_face;
                frame->next_turn = 0;
            }

            if (frame->next_face == CUBE_FACES) {
                if (depth == 0)
                    break;
                --depth;
            } else {
                const uint16_t *permutation_turn;
                const uint16_t *orientation_turn;
                uint16_t permutation = frame->permutation_rank;
                uint16_t orientation = frame->orientation_rank;
                uint8_t face = frame->next_face;
                uint8_t turn = frame->next_turn;
                uint8_t repetitions = (uint8_t) (turn + 1U);
                uint8_t i;

                ++frame->next_turn;
                if (frame->next_turn == 3) {
                    frame->next_turn = 0;
                    ++frame->next_face;
                }
                select_turn_tables(face, &permutation_turn, &orientation_turn);
                for (i = 0; i < repetitions; ++i) {
                    permutation = permutation_turn[permutation];
                    orientation = orientation_turn[orientation];
                }

                ++metrics->children_generated;
                path[depth] = (uint8_t) ((face << 1U) + face + turn);
                path_face[depth] = face;
                stack[depth + 1].permutation_rank = permutation;
                stack[depth + 1].orientation_rank = orientation;
                stack[depth + 1].heuristic =
                    heuristic(permutation, orientation, metrics);
                stack[depth + 1].entered = 0;
                ++depth;
            }
        }
        if (next_threshold == UCHAR_MAX)
            break;
        threshold = next_threshold;
    }
    return 0;
}
