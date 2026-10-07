#include "cube.h"
#include "search.h"

#include <stdint.h>

/*
 * Default target case: 21345671111111.
 * Input digits are stored zero-based, as required by cube_state_t.
 */
static const cube_state_t target_start_state = {
    {1, 0, 2, 3, 4, 5, 6},
    {0, 0, 0, 0, 0, 0, 0},
};

/* Exported symbols can be inspected in Ripes after execution. */
uint8_t target_solution[CUBE_DIAMETER];
search_metrics_t target_metrics;
uint32_t target_search_succeeded;
volatile uint32_t target_done;

/* The startup code uses this fixed area instead of heap allocation. */
uint8_t target_stack[2048] __attribute__((aligned(16)));

int target_main(void)
{
    target_search_succeeded =
        (uint32_t) idastar_solve(target_start_state, target_solution,
                                 &target_metrics);
    target_done = 1;
    return target_search_succeeded ? 0 : 1;
}
