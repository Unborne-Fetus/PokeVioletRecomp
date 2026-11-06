"""Check the production C and Python target validators against the same synthetic ExeFS trees."""
import ctypes as ct
import os
from pathlib import Path
import shlex
import struct
import subprocess
import tempfile
import unittest

from violet_target import MODULES, PROGRAM_ID, VERSIONS, check_exefs

ROOT = Path(__file__).resolve().parent.parent


class TargetTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory()
        cls.root = Path(cls.temp.name)
        library = cls.root / ('target.dll' if os.name == 'nt' else 'target.so')
        cc = shlex.split(os.environ.get('CC', 'clang'))
        subprocess.run(cc + ['-shared', '-fPIC', '-Iruntime', 'runtime/game_target.c', '-o', str(library)],
                       cwd=ROOT, check=True)
        cls.lib = ct.CDLL(str(library))
        cls.lib.game_target_check_exefs.argtypes = [ct.c_char_p, ct.c_void_p, ct.c_size_t]
        cls.lib.game_target_check_exefs.restype = ct.c_bool

    @classmethod
    def tearDownClass(cls):
        if os.name == 'nt':
            import _ctypes
            _ctypes.FreeLibrary(cls.lib._handle)
        cls.temp.cleanup()

    def setUp(self):
        self.exefs = self.root / self._testMethodName
        self.exefs.mkdir()
        self.fixture(next(iter(VERSIONS.values())))

    def fixture(self, version):
        label, ids = version
        meta = bytearray(0x98)
        meta[:4] = b'META'
        struct.pack_into('<I', meta, 0x70, 0x80)
        meta[0x80:0x84] = b'ACI0'
        struct.pack_into('<Q', meta, 0x90, PROGRAM_ID)
        (self.exefs / 'main.npdm').write_bytes(meta)
        for name, _, _ in MODULES:
            hdr = bytearray(0x60)
            hdr[:4] = b'NSO0'
            hdr[0x40:0x54] = bytes.fromhex(ids[name])
            struct.pack_into('<III', hdr, 0x34, 0x2000, 0x1000, 0x1000)
            (self.exefs / name).write_bytes(hdr)
        return label

    def check(self, expected):
        why = ct.create_string_buffer(512)
        result = self.lib.game_target_check_exefs(str(self.exefs).encode(), why, len(why))
        self.assertEqual(result, expected, why.value)
        if expected:
            self.assertTrue(check_exefs(self.exefs))
        else:
            self.assertTrue(why.value)
            with self.assertRaises((ValueError, OSError)):
                check_exefs(self.exefs)

    def test_known_versions(self):
        for version in VERSIONS.values():
            label = self.fixture(version)
            self.assertEqual(check_exefs(self.exefs), label)
            self.check(True)

    def test_layout_matches_c(self):
        class Module(ct.Structure):
            _fields_ = [('name', ct.c_char_p), ('base', ct.c_uint64), ('hle', ct.c_bool)]
        modules = (Module * len(MODULES)).in_dll(self.lib, 'g_game_modules')
        self.assertEqual([(m.name.decode(), m.base, m.hle) for m in modules], MODULES)

    def test_other_title(self):
        meta = bytearray((self.exefs / 'main.npdm').read_bytes())
        struct.pack_into('<Q', meta, 0x90, 0x0100F43008C44000)
        (self.exefs / 'main.npdm').write_bytes(meta)
        self.check(False)

    def test_missing_npdm(self):
        (self.exefs / 'main.npdm').unlink()
        self.check(False)

    def test_invalid_aci(self):
        meta = bytearray((self.exefs / 'main.npdm').read_bytes())
        struct.pack_into('<I', meta, 0x70, 0xfffffff0)
        (self.exefs / 'main.npdm').write_bytes(meta)
        self.check(False)

    def test_same_prefix_different_build(self):
        hdr = bytearray((self.exefs / 'main').read_bytes())
        hdr[0x53] ^= 1  # the first eight bytes still match; all twenty bytes must identify the build
        (self.exefs / 'main').write_bytes(hdr)
        self.check(False)

    def test_missing_multimedia(self):
        (self.exefs / 'subsdk0').unlink()
        self.check(False)

    def test_mixed_version_sdk(self):
        hdr = bytearray((self.exefs / 'sdk').read_bytes())
        hdr[0x40:0x54] = bytes.fromhex(list(VERSIONS.values())[1][1]['sdk'])
        (self.exefs / 'sdk').write_bytes(hdr)
        self.check(False)

    def test_overlapping_image(self):
        hdr = bytearray((self.exefs / 'main').read_bytes())
        struct.pack_into('<I', hdr, 0x3c, 0x8000000)
        (self.exefs / 'main').write_bytes(hdr)
        self.check(False)

    def test_truncated_nso(self):
        (self.exefs / 'sdk').write_bytes(b'NSO0')
        self.check(False)


if __name__ == '__main__':
    unittest.main()
