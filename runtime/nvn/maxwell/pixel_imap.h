// Fragment shader ImapGenericVector interpolation (NVIDIA SPH, offset 0x18).
// Each 8-bit vector encodes four 2-bit component types. This header contains
// no runtime, graphics API, or game dependencies, so it can be unit-tested.
#ifndef NVN_MAXWELL_PIXEL_IMAP_H
#define NVN_MAXWELL_PIXEL_IMAP_H
#include <stdbool.h>
#include <stdint.h>

enum {
    NVN_PIXEL_IMAP_UNUSED = 0,
    NVN_PIXEL_IMAP_CONSTANT = 1,       // Flat shading
    NVN_PIXEL_IMAP_PERSPECTIVE = 2,    // Perspective-correct interpolation
    NVN_PIXEL_IMAP_SCREEN_LINEAR = 3,  // No-perspective interpolation
};

static inline unsigned nvn_pixel_imap_component(const uint8_t imap[32], unsigned attr, unsigned component) {
    if (!imap || attr >= 32 || component >= 4) return NVN_PIXEL_IMAP_UNUSED;
    return (imap[attr] >> (component * 2)) & 3u;
}

static inline unsigned nvn_pixel_imap_first_used(const uint8_t imap[32], unsigned attr) {
    if (!imap || attr >= 32) return NVN_PIXEL_IMAP_UNUSED;
    for (unsigned i = 0; i < 4; ++i) {
        unsigned v = nvn_pixel_imap_component(imap, attr, i);
        if (v != NVN_PIXEL_IMAP_UNUSED) return v;
    }
    return NVN_PIXEL_IMAP_UNUSED;
}

// Maxwell IPA PASS/MUL produces attr/w only for perspective attributes.
// An unused component inherits the vector's nonzero interpolation mode;
// if the header declares no mode, retain the original perspective fallback.
static inline bool nvn_pixel_imap_needs_w(const uint8_t imap[32], unsigned attr, unsigned component) {
    unsigned v = nvn_pixel_imap_component(imap, attr, component);
    if (v == NVN_PIXEL_IMAP_UNUSED) v = nvn_pixel_imap_first_used(imap, attr);
    return v == NVN_PIXEL_IMAP_PERSPECTIVE || v == NVN_PIXEL_IMAP_UNUSED;
}
#endif
