#!/bin/sh
set -eu

echo 'solver,state,solution_length,nodes_expanded,children_generated,search_iterations,maximum_stack_depth,pdb_lookups,host_seconds,static_table_bytes,solution'

for state in 12345671111111 25314672313211 21345671111111; do
    ./solver_iddfs --csv "$state"
    ./solver_idastar --csv "$state"
done
