"""Fixture-only tests for the Violet preflight: no Nintendo files required."""
import importlib.util
import struct
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "tools" / "violet" / "check_dump.py"
spec = importlib.util.spec_from_file_location("check_dump", SCRIPT)
check_dump = importlib.util.module_from_spec(spec)
spec.loader.exec_module(check_dump)


def fixture(root: Path, *, title_id=check_dump.VIOLET_TITLE_ID, subsdk=True):
    exefs = root / "exefs"
    exefs.mkdir()
    npdm = bytearray(0x98)
    npdm[:4] = b"META"
    struct.pack_into("<I", npdm, 0x70, 0x80)
    npdm[0x80:0x84] = b"ACI0"
    struct.pack_into("<Q", npdm, 0x90, title_id)
    (exefs / "main.npdm").write_bytes(npdm)
    for name in ("main", "sdk", "subsdk0") if subsdk else ("main", "sdk"):
        nso = bytearray(0x100)
        nso[:4] = b"NSO0"
        nso[0x40:0x48] = bytes.fromhex("959ed65100000000") if name == "main" else b"\x09" * 8
        (exefs / name).write_bytes(nso)
    (root / "romfs" / "arc").mkdir(parents=True)
    (root / "romfs" / "arc" / "data.trpfs").write_bytes(b"")


class TestPreflight(unittest.TestCase):
    def test_good_extracted_dump(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            fixture(root)
            self.assertTrue(check_dump.inspect(root)["valid"])
            self.assertTrue(check_dump.inspect(root / "exefs")["valid"])

    def test_reject_other_title(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            fixture(root, title_id=0x0100F43008C44000)
            self.assertFalse(check_dump.inspect(root)["valid"])

    def test_require_movie_module(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            fixture(root, subsdk=False)
            self.assertIn("exefs/subsdk0 is missing", check_dump.inspect(root)["errors"])

    def test_reject_truncated_nso_segment(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            fixture(root)
            main = bytearray((root / "exefs/main").read_bytes())
            struct.pack_into("<III", main, 0x10, 0xFE, 0, 64)
            (root / "exefs/main").write_bytes(main)
            self.assertFalse(check_dump.inspect(root)["valid"])


if __name__ == "__main__":
    unittest.main()
