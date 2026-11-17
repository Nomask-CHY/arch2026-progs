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
    mv      a2, a0 # multiplicand lo
    li      a3, 0 # multiplicand hi
    li      a4, 0 # lo
    li      a5, 0 # hi
    mv      t0, a1

.mul32_loop:
    andi    t1, t0, 1
    beqz    t1, .mul32_skip
    add     a4, a4, a2
    sltu    t1, a4, a2
    add     a5, a5, a3
    add     a5, a5, t1

.mul32_skip:
    srli    t1, a2, 31
    slli    a3, a3, 1
    or      a3, a3, t1
    slli    a2, a2, 1
    srli    t0, t0, 1
    bnez    t0, .mul32_loop 

    # Two's Complement Correction
    bgez    a0, .check_b
    sub     a5, a5, a1
.check_b:
    bgez    a1, .rounding
    sub     a5, a5, a0

.rounding:
    li      t0, 0x80000         # 1u << 19 (Q-1)
    add     a4, a4, t0        # lo2 = lo + 0x80000
    sltu    t1, a4, t0
    add     a5, a5, t1

    slli    a5, a5, 12
    srli    a4, a4, 20
    or      a0, a5, a4          
    ret                                 
    .size   q_mul_asm, .-q_mul_asm
