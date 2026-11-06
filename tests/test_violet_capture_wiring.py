"""Assert F9 is selected by the render thread, not the game thread."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class NativeF9CaptureWiring(unittest.TestCase):
    def test_async_capture_window_is_published_from_game_thread_only(self):
        device = (ROOT / "runtime/nvn/vulkan/device.c").read_text()
        begin = device.index("static void present_hooks(void) {")
        end = device.index("\nvoid backend_present(", begin)
        hooks = device[begin:end]
        self.assertIn("atomic_store_explicit(&debug_capture_start,", hooks)
        self.assertIn("atomic_store_explicit(&debug_capture_length,", hooks)
        self.assertNotIn("g_debug_frame =", hooks)

    def test_render_thread_decides_drawing_and_present_frame(self):
        device = (ROOT / "runtime/nvn/vulkan/device.c").read_text()
        exec_source = (ROOT / "runtime/nvn/vulkan/exec.c").read_text()
        self.assertIn("g_debug_frame = vk_debug_capture_active(renderer_exec_frame());", exec_source)
        self.assertIn("g_debug_frame = vk_debug_capture_active(frame);", device)
        self.assertIn("return vk_debug_frame_in_window(frame, start, length);", device)

    def test_sparse_capture_report_is_not_silent(self):
        report = (ROOT / "tools/violet/graphics_capture_report.ps1").read_text()
        self.assertIn("WARNING: Very few passes were captured", report)
        self.assertIn("Group-Object", report)


if __name__ == "__main__":
    unittest.main()
