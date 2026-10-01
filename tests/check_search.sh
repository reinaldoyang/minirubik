#!/bin/sh
set -eu

states='12345671111111
25314672313211
21345671111111'

move_count()
{
    set -- $1
    echo "$#"
}

for state in $states; do
    oracle=$(./solver "$state")
    oracle_length=$(move_count "$oracle")
    for binary in ./solver_iddfs ./solver_idastar; do
        answer=$($binary "$state" 2>/dev/null)
        answer_length=$(move_count "$answer")
        if test "$answer_length" -ne "$oracle_length"; then
            echo "$binary $state: length $answer_length, BFS oracle $oracle_length" >&2
            exit 1
        fi
        # Word splitting intentionally passes each printed move as one argument.
        ./search_verify "$state" $answer
    done
    echo "$state: both searches match BFS length $oracle_length and solve"
done
