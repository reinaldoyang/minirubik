    .section .text.idastar_asm,"ax",@progbits
    .option norvc
    .globl idastar_solve_ranks_asm
    .type idastar_solve_ranks_asm, @function

/*
 * a0: permutation rank
 * a1: orientation rank
 * a2: solution byte array (11 bytes)
 * a3: search_metrics_t-compatible output (56 bytes)
 * returns a0 = 1 on success, 0 on failure
 */
idastar_solve_ranks_asm:
    addi sp, sp, -192
    sw ra, 140(sp)
    sw s0, 144(sp)
    sw s1, 148(sp)
    sw s2, 152(sp)
    sw s3, 156(sp)
    sw s4, 160(sp)
    sw s5, 164(sp)
    sw s6, 168(sp)
    sw s7, 172(sp)
    sw s8, 176(sp)
    sw s9, 180(sp)
    sw s10, 184(sp)
    sw s11, 188(sp)

    /* Local layout: frames[12] at 0, path at 96, path faces at 108. */
    mv s3, sp
    addi s4, sp, 96
    addi s5, sp, 108
    mv s6, a2
    mv s7, a3
    la s8, .Lturn_table_pairs
    la s9, idastar_permutation_pdb
    la s10, idastar_orientation_pdb
    sw a0, 120(sp)
    sw a1, 124(sp)

    /* Clear all metric fields and padding. */
    mv t0, s7
    li t1, 14
.Lclear_metrics:
    sw zero, 0(t0)
    addi t0, t0, 4
    addi t1, t1, -1
    bnez t1, .Lclear_metrics
    li t0, 40407
    sw t0, 48(s7)

    /* Root heuristic: max(permutation PDB, orientation PDB). */
    lw t0, 120(sp)
    add t0, s9, t0
    lbu t0, 0(t0)
    lw t1, 124(sp)
    add t1, s10, t1
    lbu t1, 0(t1)
    bgeu t0, t1, .Lroot_h_ready
    mv t0, t1
.Lroot_h_ready:
    sb t0, 128(sp)
    mv s1, t0
    li s11, 0                    /* nodes expanded */
    li a6, 0                     /* children generated */
    li a7, 0                     /* maximum stack depth */
    li t6, 0                     /* search iterations */

.Lthreshold_loop:
    li t0, 11
    bltu t0, s1, .Lsearch_failed
    li s0, 0                     /* depth */
    li s2, 255                   /* next threshold */
    addi t6, t6, 1
    lw t0, 120(sp)
    sh t0, 0(s3)
    lw t0, 124(sp)
    sh t0, 2(s3)
    sb zero, 6(s3)
    lbu t0, 128(sp)
    sb t0, 7(s3)

.Ldfs_loop:
    slli t0, s0, 3
    add t0, s3, t0              /* t0 = current frame */
    lbu t1, 6(t0)
    bnez t1, .Lframe_expanded

    /* Enter the frame and enforce the f = g + h threshold. */
    lbu t2, 7(t0)
    add t3, s0, t2
    sb zero, 4(t0)
    sb zero, 5(t0)
    li t1, 1
    sb t1, 6(t0)
    bgeu a7, s0, .Lmax_depth_ready
    mv a7, s0
.Lmax_depth_ready:
    bgeu s1, t3, .Lwithin_threshold
    bgeu t3, s2, .Lpruned
    mv s2, t3
.Lpruned:
    beqz s0, .Literation_done
    addi s0, s0, -1
    j .Ldfs_loop

.Lwithin_threshold:
    lhu t1, 0(t0)
    bnez t1, .Lnot_solved
    lhu t1, 2(t0)
    beqz t1, .Lsearch_succeeded
.Lnot_solved:
    addi s11, s11, 1

.Lframe_expanded:
    lbu t1, 4(t0)               /* next face */
    beqz s0, .Lface_ready
    addi t2, s0, -1
    add t2, s5, t2
    lbu t2, 0(t2)
    bne t1, t2, .Lface_ready
    addi t1, t1, 1
    sb t1, 4(t0)
    sb zero, 5(t0)
