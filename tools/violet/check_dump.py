#!/usr/bin/env python3
"""Read-only preflight for a personally extracted Pokémon Violet Switch dump.

No game files are copied, decrypted, uploaded, or committed. Only the NSO
headers and the NPDM program ID are read. This is not a boot compatibility test.
"""
from __future__ import annotations

import argparse
import json
import struct
import sys
from pathlib import Path

VIOLET_TITLE_ID = 0x01008F6008C5E000
ZA_MAIN_PREFIXES = {"7222e13ecf6adb32", "8a1c86c437394b69", "b1f12fd919eae86a"}
MODULES = ("main", "sdk", "subsdk0")


def _nso_info(path: Path) -> dict:
    with path.open("rb") as file:
        header = file.read(0x70)
        file.seek(0, 2)
        length = file.tell()
    if len(header) < 0x70 or header[:4] != b"NSO0":
        raise ValueError(f"{path.name}: expected an unencrypted NSO0 module")
    flags = struct.unpack_from("<I", header, 0x0C)[0]
    segments = {}
    for index, name in enumerate(("text", "rodata", "data")):
        offset, address, uncompressed = struct.unpack_from("<III", header, 0x10 + index * 0x10)
        compressed = struct.unpack_from("<I", header, 0x60 + index * 4)[0]
        size = compressed if flags & (1 << index) else uncompressed
        if offset > length or size > length - offset:
            raise ValueError(f"{path.name}: {name} segment points outside the file")
        segments[name] = {"memory_offset": address, "size": uncompressed}
    return {"build_id": header[0x40:0x60].hex(), "size_bytes": length, "segments": segments}


def _program_id(path: Path) -> int:
    with path.open("rb") as file:
        head = file.read(0x80)
        if len(head) < 0x80 or head[:4] != b"META":
            raise ValueError("main.npdm: expected a META header")
        aci_offset = struct.unpack_from("<I", head, 0x70)[0]
        if aci_offset < 0x80 or aci_offset > 0x100000:
            raise ValueError("main.npdm: invalid ACI0 offset")
        file.seek(aci_offset)
        aci = file.read(0x18)
    if len(aci) < 0x18 or aci[:4] != b"ACI0":
        raise ValueError("main.npdm: missing ACI0 section")
    return struct.unpack_from("<Q", aci, 0x10)[0]


def inspect(root: Path) -> dict:
    root = root.resolve()
    exefs = root if (root / "main").is_file() else root / "exefs"
    base = exefs.parent
    result = {"game": "Pokémon Violet", "title_id": None, "modules": {}, "romfs": None,
              "valid": False, "warnings": [], "errors": [], "stage": "preflight_only"}
    npdm = exefs / "main.npdm"
    if not npdm.is_file():
        result["errors"].append("exefs/main.npdm is missing")
    else:
        try:
            title_id = _program_id(npdm)
            result["title_id"] = f"{title_id:016X}"
            if title_id != VIOLET_TITLE_ID:
                result["errors"].append("Wrong game: NPDM title ID does not match Pokémon Violet")
        except (OSError, ValueError) as error:
            result["errors"].append(str(error))
    for name in MODULES:
        file = exefs / name
        if not file.is_file():
            result["errors"].append(f"exefs/{name} is missing")
            continue
        try:
            result["modules"][name] = _nso_info(file)
        except (OSError, ValueError) as error:
            result["errors"].append(str(error))
    if "main" in result["modules"]:
        main_prefix = result["modules"]["main"]["build_id"][:16]
        if main_prefix in ZA_MAIN_PREFIXES:
            result["errors"].append("This appears to be a Legends: Z-A executable, not Violet")
        if not main_prefix.startswith("959ed651"):
            result["warnings"].append("Unknown Violet main build: version-specific compatibility is unverified")
    if (base / "romfs" / "arc" / "data.trpfs").is_file():
        result["romfs"] = "extracted"
    elif (base / "romfs.bin").is_file():
        result["romfs"] = "image"
    else:
        result["errors"].append("RomFS missing (expected romfs/arc/data.trpfs or romfs.bin)")
    result["valid"] = not result["errors"]
    return result


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("game_folder", type=Path, help="Folder with exefs/ and romfs/ (or exefs/ itself)")
    parser.add_argument("--json", action="store_true", help="Print metadata only, no game bytes")
    args = parser.parse_args(argv)
    result = inspect(args.game_folder)
    if args.json:
        print(json.dumps(result, indent=2))
    else:
        print("Pokémon Violet recomp preflight:", "PASS" if result["valid"] else "FAIL")
        print("  title ID:", result["title_id"] or "unknown")
        print("  modules:", ", ".join(result["modules"]) or "none")
        print("  RomFS:", result["romfs"] or "missing")
        for message in result["warnings"]:
            print("  warning:", message)
        for message in result["errors"]:
            print("  error:", message)
        if result["valid"]:
            print("  Files look structurally correct; the Violet runtime is NOT yet bootable.")
    return 0 if result["valid"] else 2


if __name__ == "__main__":
    sys.exit(main())
