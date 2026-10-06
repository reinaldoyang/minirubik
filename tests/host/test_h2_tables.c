#include "cube.h"
#include "idastar_tables.h"
#include "search.h"

#include <limits.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

typedef uint8_t (*distance_fn_t)(uint16_t rank);
typedef void (*unrank_fn_t)(uint16_t rank, cube_state_t *state);
typedef uint16_t (*rank_fn_t)(const cube_state_t *state);

typedef struct {
    size_t expected_entries;
    size_t actual_entries;
    size_t populated_entries;
    size_t unvisited_entries;
    size_t unexpected_zero_entries;
    size_t predecessor_failures;
    size_t histogram[UCHAR_MAX + 1U];
    uint16_t solved_rank;
    uint8_t solved_value;
    uint8_t maximum_distance;
    int passed;
} table_report_t;

static table_report_t inspect_table(size_t expected_entries,
                                    size_t actual_entries,
                                    uint16_t solved_rank,
                                    uint8_t sentinel,
                                    distance_fn_t distance,
                                    unrank_fn_t unrank,
                                    rank_fn_t rank_state)
{
    table_report_t report;
    size_t rank;
    memset(&report, 0, sizeof report);
    report.expected_entries = expected_entries;
    report.actual_entries = actual_entries;
    report.solved_rank = solved_rank;
    report.solved_value = sentinel;

    for (rank = 0; rank < actual_entries; ++rank) {
        uint8_t value = distance((uint16_t) rank);
        if (value == sentinel) {
            ++report.unvisited_entries;
            continue;
        }
        ++report.populated_entries;
        ++report.histogram[value];
        if (value > report.maximum_distance)
            report.maximum_distance = value;
        if (rank != solved_rank && value == 0)
            ++report.unexpected_zero_entries;
    }

    if (solved_rank < actual_entries)
        report.solved_value = distance(solved_rank);

    for (rank = 0; rank < actual_entries && rank < expected_entries; ++rank) {
        uint8_t value = distance((uint16_t) rank);
        cube_state_t state;
        uint8_t move;
        int found_predecessor = 0;
        if (rank == solved_rank || value == sentinel || value == 0)
            continue;
        unrank((uint16_t) rank, &state);
        for (move = 0; move < CUBE_MOVES; ++move) {
            cube_state_t neighbor = cube_apply_move(state, move);
            uint16_t neighbor_rank = rank_state(&neighbor);
            if (distance(neighbor_rank) == (uint8_t) (value - 1U)) {
                found_predecessor = 1;
                break;
            }
        }
        if (!found_predecessor)
            ++report.predecessor_failures;
    }

    report.passed =
        report.actual_entries == report.expected_entries &&
        report.populated_entries == report.expected_entries &&
        report.unvisited_entries == 0 && report.solved_rank == 0 &&
        report.solved_value == 0 && report.unexpected_zero_entries == 0 &&
        report.predecessor_failures == 0;
    return report;
}

static void print_report(const char *name, const table_report_t *report,
                         uint8_t sentinel)
{
    unsigned distance;
    int separator = 0;
    printf("%s:\n", name);
    printf("  expected entries: %lu\n",
           (unsigned long) report->expected_entries);
    printf("  actual entries: %lu\n", (unsigned long) report->actual_entries);
    printf("  populated entries: %lu\n",
           (unsigned long) report->populated_entries);
    printf("  unvisited sentinel: %u\n", sentinel);
    printf("  unvisited entries: %lu\n",
           (unsigned long) report->unvisited_entries);
    printf("  solved rank: %u\n", report->solved_rank);
    printf("  solved value: %u\n", report->solved_value);
    printf("  maximum distance: %u\n", report->maximum_distance);
    printf("  histogram: {");
    for (distance = 0; distance <= report->maximum_distance; ++distance) {
        if (report->histogram[distance] != 0) {
            printf("%s%u: %lu", separator ? ", " : "", distance,
                   (unsigned long) report->histogram[distance]);
            separator = 1;
        }
    }
    puts("}");
    printf("  unexpected zero entries: %lu\n",
           (unsigned long) report->unexpected_zero_entries);
    printf("  entries without distance-1 neighbor: %lu\n",
           (unsigned long) report->predecessor_failures);
    printf("  status: %s\n\n", report->passed ? "PASS" : "FAIL");
}

