#include "search.h"
#include "search_internal.h"

#include <limits.h>
#include <string.h>

static uint8_t permutation_pdb[CUBE_PERMUTATIONS];
static uint8_t orientation_pdb[CUBE_ORIENTATIONS];
static int pdbs_ready;

typedef struct {
    cube_state_t state;
    uint8_t next_move;
    uint8_t entered;
    uint8_t heuristic;
} idastar_frame_t;

static void build_permutation_pdb(void)
{
    uint16_t queue[CUBE_PERMUTATIONS];
    uint16_t head = 0, tail = 1;
    memset(permutation_pdb, UCHAR_MAX, sizeof permutation_pdb);
    permutation_pdb[0] = 0;
    queue[0] = 0;
    while (head < tail) {
        uint16_t here = queue[head++];
        cube_state_t state;
        uint8_t face;
        cube_unrank_permutation(here, &state);
        for (face = 0; face < CUBE_FACES; ++face) {
            cube_state_t next = state;
            uint8_t turn;
            for (turn = 0; turn < 3; ++turn) {
                uint16_t there;
                next = cube_quarter_turn(next, face);
                there = cube_rank_permutation(&next);
                if (permutation_pdb[there] == UCHAR_MAX) {
                    permutation_pdb[there] =
                        (uint8_t) (permutation_pdb[here] + 1U);
                    queue[tail++] = there;
                }
            }
        }
    }
}

static void build_orientation_pdb(void)
{
    uint16_t queue[CUBE_ORIENTATIONS];
    uint16_t head = 0, tail = 1;
    memset(orientation_pdb, UCHAR_MAX, sizeof orientation_pdb);
    orientation_pdb[0] = 0;
    queue[0] = 0;
    while (head < tail) {
        uint16_t here = queue[head++];
        cube_state_t state;
        uint8_t face;
        cube_unrank_orientation(here, &state);
        for (face = 0; face < CUBE_FACES; ++face) {
            cube_state_t next = state;
            uint8_t turn;
            for (turn = 0; turn < 3; ++turn) {
                uint16_t there;
                next = cube_quarter_turn(next, face);
                there = cube_rank_orientation(&next);
                if (orientation_pdb[there] == UCHAR_MAX) {
                    orientation_pdb[there] =
                        (uint8_t) (orientation_pdb[here] + 1U);
                    queue[tail++] = there;
                }
            }
        }
    }
}

void idastar_build_pdbs(void)
{
    if (!pdbs_ready) {
        build_permutation_pdb();
        build_orientation_pdb();
        pdbs_ready = 1;
    }
}

size_t idastar_permutation_pdb_entries(void)
{
    return sizeof permutation_pdb / sizeof permutation_pdb[0];
}

size_t idastar_orientation_pdb_entries(void)
{
    return sizeof orientation_pdb / sizeof orientation_pdb[0];
}

uint8_t idastar_pdb_unvisited_value(void)
{
    return UCHAR_MAX;
}

uint8_t idastar_permutation_distance(uint16_t rank)
{
    idastar_build_pdbs();
    return permutation_pdb[rank];
}

uint8_t idastar_orientation_distance(uint16_t rank)
{
    idastar_build_pdbs();
    return orientation_pdb[rank];
}

static uint8_t heuristic(const cube_state_t *state, search_metrics_t *metrics)
{
    uint8_t permutation = permutation_pdb[cube_rank_permutation(state)];
    uint8_t orientation = orientation_pdb[cube_rank_orientation(state)];
    metrics->pdb_lookups += 2;
    return permutation > orientation ? permutation : orientation;
}

int idastar_solve(cube_state_t start, uint8_t solution[CUBE_DIAMETER],
                  search_metrics_t *metrics)
{
    idastar_frame_t stack[CUBE_DIAMETER + 1];
    uint8_t path[CUBE_DIAMETER];
    uint8_t root_heuristic, threshold;
    double started = search_now_seconds();
    memset(metrics, 0, sizeof *metrics);
    metrics->static_table_bytes =
        (uint32_t) (sizeof permutation_pdb + sizeof orientation_pdb);
    idastar_build_pdbs();
    root_heuristic = heuristic(&start, metrics);
    threshold = root_heuristic;

    while (threshold <= CUBE_DIAMETER) {
        uint8_t depth = 0;
        uint8_t next_threshold = UCHAR_MAX;
        ++metrics->search_iterations;
        stack[0].state = start;
        stack[0].heuristic = root_heuristic;
        stack[0].entered = 0;

        for (;;) {
            idastar_frame_t *frame = &stack[depth];
            if (!frame->entered) {
                uint8_t estimate = (uint8_t) (depth + frame->heuristic);
                frame->entered = 1;
                frame->next_move = 0;
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
                if (cube_is_solved(&frame->state)) {
                    metrics->solution_length = depth;
                    memcpy(solution, path, depth);
                    metrics->host_seconds = search_now_seconds() - started;
                    return 1;
                }
                ++metrics->nodes_expanded;
            }

            while (frame->next_move < CUBE_MOVES && depth > 0 &&
                   frame->next_move / 3U == path[depth - 1] / 3U)
                ++frame->next_move;

            if (frame->next_move == CUBE_MOVES) {
                if (depth == 0)
                    break;
                --depth;
            } else {
                uint8_t move = frame->next_move++;
                ++metrics->children_generated;
                path[depth] = move;
                stack[depth + 1].state = cube_apply_move(frame->state, move);
                stack[depth + 1].heuristic =
                    heuristic(&stack[depth + 1].state, metrics);
                stack[depth + 1].entered = 0;
                ++depth;
            }
        }
        if (next_threshold == UCHAR_MAX)
            break;
        threshold = next_threshold;
    }
    metrics->host_seconds = search_now_seconds() - started;
    return 0;
}
