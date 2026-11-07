"""No-ZIP Violet graphics reporter tests: only synthetic logs and captures."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("violet_graphics_local_report", ROOT / "tools/violet/graphics_local_report.py")
REPORT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(REPORT)

class GraphicsLocalReport(unittest.TestCase):
    def test_fault_detection_ignores_enabled_message(self):
        with tempfile.TemporaryDirectory() as temp:
            p = Path(temp)
            (p / "20261106-000000-stderr.log").write_text(
                "[vk] GPU address binding report: on (a device fault names objects)\n"
                "[vtxstate] skipped draw: vs 7442117000 reads attribs 0x21, 1 bound\n",
                encoding="utf-8")
            (p / "20261106-000001-stderr.log").write_text(
                "[vk] device fault:\n[vk] address read invalid 0x1cee0000\n", encoding="utf-8")
            summary = REPORT.summarize_logs(p)
            self.assertEqual(summary["actual_device_fault_logs"], 1)
            self.assertEqual(summary["skipped_vertex_draw_messages"], 1)
            self.assertEqual(summary["most_skipped_vertex_shaders"][0]["shader"], "7442117000")

    def test_new_hair_quad_path_is_reported_without_sensitive_logs(self):
        with tempfile.TemporaryDirectory() as temp:
            p = Path(temp)
            (p / "20261107-040000-stderr.log").write_text(
                "[vk] fragment shaders' own derivatives: quad swaps (LARECOMP_SHADER_QUAD_CONTROL, "
                "LARECOMP_SHADER_QUAD_DERIV); the driver's quad control and maximal reconvergence: yes; "
                "quads in step through the iris loop: yes (LARECOMP_SHADER_QUAD_LOCKSTEP)\\n",
                encoding="utf-8")
            (p / "20261107-050000-stderr.log").write_text(
                "[vk] fragment shaders' own derivatives: quad swaps in full quads, "
                "quads kept together (quad control); the driver's quad control and maximal "
                "reconvergence: yes; quads in step through the iris loop: yes\\n",
                encoding="utf-8")
            summary = REPORT.summarize_logs(p)
            self.assertEqual(summary["detail_shader_mode"], "full_quad_control")
            self.assertEqual(summary["detail_shader_mode_log"], "20261107-050000-stderr.log")
            self.assertNotIn("the driver's", repr(summary))

    def test_hair_probe_coordinates_follow_local_capture(self):
        with tempfile.TemporaryDirectory() as temp:
            build = Path(temp)
            folder = build / "violet-graphics-diagnostics"
            folder.mkdir()
            path = folder / "probe-coordinates.json"
            path.write_text('{"x": 320, "y": 220}', encoding="utf-8")
            self.assertEqual(REPORT.probe_coordinates(build), (320, 220))
            path.write_text('{"x": 5000, "y": -1}', encoding="utf-8")
            self.assertEqual(REPORT.probe_coordinates(build), (400, 780))
            path.write_text('invalid-json', encoding="utf-8")
            self.assertEqual(REPORT.probe_coordinates(build), (400, 780))

    def test_probe_draw_reader_reports_shader_ids_without_raw_data(self):
        log = ("[probe] build/probe_4979_01.png: draw 783 target 0 1920x1080 fmt 0: "
               "vs 76e62e9c00 fs 76e6353600 indexed count 3075 inst 1 | vbuf0 abc size 100 stride 24\\n")
        rows = REPORT.parse_probe_lines(log)
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["draw"], 783)
        self.assertEqual(rows[0]["vertex_shader"], "76e62e9c00")
        self.assertEqual(rows[0]["fragment_shader"], "76e6353600")
        self.assertNotIn("vbuf0", repr(rows))
        self.assertNotIn("abc", repr(rows))

    def test_capture_selection_prefers_complete_frame(self):
        with tempfile.TemporaryDirectory() as temp:
            d = Path(temp)
            for i in range(12):
                (d / f"pass_4979_{i:03}.png").write_bytes(b"")
            for i in range(2):
                (d / f"pass_4980_{i:03}.png").write_bytes(b"")
            frame, files = REPORT.scene_frame_files(d)
            self.assertEqual(frame, "4979")
            self.assertEqual(len(files), 12)

    def test_summary_without_captures_is_safe(self):
        with tempfile.TemporaryDirectory() as temp:
            d = Path(temp)
            result = REPORT.summarize(d)
            self.assertIsNone(result["capture_frame"])
            self.assertEqual(result["capture_pass_count"], 0)
            self.assertTrue(result["local_only"])
            target = REPORT.write_summary(d)
            saved = target.read_text(encoding="utf-8")
            self.assertIn("capture_pass_count", saved)
            self.assertNotIn(str(ROOT), saved)  # no private absolute paths

if __name__ == "__main__": unittest.main()
