# op1, op2, op3 and q_mul: hand-written RV32I.
#
# uint32_t op1_asm(uint32_t a, uint32_t b, int *n)   a0, a1, a2 -> a0
# uint32_t op2_asm(uint32_t a, uint32_t b)           a0, a1 -> a0
# uint32_t op3_asm(uint32_t a, uint32_t b)           a0, a1 -> a0
# int32_t  q_mul_asm(int32_t a, int32_t b)           a0, a1 -> a0
#
# RV32I and Zicsr only: no mul, div, rem, no floating point, no compressed
# instructions. q_mul forms a 64-bit product in a register pair. Tests:
# tests/tfixed.c.

    .text

    .globl  op1_asm
    .type   op1_asm, @function
    .align  2
op1_asm:
    li      t0, 0
    beqz    a1, .op1_loop_end
.op1_loop:
    and     t1, a0, a1      # carries
    xor     a0, a0, a1      # sum without carries
    slli    a1, t1, 1       # b = carries << 1
    addi    t0, t0, 1
    bnez    a1, .op1_loop
.op1_loop_end:
    sw      t0, 0(a2)    
    ret
    .size   op1_asm, .-op1_asm
    
    .globl  op2_asm
    .type   op2_asm, @function
    .align  2
op2_asm:
    sub     a0, a0, a1
    ret
    .size   op2_asm, .-op2_asm

    .globl  op3_asm
    .type   op3_asm, @function
    .align  2
op3_asm:
    xor     t0, a0, a1      # a ^ b, before a0 is overwritten
    and     a0, a0, a1      # a & b
    srli    t0, t0, 1
    add     a0, a0, t0
    ret
    .size   op3_asm, .-op3_asm

    .globl  q_mul_asm
    .type   q_mul_asm, @function
    .align  2
q_mul_asm:
    li      t0, 0xFFFF
    and     t2, a0, t0 #al -> t2
    and     t3, a1, t0 #bl -> t3
    srli    t0, a0, 16 #ah -> t0
    srli    t1, a1, 16 #bh -> t1

    # calculate hh hl lh ll -> a5, a6, a7, a4 (caller-saved only)
    # hh
    mv      a2, t0
    mv      a3, t1
    jal     t5, .mul16
    mv      a5, a4
    # hl
    mv      a2, t0
    mv      a3, t3
    jal     t5, .mul16
    mv      a6, a4
    # lh
    mv      a2, t2
    mv      a3, t1
    jal     t5, .mul16
    mv      a7, a4
    # ll
    mv      a2, t2
    mv      a3, t3
    jal     t5, .mul16
    # ll stays in a4
    
    # mid = (ll >> 16) + (lh & 0xFFFF) + (hl & 0xFFFF)
    li      t2, 0xFFFF
    srli    t3, a4, 16
    and     t0, a7, t2
    and     t1, a6, t2
    add     t0, t0, t1
    add     t0, t0, t3 # mid -> t0

    # hi = hh + (lh >> 16) + (hl >> 16) + (mid >> 16) -> t4
    srli    t1, a7, 16          
    srli    t2, a6, 16          
    srli    t3, t0, 16          
    add     t4, a5, t1          
    add     t4, t4, t2          
    add     t4, t4, t3         

    # lo = (mid << 16) | (ll & 0xFFFF) -> t1 
    slli    t2, t0, 16          
    li      t3, 0xFFFF
    and     t3, a4, t3          
    or      t1, t2, t3

    bgez    a0, .check_b
    sub     t4, t4, a1
.check_b:
    bgez    a1, .rounding
    sub     t4, t4, a0
.rounding:
    li      t2, 0x80000         # 1u << 19 (Q-1)
    add     t3, t1, t2          # lo2 = lo + 0x80000

    li      t2, 0xFFF80000
    sltu    t6, t1, t2          # lo < 0xFFF80000
    xori    t6, t6, 1           # lo >= 0xFFF80000
    add     t4, t4, t6          # hi += carry

    # lo2 >> 20) | (hi << 12)
    srli    t2, t3, 20          # lo2 >> 20
    slli    t3, t4, 12          # hi << 12
    or      a0, t2, t3          
    ret                                 

.mul16:
    li      a4, 0
.mul16_loop:
    andi    t6, a3, 1
    beqz    t6, .mul16_skip
    add     a4, a4, a2
.mul16_skip:
    slli    a2, a2, 1
    srli    a3, a3, 1
    bnez    a3, .mul16_loop
    jr      t5
    
    .size   q_mul_asm, .-q_mul_asm
