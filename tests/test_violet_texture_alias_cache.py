"""Protect the real Vulkan per-frame view cache from stale copy aliases.

The alias table can remap a depth/stencil destination to a different image
within the same frame. The cache key must include that image, not only the
original NVN descriptor's texture pointer.
"""
from pathlib import Path
import unittest

SOURCE = (Path(__file__).resolve().parents[1] /
          "runtime/nvn/vulkan/exec.c").read_text(encoding="utf-8")


class VulkanTextureViewCache(unittest.TestCase):
    def test_alias_resolved_before_cache_lookup(self):
        start = SOURCE.index("static void texture_info(")
        end = SOURCE.index("static VkDescriptorSet stage_set(", start)
        body = SOURCE[start:end]
        resolved = body.index("NvnTexture *sampled_tex = naliases ? alias_read(e->tex) : e->tex;")
        key = body.index("memo[ms].tex == sampled_tex")
        read = body.index("view = vk_view(sampled_tex")
        self.assertLess(resolved, key)
        self.assertLess(key, read)
        self.assertIn("memo[ms].tex = sampled_tex", body)
        self.assertNotIn("memo[ms].tex == e->tex", body)

    def test_alias_invalidation_advances_view_generation(self):
        alias_start = SOURCE.index("static void alias_drop(")
        alias_end = SOURCE.index("static void alias_copy(", alias_start)
        alias = SOURCE[alias_start:alias_end]
        self.assertIn("vk_view_gen++", alias)


if __name__ == "__main__":
    unittest.main()
