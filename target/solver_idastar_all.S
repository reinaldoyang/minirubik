/*
 * Self-contained hand-written RV32I IDA* solver.
 * Default input: 21345671111111 (permutation rank 720, orientation rank 0).
 */

#ifndef TARGET_PERMUTATION_RANK
#define TARGET_PERMUTATION_RANK 720
#endif

#ifndef TARGET_ORIENTATION_RANK
#define TARGET_ORIENTATION_RANK 0
#endif

#ifndef TARGET_EXPECTED_LENGTH
#define TARGET_EXPECTED_LENGTH 11
#endif

/* ===== Startup ===== */
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

/* ===== Target harness and result storage ===== */
    .section .text.target_main,"ax",@progbits
    .option norvc
    .globl target_main
    .type target_main, @function

target_main:
    addi sp, sp, -16
    sw ra, 12(sp)
    sw s0, 8(sp)
    sw s1, 4(sp)
    sw s2, 0(sp)
    li s0, TARGET_PERMUTATION_RANK
    li s1, TARGET_ORIENTATION_RANK
    mv a0, s0
    mv a1, s1
    la a2, target_solution
    la a3, target_metrics
    call idastar_solve_ranks_asm
    mv s2, a0
    la t0, target_search_succeeded
    sw s2, 0(t0)

    /* A valid result must exist and have this case's exact BFS length. */
    beqz s2, .Lvalidation_failed
    la t0, target_metrics
    lbu a3, 0(t0)
    li t1, TARGET_EXPECTED_LENGTH
    bne a3, t1, .Lvalidation_failed

    /* Replay solution[] from the preserved input ranks. */
    mv a0, s0
    mv a1, s1
    la a2, target_solution
    call validate_solution_ranks_asm
    beqz a0, .Lvalidation_failed

    li s2, 1
    la a0, .Lvalidation_pass_message
    j .Lvalidation_result

.Lvalidation_failed:
    li s2, 0
    la a0, .Lvalidation_fail_message

.Lvalidation_result:
    la t0, target_validation_passed
    sw s2, 0(t0)
    li a7, 4
    ecall

    li t1, 1
    la t0, target_done
    sw t1, 0(t0)
    seqz a0, s2
    lw s2, 0(sp)
    lw s1, 4(sp)
    lw s0, 8(sp)
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

    .globl target_validation_passed
    .type target_validation_passed, @object
target_validation_passed:
    .space 4
    .size target_validation_passed, 4

    .globl target_done
    .type target_done, @object
target_done:
    .space 4
    .size target_done, 4

    .section .rodata.target_messages,"a",@progbits
.Lvalidation_pass_message:
    .asciz "validation: PASS\n"
.Lvalidation_fail_message:
    .asciz "validation: FAIL\n"

/* ===== In-target solution validation ===== */
    .section .text.validate_solution,"ax",@progbits
    .option norvc
    .type validate_solution_ranks_asm, @function

/*
 * a0: initial permutation rank
 * a1: initial orientation rank
 * a2: solution byte array
 * a3: solution length
 * returns a0 = 1 iff replay reaches ranks (0, 0)
 *
 * Leaf function: it uses only caller-saved registers and therefore needs no
 * stack frame.  Move encoding is face * 3 + turn, with turn 0/1/2 applying
 * the selected quarter-turn transition 1/2/3 times.
 */
validate_solution_ranks_asm:
    mv t0, a0                     /* current permutation rank */
    mv t1, a1                     /* current orientation rank */
    li t2, 0                      /* solution index */

.Lvalidate_next_move:
    bgeu t2, a3, .Lvalidate_final_state
    add t3, a2, t2
    lbu a4, 0(t3)                 /* encoded move */

    li t3, 3
    bltu a4, t3, .Lvalidate_face_zero
    li t3, 6
    bltu a4, t3, .Lvalidate_face_one
    li t3, 9
    bgeu a4, t3, .Lvalidate_invalid_move
    addi a4, a4, -6
    li a5, 16                     /* face 2 table-pair byte offset */
    j .Lvalidate_tables_ready

.Lvalidate_face_one:
    addi a4, a4, -3
    li a5, 8                      /* face 1 table-pair byte offset */
    j .Lvalidate_tables_ready

.Lvalidate_face_zero:
    li a5, 0

.Lvalidate_tables_ready:
    la t3, .Lturn_table_pairs
    add t3, t3, a5
    lw t4, 0(t3)                 /* permutation quarter-turn table */
    lw t5, 4(t3)                 /* orientation quarter-turn table */
    addi t6, a4, 1               /* 1, 2, or 3 quarter turns */

.Lvalidate_apply_quarter_turn:
    slli a6, t0, 1
    add a6, t4, a6
    lhu t0, 0(a6)
    slli a6, t1, 1
    add a6, t5, a6
    lhu t1, 0(a6)
    addi t6, t6, -1
    bnez t6, .Lvalidate_apply_quarter_turn

    addi t2, t2, 1
    j .Lvalidate_next_move

.Lvalidate_final_state:
    or t0, t0, t1
    seqz a0, t0
    ret

.Lvalidate_invalid_move:
    li a0, 0
    ret

    .size validate_solution_ranks_asm, .-validate_solution_ranks_asm

/* ===== IDA* search ===== */
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

    /* Apply once for turn 0, twice for turn 1, three times for turn 2. */
    slli a2, a0, 1
    add a2, t5, a2
    lhu a0, 0(a2)
    slli a2, a1, 1
    add a2, t4, a2
    lhu a1, 0(a2)
    beqz t2, .Lquarter_turns_done

    slli a2, a0, 1
    add a2, t5, a2
    lhu a0, 0(a2)
    slli a2, a1, 1
    add a2, t4, a2
    lhu a1, 0(a2)
    addi t3, t2, -1
    beqz t3, .Lquarter_turns_done

    slli a2, a0, 1
    add a2, t5, a2
    lhu a0, 0(a2)
    slli a2, a1, 1
    add a2, t4, a2
    lhu a1, 0(a2)

.Lquarter_turns_done:

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
