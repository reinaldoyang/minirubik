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

#ifndef RENDER
#define RENDER 0
#endif

#ifndef RENDER_DELAY
#define RENDER_DELAY 500000
#endif

    .equ RENDER_ENABLED, RENDER
    .equ RENDER_DELAY_COUNT, RENDER_DELAY

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

    /* Show the scrambled input before the solver starts. */
    .if RENDER_ENABLED
    mv a0, s0
    mv a1, s1
    call render_initial_state
    .endif

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

    /* The GUI build animates only the returned solution, never search nodes. */
    .if RENDER_ENABLED
    la a0, target_solution
    mv a1, a3
    call animate_solution
    la t0, target_metrics
    lbu a3, 0(t0)
    .endif

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

    .if RENDER_ENABLED
    .balign 4
target_render_position:
    .space 8
target_render_orientation:
    .space 8
target_render_available:
    .space 7
target_render_next_position:
    .space 7
target_render_next_orientation:
    .space 7
    .endif

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

/* ===== Optional Ripes LED cube renderer ===== */
    .if RENDER_ENABLED
    .section .text.led_renderer,"ax",@progbits
    .option norvc

/*
 * Reconstruct and draw the initial state before IDA* starts.
 */
render_initial_state:
    addi sp, sp, -16
    sw ra, 12(sp)
    call unrank_render_state
    call clear_led_matrix
    call render_cube
    call render_delay
    lw ra, 12(sp)
    addi sp, sp, 16
    ret

/*
 * Replay and redraw every move returned by IDA*.
 * a0: solution byte array
 * a1: solution length
 */
animate_solution:
    addi sp, sp, -32
    sw ra, 28(sp)
    sw s0, 24(sp)
    sw s1, 20(sp)
    sw s2, 16(sp)
    mv s0, a0
    mv s1, a1
    li s2, 0

.Lanimate_next_move:
    bgeu s2, s1, .Lanimate_done
    add t0, s0, s2
    lbu a0, 0(t0)
    call apply_render_move
    call render_cube
    call render_delay
    addi s2, s2, 1
    j .Lanimate_next_move

.Lanimate_done:
    lw s2, 16(sp)
    lw s1, 20(sp)
    lw s0, 24(sp)
    lw ra, 28(sp)
    addi sp, sp, 32
    ret

/* Convert the two search ranks into p[8] and o[8] for drawing. */
unrank_render_state:
    addi sp, sp, -32
    sw ra, 28(sp)
    sw s0, 24(sp)
    sw s1, 20(sp)
    sw s2, 16(sp)
    sw s3, 12(sp)
    sw s4, 8(sp)
    sw s5, 4(sp)
    sw s6, 0(sp)
    mv s0, a0                    /* permutation rank */
    mv s6, a1                    /* orientation rank */
    la s3, target_render_position
    la s4, target_render_available

    /* available[] = {0, 1, 2, 3, 4, 5, 6}. */
    li t0, 0
.Lrender_init_available:
    add t1, s4, t0
    sb t0, 0(t1)
    addi t0, t0, 1
    li t1, 7
    bltu t0, t1, .Lrender_init_available

    la s1, .Lrender_factors
    li s2, 0                     /* destination position */
    li s5, 7                     /* available entries */

.Lrender_unrank_permutation:
    lhu t0, 0(s1)                /* factorial divisor */
    li t1, 0                     /* quotient */
.Lrender_permutation_divide:
    bltu s0, t0, .Lrender_permutation_digit
    sub s0, s0, t0
    addi t1, t1, 1
    j .Lrender_permutation_divide

.Lrender_permutation_digit:
    add t2, s4, t1
    lbu t3, 0(t2)
    add t4, s3, s2
    sb t3, 0(t4)

    /* Delete available[quotient] by shifting later entries left. */
    mv t2, t1
.Lrender_shift_available:
    addi t3, t2, 1
    bgeu t3, s5, .Lrender_shift_done
    add t4, s4, t3
    lbu t5, 0(t4)
    add t4, s4, t2
    sb t5, 0(t4)
    mv t2, t3
    j .Lrender_shift_available

