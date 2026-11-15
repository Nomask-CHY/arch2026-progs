# BFloat16 routines: hand-written RV32I.
#
# uint16_t bf16_from_f32_asm(uint32_t f32bits)   a0 -> a0
# uint16_t bf16_mul_asm(uint16_t a, uint16_t b)  a0, a1 -> a0
# uint16_t bf16_sqrt_asm(uint16_t a)             a0 -> a0
#
# RV32I and Zicsr only: no mul, div, rem, no floating point, no compressed
# instructions. Tests: tests/tbf16.c.

    .text

    .globl  bf16_from_f32_asm
    .type   bf16_from_f32_asm, @function
    .align  2
bf16_from_f32_asm:
    li      t0, 0x7f800000
    and     t1, a0, t0
    beq     t1, t0, .special_case

    # uint32_t lsb = (f32bits >> 16) & 1U;
    srli    t1, a0, 16
    andi    t1, t1, 1
    # uint32_t rounding_bias = 0x7fff + lsb;
    lui     t2, 0x8
    add     a0, a0, t1
    addi    t2, t2, -1
    # uint32_t bf16bits = (f32bits + rounding_bias) >> 16;
    add     a0, a0, t2
.special_case:
    # return (uint16_t) (f32bits >> 16);
    srli    a0, a0, 16    
    ret
    .size   bf16_from_f32_asm, .-bf16_from_f32_asm

    .globl  bf16_mul_asm
    .type   bf16_mul_asm, @function
    .align  2
bf16_mul_asm:
    # uint16_t prod_sign = (a ^ b) & 0x8000; -> t0
    xor     t0, a0, a1
    li      t1, 0x8000
    and     t0, t0, t1
    # int is_zero_a = (a & 0x7fff) == 0; -> t1
    # int is_zero_b = (b & 0x7fff) == 0; -> t2
    li      t2, 0x7fff
    and     t1, a0, t2
    and     t2, a1, t2
    # check ((a & 0x7f80U) == 0x7f80U)
    # t3 = 0x7f80U
    li      t3, 0x7f80
    and     t4, a0, t3
    bne     t4, t3, .check_b_exp
    # check (a & 0x007fU) == 0U
    andi    t4, a0, 0x007f
    bnez    t4, .ret_a
    # check (is_zero_b) return 0x7fc0;
    beqz    t2, .ret_nan
    # return prod_sign | 0x7f80U;
    or      a0, t0, t3
    ret

.check_b_exp:
    # check ((b & 0x7f80U) == 0x7f80U)
    and     t4, a1, t3
    bne     t4, t3, .check_zero
    # check (b & 0x007fU) == 0U
    andi    t4, a1, 0x007f
    bnez    t4, .ret_b
    # check (is_zero_a) return 0x7fc0;
    beqz    t1, .ret_nan
    # return prod_sign | 0x7f80U;
    or      a0, t0, t3
    ret

.check_zero:
    # check (is_zero_a || is_zero_b) return prod_sign;
    beqz    t1, .ret_sign
    beqz    t2, .ret_sign

    # exp_a(b) = (a(b) >> 7) & 0xff;
    srli    t1, a0, 7
    andi    t1, t1, 0x00ff
    srli    t2, a1, 7
    andi    t2, t2, 0x00ff
    # frac_a(b) = a(b) & 0x007fU;
    andi    t3, a0, 0x007f
    andi    t4, a1, 0x007f
    # Normalize a
    bnez    t1, .add_implicit_a
    li      t1, 1
.norm_a_loop:

    andi    t5, t3, 0x0080
    bnez    t5, .norm_b
    slli    t3, t3, 1
    addi    t1, t1, -1
    j       .norm_a_loop

.add_implicit_a:
    ori     t3, t3, 0x0080

.norm_b:
    # Normalize b
    bnez    t2, .add_implicit_b
    li      t2, 1

.norm_b_loop:
    andi    t5, t4, 0x0080
    bnez    t5, .prod_exp
    slli    t4, t4, 1
    addi    t2, t2, -1
    j       .norm_b_loop

.add_implicit_b:
    ori     t4, t4, 0x0080

.prod_exp:
    # int32_t prod_exp = exp_a + exp_b - 127; -> t1
    add     t1, t1, t2
    addi    t1, t1, -127
    # uint32_t prod_frac = frac_a * frac_b; -> t2 (RV32I shift-and-add)
    li      t2, 0

.prod_frac_loop:
    beqz    t4, .prod_frac_done
    andi    t5, t4, 1
    beqz    t5, .prod_frac_shift
    add     t2, t2, t3

.prod_frac_shift:
    slli    t3, t3, 1
    srli    t4, t4, 1
    j       .prod_frac_loop

.prod_frac_done:
    # Renormalized by one bit when it reaches bit 15
    li      t5, 0x8000
    and     t5, t5, t2
    beqz    t5, .after_renorm
    srli    t2, t2, 1
    addi    t1, t1, 1

