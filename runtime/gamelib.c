// Loads the recompiled game code library (runtime/gamelib.h).
#include "gamelib.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#ifdef _WIN32
#include <windows.h>
#else
#include <dlfcn.h>
#endif

#include "gamebuild.h"
#include "paths.h"
#include "rt.h"

static const GameLibTables *g_tables;
static char g_error[256];

bool gamelib_old_cpu(void) {
#if defined(__x86_64__)
    const char *e = getenv("LARECOMP_OLD_CPU");  // (testing it on a newer CPU)
    if (e && *e == '1') return true;
    __builtin_cpu_init();
    return !(__builtin_cpu_supports("avx2") && __builtin_cpu_supports("fma") && __builtin_cpu_supports("bmi2"));
#else
    return false;
#endif
}

// The library's id file (<library>.id, written next to it by the build): its id (gamelib_full_id), read without
// loading it.
static bool id_matches(const char *lib, const char *want) {
    char path[1100], id[128] = {0};
    snprintf(path, sizeof path, "%s.id", lib);
    FILE *f = fopen(path, "rb");
    if (!f) return false;
    size_t n = fread(id, 1, sizeof id - 1, f);
    fclose(f);
    while (n && (id[n - 1] == '\n' || id[n - 1] == '\r')) id[--n] = 0;
    return !strcmp(id, want);
}

static bool exists(const char *p) {
    FILE *f = fopen(p, "rb");
    if (f) fclose(f);
    return f != NULL;
}

// The places to look, in order (gamelib.h). Returns how many were filled.
static int candidates(const char *game_dir, char out[3][1100]) {
    int n = 0;
    const char *env = getenv("LARECOMP_GAME_LIB");
    if (env && *env) snprintf(out[n++], 1100, "%s", env);
    char exe_side[1024];
    if (rt_resource(GAMELIB_NAME, NULL, exe_side, sizeof exe_side) && exists(exe_side))
        snprintf(out[n++], 1100, "%s", exe_side);
    if (game_dir) snprintf(out[n++], 1100, "%s/%s", game_dir, GAMELIB_NAME);
    return n;
}

bool gamelib_present(const char *game_dir) {
    if (g_tables) return true;
    char want[GAMELIB_FULL_ID_SIZE];
    if (!game_dir || !gamelib_full_id(game_dir, want, sizeof want)) return false;
    char c[3][1100];
    int n = candidates(game_dir, c);
    for (int i = 0; i < n; i++)
        if (exists(c[i]) && id_matches(c[i], want)) return true;
    return false;
}

static const GameLibTables *open_lib(const char *path, const char *want) {
#ifdef _WIN32
    HMODULE h = LoadLibraryA(path);
    if (!h) { snprintf(g_error, sizeof g_error, "can't load %s (error %lu)", path, GetLastError()); return NULL; }
    GameLibEntry entry = (GameLibEntry)(void *)GetProcAddress(h, GAMELIB_ENTRY);
#else
    void *h = dlopen(path, RTLD_NOW | RTLD_LOCAL);
    if (!h) { snprintf(g_error, sizeof g_error, "%s", dlerror()); return NULL; }
    GameLibEntry entry = (GameLibEntry)dlsym(h, GAMELIB_ENTRY);
#endif
    if (!entry) { snprintf(g_error, sizeof g_error, "%s: not game code", path); return NULL; }
    const GameLibTables *t = entry();
    if (!t || t->abi != GAMELIB_ABI || !t->id || strcmp(t->id, want)) {
        snprintf(g_error, sizeof g_error, "%s was built for another version", path);
        return NULL;  // (left loaded: nothing of it runs)
    }
    if (t->module_count != GAME_MODULE_COUNT || !t->modules) {
        snprintf(g_error, sizeof g_error, "%s has an incomplete module table", path);
        return NULL;
    }
    for (unsigned i = 0; i < t->module_count; i++) {
        const GameLibModule *m = &t->modules[i];
        if (!m->name || strcmp(m->name, g_game_modules[i].name) || !m->addrs || !m->fns || !m->count || !*m->count) {
            snprintf(g_error, sizeof g_error, "%s has an invalid %s function table", path, g_game_modules[i].name);
            return NULL;
        }
    }
    return t;
}

bool gamelib_load(const char *game_dir, char *why, size_t why_size) {
    static bool tried;
    if (!tried) {
        tried = true;
        snprintf(g_error, sizeof g_error, "the game code hasn't been built: set up the game files on the start screen");
        char want[GAMELIB_FULL_ID_SIZE] = "";
        if (!game_dir || !gamelib_full_id(game_dir, want, sizeof want)) {
            snprintf(g_error, sizeof g_error, "the game files' exefs/main is missing or unreadable");
            if (why) snprintf(why, why_size, "%s", g_error);
            return false;
        }
        char c[3][1100];
        int n = candidates(game_dir, c);
        const char *env = getenv("LARECOMP_GAME_LIB");
        for (int i = 0; i < n && !g_tables; i++) {
            if (!exists(c[i])) continue;
            bool given = i == 0 && env && *env;  // LARECOMP_GAME_LIB: loaded as given, the library's own id decides
            if (!given && !id_matches(c[i], want)) {
                snprintf(g_error, sizeof g_error, "%s was built for another version", c[i]);
                continue;
            }
            g_tables = open_lib(c[i], want);
            if (g_tables) {
                uint64_t count = 0;
                for (unsigned j = 0; j < g_tables->module_count; j++) count += *g_tables->modules[j].count;
                LOG("[gamelib] %s (%u modules, %llu functions)\n", c[i], g_tables->module_count, (unsigned long long)count);
            }
        }
    }
    if (!g_tables && why) snprintf(why, why_size, "%s", g_error);
    return g_tables != NULL;
}

const GameLibTables *gamelib_tables(void) { return g_tables; }
