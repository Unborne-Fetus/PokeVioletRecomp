"""Unit tests for native Violet PE export/DWARF crash lookup; no game EXE needed."""
from __future__ import annotations

from contextlib import redirect_stdout
import importlib.util
import io
from pathlib import Path
import struct
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "tools" / "violet" / "addr2line_crash.py"
spec = importlib.util.spec_from_file_location("violet_addr2line_crash", SCRIPT)
symbolizer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(symbolizer)


def fake_pe(path: Path):
    """Build a tiny but structurally sound PE32+ image with one named export."""
    b = bytearray(0x900)
    b[:2] = b"MZ"
    struct.pack_into("<I", b, 0x3C, 0x80)
    b[0x80:0x84] = b"PE\x00\x00"
    struct.pack_into("<H", b, 0x84, 0x8664)  # x64
    struct.pack_into("<H", b, 0x86, 2)  # two sections
    struct.pack_into("<H", b, 0x94, 0xF0)  # PE32+ optional header size
    opt = 0x98
    struct.pack_into("<H", b, opt, 0x20B)
    struct.pack_into("<Q", b, opt + 24, 0x140000000)
    struct.pack_into("<II", b, opt + 112, 0x2000, 0x100)  # export directory
    sections = opt + 0xF0
    b[sections:sections+8] = b".text\x00\x00\x00"
    struct.pack_into("<IIII", b, sections + 8, 0x200, 0x1000, 0x200, 0x200)
    sec2 = sections + 40
    b[sec2:sec2+8] = b".edata\x00\x00"
    struct.pack_into("<IIII", b, sec2 + 8, 0x400, 0x2000, 0x400, 0x400)
    # IMAGE_EXPORT_DIRECTORY, offset of RVA 0x2000 = file offset 0x400
    struct.pack_into("<IIHHIIIIIII", b, 0x400, 0, 0, 0, 0, 0,
                     1, 1, 1, 0x2050, 0x2054, 0x2058)
    struct.pack_into("<I", b, 0x450, 0x1010)  # function RVA
    struct.pack_into("<I", b, 0x454, 0x2060)  # symbol name RVA
    struct.pack_into("<H", b, 0x458, 0)       # ordinal index
    b[0x460:0x46B] = b"VioletTest\x00"
    path.write_bytes(b)


class CrashPELookupTests(unittest.TestCase):
    def test_read_image_base_and_named_export(self):
        with tempfile.TemporaryDirectory() as tmp:
            exe = Path(tmp) / "lasrecomp.exe"
            fake_pe(exe)
            pe = symbolizer.PE(exe)
            self.assertEqual(pe.image_base, 0x140000000)
            self.assertEqual(pe.named_exports(), [(0x1010, "VioletTest")])
            self.assertEqual(pe.offset(0x1010), 0x210)

    def test_symbolization_does_not_claim_nearest_export_is_exact(self):
        with tempfile.TemporaryDirectory() as tmp:
            exe = Path(tmp) / "lasrecomp.exe"
            fake_pe(exe)
            log = ("*** exception c0000005 accessing 0\n"
                   "host backtrace (guest functions are f_<addr>):\n"
                   "  #10 00007ff6ac7aefd8 lasrecomp+1010\n"
                   "  #11 00007ff6ac7f2f36 lasrecomp+1020\n")
            buf = io.StringIO()
            with redirect_stdout(buf):
                result = symbolizer.analyze(log, exe, None)
            output = buf.getvalue()
            self.assertEqual(result, 0)
            self.assertIn("0x140000000", output)
            self.assertIn("export VioletTest (exact entry)", output)
            self.assertIn("approximate, NOT proven containing", output)
            self.assertIn("lasrecomp+0x1020", output)

    def test_parse_realistic_frames_no_repetition(self):
        log = ("  #0  00007ff6ac7e7e9f lasrecomp+b7e9f\n"
               "[shader] first visit: pipeline\n"
               "  #10 00007ff6ac7aefd8 lasrecomp+7efd8\n"
               "  #11 00007ff6ac7f2f36 lasrecomp+c2f36\n"
               "  #12 00007ff6ac7f2f36 lasrecomp+c2f36\n")
        self.assertEqual(symbolizer.parse_frames(log),
                         [(0, 0xB7E9F), (10, 0x7EFD8), (11, 0xC2F36)])


if __name__ == "__main__":
    unittest.main()