.Lrender_shift_done:
    addi s2, s2, 1
    addi s1, s1, 2
    addi s5, s5, -1
    li t0, 7
    bltu s2, t0, .Lrender_unrank_permutation
    li t0, 7                     /* fixed UFL corner */
    sb t0, 7(s3)

    /* Decode six base-3 digits, then derive the constrained seventh. */
    la s3, target_render_orientation
    li s2, 5
    li s5, 0                     /* orientation sum */
.Lrender_unrank_orientation:
    mv t0, s6                    /* remainder */
    li t1, 0                     /* quotient */
    li t2, 3
.Lrender_orientation_divide:
    bltu t0, t2, .Lrender_orientation_digit
    addi t0, t0, -3
    addi t1, t1, 1
    j .Lrender_orientation_divide

.Lrender_orientation_digit:
    add t3, s3, s2
    sb t0, 0(t3)
    add s5, s5, t0
    mv s6, t1
    beqz s2, .Lrender_orientation_constraint
    addi s2, s2, -1
    j .Lrender_unrank_orientation

.Lrender_orientation_constraint:
    li t0, 3
.Lrender_sum_modulo:
    bltu s5, t0, .Lrender_sum_ready
    addi s5, s5, -3
    j .Lrender_sum_modulo
.Lrender_sum_ready:
    beqz s5, .Lrender_last_orientation_zero
    sub t0, t0, s5
    j .Lrender_store_last_orientation
.Lrender_last_orientation_zero:
    li t0, 0
.Lrender_store_last_orientation:
    sb t0, 6(s3)
    sb zero, 7(s3)               /* fixed UFL corner */

    lw s6, 0(sp)
    lw s5, 4(sp)
    lw s4, 8(sp)
    lw s3, 12(sp)
    lw s2, 16(sp)
    lw s1, 20(sp)
    lw s0, 24(sp)
    lw ra, 28(sp)
    addi sp, sp, 32
    ret

/* Apply one encoded R/R2/R'/B/B2/B'/D/D2/D' move to p[] and o[]. */
apply_render_move:
    addi sp, sp, -32
    sw ra, 28(sp)
    sw s0, 24(sp)
    sw s1, 20(sp)
    sw s2, 16(sp)
    sw s3, 12(sp)
    sw s4, 8(sp)
    sw s5, 4(sp)
    sw s6, 0(sp)

    li t0, 3
    bltu a0, t0, .Lrender_move_r
    li t0, 6
    bltu a0, t0, .Lrender_move_b
    li t0, 9
    bgeu a0, t0, .Lrender_move_done
    addi s2, a0, -5             /* D repetitions: move - 6 + 1 */
    li s1, 14
    j .Lrender_move_tables
.Lrender_move_b:
    addi s2, a0, -2             /* B repetitions: move - 3 + 1 */
    li s1, 7
    j .Lrender_move_tables
.Lrender_move_r:
    addi s2, a0, 1
    li s1, 0

.Lrender_move_tables:
    la s3, .Lrender_move_sources
    add s3, s3, s1
    la s4, .Lrender_move_twists
    add s4, s4, s1
    la s5, target_render_position
    la s6, target_render_orientation

.Lrender_move_quarter_turn:
    li t0, 0
.Lrender_move_destination:
    add t6, s3, t0
    lbu t1, 0(t6)                /* source position */
    add t6, s5, t1
    lbu t2, 0(t6)
    la t3, target_render_next_position
    add t3, t3, t0
    sb t2, 0(t3)

    add t6, s6, t1
    lbu t2, 0(t6)
    add t6, s4, t0
    lbu t3, 0(t6)
    add t2, t2, t3
    li t3, 3
    bltu t2, t3, .Lrender_move_orientation_ready
    addi t2, t2, -3
