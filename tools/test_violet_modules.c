// The real library entry and dispatcher must resolve main, multimedia and SDK functions independently.
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "gamelib.h"
#include "rt.h"

#define FIXTURE_MODULE(name, base, hle) \
    static void name##_first(Cpu *c) { c->x[0] = base + 0x100; } \
    static void name##_second(Cpu *c) { c->x[0] = base + 0x200; } \
    const uint64_t name##_fn_addrs[] = {base + 0x100, base + 0x200}; \
    const GuestFn name##_fn_ptrs[] = {name##_first, name##_second}; \
    const uint64_t name##_fn_count = 2;
GAME_MODULES(FIXTURE_MODULE)
#undef FIXTURE_MODULE

extern const GameLibTables *lasgame_tables(void);
const GameLibTables *gamelib_tables(void) { return lasgame_tables(); }
extern const char *rt_host_fn_name(uint64_t pc, uint64_t *offset);

// This test runs table lookup only. Any accidental entry into the OS/guest execution paths must fail immediately.
int g_game_is_la;
uint8_t g_main_build_id[8];
void rt_fatal_msg(const char *fmt, ...) { (void)fmt; abort(); }
void plat_print_backtrace(void) { abort(); }
Cpu *kernel_current_cpu(void) { abort(); }
void plat_fatal_notice(void) { abort(); }
uint64_t loader_find_symbol(const char *name) { (void)name; abort(); }
const char *loader_symbol_at(uint64_t a, uint64_t *o) { (void)a; (void)o; abort(); }
void plat_commit(uint64_t a, uint64_t n) { (void)a; (void)n; abort(); }
int plat_protect(uint64_t a, uint64_t n, int p) { (void)a; (void)n; (void)p; abort(); }
const char *plat_symbol(uint64_t a, uint64_t *o) { (void)a; (void)o; abort(); }
uint64_t renderer_present_count(void) { abort(); }
void rt_crash_fault(const char *s, uint64_t a, uint64_t p) { (void)s; (void)a; (void)p; abort(); }
void plat_crash_handler_install(void) { abort(); }
uint64_t plat_now_ns(void) { abort(); }
void plat_sleep_until_ns(uint64_t t) { (void)t; abort(); }
void plat_dump_threads(void) { abort(); }
void rt_unwind_point(void) { abort(); }

int main(void) {
    const GameLibTables *g = lasgame_tables();
    assert(g->abi == GAMELIB_ABI && g->module_count == GAME_MODULE_COUNT);
    dispatch_init();
    Cpu cpu = {0};
    for (unsigned i = 0; i < g->module_count; i++) {
        const GameLibModule *m = &g->modules[i];
        assert(!strcmp(m->name, g_game_modules[i].name));
        assert(*m->count == 2);
        for (unsigned j = 0; j < *m->count; j++) {
            GuestFn fn = dispatch_lookup(m->addrs[j]);
            assert(fn == m->fns[j]);
            fn(&cpu);
            assert(cpu.x[0] == m->addrs[j]);
            char expected[32];
            snprintf(expected, sizeof expected, "f_%llx", (unsigned long long)m->addrs[j]);
            uint64_t offset = UINT64_MAX;
            const char *name = rt_host_fn_name((uint64_t)(uintptr_t)fn, &offset);
            assert(name && !strcmp(name, expected) && offset == 0);
        }
        assert(!dispatch_lookup(g_game_modules[i].base));
        assert(!dispatch_lookup(g_game_modules[i].base + 0x180));
    }
    assert(!dispatch_lookup(0));
    puts("Violet module entry, dispatch and host symbol lookup passed (main, subsdk0, sdk)");
}
