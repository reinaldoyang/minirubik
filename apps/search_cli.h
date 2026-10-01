#ifndef SEARCH_CLI_H
#define SEARCH_CLI_H

#include "search.h"

typedef int (*search_solver_t)(cube_state_t start,
                               uint8_t solution[CUBE_DIAMETER],
                               search_metrics_t *metrics);

int search_cli(int argc, char **argv, const char *solver_name,
               search_solver_t solve);

#endif
