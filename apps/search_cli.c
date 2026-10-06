#include "search_cli.h"
#include "search_internal.h"

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

static void print_seconds(FILE *stream, uint64_t nanoseconds)
{
    fprintf(stream, "%" PRIu64 ".%09" PRIu64,
            nanoseconds / UINT64_C(1000000000),
            nanoseconds % UINT64_C(1000000000));
}

static void print_human_metrics(const char *solver_name,
                                const search_metrics_t *metrics)
{
    fprintf(stderr,
            "%s: length=%u nodes=%" PRIu64 " children=%" PRIu64
            " iterations=%" PRIu64 " max_depth=%u pdb_lookups=%" PRIu64
            " seconds=",
            solver_name, metrics->solution_length, metrics->nodes_expanded,
            metrics->children_generated, metrics->search_iterations,
            metrics->maximum_stack_depth, metrics->pdb_lookups);
    print_seconds(stderr, metrics->host_nanoseconds);
    fprintf(stderr, " table_bytes=%" PRIu32 "\n",
            metrics->static_table_bytes);
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
    uint64_t started;
    if (!input || !cube_parse(input, &state)) {
        fprintf(stderr, "usage: %s [--csv] PPPPPPPOOOOOOO\n",
                argc > 0 && argv[0] ? argv[0] : solver_name);
        return 2;
    }
    started = search_now_nanoseconds();
    if (!solve(state, solution, &metrics)) {
        fputs("search failed\n", stderr);
        return 1;
    }
    metrics.host_nanoseconds = search_now_nanoseconds() - started;
    if (csv) {
        printf("%s,%s,%u,%" PRIu64 ",%" PRIu64 ",%" PRIu64
               ",%u,%" PRIu64 ",",
               solver_name, input, metrics.solution_length,
               metrics.nodes_expanded, metrics.children_generated,
               metrics.search_iterations, metrics.maximum_stack_depth,
               metrics.pdb_lookups);
        print_seconds(stdout, metrics.host_nanoseconds);
        printf(",%" PRIu32 ",\"", metrics.static_table_bytes);
        for (i = 0; i < metrics.solution_length; ++i)
            printf("%s%s", i ? " " : "", cube_move_names[solution[i]]);
        puts("\"");
    } else {
        print_solution(solution, metrics.solution_length);
        print_human_metrics(solver_name, &metrics);
    }
    return fflush(stdout) != 0 || ferror(stdout);
}