.Lrender_move_orientation_ready:
    la t3, target_render_next_orientation
    add t3, t3, t0
    sb t2, 0(t3)

    addi t0, t0, 1
    li t1, 7
    bltu t0, t1, .Lrender_move_destination

    li t0, 0
    la t1, target_render_next_position
    la t2, target_render_next_orientation
.Lrender_move_copy:
    add t3, t1, t0
    lbu t4, 0(t3)
    add t3, s5, t0
    sb t4, 0(t3)
    add t3, t2, t0
    lbu t4, 0(t3)
    add t3, s6, t0
    sb t4, 0(t3)
    addi t0, t0, 1
    li t3, 7
    bltu t0, t3, .Lrender_move_copy

    addi s2, s2, -1
    bnez s2, .Lrender_move_quarter_turn

.Lrender_move_done:
    lw s6, 0(sp)
    lw s5, 4(sp)
    lw s4, 8(sp)
    lw s3, 12(sp)
    lw s2, 16(sp)
    lw s1, 20(sp)
    lw s0, 24(sp)
    lw ra, 28(sp)
    addi sp, sp, 32
    ret

/* Clear all WIDTH * HEIGHT LEDs in row-major order. */
clear_led_matrix:
    lui t0, %hi(LED_MATRIX_0_BASE)
    addi t0, t0, %lo(LED_MATRIX_0_BASE)
    lui t1, %hi(LED_MATRIX_0_WIDTH)
    addi t1, t1, %lo(LED_MATRIX_0_WIDTH)
    lui t2, %hi(LED_MATRIX_0_HEIGHT)
    addi t2, t2, %lo(LED_MATRIX_0_HEIGHT)
.Lrender_clear_row:
    mv t3, t1
.Lrender_clear_column:
    sw zero, 0(t0)
    addi t0, t0, 4
    addi t3, t3, -1
    bnez t3, .Lrender_clear_column
    addi t2, t2, -1
    bnez t2, .Lrender_clear_row
    ret

/* Draw 24 facelets, each as a 4-by-3 block, into the 35-by-25 matrix. */
render_cube:
    addi sp, sp, -48
    sw ra, 44(sp)
    sw s0, 40(sp)
    sw s1, 36(sp)
    sw s2, 32(sp)
    sw s3, 28(sp)
    sw s4, 24(sp)
    sw s5, 20(sp)
    sw s6, 16(sp)
    sw s7, 12(sp)
    sw s8, 8(sp)

    lui s0, %hi(LED_MATRIX_0_BASE)
    addi s0, s0, %lo(LED_MATRIX_0_BASE)
    lui s1, %hi(LED_MATRIX_0_WIDTH)
    addi s1, s1, %lo(LED_MATRIX_0_WIDTH)
    slli s2, s1, 2              /* row stride in bytes */
    la s3, .Lrender_facelets
    li s4, 24
    la s5, target_render_position
    la s6, target_render_orientation
    la s7, .Lrender_cubie_colors
    la s8, .Lrender_rgb

.Lrender_facelet:
    lbu t0, 0(s3)               /* corner position */
    lbu t1, 1(s3)               /* face index within corner */
    lbu t2, 2(s3)               /* matrix x */
    lbu t3, 3(s3)               /* matrix y */

    add t4, s5, t0
    lbu t4, 0(t4)               /* cubie identity */
    add t5, s6, t0
    lbu t5, 0(t5)               /* cubie orientation */
    add t1, t1, t5
    li t5, 3
    bltu t1, t5, .Lrender_color_index_ready
    addi t1, t1, -3
.Lrender_color_index_ready:
    slli t5, t4, 1
    add t5, t5, t4              /* cubie * 3 */
    add t5, t5, t1
    add t5, s7, t5
    lbu t5, 0(t5)               /* U/R/F/D/L/B color index */
    slli t5, t5, 2
    add t5, s8, t5
    lw a0, 0(t5)                /* 24-bit RGB */

    slli t2, t2, 2
    add t0, s0, t2
