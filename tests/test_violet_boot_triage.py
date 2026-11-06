"""Synthetic Violet crash-log regression tests: no game data or GPU required."""
import importlib.util
from pathlib import Path
import unittest

MODULE = Path(__file__).resolve().parents[1] / "tools" / "violet" / "boot_triage.py"
spec = importlib.util.spec_from_file_location("violet_boot_triage", MODULE)
triage = importlib.util.module_from_spec(spec)
spec.loader.exec_module(triage)


class BootTriageTests(unittest.TestCase):
    def test_zero_payload_still_has_termination_code(self):
        report = triage.analyze("\n".join([
            "loaded main at 7000000000 size 47d3000 syms 140",
            "loaded sdk at 7008000000 size da8000 syms 120",
            "[ipc] STUB hwopus cmd 0 (in 0 bytes, x0 a0 b0 c0) -> ok",
            "[am] SetTerminateResult 0x2a2 (2162-1)",
            "[kernel] abort payload Result is zero (the failure condition is not identified)",
            "  guest #0 7002ac3f4c (main+0x2ac3f4c)",
            "  guest #1 70083cd970 (sdk+0x3cd970)",
            "FATAL: svcBreak(reason=0, info=700ef00000, size=4) at 70083cd970",
        ]))
        self.assertEqual(report["outcome"], "guest-abort-before-frame-stats")
        self.assertEqual(report["set_terminate_result"], "0x2a2")
        self.assertEqual(report["abort"]["payload_result"], "0x0")
        self.assertEqual(report["abort"]["location"]["module"], "sdk")
        self.assertEqual(report["abort"]["location"]["offset"], "0x3cd970")
        self.assertEqual(report["guest_stack"][0]["module"], "main")
        self.assertTrue(report["recent_stub_or_unhandled_calls"])

    def test_timeout_is_not_assumed_successful_boot(self):
        report = triage.analyze("loaded main at 7000000000 size 47d3000\n", timed_out=True)
        self.assertEqual(report["outcome"], "time-limit")
        self.assertEqual(report["fps_lines_with_positive_frame_count"], 0)

    def test_frames_are_detected_without_abort(self):
        report = triage.analyze("[vk] t=12.4 frame 5 30.0 fps max 40ms level test\n")
        self.assertEqual(report["fps_lines_with_positive_frame_count"], 1)
        self.assertEqual(report["outcome"], "unclassified")

    def test_native_null_access_violation_is_classified_and_attributed(self):
        report = triage.analyze("\n".join([
            "loaded main at 7000000000 size 47d4000",
            "loaded sdk at 7008000000 size da8000",
            "[shader] first visit 16: pipeline test",
            "*** exception c0000005 accessing 0",
            "    host pc 7ff6ac7b1234 (f_7000cd27a0+24)",
            "    host lr 7ff6ac7b0cc4 (f_7000cd27c4)",
            "host backtrace (guest functions are f_<addr>):",
            "  #0  00007ff6ac7b1234 f_7000cd27a0+24",
            "  #1  00007ff6ac7b0cc4 f_7000cd27c4+0",
            "guest: sp=7227109cc0 lr=7000cd27c4",
            "  x0  0000007717f87000  x1  0000007717f79000  x2  0000000000000000  x3  0000000000000000",
            "[crash] Violet Recomp stopped because of an error (exception c0000005 accessing 0)",
        ]))
        self.assertEqual(report["outcome"], "host-access-violation")
        fault = report["native_fault"]
        self.assertEqual(fault["exception_code"], "0xc0000005")
        self.assertEqual(fault["access_address"], "0x0")
        self.assertEqual(fault["host_pc"]["symbol"], "f_7000cd27a0+24")
        self.assertEqual(fault["host_backtrace"][0]["frame"], 0)
        self.assertEqual(report["guest_context_at_fault"]["lr"]["module"], "main")
        self.assertEqual(report["guest_context_at_fault"]["registers"]["x2"], "0x0000000000000000")
        self.assertTrue(report["recent_shader_activity"])
        self.assertIn("exception", report["crash_summary"])

    def test_host_crash_must_not_be_inferred_from_shader_activity_or_stubs(self):
        report = triage.analyze("\n".join([
            "[ipc] STUB pl:u cmd 0 (in 4 bytes, x0 a0 b0 c0) -> ok",
            "[vk] full-screen draw waited 9.7 ms for its pipeline",
            "*** exception c0000005 accessing 0",
            "    host pc 7ff6ac7b1234 (lasrecomp+1234)",
        ]))
        self.assertEqual(report["outcome"], "host-access-violation")
        self.assertEqual(report["native_fault"]["host_pc"]["symbol"], "lasrecomp+1234")
        self.assertTrue(any("does not by itself prove" in note.lower() for note in report["notes"]))

    def test_unmapped_addresses_are_not_labeled_as_guest_module(self):
        self.assertIsNone(triage.location(0x7080000000, [("main", 0x7000000000, 0x47d3000)])["module"])


if __name__ == "__main__":
    unittest.main()
