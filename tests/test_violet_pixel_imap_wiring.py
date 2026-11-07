"""Source-contract regression tests for Maxwell fragment interpolation.

These exercise that the native translator actually consumes the NVIDIA SPH
metadata tested independently by test_violet_pixel_imap.c. No game files.
"""
from pathlib import Path
import unittest

TEXT = (Path(__file__).resolve().parents[1] /
        "runtime/nvn/maxwell/translate.c").read_text(encoding="utf-8")


class FragmentPixelInterpolation(unittest.TestCase):
    def test_header_is_read_at_documented_offset(self):
        self.assertIn('if (c->glsl) memcpy(c->imap, sph + 0x18, sizeof c->imap);', TEXT)

    def test_interpolation_is_derived_from_sph_not_ipa_opcode(self):
        start = TEXT.index('    } else if (stage == STAGE_FRAGMENT) {\n        for (int i = 0; i < 32; i++)', TEXT.index('static ShaderInfo *glsl_finish'))
        body = TEXT[start:start + 1300]
        self.assertIn('nvn_pixel_imap_first_used(c->imap, (unsigned)i)', body)
        self.assertIn('type == NVN_PIXEL_IMAP_CONSTANT ? "flat "', body)
        self.assertIn('type == NVN_PIXEL_IMAP_SCREEN_LINEAR ? "noperspective "', body)
        self.assertNotIn('c->flat_mask & (1u << i)', body)

    def test_perspective_correction_only_for_appropriate_varyings(self):
        start = TEXT.index('static void attr_load(')
        end = TEXT.index('static void attr_store(', start)
        body = TEXT[start:end]
        self.assertIn('!c->glsl || nvn_pixel_imap_needs_w(c->imap', body)
        self.assertIn('if (perspective) sprintf', body)
        self.assertIn('if (perspective)\n                        sprintf', body)

    def test_msl_opcode_compatibility(self):
        self.assertIn('if (!c->glsl && mode == 2) c->flat_mask |= 1u << at;', TEXT)

    def test_cache_fingerprint_and_rebuild_depend_on_pixel_imap_helper(self):
        makefile = (Path(__file__).resolve().parents[1] / "Makefile").read_text(encoding="utf-8")
        self.assertIn("TRANSLATOR_SRCS := runtime/nvn/maxwell/translate.c runtime/nvn/maxwell/shader.h runtime/nvn/maxwell/pixel_imap.h", makefile)
        self.assertIn("$(B)/rt/nvn/shader_prep.o: $(TRANSLATOR_SRCS)", makefile)
        self.assertIn("$(B)/rt/nvn/maxwell/translate.o: $(TRANSLATOR_SRCS)", makefile)

    def test_cached_glsl_is_versioned(self):
        self.assertIn('"pixel-imap-v1:" SHADER_TRANSLATOR_ID', TEXT)
        self.assertIn('"pixel-imap-v1:" __DATE__', TEXT)


if __name__ == "__main__":
    unittest.main()
