#include "gcd.h"

uint32_t gcd_u32(uint32_t a, uint32_t b)
{
    if (a == 0)
        return b;
    if (b == 0)
        return a;

    uint32_t shift = 0;
    while (((a | b) & 1) == 0) {
        a >>= 1;
        b >>= 1;
        shift++;
    }

    while ((a & 1) == 0) {
        a >>= 1;
    }

    do {
        while ((b & 1) == 0) {
            b >>= 1;
        }
        if (a > b) {
            uint32_t t = a;
            a = b;
            b = t;
        }
        b -= a;
    } while (b != 0);

    return a << shift;
}
