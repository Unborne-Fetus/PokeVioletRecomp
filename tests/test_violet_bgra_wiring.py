"""Regression tests for the NVN/BGRA format enum bridge used by Violet materials.

NVN 0x98 is A1BGR5 (16 bits); 0x99..0x9C are BGRX/BGRA 32-bit.
The old code incorrectly shifted the Vulkan mappings one slot earlier,
treating A1BGR5 as 32-bit and treating BGRA8 as BGRX8_SRGB.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
TEX = (ROOT / "runtime/nvn/vulkan/textures.c").read_text(encoding="utf-8")
FORMATS = (ROOT / "runtime/nvn/formats.c").read_text(encoding="utf-8")

class VioletBgraFormatMappings(unittest.TestCase):
    def test_correct_vk_format_cases(self):
        cases = {
            "98": "VK_FORMAT_A1R5G5B5_UNORM_PACK16",
            "99": "VK_FORMAT_B8G8R8A8_UNORM",
            "9A": "VK_FORMAT_B8G8R8A8_UNORM",
            "9B": "VK_FORMAT_B8G8R8A8_SRGB",
            "9C": "VK_FORMAT_B8G8R8A8_SRGB",
        }
        for code, fmt in cases.items():
            with self.subTest(code=code):
                self.assertRegex(TEX, rf"case 0x{code}: return \(VkFmt\)\{{{fmt}")
        self.assertRegex(TEX, r"case 0x99: return \(VkFmt\)\{VK_FORMAT_B8G8R8A8_UNORM, 0, 1\}")
        self.assertRegex(TEX, r"case 0x9B: return \(VkFmt\)\{VK_FORMAT_B8G8R8A8_SRGB, 0, 1\}")

    def test_16bit_and_32bit_formats_have_explicit_sizes(self):
        for code in ("95", "96", "97", "98"):
            with self.subTest(code=code):
                self.assertRegex(FORMATS, rf"\[0x{code}\] = C\(2\)")
        for code in ("99", "9A", "9B", "9C"):
            with self.subTest(code=code):
                self.assertRegex(FORMATS, rf"\[0x{code}\] = C\(4\)")

if __name__ == "__main__":
    unittest.main()
