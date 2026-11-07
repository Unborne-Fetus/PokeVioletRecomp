// Integration regression for NVIDIA SPH fragment interpolation.
// Synthesizes public Maxwell IPA instructions; no game shaders or assets are used.
// Unlike a source-string test, this runs the real translator and inspects its GLSL.
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "../runtime/nvn/maxwell/shader.h"

static uint64_t ipa_pass(unsigned dst, unsigned attr) {
    // IPA.PASS Rdst, a[attr].x, RZ; PT predicate, no indexed addressing.
    // SPH, not IPA, determines how the input is interpolated.
    return 0xe00000000000ff00ull | (7ull << 16) |
           ((uint64_t)(0x80u + 16u * attr) << 28) | dst;
}

static int expect(const char *glsl, const char *needle) {
    if (strstr(glsl, needle)) return 1;
    fprintf(stderr, "missing GLSL expression: %s\n", needle);
    return 0;
}

int main(void) {
    // Aligned NVN blob: 0x30-byte NVN header, 0x50-byte SPH,
    // followed by two instruction groups (one scheduling word per group).
    uint64_t blob_words[128] = {0};
    uint8_t *blob = (uint8_t *)blob_words;
    uint8_t *sph = blob + 0x30;
    sph[0x18] = 0x55; // varying 0: constant/flat
    sph[0x19] = 0xAA; // varying 1: perspective
    sph[0x1a] = 0xFF; // varying 2: screen-linear/noperspective
    uint32_t target = 0xFu;
    memcpy(sph + 0x48, &target, sizeof target);

    uint64_t *code = (uint64_t *)(blob + 0x80);
    code[0] = 0x001f8000fc0007e0ull; // scheduling
    code[1] = ipa_pass(4, 0);
    code[2] = ipa_pass(5, 1);
    code[3] = ipa_pass(6, 2);
    code[4] = 0x001f8000fc0007e0ull; // scheduling
    code[5] = 0xe30000000007000full; // EXIT
    code[6] = 0xe2400fffff87000full; // self branch sentinel

    ShaderKey key = {0};
    key.glsl = 1;
    key.vs_out_mask = 0x7u;
    ShaderInfo *shader = maxwell_translate(blob, sizeof blob_words, STAGE_FRAGMENT, &key);
    if (!shader || !shader->msl) {
        fprintf(stderr, "Maxwell translator failed: %s\n", shader ? shader->error : "(null)");
        if (shader) maxwell_free(shader);
        return 1;
    }
    const char *glsl = shader->msl;
    int ok = 1;
    ok &= expect(glsl, "layout(location = 0) flat in vec4 v0;");
    ok &= expect(glsl, "layout(location = 1) in vec4 v1;");
    ok &= expect(glsl, "layout(location = 2) noperspective in vec4 v2;");
    ok &= expect(glsl, "r4 = as_u(v0[0]);");
    ok &= expect(glsl, "r5 = as_u(v1[0] * gl_FragCoord.w);");
    ok &= expect(glsl, "r6 = as_u(v2[0]);");
    if (!ok) fprintf(stderr, "Synthetic Maxwell fragment GLSL:\n%s\n", glsl);
    maxwell_free(shader);
    if (ok) puts("PASS: synthesized Maxwell IPA honors SPH interpolation in GLSL");
    return ok ? 0 : 1;
}
