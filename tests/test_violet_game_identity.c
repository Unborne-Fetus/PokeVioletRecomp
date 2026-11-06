// Tests the runtime's Pokémon Violet NPDM detector using invented bytes only.
// No Nintendo executable, game data, or credentials are required.
#define _GNU_SOURCE
#include "game_identity.h"
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static void make_npdm(const char *path, uint64_t title_id, int aci_offset, size_t length) {
    unsigned char data[0x98] = {0};
    memcpy(data, "META", 4);
    uint32_t offset = (uint32_t)aci_offset;
    memcpy(data + 0x70, &offset, 4);
    memcpy(data + 0x80, "ACI0", 4);
    memcpy(data + 0x90, &title_id, 8);
    FILE *f = fopen(path, "wb");
    assert(f != NULL);
    assert(length <= sizeof data);
    assert(fwrite(data, 1, length, f) == length);
    assert(fclose(f) == 0);
}

int main(void) {
    char dir[] = "/tmp/violet-identity-XXXXXX";
    assert(mkdtemp(dir) != NULL);
    char path[300];
    assert(snprintf(path, sizeof path, "%s/main.npdm", dir) < (int)sizeof path);

    assert(!rt_is_violet_exefs(dir));
    make_npdm(path, UINT64_C(0x01008F6008C5E000), 0x80, 0x98);
    assert(rt_is_violet_exefs(dir));
    make_npdm(path, UINT64_C(0x0100F43008C44000), 0x80, 0x98);
    assert(!rt_is_violet_exefs(dir));
    make_npdm(path, UINT64_C(0x01008F6008C5E000), 0x80, 0x80);
    assert(!rt_is_violet_exefs(dir));
    make_npdm(path, UINT64_C(0x01008F6008C5E000), 0x110000, 0x98);
    assert(!rt_is_violet_exefs(dir));
    remove(path);
    rmdir(dir);
    return 0;
}
