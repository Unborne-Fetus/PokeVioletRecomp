// NVIDIA SPH PixelImap decoding and perspective correction regression tests.
// No proprietary shaders or game data required.
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include "../runtime/nvn/maxwell/pixel_imap.h"

int main(void) {
    uint8_t imap[32] = {0};
    // Four 2-bit fields for X/Y/Z/W: Constant, Perspective,
    // ScreenLinear, Unused -> 0b00_11_10_01 = 0x39.
    imap[7] = 0x39;
    assert(nvn_pixel_imap_component(imap, 7, 0) == NVN_PIXEL_IMAP_CONSTANT);
    assert(nvn_pixel_imap_component(imap, 7, 1) == NVN_PIXEL_IMAP_PERSPECTIVE);
    assert(nvn_pixel_imap_component(imap, 7, 2) == NVN_PIXEL_IMAP_SCREEN_LINEAR);
    assert(nvn_pixel_imap_component(imap, 7, 3) == NVN_PIXEL_IMAP_UNUSED);
    assert(nvn_pixel_imap_first_used(imap, 7) == NVN_PIXEL_IMAP_CONSTANT);
    assert(!nvn_pixel_imap_needs_w(imap, 7, 0));
    assert(nvn_pixel_imap_needs_w(imap, 7, 1));
    assert(!nvn_pixel_imap_needs_w(imap, 7, 2));
    assert(!nvn_pixel_imap_needs_w(imap, 7, 3)); // unused inherits constant
    imap[8] = 0b10101010; // 4 perspective components
    assert(nvn_pixel_imap_first_used(imap, 8) == NVN_PIXEL_IMAP_PERSPECTIVE);
    for (unsigned i = 0; i < 4; i++)
        assert(nvn_pixel_imap_needs_w(imap, 8, i));
    imap[9] = 0b11111111; // 4 screen-linear components
    assert(nvn_pixel_imap_first_used(imap, 9) == NVN_PIXEL_IMAP_SCREEN_LINEAR);
    for (unsigned i = 0; i < 4; i++)
        assert(!nvn_pixel_imap_needs_w(imap, 9, i));
    imap[10] = 0b01010101; // 4 flat components
    assert(nvn_pixel_imap_first_used(imap, 10) == NVN_PIXEL_IMAP_CONSTANT);
    assert(!nvn_pixel_imap_needs_w(imap, 10, 0));
    assert(nvn_pixel_imap_needs_w(imap, 11, 1)); // empty header fallback
    assert(nvn_pixel_imap_first_used(imap, 31) == NVN_PIXEL_IMAP_UNUSED);
    assert(nvn_pixel_imap_component(imap, 32, 0) == NVN_PIXEL_IMAP_UNUSED);
    assert(nvn_pixel_imap_component(imap, 3, 4) == NVN_PIXEL_IMAP_UNUSED);
    puts("PASS: NVIDIA PixelImap SPH fragment semantics");
    return 0;
}