.Lrender_add_rows:
    beqz t3, .Lrender_block
    add t0, t0, s2
    addi t3, t3, -1
    j .Lrender_add_rows

.Lrender_block:
    li t1, 3
.Lrender_block_row:
    mv t2, t0
    li t3, 4
.Lrender_block_pixel:
    sw a0, 0(t2)
    addi t2, t2, 4
    addi t3, t3, -1
    bnez t3, .Lrender_block_pixel
    add t0, t0, s2
    addi t1, t1, -1
    bnez t1, .Lrender_block_row

    addi s3, s3, 4
    addi s4, s4, -1
    bnez s4, .Lrender_facelet

    lw s8, 8(sp)
    lw s7, 12(sp)
    lw s6, 16(sp)
    lw s5, 20(sp)
    lw s4, 24(sp)
    lw s3, 28(sp)
    lw s2, 32(sp)
    lw s1, 36(sp)
    lw s0, 40(sp)
    lw ra, 44(sp)
    addi sp, sp, 48
    ret

render_delay:
    li t0, RENDER_DELAY_COUNT
.Lrender_delay_loop:
    addi t0, t0, -1
    bnez t0, .Lrender_delay_loop
    ret

    .section .rodata.led_renderer,"a",@progbits
    .balign 2
.Lrender_factors:
    .half 720, 120, 24, 6, 2, 1, 1

/* Each destination takes its cubie and twist from these seven-entry rows. */
.Lrender_move_sources:
    .byte 1, 4, 2, 0, 3, 5, 6
    .byte 0, 1, 2, 4, 5, 6, 3
    .byte 0, 2, 5, 3, 1, 4, 6
.Lrender_move_twists:
    .byte 1, 2, 0, 2, 1, 0, 0
    .byte 0, 0, 0, 1, 2, 1, 2
    .byte 0, 0, 0, 0, 0, 0, 0

/* Cubie colors in cyclic corner order; 0..5 mean U, R, F, D, L, B. */
.Lrender_cubie_colors:
    .byte 0, 1, 2               /* URF */
    .byte 3, 2, 1               /* DFR */
    .byte 3, 4, 2               /* DLF */
    .byte 0, 5, 1               /* UBR */
    .byte 3, 1, 5               /* DRB */
    .byte 3, 5, 4               /* DBL */
    .byte 0, 4, 5               /* ULB */
    .byte 0, 2, 4               /* fixed UFL */

    .balign 4
.Lrender_rgb:
    .word 0xffffff              /* U: white */
    .word 0xff0000              /* R: red */
    .word 0x00ff00              /* F: green */
    .word 0xffff00              /* D: yellow */
    .word 0xff8000              /* L: orange */
    .word 0x0000ff              /* B: blue */

/*
 * Entries are {corner position, corner-face index, x, y}.  Face slots are
 *        U
 *      L F R B
 *        D
 * Each facelet is 4 by 3 LEDs.  Slot separators produce 35 by 20 pixels;
 * rows 20..24 remain black in the required 35-by-25 matrix.
 */
.Lrender_facelets:
    .byte 6, 0,  9,  0,   3, 0, 13,  0   /* U */
    .byte 7, 0,  9,  3,   0, 0, 13,  3
    .byte 6, 1,  0,  7,   7, 2,  4,  7   /* L */
    .byte 5, 2,  0, 10,   2, 1,  4, 10
    .byte 7, 1,  9,  7,   0, 2, 13,  7   /* F */
    .byte 2, 2,  9, 10,   1, 1, 13, 10
    .byte 0, 1, 18,  7,   3, 2, 22,  7   /* R */
    .byte 1, 2, 18, 10,   4, 1, 22, 10
    .byte 3, 1, 27,  7,   6, 2, 31,  7   /* B */
    .byte 4, 2, 27, 10,   5, 1, 31, 10
    .byte 2, 0,  9, 14,   1, 0, 13, 14   /* D */
    .byte 5, 0,  9, 17,   4, 0, 13, 17
    .endif

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