.after_renorm:
    # uint16_t frac_res = (uint16_t) ((prod_frac >> 7) & 0x7FU); -> t3
    srli    t3, t2, 7
    andi    t3, t3, 0x007f
    # overflow check: if (prod_exp >= 255) return prod_sign | 0x7f80U;
    li      t4, 255
    bge     t1, t4, .ret_inf
    bgtz    t1, .normalized_result
    # underflow check: if (prod_exp < -6) return prod_sign;
    li      t4, -6
    blt     t1, t4, .ret_sign
    # frac_res >>= (1 - prod_exp);
    li      t4, 1
    sub     t4, t4, t1
    srl     t3, t3, t4
    or      a0, t0, t3
    ret    
.normalized_result:
    # uint16_t exp_res = (uint16_t) ((prod_exp << 7) & 0x7f80U); -> t4
    slli    t1, t1, 7
    or      a0, t0, t1
    or      a0, a0, t3
    ret

.ret_a:
    ret
.ret_b:
    mv      a0, a1
    ret
.ret_nan:
    li      a0, 0x7fc0
    ret
.ret_sign:
    mv      a0, t0
    ret
.ret_inf:
    li      t3, 0x7f80
    or      a0, t0, t3
    ret
    .size   bf16_mul_asm, .-bf16_mul_asm

    .globl  bf16_sqrt_asm
    .type   bf16_sqrt_asm, @function
    .align  2
bf16_sqrt_asm:
    # Exponent field 0xFF (Inf and NaN): return the top 16 bits unchanged
    # t0 = 0x7f80U
    li      t0, 0x7f80
    and     t1, a0, t0
    bne     t1, t0, .sqrt_check_zero        
    # (a == 0xff80U) return 0x7fc0U
    li      t1, 0xff80
    beq     a0, t1, .sqrt_ret_nan
    ret   
.sqrt_check_zero:
    # check (is_zero_a) return a;
    li      t1, 0x7fff
    and     t1, a0, t1
    beqz    t1, .sqrt_ret_zero

    # check if (a & 0x8000U) return 0x7fc0U;
    li      t1, 0x8000
    and     t1, a0, t1
    bnez    t1, .sqrt_ret_nan
    # check if (!(a & 0x7f80U)) return 0x0000U;
    and     t1, a0, t0
    beqz    t1, .sqrt_ret_zero

    # int16_t exp = ((a >> 7) & 0xffU) - 127; -> t0
    srli    t0, a0, 7
    andi    t0, t0, 0x00ff
    addi    t0, t0, -127

    # uint16_t frac = (a & 0x7fU) | 0x80U; -> t1
    andi    t1, a0, 0x007f
    ori     t1, t1, 0x0080

    # check if (exp & 1) { frac <<= 1; exp--; }
    andi    t2, t0, 1
    beqz    t2, .sqrt_exp_even
    slli    t1, t1, 1
    addi    t0, t0, -1

.sqrt_exp_even:
    # exp >>= 1; (signed arithmetic shift right)
    srai    t0, t0, 1

    # binary search for the square root of frac, using the method of
    li      t2, 90
    li      t3, 256
    li      t4, 90

.sqrt_bsearch_loop:
    bgtu    t2, t3, .sqrt_bsearch_done
    # uint32_t mid = (low + high) >> 1; -> t5   
    add     t5, t2, t3
    srli    t5, t5, 1

    # uint32_t sqr = mid * mid; -> t6 (RV32I shift-and-add)
    li      t6, 0
    mv      a1, t5
    mv      a2, t5

.sqrt_mul_loop:
    beqz    a2, .sqrt_mul_done
    andi    a3, a2, 1
    beqz    a3, .sqrt_mul_shift
    add     t6, t6, a1
.sqrt_mul_shift:
    slli    a1, a1, 1
    srli    a2, a2, 1
    j       .sqrt_mul_loop

.sqrt_mul_done:
    # check if ((mid * mid >> 7) <= frac)
    srli    t6, t6, 7
    bgtu    t6, t1, .sqrt_bsearch_high
    # res = mid; low = mid + 1;
    mv      t4, t5
    addi    t2, t5, 1
    j       .sqrt_bsearch_loop

.sqrt_bsearch_high:
    # high = mid - 1;
    addi    t3, t5, -1
    j       .sqrt_bsearch_loop

.sqrt_bsearch_done:
    # check if (res < 128) { res <<= 1; exp--; }
    li      t2, 128
    bgeu    t4, t2, .sqrt_add_bias 
    slli    t4, t4, 1
    addi    t0, t0, -1

.sqrt_add_bias:
    addi    t0, t0, 127
    # check if (exp >= 0xff) return 0x7f80U;
    li      t2, 255
    bge     t0, t2, .sqrt_ret_inf
    # check if (exp <= 0) return 0x0000U;
    blez    t0, .sqrt_ret_zero

    slli    t0, t0, 7
    andi    t4, t4, 0x007f
    or      a0, t0, t4
    ret

.sqrt_ret_zero:
    li      a0, 0
    ret
.sqrt_ret_nan:
    li      a0, 0x7fc0
    ret
.sqrt_ret_inf:
    li      a0, 0x7f80
    ret
    .size   bf16_sqrt_asm, .-bf16_sqrt_asm
