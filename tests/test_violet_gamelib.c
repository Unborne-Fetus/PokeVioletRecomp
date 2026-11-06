// Synthetic link test: no Nintendo code or dumped files.
#include <assert.h>
#include <stddef.h>
#include <stdint.h>
#include "gamelib.h"

static void fake_guest(Cpu *cpu) { (void)cpu; }
const uint64_t main_fn_addrs[] = {UINT64_C(0x7000000000)};
const uint64_t sdk_fn_addrs[] = {UINT64_C(0x7008000000)};
const uint64_t main_fn_count = 1, sdk_fn_count = 1;
const GuestFn main_fn_ptrs[] = {fake_guest};
const GuestFn sdk_fn_ptrs[] = {fake_guest};

#ifdef RECOMP_HAS_SUBSDK0
const uint64_t subsdk0_fn_addrs[] = {UINT64_C(0x7004000000)};
const uint64_t subsdk0_fn_count = 1;
const GuestFn subsdk0_fn_ptrs[] = {fake_guest};
#endif

extern const GameLibTables *lasgame_tables(void);

int main(void) {
    const GameLibTables *lib = lasgame_tables();
    assert(lib != NULL);
    assert(lib->abi == GAMELIB_ABI);
    assert(lib->main_count && *lib->main_count == 1);
    assert(lib->sdk_count && *lib->sdk_count == 1);
    assert(lib->main_addrs[0] == UINT64_C(0x7000000000));
    assert(lib->sdk_addrs[0] == UINT64_C(0x7008000000));
#ifdef RECOMP_HAS_SUBSDK0
    assert(lib->subsdk0_count && *lib->subsdk0_count == 1);
    assert(lib->subsdk0_addrs[0] == UINT64_C(0x7004000000));
    assert(lib->subsdk0_fns[0] == fake_guest);
#else
    assert(lib->subsdk0_count == NULL);
    assert(lib->subsdk0_addrs == NULL);
    assert(lib->subsdk0_fns == NULL);
#endif
    return 0;
}
