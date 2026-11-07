// NVN BGR formats, as declared by the official NVNformat enum:
// 0x95 BGR565, 0x96 BGR5, 0x97 BGR5A1, 0x98 A1BGR5,
// 0x99 BGRX8, 0x9A BGRA8, 0x9B BGRX8_SRGB, 0x9C BGRA8_SRGB.
// An off-by-one previously made 0x98 consume four bytes per texel
// (although it occupies two), while 0x9C fell through to a default.
#include <stdint.h>
#include <stdio.h>
#include "../runtime/nvn/tegra.h"

int main(void) {
    const struct { uint32_t id; uint8_t bytes; } cases[] = {
        {0x95,2},{0x96,2},{0x97,2},{0x98,2},
        {0x99,4},{0x9A,4},{0x9B,4},{0x9C,4}
    };
    for (unsigned i=0; i<sizeof(cases)/sizeof(cases[0]); ++i) {
        const FormatInfo *info=nvn_format_info(cases[i].id);
        if (!info || info->bpb != cases[i].bytes || info->bw != 1 || info->bh != 1) {
            fprintf(stderr, "bad NVN format 0x%x: expected %u B/texel, got %u\n",
                    cases[i].id, cases[i].bytes, info ? info->bpb : 0);
            return 1;
        }
    }
    puts("PASS: eight NVN BGR/BGRA texture sizes match the SDK enums");
    return 0;
}
