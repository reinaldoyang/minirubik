#include "search.h"
#include "search_internal.h"

#include <string.h>

typedef struct {
    cube_state_t state;
    uint8_t next_move;
    uint8_t entered;
} iddfs_frame_t;

int iddfs_solve(cube_state_t start, uint8_t solution[CUBE_DIAMETER],
                search_metrics_t *metrics)
{
    iddfs_frame_t stack[CUBE_DIAMETER + 1];
    uint8_t path[CUBE_DIAMETER];
    uint8_t limit;
    double started = search_now_seconds();
    memset(metrics, 0, sizeof *metrics);

    for (limit = 0; limit <= CUBE_DIAMETER; ++limit) {
        uint8_t depth = 0;
        ++metrics->search_iterations;
        stack[0].state = start;
        stack[0].entered = 0;

        for (;;) {
            iddfs_frame_t *frame = &stack[depth];
            if (!frame->entered) {
                frame->entered = 1;
                frame->next_move = 0;
                if (depth > metrics->maximum_stack_depth)
                    metrics->maximum_stack_depth = depth;
                if (cube_is_solved(&frame->state)) {
                    metrics->solution_length = depth;
                    memcpy(solution, path, depth);
                    metrics->host_seconds = search_now_seconds() - started;
                    return 1;
                }
                if (depth == limit) {
                    if (depth == 0)
                        break;
                    --depth;
                    continue;
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
                stack[depth + 1].entered = 0;
                ++depth;
            }
        }
    }
    metrics->host_seconds = search_now_seconds() - started;
    return 0;
}
