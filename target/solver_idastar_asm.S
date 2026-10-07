    .section .text.target_main,"ax",@progbits
    .option norvc
    .globl target_main
    .type target_main, @function

target_main:
    addi sp, sp, -16
    sw ra, 12(sp)
    li a0, 720                    /* permutation rank of 2134567 */
    li a1, 0                      /* orientation rank of 1111111 */
    la a2, target_solution
    la a3, target_metrics
    call idastar_solve_ranks_asm
    la t0, target_search_succeeded
    sw a0, 0(t0)
    li t1, 1
    la t0, target_done
    sw t1, 0(t0)
    seqz a0, a0
    lw ra, 12(sp)
    addi sp, sp, 16
    ret

    .size target_main, .-target_main

    .section .bss.target,"aw",@nobits
    .balign 16
    .globl target_stack
    .type target_stack, @object
target_stack:
    .space 2048
    .size target_stack, 2048

    .balign 8
    .globl target_metrics
    .type target_metrics, @object
target_metrics:
    .space 56
    .size target_metrics, 56

    .globl target_solution
    .type target_solution, @object
target_solution:
    .space 11
    .size target_solution, 11

    .balign 4
    .globl target_search_succeeded
    .type target_search_succeeded, @object
target_search_succeeded:
    .space 4
    .size target_search_succeeded, 4

    .globl target_done
    .type target_done, @object
target_done:
    .space 4
    .size target_done, 4
