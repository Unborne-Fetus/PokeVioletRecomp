// Entry of the game code library (runtime/gamelib.h), compiled into it with the generated code: the function
// tables, found by name when the app loads the library. Everything else in it stays hidden.
#include "gamelib.h"

#define DECLARE_MODULE(name, base, hle) \
    extern const uint64_t name##_fn_addrs[], name##_fn_count; \
    extern const GuestFn name##_fn_ptrs[];
GAME_MODULES(DECLARE_MODULE)
#undef DECLARE_MODULE

GAMELIB_EXPORT const GameLibTables *lasgame_tables(void) {
    static const GameLibModule modules[] = {
#define MODULE_TABLE(name, base, hle) {#name, name##_fn_addrs, name##_fn_ptrs, &name##_fn_count},
        GAME_MODULES(MODULE_TABLE)
#undef MODULE_TABLE
    };
    static const GameLibTables t = {GAMELIB_ABI, GAMELIB_ID, GAME_MODULE_COUNT, modules};
    return &t;
}
