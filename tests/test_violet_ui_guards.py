"""Guard the shared UI's Zelda-only overlay queries against Violet startup.

A source-contract test complements the compiled pets first-frame test. It makes
future menu changes fail CI if they restore an eager Zelda UI call on Violet.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]


def body(path, fn):
    source = (ROOT / path).read_text(encoding="utf-8")
    match = re.search(fn + r"\s*\([^;]*?\)\s*\{", source)
    if not match:
        raise AssertionError(f"Could not find {fn}() in {path}")
    return source[match.end(): match.end() + 1800]


class VioletFirstFrameUI(unittest.TestCase):
    def test_menu_checks_game_identity_before_zelda_overlay_queries(self):
        source = body("runtime/ui/menu.mm", r"void menu_render")
        # Marked with a shared bool set before invoking any Zelda overlay.
        self.assertIn("bool la = g_game_is_la != 0;", source)
        for statement in (
            "la && !open && inventory_overlay_wanted()",
            "la && !open && tracker_overlay_wanted()",
            "la && !open && tracker_dungeon_wanted()",
            "la && !open && chaos_overlay_wanted()",
            "la && race_overlay_wanted()",
            "la && !open && pickup_flyin_wanted()",
        ):
            self.assertIn(statement, source)

    def test_inventory_overlay_has_early_exit_before_pets(self):
        source = body("runtime/ui/inventory_overlay.mm", r"bool inventory_overlay_wanted")
        self.assertLess(source.index("if (!g_game_is_la) return false;"), source.index("companion_card()"))

    def test_companion_read_checks_for_zelda(self):
        source = body("runtime/hle/pets.c", r"int pets_current")
        self.assertLess(source.index("if (!g_game_is_la || !GA(LIVE_SAVE)) return C_NONE;"),
                        source.index("*(volatile uint8_t *)(uintptr_t)COMPANION"))

    def test_companion_menu_options_skips_non_zelda(self):
        source = body("runtime/hle/pets.c", r"int pets_menu_options")
        self.assertLess(source.index("if (!g_game_is_la) return 0;"), source.index("pets_callable("))


if __name__ == "__main__":
    unittest.main()
