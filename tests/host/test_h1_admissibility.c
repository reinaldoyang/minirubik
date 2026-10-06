#include "cube.h"
#include "exact_bfs.h"
#include "search.h"
#include "search_internal.h"

#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

enum { MAX_VIOLATION_EXAMPLES = 8 };

typedef struct {
    uint32_t combined_rank;
    uint16_t permutation_rank;
    uint16_t orientation_rank;
    uint8_t heuristic;
    uint8_t exact_distance;
} violation_example_t;

int main(void)
{
    violation_example_t examples[MAX_VIOLATION_EXAMPLES];
    uint8_t *exact_distance;
    uint64_t states_checked = 0;
    uint64_t violations = 0;
    uint64_t exact_matches = 0;
    uint64_t heuristic_sum = 0;
    uint64_t exact_sum = 0;
    int64_t gap_sum = 0;
    uint8_t maximum_heuristic = 0;
    uint8_t maximum_exact_distance = 0;
    uint8_t maximum_gap = 0;
    uint32_t rank;
    uint64_t started = search_now_nanoseconds();
    uint64_t elapsed;

    exact_distance = host_build_exact_bfs_distances();
    if (!exact_distance) {
        fputs("H1 internal validation failed while building BFS oracle\n",
              stderr);
        return 1;
    }

    idastar_build_pdbs();
    for (rank = 0; rank < CUBE_STATES; ++rank) {
        uint16_t permutation =
            (uint16_t) (rank / CUBE_ORIENTATIONS);
        uint16_t orientation =
            (uint16_t) (rank % CUBE_ORIENTATIONS);
        uint8_t permutation_distance =
            idastar_permutation_distance(permutation);
        uint8_t orientation_distance =
            idastar_orientation_distance(orientation);
        uint8_t heuristic = permutation_distance > orientation_distance
                                ? permutation_distance
                                : orientation_distance;
        uint8_t exact = exact_distance[rank];
        int gap;

        if (exact == UCHAR_MAX) {
            fprintf(stderr, "H1 BFS oracle left rank %lu unvisited\n",
                    (unsigned long) rank);
            free(exact_distance);
            return 1;
        }
        ++states_checked;
        heuristic_sum += heuristic;
        exact_sum += exact;
        gap = (int) exact - (int) heuristic;
        gap_sum += gap;
        if (heuristic > maximum_heuristic)
            maximum_heuristic = heuristic;
        if (exact > maximum_exact_distance)
            maximum_exact_distance = exact;
        if (gap > maximum_gap)
            maximum_gap = (uint8_t) gap;
        if (heuristic == exact)
            ++exact_matches;
        if (heuristic > exact) {
            if (violations < MAX_VIOLATION_EXAMPLES) {
                examples[violations].combined_rank = rank;
                examples[violations].permutation_rank = permutation;
                examples[violations].orientation_rank = orientation;
                examples[violations].heuristic = heuristic;
                examples[violations].exact_distance = exact;
            }
            ++violations;
        }
    }
    free(exact_distance);
    elapsed = search_now_nanoseconds() - started;

    puts("H1 admissibility test:");
    printf("  states checked: %llu\n",
           (unsigned long long) states_checked);
    printf("  admissibility violations: %llu\n",
           (unsigned long long) violations);
    printf("  maximum heuristic: %u\n", maximum_heuristic);
    printf("  maximum exact distance: %u\n", maximum_exact_distance);
    printf("  exact heuristic matches: %llu (%.6f%%)\n",
           (unsigned long long) exact_matches,
           states_checked ? 100.0 * (double) exact_matches / states_checked
                          : 0.0);
    printf("  average heuristic: %.6f\n",
           states_checked ? (double) heuristic_sum / states_checked : 0.0);
    printf("  average exact distance: %.6f\n",
           states_checked ? (double) exact_sum / states_checked : 0.0);
    printf("  average gap: %.6f\n",
           states_checked ? (double) gap_sum / states_checked : 0.0);
    printf("  maximum gap: %u\n", maximum_gap);
    printf("  elapsed time: %llu.%06llu seconds\n",
           (unsigned long long) (elapsed / UINT64_C(1000000000)),
           (unsigned long long) ((elapsed % UINT64_C(1000000000)) /
                                 UINT64_C(1000)));
    if (violations != 0) {
        uint64_t i;
        uint64_t examples_to_print = violations < MAX_VIOLATION_EXAMPLES
                                         ? violations
                                         : MAX_VIOLATION_EXAMPLES;
        puts("  first violations:");
        for (i = 0; i < examples_to_print; ++i) {
            printf("    - {rank: %lu, permutation: %u, orientation: %u, "
                   "heuristic: %u, exact: %u}\n",
                   (unsigned long) examples[i].combined_rank,
                   examples[i].permutation_rank,
                   examples[i].orientation_rank, examples[i].heuristic,
                   examples[i].exact_distance);
        }
    }
    printf("  status: %s\n", violations == 0 ? "PASS" : "FAIL");
    return violations == 0 ? 0 : 1;
}
