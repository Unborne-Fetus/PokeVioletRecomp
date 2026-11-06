"""Configure the local Windows Zig build: explicit host exports and conservative optimization for giant functions."""
from pathlib import Path
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]
BUILD = Path('build/violet-gnu')


def write_if_changed(path, content):
    if not path.exists() or path.read_text(encoding='utf-8') != content:
        path.write_text(content, encoding='utf-8', newline='\n')


def main():
    # Zig's Windows library search does not pick up MSYS2's .dll.a suffix. Keep the original archives and add aliases.
    lib = Path('build/msys-deps/ucrt64/lib')
    for source in lib.glob('lib*.dll.a'):
        alias = lib / (source.name[3:-6] + '.lib')
        if not alias.exists():
            shutil.copyfile(source, alias)
    # Some codec packages require OpenMP through a virtual dependency not included in the private package set.
    openmp = Path('build/msys-deps/ucrt64/bin/libgomp-1.dll')
    if not openmp.exists():
        installed = Path('C:/msys64/ucrt64/bin/libgomp-1.dll')
        if not installed.exists():
            raise SystemExit('The MSYS2 UCRT64 OpenMP runtime (libgomp-1.dll) is missing.')
        shutil.copyfile(installed, openmp)
    objects = sorted((BUILD / 'rt').rglob('*.o'))
    if not objects:
        raise SystemExit('Build runtime-objs before creating the runtime export table.')
    nm = Path('C:/msys64/ucrt64/bin/nm.exe')
    symbols = subprocess.check_output([str(nm), '-g', '--defined-only', *map(str, objects)], text=True)
    exports = {}
    for line in symbols.splitlines():
        match = re.fullmatch(r'[0-9a-fA-F]+\s+([TDBR])\s+([A-Za-z_][A-Za-z0-9_.$?@]*)', line.strip())
        if match and not match[2].startswith(('_Z', '__')) and match[2] != 'main':
            exports[match[2]] = match[1]
    if 'rt_dispatch' not in exports:
        raise SystemExit('The compiled runtime has no rt_dispatch export.')
    definition = BUILD / 'runtime_exports.def'
    write_if_changed(definition, 'EXPORTS\n' + '\n'.join(
        name + (' DATA' if kind != 'T' else '') for name, kind in sorted(exports.items())) + '\n')
    # Compiler-rt in this Zig build omits the GNU CPU-detection routines used by __builtin_cpu_supports.
    runtimes = sorted(Path('C:/msys64/ucrt64/lib/gcc/x86_64-w64-mingw32').glob('*/libgcc.a'))
    if not runtimes:
        raise SystemExit('The installed MSYS2 UCRT64 x86-64 GCC support archive is missing.')
    write_if_changed(BUILD / 'toolchain.mk', f'LDFLAGS += {runtimes[-1].as_posix()}\n'
                     f'$(EXE): {definition.as_posix()}\n')
    giants = []
    for source in sorted(Path('generated').glob('*/*.c')):
        if source.name.endswith('_table.c'):
            continue
        definitions = labels = 0
        with source.open(encoding='utf-8') as f:
            for line in f:
                if line.startswith('void f_') and '(Cpu *c) {' in line:
                    definitions += 1
                elif line.startswith('L_'):
                    labels += 1
        if definitions == 1 and labels > 1000:
            obj = BUILD / 'obj' / source.relative_to('generated').with_suffix('.o')
            giants.append(f'{obj.as_posix()}: GENFLAGS += -O0')
    write_if_changed(BUILD / 'giants.mk', '\n'.join(giants) + '\n')
    print(f'Configured {len(exports)} host exports and {len(giants)} giant functions')


if __name__ == '__main__':
    import os
    os.chdir(ROOT)
    main()
