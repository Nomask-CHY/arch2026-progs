#include "bf16.h"

uint16_t bf16_from_f32(uint32_t f32bits)
{
    if ((f32bits & 0x7f800000) == 0x7f800000) {
        /*Exponent field 0xFF (Inf and NaN): return the top 16 bits unchanged*/
        return (uint16_t) (f32bits >> 16);
    }

    uint32_t lsb = (f32bits >> 16) & 1U;
    f32bits += 0x7fffU + lsb; /* round to nearest, ties to even */
    return (uint16_t) (f32bits >> 16);
}

uint16_t bf16_mul(uint16_t a, uint16_t b)
{
    uint16_t prod_sign = (a ^ b) & 0x8000;
    int is_zero_a = (a & 0x7fff) == 0;
    int is_zero_b = (b & 0x7fff) == 0;

    /*Examined in order a, then b. If a has exponent 0xFF: */
    if ((a & 0x7f80U) == 0x7f80U) {
        if (a & 0x007fU)
            return a; /* a is NaN, return unchanged */
        if (is_zero_b)
            return 0x7fc0;          /* Inf times 0 is quiet NaN */
        return prod_sign | 0x7f80U; /* Inf with product sign */
    }

    if ((b & 0x7f80U) == 0x7f80U) {
        if (b & 0x007fU)
            return b; /* b is NaN, return unchanged */
        if (is_zero_a)
            return 0x7fc0;          /* Inf times 0 is quiet NaN */
        return prod_sign | 0x7f80U; /* Inf with product sign */
    }

    if (is_zero_a || is_zero_b)
        return prod_sign; /* Zero times finite value is zero with product sign
                           */

    int32_t exp_a = (a >> 7) & 0xff;
    int32_t exp_b = (b >> 7) & 0xff;
    int32_t frac_a = a & 0x007fU;
    int32_t frac_b = b & 0x007fU;

    /*Normalize denormalized numbers*/
    if (exp_a == 0) {
        exp_a = 1;
        while ((frac_a & 0x0080U) == 0) {
            frac_a <<= 1;
            exp_a--;
        }
    } else {
        frac_a |= 0x0080U; /* Add implicit leading 1 for normalized numbers */
    }

    if (exp_b == 0) {
        exp_b = 1;
        while ((frac_b & 0x0080U) == 0) {
            frac_b <<= 1;
            exp_b--;
        }
    } else {
        frac_b |= 0x0080U; /* Add implicit leading 1 for normalized numbers */
    }

    int32_t prod_exp = exp_a + exp_b - 127; /* Subtract bias */
    uint32_t prod_frac = frac_a * frac_b;

    /* Renormalized by one bit when it reaches bit 15 */
    if (prod_frac & 0x8000U) {
        prod_frac >>= 1;
        prod_exp++;
    }

    uint16_t frac_res = (uint16_t) ((prod_frac >> 7) & 0x7FU);

    /*Overflow*/
    if (prod_exp >= 0xff) {
        return prod_sign | 0x7f80U; /* Inf with product sign */
    }

    /*Result exponent <= 0*/
    if (prod_exp <= 0) {
        if (prod_exp < -6) {
            return prod_sign; /* Result is zero with product sign */
        }
        frac_res >>=
            (1 - prod_exp); /* Denormalize by shifting fraction right */
        /* Truncate to lower 7 bits (bits 13..7 shifted down) */
        return prod_sign | frac_res;
    }

    /*Normalized result*/
    return prod_sign | (uint16_t) (prod_exp << 7) | frac_res;
}

uint16_t bf16_sqrt(uint16_t a)
{
    if ((a & 0x7f80U) == 0x7f80U) {
        /*Exponent field 0xFF (Inf and NaN): return the top 16 bits unchanged*/
        if (a == 0xff80U) {
            return 0x7fc0U; /* sqrt(-Inf) is quiet NaN */
        }
        return a; /* sqrt(Inf or NaN) is unchanged */
    }

    if (!(a & 0x7fffU)) {
        return 0x0000U; /* sqrt(±0) is +0 */
    }

    if (a & 0x8000U) {
        return 0x7fc0; /* sqrt(negative finite) is quiet NaN */
    }

    if (!(a & 0x7f80U)) {
        return 0x0000U; /* sqrt(positive denormal) is +0 */
    }

    int16_t exp = ((a >> 7) & 0xffU) - 127;
    uint16_t frac = a & 0x7fU;
    frac |= 0x80U; /* Add implicit leading 1 for normalized numbers */

    if (exp & 1) {
        frac <<= 1; /* Make exponent even by doubling significand */
        exp--;
    }

    exp >>= 1; /* Divide exponent by 2 */

    uint32_t low = 90;
    uint32_t high = 256;
    uint32_t res = 90;

    while (low <= high) {
        uint32_t mid = (low + high) >> 1;
        if (mid * mid >> 7 <= frac) {
            res = mid;
            low = mid + 1;
        } else {
            high = mid - 1;
        }
    }

    if (res < 128) {
        res <<= 1;
        exp--;
    }

    exp += 127; /* Add bias back */

    if (exp >= 0xff) {
        return 0x7f80U; /* Result is Inf */
    }
    if (exp <= 0) {
        return 0x0000U; /* Result is +0 */
    }

    return (uint16_t) ((exp) << 7 | (res & 0x7fU));
}
