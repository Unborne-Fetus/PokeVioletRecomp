// Minimal, read-only identity check on an extracted Switch ExeFS.
// Never infer a game from the filename or a shared SDK module.
#pragma once
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

static inline bool rt_is_violet_exefs(const char *dir) {
    char path[1100];
    snprintf(path, sizeof path, "%s/main.npdm", dir);
    FILE *f = fopen(path, "rb");
    if (!f) return false;
    unsigned char meta[0x80], aci[0x18];
    bool valid = fread(meta, 1, sizeof meta, f) == sizeof meta &&
                 !memcmp(meta, "META", 4);
    uint32_t aci_off = 0;
    if (valid) memcpy(&aci_off, meta + 0x70, sizeof aci_off);
    valid = valid && aci_off >= 0x80 && aci_off <= 0x100000 &&
            fseek(f, (long)aci_off, SEEK_SET) == 0 &&
            fread(aci, 1, sizeof aci, f) == sizeof aci &&
            !memcmp(aci, "ACI0", 4);
    fclose(f);
    uint64_t program_id = 0;
    if (valid) memcpy(&program_id, aci + 0x10, sizeof program_id);
    return valid && program_id == UINT64_C(0x01008F6008C5E000);
}
