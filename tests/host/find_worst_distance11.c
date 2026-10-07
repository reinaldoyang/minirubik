#include "cube.h"
#include "exact_bfs.h"
#include "search.h"
#include "search_internal.h"

#include <inttypes.h>
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

enum { TOP_CANDIDATES = 10, MAX_FAILURE_EXAMPLES = 8 };

typedef struct {
    uint32_t combined_rank;
    uint16_t permutation_rank;
    uint16_t orientation_rank;
    uint64_t nodes_expanded;
    uint64_t children_generated;
    uint64_t search_iterations;
    uint64_t pdb_lookups;
} candidate_t;

static int candidate_is_better(const candidate_t *left,
                               const candidate_t *right)
{
    if (left->nodes_expanded != right->nodes_expanded)
        return left->nodes_expanded > right->nodes_expanded;
    if (left->children_generated != right->children_generated)
        return left->children_generated > right->children_generated;
    return left->combined_rank < right->combined_rank;
}

static void insert_candidate(candidate_t top[TOP_CANDIDATES],
                             size_t *top_count,
                             const candidate_t *candidate)
{
    size_t position;

    if (*top_count == TOP_CANDIDATES) {
        if (!candidate_is_better(candidate, &top[TOP_CANDIDATES - 1]))
            return;
        position = TOP_CANDIDATES - 1;
    } else {
        position = *top_count;
        ++*top_count;
    }

    while (position > 0 &&
           candidate_is_better(candidate, &top[position - 1])) {
        top[position] = top[position - 1];
        --position;
    }
    top[position] = *candidate;
}

static int solution_reaches_solved(cube_state_t state,
                                   const uint8_t solution[CUBE_DIAMETER],
                                   uint8_t length)
{
    uint8_t index;

    if (length > CUBE_DIAMETER)
        return 0;
    for (index = 0; index < length; ++index) {
        if (solution[index] >= CUBE_MOVES)
            return 0;
        state = cube_apply_move(state, solution[index]);
    }
    return cube_is_solved(&state);
}

static void format_state(const cube_state_t *state,
                         char text[2 * CUBE_CUBIES + 1])
{
    uint8_t index;

    for (index = 0; index < CUBE_CUBIES; ++index)
        text[index] = (char) ('1' + state->p[index]);
    for (index = 0; index < CUBE_CUBIES; ++index)
        text[CUBE_CUBIES + index] = (char) ('1' + state->o[index]);
    text[2 * CUBE_CUBIES] = '\0';
}

int main(void)
{
    candidate_t top[TOP_CANDIDATES];
    size_t top_count = 0;
    uint8_t *exact_distance;
    uint64_t distance11_states = 0;
    uint64_t invalid_results = 0;
    uint64_t started = search_now_nanoseconds();
    uint64_t elapsed;
    uint32_t rank;

    exact_distance = host_build_exact_bfs_distances();
    if (!exact_distance) {
        fputs("distance-11 scan failed while building BFS oracle\n", stderr);
        return 1;
    }
    idastar_build_pdbs();

    for (rank = 0; rank < CUBE_STATES; ++rank) {
        cube_state_t start;
        uint8_t solution[CUBE_DIAMETER];
        search_metrics_t metrics;
        candidate_t candidate;
        int search_succeeded;

        if (exact_distance[rank] == UCHAR_MAX) {
            fprintf(stderr, "BFS oracle left rank %" PRIu32 " unvisited\n",
                    rank);
            free(exact_distance);
            return 1;
        }
        if (exact_distance[rank] != CUBE_DIAMETER)
            continue;

        ++distance11_states;
        cube_unrank(rank, &start);
        search_succeeded = idastar_solve(start, solution, &metrics);
        if (!search_succeeded || metrics.solution_length != CUBE_DIAMETER ||
            !solution_reaches_solved(start, solution,
                                     metrics.solution_length)) {
            if (invalid_results < MAX_FAILURE_EXAMPLES) {
                fprintf(stderr,
                        "invalid result: rank=%" PRIu32
                        " search_ok=%d returned_length=%u\n",
                        rank, search_succeeded, metrics.solution_length);
            }
            ++invalid_results;
            continue;
        }

        candidate.combined_rank = rank;
        candidate.permutation_rank =
            (uint16_t) (rank / CUBE_ORIENTATIONS);
        candidate.orientation_rank =
            (uint16_t) (rank % CUBE_ORIENTATIONS);
        candidate.nodes_expanded = metrics.nodes_expanded;
        candidate.children_generated = metrics.children_generated;
        candidate.search_iterations = metrics.search_iterations;
        candidate.pdb_lookups = metrics.pdb_lookups;
        insert_candidate(top, &top_count, &candidate);
    }

    free(exact_distance);
    elapsed = search_now_nanoseconds() - started;

    puts("Distance-11 IDA* worst cases:");
    printf("  distance-11 states examined: %" PRIu64 "\n",
           distance11_states);
    printf("  invalid search results: %" PRIu64 "\n", invalid_results);
    puts("  top candidates:");
    if (top_count == 0)
        puts("    []");
    else {
        size_t index;
        for (index = 0; index < top_count; ++index) {
            cube_state_t state;
            char state_text[2 * CUBE_CUBIES + 1];

            cube_unrank(top[index].combined_rank, &state);
            format_state(&state, state_text);
            printf("    - {place: %u, state: %s, rank: %" PRIu32
                   ", permutation: %u, orientation: %u, nodes: %" PRIu64
                   ", children: %" PRIu64 ", iterations: %" PRIu64
                   ", pdb_lookups: %" PRIu64 "}\n",
                   (unsigned) (index + 1), state_text,
                   top[index].combined_rank, top[index].permutation_rank,
                   top[index].orientation_rank, top[index].nodes_expanded,
                   top[index].children_generated,
                   top[index].search_iterations, top[index].pdb_lookups);
        }
    }
    printf("  elapsed time: %" PRIu64 ".%06" PRIu64 " seconds\n",
           elapsed / UINT64_C(1000000000),
           (elapsed % UINT64_C(1000000000)) / UINT64_C(1000));
    printf("  status: %s\n", invalid_results == 0 && top_count != 0
                                  ? "PASS"
                                  : "FAIL");
    return invalid_results == 0 && top_count != 0 ? 0 : 1;
}
