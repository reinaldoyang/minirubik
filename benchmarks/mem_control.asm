.equ WORDS, 1048576        # Control: 1,048,576 words = 4 MiB

.text
.globl main

main:
    li x5, 0x10010000     # Current guest-memory address
    li x6, WORDS          # Number of words remaining

write_loop:
    sw x0, 0(x5)
    addi x5, x5, 0    # Keep the address unchanged
    addi x6, x6, -1
    bne x6, x0, write_loop

    li a7, 10
    ecall