# gcd_u32_asm: binary GCD, hand-written RV32I.
#
# uint32_t gcd_u32_asm(uint32_t a, uint32_t b)   a in a0, b in a1, result in a0
#
# RV32I and Zicsr only: no mul, div, rem, no floating point, no compressed
# instructions. Tests: tests/tgcd.c.

    .text

    .globl  gcd_u32_asm
    .type   gcd_u32_asm, @function
    .align  2
gcd_u32_asm:
    beqz    a0, .ret_b 
    beqz    a1, .ret_a

    li      t0, 0
    
    or      t1, a0, a1
    andi    t1, t1, 1
    bnez    t1, .check_a_even

.both_even:
    srli    a0, a0, 1
    srli    a1, a1, 1
    addi    t0, t0, 1
    or      t1, a0, a1
    andi    t1, t1, 1
    beqz    t1, .both_even

.check_a_even:
    andi    t1, a0, 1
    bnez    t1, .check_b_even

.a_even:
    srli    a0, a0, 1
    andi    t1, a0, 1
    beqz    t1, .a_even

.check_b_even:
    andi    t1, a1, 1
    bnez    t1, .both_odd

.b_even:
    srli    a1, a1, 1
    andi    t1, a1, 1
    beqz    t1, .b_even

.both_odd:
    beq     a0, a1, .done
    bltu    a0, a1, .a_lt_b
    sub     t2, a0, a1
    mv      a0, a1
    mv      a1, t2
    j       .b_even
.a_lt_b:
    sub     a1, a1, a0
    srli    a1, a1, 1
    andi    t1, a1, 1
    beqz    t1, .b_even
    j       .both_odd
.done:
    sll     a0, a0, t0
    ret
.ret_b:
    mv      a0, a1
.ret_a:
    ret
    .size   gcd_u32_asm, .-gcd_u32_asm
