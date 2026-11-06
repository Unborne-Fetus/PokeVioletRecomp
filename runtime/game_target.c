#include "game_target.h"
#include <stdio.h>
#include <string.h>

const GameTargetModule g_game_modules[GAME_MODULE_COUNT] = {
#define TARGET_MODULE(name, base, hle) {#name, base, hle},
    GAME_MODULES(TARGET_MODULE)
#undef TARGET_MODULE
};
static const GameTargetVersion versions[] = {
#define VIOLET_VERSION(key, label, main, multimedia, sdk) {#key, label, main, multimedia, sdk},
#include "violet_versions.h"
#undef VIOLET_VERSION
};

static uint32_t u32(const uint8_t *p) {
    return (uint32_t)p[0] | (uint32_t)p[1] << 8 | (uint32_t)p[2] << 16 | (uint32_t)p[3] << 24;
}
static uint64_t u64(const uint8_t *p) { return u32(p) | (uint64_t)u32(p + 4) << 32; }
static bool id_matches(const uint8_t id[20], const char *hex) {
    static const char digits[] = "0123456789ABCDEF";
    for (int i = 0; i < 20; i++)
        if (hex[2*i] != digits[id[i] >> 4] || hex[2*i+1] != digits[id[i] & 15]) return false;
    return true;
}
static bool nso_header(const char *path, uint8_t hdr[0x60]) {
    FILE *f = fopen(path, "rb");
    if (!f) return false;
    bool ok = fread(hdr, 1, 0x60, f) == 0x60 && !memcmp(hdr, "NSO0", 4);
    fclose(f);
    return ok;
}
const GameTargetVersion *game_target_version(const uint8_t id[20]) {
    for (size_t i = 0; i < sizeof versions / sizeof *versions; i++)
        if (id_matches(id, versions[i].main_id)) return &versions[i];
    return NULL;
}
const GameTargetVersion *game_target_version_of_main(const char *path) {
    uint8_t hdr[0x60];
    return nso_header(path, hdr) ? game_target_version(hdr + 0x40) : NULL;
}

bool game_target_check_exefs(const char *exefs, char *why, size_t size) {
    char path[1200];
    uint8_t meta[0x80], aci0[0x18], hdr[0x60];
    snprintf(path, sizeof path, "%s/main.npdm", exefs);
    FILE *f = fopen(path, "rb");
    bool ok = f && fread(meta, 1, sizeof meta, f) == sizeof meta && !memcmp(meta, "META", 4) &&
              u32(meta + 0x70) >= sizeof meta && !fseek(f, u32(meta + 0x70), SEEK_SET) &&
              fread(aci0, 1, sizeof aci0, f) == sizeof aci0 && !memcmp(aci0, "ACI0", 4);
    if (f) fclose(f);
    if (!ok) {
        snprintf(why, size, "exefs/main.npdm is missing or invalid");
        return false;
    }
    if (u64(aci0 + 0x10) != GAME_PROGRAM_ID) {
        snprintf(why, size, "these are not Pokémon Violet's game files (program %016llX)",
                 (unsigned long long)u64(aci0 + 0x10));
        return false;
    }
    snprintf(path, sizeof path, "%s/main", exefs);
    const GameTargetVersion *v = game_target_version_of_main(path);
    if (!v) {
        snprintf(why, size, "unrecognized Violet executable: configured versions are 1.0.0 and 4.0.0");
        return false;
    }
    const char *ids[] = {v->main_id, v->subsdk0_id, v->sdk_id};
    for (int i = 0; i < GAME_MODULE_COUNT; i++) {
        const GameTargetModule *m = &g_game_modules[i];
        snprintf(path, sizeof path, "%s/%s", exefs, m->name);
        if (!nso_header(path, hdr) || !id_matches(hdr + 0x40, ids[i])) {
            snprintf(why, size, "exefs/%s is missing, invalid or from another game version", m->name);
            return false;
        }
        uint64_t end = u32(hdr + 0x34) + (uint64_t)u32(hdr + 0x38) + u32(hdr + 0x3c);
        end = (end + 0x3fff) & ~0x3fffull;
        uint64_t limit = i + 1 < GAME_MODULE_COUNT ? g_game_modules[i+1].base : GAME_CODE_END;
        if (!end || end > limit - m->base) {
            snprintf(why, size, "exefs/%s does not fit its configured guest address range", m->name);
            return false;
        }
    }
    if (size) why[0] = 0;
    return true;
}
