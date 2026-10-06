#include "cube.h"
#include "exact_bfs.h"
#include "search.h"
#include "search_internal.h"

#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

enum { MAX_FAILURE_EXAMPLES = 8, PROGRESS_INTERVAL = 100000 };

typedef struct {
    uint32_t combined_rank;
    uint16_t permutation_rank;
    uint16_t orientation_rank;
    uint8_t exact_distance;
    uint8_t returned_length;
    int search_succeeded;
    int solution_solved;
} failure_example_t;

int main(void)
{
    failure_example_t examples[MAX_FAILURE_EXAMPLES];
    uint8_t *exact_distance;
    uint64_t states_checked = 0;
    uint64_t search_failures = 0;
    uint64_t length_mismatches = 0;
    uint64_t invalid_solutions = 0;
    uint64_t total_nodes_expanded = 0;
    uint64_t failures = 0;
    uint32_t rank;
    double started = search_now_seconds();
    double elapsed;

    exact_distance = host_build_exact_bfs_distances();
    if (!exact_distance) {
        fputs("H3 internal validation failed while building BFS oracle\n",
              stderr);
        return 1;
    }
    idastar_build_pdbs();

    for (rank = 0; rank < CUBE_STATES; ++rank) {
        cube_state_t start;
        cube_state_t result;
        uint8_t solution[CUBE_DIAMETER];
        search_metrics_t metrics;
        uint8_t exact = exact_distance[rank];
        int solved;
        int search_succeeded;
        uint8_t move_index;

        if (exact == UCHAR_MAX) {
            fprintf(stderr, "H3 BFS oracle left rank %lu unvisited\n",
                    (unsigned long) rank);
            free(exact_distance);
            return 1;
        }
        cube_unrank(rank, &start);
        search_succeeded = idastar_solve(start, solution, &metrics);
        total_nodes_expanded += metrics.nodes_expanded;
        result = start;
        if (search_succeeded) {
            for (move_index = 0; move_index < metrics.solution_length;
                 ++move_index)
                result = cube_apply_move(result, solution[move_index]);
        }
        solved = search_succeeded && cube_is_solved(&result);

        ++states_checked;
        if (!search_succeeded)
            ++search_failures;
        if (!search_succeeded || metrics.solution_length != exact)
            ++length_mismatches;
        if (!solved)
            ++invalid_solutions;
        if (!search_succeeded || metrics.solution_length != exact || !solved) {
            if (failures < MAX_FAILURE_EXAMPLES) {
                examples[failures].combined_rank = rank;
                examples[failures].permutation_rank =
                    (uint16_t) (rank / CUBE_ORIENTATIONS);
                examples[failures].orientation_rank =
                    (uint16_t) (rank % CUBE_ORIENTATIONS);
                examples[failures].exact_distance = exact;
                examples[failures].returned_length = metrics.solution_length;
                examples[failures].search_succeeded = search_succeeded;
                examples[failures].solution_solved = solved;
            }
            ++failures;
        }

        if ((rank + 1U) % PROGRESS_INTERVAL == 0) {
            fprintf(stderr, "H3 progress: %lu/%d states (%.2f%%)\n",
                    (unsigned long) (rank + 1U), CUBE_STATES,
                    100.0 * (double) (rank + 1U) / CUBE_STATES);
            fflush(stderr);
        }
    }
    free(exact_distance);
    elapsed = search_now_seconds() - started;

    puts("H3 optimality test:");
    printf("  states checked: %llu\n",
           (unsigned long long) states_checked);
    printf("  search failures: %llu\n",
           (unsigned long long) search_failures);
    printf("  length mismatches: %llu\n",
           (unsigned long long) length_mismatches);
    printf("  invalid returned solutions: %llu\n",
           (unsigned long long) invalid_solutions);
    printf("  total nodes expanded: %llu\n",
           (unsigned long long) total_nodes_expanded);
    printf("  elapsed time: %.6f seconds\n", elapsed);
    if (failures != 0) {
        uint64_t i;
        uint64_t examples_to_print = failures < MAX_FAILURE_EXAMPLES
                                         ? failures
                                         : MAX_FAILURE_EXAMPLES;
        puts("  first failures:");
        for (i = 0; i < examples_to_print; ++i) {
            printf("    - {rank: %lu, permutation: %u, orientation: %u, "
                   "exact: %u, returned: %u, search_ok: %d, solved: %d}\n",
                   (unsigned long) examples[i].combined_rank,
                   examples[i].permutation_rank,
                   examples[i].orientation_rank,
                   examples[i].exact_distance,
                   examples[i].returned_length,
                   examples[i].search_succeeded,
                   examples[i].solution_solved);
        }
    }
    printf("  status: %s\n", failures == 0 ? "PASS" : "FAIL");
    return failures == 0 ? 0 : 1;
}