static int inspect_transition_tables(void)
{
    const uint16_t *const permutation_tables[CUBE_FACES] = {
        idastar_permutation_turn_r,
        idastar_permutation_turn_b,
        idastar_permutation_turn_d,
    };
    const uint16_t *const orientation_tables[CUBE_FACES] = {
        idastar_orientation_turn_r,
        idastar_orientation_turn_b,
        idastar_orientation_turn_d,
    };
    size_t invalid_entries = 0;
    size_t mismatches = 0;
    uint16_t rank;

    for (rank = 0; rank < CUBE_PERMUTATIONS; ++rank) {
        cube_state_t state;
        uint8_t face;
        cube_unrank_permutation(rank, &state);
        for (face = 0; face < CUBE_FACES; ++face) {
            cube_state_t next = cube_quarter_turn(state, face);
            uint16_t expected = cube_rank_permutation(&next);
            uint16_t actual = permutation_tables[face][rank];
            if (actual >= CUBE_PERMUTATIONS)
                ++invalid_entries;
            if (actual != expected)
                ++mismatches;
        }
    }
    for (rank = 0; rank < CUBE_ORIENTATIONS; ++rank) {
        cube_state_t state;
        uint8_t face;
        cube_unrank_orientation(rank, &state);
        for (face = 0; face < CUBE_FACES; ++face) {
            cube_state_t next = cube_quarter_turn(state, face);
            uint16_t expected = cube_rank_orientation(&next);
            uint16_t actual = orientation_tables[face][rank];
            if (actual >= CUBE_ORIENTATIONS)
                ++invalid_entries;
            if (actual != expected)
                ++mismatches;
        }
    }

    puts("Rank-transition tables:");
    printf("  expected entries: %u\n",
           CUBE_FACES * (CUBE_PERMUTATIONS + CUBE_ORIENTATIONS));
    printf("  invalid entries: %lu\n", (unsigned long) invalid_entries);
    printf("  cube-model mismatches: %lu\n", (unsigned long) mismatches);
    printf("  status: %s\n\n",
           invalid_entries == 0 && mismatches == 0 ? "PASS" : "FAIL");
    return invalid_entries == 0 && mismatches == 0;
}

int main(void)
{
    uint8_t sentinel = idastar_pdb_unvisited_value();
    uint16_t solved_permutation_rank = cube_rank_permutation(&cube_solved);
    uint16_t solved_orientation_rank = cube_rank_orientation(&cube_solved);
    table_report_t permutation;
    table_report_t orientation;
    int transitions_passed;

    idastar_build_pdbs();
    permutation = inspect_table(
        CUBE_PERMUTATIONS, idastar_permutation_pdb_entries(),
        solved_permutation_rank, sentinel, idastar_permutation_distance,
        cube_unrank_permutation, cube_rank_permutation);
    orientation = inspect_table(
        CUBE_ORIENTATIONS, idastar_orientation_pdb_entries(),
        solved_orientation_rank, sentinel, idastar_orientation_distance,
        cube_unrank_orientation, cube_rank_orientation);

    print_report("Permutation PDB", &permutation, sentinel);
    print_report("Orientation PDB", &orientation, sentinel);
    transitions_passed = inspect_transition_tables();
    printf("H2: %s\n",
           permutation.passed && orientation.passed && transitions_passed
               ? "PASS"
               : "FAIL");
    return permutation.passed && orientation.passed && transitions_passed ? 0
                                                                           : 1;
}
