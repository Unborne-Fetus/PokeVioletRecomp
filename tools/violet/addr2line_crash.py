#!/usr/bin/env python3
"""Read-only native symbol lookup for Violet's lasrecomp.exe.

Uses the linked PE's *own* image base and exported functions, plus MinGW/DWARF
addr2line when available. No PDB is necessary. No game data or executable is changed.
"""
from __future__ import annotations

import argparse
import bisect
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess

FRAMES = re.compile(r"(?m)^\s*#(\d+)\s+[0-9a-f]+\s+lasrecomp\+([0-9a-f]+)\s*$", re.I)
HOST_PC = re.compile(r"(?m)^\s*host pc\s+([0-9a-f]+)\s+\(", re.I)
CRASH_PC = re.compile(r"(?m)^\*\*\* exception ([0-9a-f]+) accessing (0x[0-9a-f]+|[0-9a-f]+)", re.I)


def get_int(blob: bytes, offset: int, kind: str = "I") -> int:
    return struct.unpack_from("<" + kind, blob, offset)[0]


class PE:
    def __init__(self, path: Path):
        self.path = path
        self.data = path.read_bytes()
        b = self.data
        if len(b) < 0x100 or b[:2] != b"MZ":
            raise ValueError("Not a Windows PE executable")
        peoff = get_int(b, 0x3C)
        if peoff + 24 > len(b) or b[peoff:peoff+4] != b"PE\x00\x00":
            raise ValueError("Missing PE header")
        num_sections = get_int(b, peoff + 6, "H")
        optional_size = get_int(b, peoff + 20, "H")
        optional = peoff + 24
        magic = get_int(b, optional, "H")
        if magic == 0x20B:
            self.image_base = get_int(b, optional + 24, "Q")
            directory = optional + 112
        elif magic == 0x10B:
            self.image_base = get_int(b, optional + 28, "I")
            directory = optional + 96
        else:
            raise ValueError("Unsupported PE optional header")
        self.exports_rva = 0
        self.exports_size = 0
        if directory + 8 <= optional + optional_size:
            self.exports_rva, self.exports_size = struct.unpack_from("<II", b, directory)
        self.sections = []
        table = optional + optional_size
        for i in range(num_sections):
            off = table + i * 40
            if off + 40 > len(b):
                raise ValueError("Truncated PE section table")
            name = b[off:off+8].rstrip(b"\x00").decode("ascii", "replace")
            virtual_size, rva, raw_size, raw_ptr = struct.unpack_from("<IIII", b, off + 8)
            self.sections.append((name, rva, max(virtual_size, raw_size), raw_ptr, raw_size))

    def offset(self, rva: int, length: int = 1) -> int:
        for _name, start, size, raw, raw_size in self.sections:
            d = rva - start
            if 0 <= d and d + length <= raw_size and d < size and raw + d + length <= len(self.data):
                return raw + d
        raise ValueError(f"RVA 0x{rva:x} is not file-backed")

    def cstring(self, rva: int) -> str:
        pos = self.offset(rva)
        end = self.data.find(b"\x00", pos, min(len(self.data), pos + 2048))
        if end < 0:
            raise ValueError("Unterminated PE export name")
        return self.data[pos:end].decode("utf-8", "replace")

    def named_exports(self) -> list[tuple[int, str]]:
        if not self.exports_rva:
            return []
        b = self.data
        start = self.offset(self.exports_rva, 40)
        fields = struct.unpack_from("<IIHHIIIIIII", b, start)
        num_funcs, num_names = fields[6], fields[7]
        func_rva, name_rva, ordinal_rva = fields[8], fields[9], fields[10]
        if num_funcs > 500000 or num_names > 500000:
            raise ValueError("Invalid export directory counts")
        funcs = self.offset(func_rva, num_funcs * 4)
        names = self.offset(name_rva, num_names * 4)
        ordinals = self.offset(ordinal_rva, num_names * 2)
        found = []
        for i in range(num_names):
            idx = get_int(b, ordinals + 2 * i, "H")
            if idx >= num_funcs:
                continue
            symbol_rva = get_int(b, funcs + 4 * idx)
            # A forwarded export is a string RVA inside the export directory.
            if not symbol_rva or self.exports_rva <= symbol_rva < self.exports_rva + self.exports_size:
                continue
            label = self.cstring(get_int(b, names + 4 * i))
            found.append((symbol_rva, label))
        return sorted(set(found))


