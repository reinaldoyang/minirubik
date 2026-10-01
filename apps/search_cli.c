#include "search_cli.h"

#include <inttypes.h>
#include <stdio.h>
#include <string.h>

static void print_solution(const uint8_t *solution, uint8_t length)
{
    uint8_t i;
    for (i = 0; i < length; ++i)
        printf("%s%s", i ? " " : "", cube_move_names[solution[i]]);
    putchar('\n');
}

static void print_human_metrics(const char *solver_name,
                                const search_metrics_t *metrics)
{
    fprintf(stderr,
            "%s: length=%u nodes=%" PRIu64 " children=%" PRIu64
            " iterations=%" PRIu64 " max_depth=%u pdb_lookups=%" PRIu64
            " seconds=%.9f table_bytes=%" PRIu32 "\n",
            solver_name, metrics->solution_length, metrics->nodes_expanded,
            metrics->children_generated, metrics->search_iterations,
            metrics->maximum_stack_depth, metrics->pdb_lookups,
            metrics->host_seconds, metrics->static_table_bytes);
}

int search_cli(int argc, char **argv, const char *solver_name,
               search_solver_t solve)
{
    int csv = argc == 3 && !strcmp(argv[1], "--csv");
    const char *input = csv ? argv[2] : argc == 2 ? argv[1] : NULL;
    cube_state_t state;
    uint8_t solution[CUBE_DIAMETER];
    search_metrics_t metrics;
    uint8_t i;
    if (!input || !cube_parse(input, &state)) {
        fprintf(stderr, "usage: %s [--csv] PPPPPPPOOOOOOO\n",
                argc > 0 && argv[0] ? argv[0] : solver_name);
        return 2;
    }
    if (!solve(state, solution, &metrics)) {
        fputs("search failed\n", stderr);
        return 1;
    }
    if (csv) {
        printf("%s,%s,%u,%" PRIu64 ",%" PRIu64 ",%" PRIu64
               ",%u,%" PRIu64 ",%.9f,%" PRIu32 ",\"",
               solver_name, input, metrics.solution_length,
               metrics.nodes_expanded, metrics.children_generated,
               metrics.search_iterations, metrics.maximum_stack_depth,
               metrics.pdb_lookups, metrics.host_seconds,
               metrics.static_table_bytes);
        for (i = 0; i < metrics.solution_length; ++i)
            printf("%s%s", i ? " " : "", cube_move_names[solution[i]]);
        puts("\"");
    } else {
        print_solution(solution, metrics.solution_length);
        print_human_metrics(solver_name, &metrics);
    }
    return fflush(stdout) != 0 || ferror(stdout);
}
