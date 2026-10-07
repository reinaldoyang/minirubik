    .section .text.start,"ax",@progbits
    .option norvc
    .globl _start
    .type _start, @function

_start:
    .option push
    .option norelax
    la gp, __global_pointer$
    .option pop
    la sp, target_stack
    li t0, 2048
    add sp, sp, t0
    call target_main
    li a7, 10
    ecall

1:
    j 1b

    .size _start, .-_start
