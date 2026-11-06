// Violet's GameAddrs table is zero; importing Zelda pets must never touch its
// LIVE_SAVE + 0x555D companion byte during the very first overlay frame.
// This is a standalone regression test, independent of any game files.
#include <stdint.h>
#include <stdio.h>
#include "../runtime/game_addresses.h"

int g_game_is_la = 0;
static const GameAddrs no_zelda_addresses = {0};
const GameAddrs *g_ga = &no_zelda_addresses;

int pets_current(void);

int main(void) {
    if (pets_current() != 0) {
        fputs("FAIL: non-Zelda pets_current should return no companion\n", stderr);
        return 1;
    }
    // A second call mirrors another menu frame after the first present.
    if (pets_current() != 0) {
        fputs("FAIL: non-Zelda companion was accessed after a second frame\n", stderr);
        return 2;
    }
    puts("PASS: Violet companion state is safely unavailable (no 0x555D dereference)");
    return 0;
}
