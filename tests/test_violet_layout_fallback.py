"""Violet launcher must not skip geometry already supported by Vulkan defaults."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
RUNNER = (ROOT / "tools/violet/run.ps1").read_text(encoding="utf-8")
EXEC = (ROOT / "runtime/nvn/vulkan/exec.c").read_text(encoding="utf-8")

class VioletVertexLayoutFallback(unittest.TestCase):
    def test_vk_supplies_missing_attribute_constant(self):
        self.assertIn("l->attr_bind[i] = ZERO_BINDING;", EXEC)
        self.assertIn("static const float zero[4] = {0, 0, 0, 1};", EXEC)
        self.assertIn("rec_CmdBindVertexBuffers(cb, (uint32_t)s, 1, &sp.buf, &off);", EXEC)

    def test_redundant_layout_guard_can_be_disabled(self):
        self.assertIn('ENV("LARECOMP_SKIP_BAD_LAYOUT")', EXEC)
        self.assertIn("if (on && st.nattrib <= 1 && (pr->vi->attr_mask & ~1u))", EXEC)

    def test_hair_quad_control_is_not_forced_for_violet(self):
        self.assertNotIn("LARECOMP_SHADER_QUAD_CONTROL", RUNNER)
        shader = (ROOT / "runtime/nvn/maxwell/translate.c").read_text(encoding="utf-8")
        self.assertIn('on = maxwell_quad_control_ok &&', shader)
        self.assertIn('128 * (uint64_t)quad_control_on()', shader)

    def test_violet_only_default_is_reversible(self):
        self.assertIn("$oldBadLayout = [Environment]::GetEnvironmentVariable('LARECOMP_SKIP_BAD_LAYOUT', 'Process')", RUNNER)
        self.assertIn("if ($null -eq $oldBadLayout)", RUNNER)
        self.assertIn("[Environment]::SetEnvironmentVariable('LARECOMP_SKIP_BAD_LAYOUT', '0', 'Process')", RUNNER)
        self.assertIn("[Environment]::SetEnvironmentVariable('LARECOMP_SKIP_BAD_LAYOUT', $oldBadLayout, 'Process')", RUNNER)

if __name__ == '__main__': unittest.main()
