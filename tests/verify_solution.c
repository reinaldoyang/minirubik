#include "cube.h"

#include <stdio.h>

int main(int argc, char **argv)
{
    cube_state_t state;
    int i;
    if (argc < 2 || !cube_parse(argv[1], &state)) {
        fputs("invalid state\n", stderr);
        return 2;
    }
    for (i = 2; i < argc; ++i) {
        int move = cube_move_from_name(argv[i]);
        if (move < 0) {
            fprintf(stderr, "invalid move: %s\n", argv[i]);
            return 2;
        }
        state = cube_apply_move(state, (uint8_t) move);
    }
    if (!cube_is_solved(&state)) {
        fputs("solution does not solve the state\n", stderr);
        return 1;
    }
    return 0;
}
