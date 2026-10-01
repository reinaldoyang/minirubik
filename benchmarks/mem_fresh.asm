.equ WORDS, 65536        # Control: 4096 words = 16 KiB

.text
.globl main

main:
    li x5, 0x10010000     # Current guest-memory address
    li x6, WORDS          # Number of words remaining

write_loop:
    sw x0, 0(x5)          # Write 4 guest bytes
    addi x5, x5, 4        # Advance to the next word
    addi x6, x6, -1       # One fewer word remaining
    bne x6, x0, write_loop

    li a7, 10
    ecall