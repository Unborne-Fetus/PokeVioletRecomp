"""Generate every Violet module from privately imported game files; module bases match the runtime."""
import argparse
import platform
from pathlib import Path
import subprocess
import sys
from violet_target import MODULES, check_exefs


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('exefs', type=Path)
    parser.add_argument('outdir', type=Path)
    parser.add_argument('--simd', choices=('asm', 'c'),
                        default='asm' if platform.machine().lower() in ('arm64', 'aarch64') else 'c')
    parser.add_argument('--limit', type=int, default=0)
    args = parser.parse_args()
    try:
        version = check_exefs(args.exefs)
    except (OSError, ValueError) as e:
        parser.exit(1, f'{e}\n')
    print(f'Pokémon Violet {version}: generating {len(MODULES)} modules, no game-specific patches', flush=True)
    tools = Path(__file__).resolve().parent
    for name, base, use_hle in MODULES:
        command = [sys.executable, str(tools / 'gen.py'), name, str(args.exefs / name), hex(base),
                   str(args.outdir / name), '--simd', args.simd]
        if use_hle:
            command += ['--hle', str(tools.parent / 'runtime/hle/hle_symbols.txt')]
        if args.limit:
            command += ['--limit', str(args.limit)]
        subprocess.run(command, check=True)


if __name__ == '__main__':
    main()
