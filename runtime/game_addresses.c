// The game-address tables of every supported game version and their selection by build ID (game_addresses.h).
#include "game_addresses.h"

#include <stdio.h>
#include <string.h>

#include "rt.h"

#define GA_ADDR(name, value) .name = UINT64_C(value),
static const GameAddrs ga_v1_0_0 = {
#include "game_addresses/patches_v1_0_0.h"
#include "game_addresses/runtime_v1_0_0.h"
};
static const GameAddrs ga_v1_0_1 = {
#include "game_addresses/patches_v1_0_1.h"
#include "game_addresses/runtime_v1_0_1.h"
};
#undef GA_ADDR

static const GameVersion versions[] = {
#define GA_VERSION(key, label, build_id) {#key, label, build_id, &ga_##key},
#define GA_RELEASE(key, label, npdm_sha256)
#include "game_addresses/versions.h"
#undef GA_VERSION
#undef GA_RELEASE
};

const GameAddrs *g_ga;
static const GameVersion *g_version;

static int hexval(char c) { return c <= '9' ? c - '0' : c - 'A' + 10; }

uint8_t g_main_build_id[8];  // (game_addresses.h: code that only fits one build of a game)
const GameVersion *game_version_by_build_id(const uint8_t id[20]) {
    for (size_t i = 0; i < sizeof versions / sizeof versions[0]; i++) {
        const char *h = versions[i].build_id;
        int k = 0;
        while (k < 20 && id[k] == (uint8_t)(hexval(h[2 * k]) << 4 | hexval(h[2 * k + 1]))) k++;
        if (k == 20) return &versions[i];
    }
    return NULL;
}

// The main program's build ID (0x40 in the file). false: missing or not a program.
static bool read_build_id(const char *path, uint8_t id[20]) {
    uint8_t hdr[0x60];
    FILE *f = fopen(path, "rb");
    if (!f) return false;
    bool ok = fread(hdr, 1, sizeof hdr, f) == sizeof hdr && !memcmp(hdr, "NSO0", 4);
    fclose(f);
    if (ok) memcpy(id, hdr + 0x40, 20);
    return ok;
}

const GameVersion *game_version_of_main(const char *main_path) {
    uint8_t id[20];
    return read_build_id(main_path, id) ? game_version_by_build_id(id) : NULL;
}

const GameVersion *game_version_of(const char *game_dir) {
    char path[1100];
    snprintf(path, sizeof path, "%s/exefs/main", game_dir);
    return game_version_of_main(path);
}

// exefs/main.npdm's program ID (ACI0 +0x10) is Link's Awakening's; also when there is no readable one
static bool is_la_program(const char *exefs) {
    char path[1100];
    snprintf(path, sizeof path, "%s/main.npdm", exefs);
    FILE *f = fopen(path, "rb");
    if (!f) return true;
    uint8_t meta[0x80], aci0[0x18];
    uint32_t at;
    bool ok = fread(meta, 1, sizeof meta, f) == sizeof meta && !memcmp(meta, "META", 4) &&
              (memcpy(&at, meta + 0x70, 4), !fseek(f, at, SEEK_SET)) && fread(aci0, 1, sizeof aci0, f) == sizeof aci0 &&
              !memcmp(aci0, "ACI0", 4);
    fclose(f);
    uint64_t pid = 0;
    if (ok) memcpy(&pid, aci0 + 0x10, 8);
    return !ok || pid == 0x01006BB00C6F0000ull;
}

// The game files in game_dir are Link's Awakening's (or none: unknown) - asked before the game boots (exec.c's heap
// chunk decision at device creation, which the start screen makes before the boot sets g_game_is_la)
bool game_files_are_la(const char *game_dir) {
    (void)game_dir;
    return false;  // this fork targets Violet, including before any game files have been imported
}

bool game_version_select(const char *game_dir, char *why, size_t why_size) {
    uint8_t id[20];
    char exefs[1100], path[1100];
    snprintf(exefs, sizeof exefs, "%s/exefs", game_dir);
    if (!game_target_check_exefs(exefs, why, why_size)) return false;
    snprintf(path, sizeof path, "%s/main", exefs);
    if (!read_build_id(path, id)) {
        snprintf(why, why_size, "the game files' exefs/main is missing or unreadable");
        return false;
    }
    memcpy(g_main_build_id, id, sizeof g_main_build_id);
    // The inherited Zelda helpers remain compiled, but no Zelda address is a Violet address.
    static const GameAddrs disabled = {0};
    g_ga = &disabled;
    g_version = NULL;
    g_game_is_la = 0;
    const GameTargetVersion *v = game_target_version(id);
    LOG("[game] Pokémon Violet %s (main build ID %.16s): no game-specific hooks\n", v->label, v->main_id);
    return true;
}

const GameVersion *game_version(void) { return g_version; }
