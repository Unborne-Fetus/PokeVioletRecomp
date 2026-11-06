"""Violet's verified executable versions and module layout (the runtime's same headers)."""
from pathlib import Path
import re
import struct
import sys

RUNTIME = Path(getattr(sys, '_MEIPASS', Path(__file__).resolve().parent.parent)) / 'runtime'
_target = (RUNTIME / 'game_target.h').read_text(encoding='utf-8')
_constants = {name: int(value, 16) for name, value in
              re.findall(r'^#define (\w+) (0x[0-9A-Fa-f]+)ull$', _target, re.M)}
PROGRAM_ID = _constants['GAME_PROGRAM_ID']
MODULES = [(name, _constants[base], bool(int(hle))) for name, base, hle in
           re.findall(r'\bX\((\w+), (\w+), ([01])\)', _target)]
VERSIONS = {}
for _key, _label, _main, _multimedia, _sdk in re.findall(
        r'VIOLET_VERSION\((\w+), "([^"]+)", "([A-F0-9]{40})", "([A-F0-9]{40})", "([A-F0-9]{40})"\)',
        (RUNTIME / 'violet_versions.h').read_text(encoding='utf-8')):
    VERSIONS[_main.lower()] = (_label, {'main': _main.lower(), 'subsdk0': _multimedia.lower(), 'sdk': _sdk.lower()})


def read_header(path):
    with Path(path).open('rb') as f:
        header = f.read(0x60)
    if len(header) != 0x60 or header[:4] != b'NSO0':
        raise ValueError(f'{path}: missing or invalid NSO executable')
    return header


def check_exefs(exefs):
    """Refuse other titles, unrecognized builds, mixed-version modules and overlapping images before generation."""
    exefs = Path(exefs)
    meta = (exefs / 'main.npdm').read_bytes()
    if len(meta) < 0x80 or meta[:4] != b'META':
        raise ValueError('exefs/main.npdm is invalid')
    aci = struct.unpack_from('<I', meta, 0x70)[0]
    if aci < 0x80 or aci + 0x18 > len(meta) or meta[aci:aci+4] != b'ACI0':
        raise ValueError('exefs/main.npdm has no valid ACI0')
    program = struct.unpack_from('<Q', meta, aci + 0x10)[0]
    if program != PROGRAM_ID:
        raise ValueError(f'these are not Pokémon Violet files (program {program:016X})')
    main_id = read_header(exefs / 'main')[0x40:0x54].hex()
    if main_id not in VERSIONS:
        raise ValueError(f'unrecognized Violet build {main_id}; configured versions are 1.0.0 and 4.0.0')
    label, ids = VERSIONS[main_id]
    for i, (name, base, _) in enumerate(MODULES):
        hdr = read_header(exefs / name)
        if hdr[0x40:0x54].hex() != ids[name]:
            raise ValueError(f'exefs/{name} is from another game version')
        data_off, data_size, bss = struct.unpack_from('<III', hdr, 0x34)
        size = (data_off + data_size + bss + 0x3fff) & ~0x3fff
        limit = MODULES[i+1][1] if i+1 < len(MODULES) else _constants['GAME_CODE_END']
        if not size or size > limit - base:
            raise ValueError(f'exefs/{name} does not fit its configured guest address range')
    return label