def addr2line_exe() -> Path | None:
    candidates = [
        os.environ.get("VIOLET_ADDR2LINE", ""),
        r"C:\msys64\ucrt64\bin\addr2line.exe",
        r"C:\msys64\clang64\bin\llvm-addr2line.exe",
        r"C:\msys64\usr\bin\addr2line.exe",
        shutil.which("x86_64-w64-mingw32-addr2line") or "",
        shutil.which("addr2line") or "",
        shutil.which("llvm-addr2line") or "",
    ]
    for val in candidates:
        if val and Path(val).is_file():
            return Path(val)
    return None


def dwarf_symbols(tool: Path | None, pe: PE, rvas: list[int]) -> dict[int, str]:
    if not tool:
        return {}
    addrs = [f"0x{pe.image_base + x:x}" for x in rvas]
    try:
        cmd = [str(tool), "-f", "-C", "-p", "-e", str(pe.path), *addrs]
        done = subprocess.run(cmd, text=True, capture_output=True, timeout=40, check=False)
    except (OSError, subprocess.TimeoutExpired) as exc:
        print(f"addr2line unavailable: {exc}")
        return {}
    if done.returncode:
        print(f"addr2line exited {done.returncode}: {done.stderr[:300].strip()}")
        return {}
    output = done.stdout.splitlines()
    if len(output) != len(rvas):
        print(f"addr2line returned {len(output)} records for {len(rvas)} addresses")
        return {}
    return {rva: out.strip() for rva, out in zip(rvas, output)
            if out.strip() and not out.strip().startswith("??")}


def locate_export(exports: list[tuple[int, str]], rva: int) -> str | None:
    if not exports:
        return None
    i = bisect.bisect_right(exports, (rva, "\uffff")) - 1
    if i < 0:
        return None
    addr, symbol = exports[i]
    delta = rva - addr
    if delta == 0:
        return f"export {symbol} (exact entry)"
    # The next export can be separated by static functions / linker padding.
    # A nearest export is a lead, not proof of the containing function.
    if delta < 0x4000:
        return f"nearest export {symbol}+0x{delta:x} (approximate, NOT proven containing)"
    return None


def parse_frames(log: str) -> list[tuple[int, int]]:
    frames = []
    seen = set()
    for frame, addr in FRAMES.findall(log):
        rva = int(addr, 16)
        if rva not in seen:
            frames.append((int(frame), rva))
            seen.add(rva)
    return frames


def analyze(log: str, exe: Path, tool: Path | None = None) -> int:
    pe = PE(exe)
    frames = parse_frames(log)
    if not frames:
        raise ValueError("No lasrecomp+RVA stack frames found in crash log")
    exports = pe.named_exports()
    print(f"EXE: {exe}")
    print(f"PE preferred image base: 0x{pe.image_base:x}")
    print(f"PE named exports: {len(exports)}")
    if tool:
        print(f"DWARF addr2line: {tool}")
    else:
        print("DWARF addr2line: unavailable (checked MSYS2 UCRT64 and PATH)")
    rvas = [x for _, x in frames]
    dwarf = dwarf_symbols(tool, pe, rvas)
    print()
    for frame, rva in frames:
        parts = [f"#{frame:02d} lasrecomp+0x{rva:x}"]
        if rva in dwarf:
            parts.append(f"DWARF: {dwarf[rva]}")
        export = locate_export(exports, rva)
        if export:
            parts.append(export)
        if len(parts) == 1:
            parts.append("no symbol found")
        print(" | ".join(parts))
    print()
    if not dwarf and not exports:
        print("No resolvable DWARF or exported names; verify the matching EXE was not stripped.")
    elif not dwarf:
        print("No DWARF line names found. Export matches are approximate unless exact.")
    print("This resolves Windows native stack RVAs; it does not infer a cause from nearby shader logs.")
    return 0


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--log", type=Path, required=True)
    p.add_argument("--exe", type=Path, required=True)
    args = p.parse_args()
    log = args.log.read_text(encoding="utf-8", errors="replace")
    return analyze(log, args.exe.resolve(), addr2line_exe())


if __name__ == "__main__":
    raise SystemExit(main())
