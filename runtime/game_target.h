// Violet's identity and module layout, shared by the runtime, library entry and Python generator.
#pragma once
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define GAME_PROGRAM_ID 0x01008F6008C5E000ull
#define GAME_NAME "Pokémon Violet"
#define RECOMP_NAME "Violet Recomp"
#define MAIN_BASE 0x7000000000ull
#define SUBSDK0_BASE 0x7006000000ull
#define SDK_BASE 0x7008000000ull
#define GAME_CODE_END 0x7080000000ull

// name, guest base, use the SDK's host-function list. Violet needs multimedia.nss (subsdk0) as well as nnSdk.nss.
#define GAME_MODULES(X) \
    X(main, MAIN_BASE, 0) \
    X(subsdk0, SUBSDK0_BASE, 0) \
    X(sdk, SDK_BASE, 1)
#define GAME_MODULE_COUNT_ONE(name, base, hle) + 1
enum { GAME_MODULE_COUNT = 0 GAME_MODULES(GAME_MODULE_COUNT_ONE) };
#undef GAME_MODULE_COUNT_ONE

typedef struct {
    const char *key, *label;
    const char *main_id, *subsdk0_id, *sdk_id;
} GameTargetVersion;
typedef struct {
    const char *name;
    uint64_t base;
    bool hle;
} GameTargetModule;

#ifdef __cplusplus
extern "C" {
#endif
extern const GameTargetModule g_game_modules[GAME_MODULE_COUNT];
const GameTargetVersion *game_target_version(const uint8_t id[20]);
const GameTargetVersion *game_target_version_of_main(const char *path);
// Check title identity, every module's build and non-overlapping image ranges before copying or running any code.
bool game_target_check_exefs(const char *exefs, char *why, size_t size);
#ifdef __cplusplus
}
#endif
