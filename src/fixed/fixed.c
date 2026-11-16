#include "fixed.h"

/* Dummies: every function returns 0. Replace with the real routines. */
uint32_t op1(uint32_t a, uint32_t b, int *n)
{
    int passes = 0;
    while (b != 0) {
        uint32_t c = (a & b) << 1;
        a = a ^ b;
        b = c;
        passes++;
    }
    *n = passes;
    return a;
}

uint32_t op2(uint32_t a, uint32_t b)
{
    return a - b;
}

uint32_t op3(uint32_t a, uint32_t b)
{
    return (a & b) + ((a ^ b) >> 1);
}

int32_t q_mul(int32_t a, int32_t b)
{
    uint32_t ua = (uint32_t) a, ub = (uint32_t) b;
    uint32_t al = ua & 0xFFFF, ah = ua >> 16;
    uint32_t bl = ub & 0xFFFF, bh = ub >> 16;
    uint32_t ll = al * bl, lh = al * bh, hl = ah * bl, hh = bh * ah;

    /*Bits 31 ~ 16*/
    uint32_t mid = (ll >> 16) + (lh & 0xFFFF) + (hl & 0xFFFF);
    /*Bits 63 ~ 32*/
    uint32_t hi = hh + (lh >> 16) + (hl >> 16) + (mid >> 16);
    /*Bits 31 ~ 0*/
    uint32_t lo = (mid << 16) | (ll & 0xFFFF);

    if (a < 0)
        hi -= ub;
    if (b < 0)
        hi -= ua;

    uint32_t lo2 = lo + (1u << (Q - 1));
    hi += lo >= 0xFFF80000u;
    return (int32_t) ((lo2 >> Q) | (hi << (32 - Q)));
}