.Lface_ready:
    li t2, 3
    bne t1, t2, .Lgenerate_child
    beqz s0, .Literation_done
    addi s0, s0, -1
    j .Ldfs_loop

.Lgenerate_child:
    lbu t2, 5(t0)               /* turn index: 0, 1, or 2 */
    addi t3, t2, 1              /* quarter-turn repetitions */
    li t4, 3
    bne t3, t4, .Lstore_next_turn
    sb zero, 5(t0)
    addi t4, t1, 1
    sb t4, 4(t0)
    j .Lselect_tables
.Lstore_next_turn:
    sb t3, 5(t0)

.Lselect_tables:
    slli t4, t1, 3
    add t4, s8, t4
    lw t5, 0(t4)                /* permutation quarter-turn table */
    lw t4, 4(t4)                /* orientation quarter-turn table */
    lhu a0, 0(t0)
    lhu a1, 2(t0)
.Lapply_quarter_turn:
    slli a2, a0, 1
    add a2, t5, a2
    lhu a0, 0(a2)
    slli a2, a1, 1
    add a2, t4, a2
    lhu a1, 0(a2)
    addi t3, t3, -1
    bnez t3, .Lapply_quarter_turn

    addi a6, a6, 1
    slli t3, t1, 1
    add t3, t3, t1
    add t3, t3, t2             /* move = face * 3 + turn */
    add t4, s4, s0
    sb t3, 0(t4)
    add t4, s5, s0
    sb t1, 0(t4)

    addi t0, t0, 8             /* child frame */
    sh a0, 0(t0)
    sh a1, 2(t0)
    add t3, s9, a0
    lbu t3, 0(t3)
    add t4, s10, a1
    lbu t4, 0(t4)
    bgeu t3, t4, .Lchild_h_ready
    mv t3, t4
.Lchild_h_ready:
    sb zero, 6(t0)
    sb t3, 7(t0)
    addi s0, s0, 1
    j .Ldfs_loop

.Literation_done:
    li t0, 255
    beq s2, t0, .Lsearch_failed
    mv s1, s2
    j .Lthreshold_loop

.Lsearch_succeeded:
    sb s0, 0(s7)
    li t0, 0
.Lcopy_solution:
    bgeu t0, s0, .Lsuccess_metrics
    add t1, s4, t0
    lbu t2, 0(t1)
    add t1, s6, t0
    sb t2, 0(t1)
    addi t0, t0, 1
    j .Lcopy_solution
.Lsuccess_metrics:
    li t5, 1
    j .Lwrite_metrics

.Lsearch_failed:
    li t5, 0

.Lwrite_metrics:
    sb a7, 1(s7)
    sw s11, 8(s7)
    sw zero, 12(s7)
    sw a6, 16(s7)
    sw zero, 20(s7)
    sw t6, 24(s7)
    sw zero, 28(s7)
    addi t0, a6, 1
    slli t0, t0, 1
    sw t0, 32(s7)
    sw zero, 36(s7)
    mv a0, t5

    lw ra, 140(sp)
    lw s0, 144(sp)
    lw s1, 148(sp)
    lw s2, 152(sp)
    lw s3, 156(sp)
    lw s4, 160(sp)
    lw s5, 164(sp)
    lw s6, 168(sp)
    lw s7, 172(sp)
    lw s8, 176(sp)
    lw s9, 180(sp)
    lw s10, 184(sp)
    lw s11, 188(sp)
    addi sp, sp, 192
    ret

    .size idastar_solve_ranks_asm, .-idastar_solve_ranks_asm

    .section .rodata.idastar_asm_tables,"a",@progbits
    .balign 4
.Lturn_table_pairs:
    .word idastar_permutation_turn_r
    .word idastar_orientation_turn_r
    .word idastar_permutation_turn_b
    .word idastar_orientation_turn_b
    .word idastar_permutation_turn_d
    .word idastar_orientation_turn_d
