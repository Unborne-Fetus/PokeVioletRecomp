"""Compile the production library entry and dispatcher against tiny module function tables."""
import os
from pathlib import Path
import shlex
import subprocess
import tempfile

root = Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory() as temp:
    output = Path(temp) / ('modules.exe' if os.name == 'nt' else 'modules')
    cc = shlex.split(os.environ.get('CC', 'clang'))
    subprocess.run(cc + ['-O0', '-ffunction-sections', '-fdata-sections', '-Iruntime',
                        'runtime/dispatch.c', 'runtime/game_target.c', 'tools/gamelib_entry.c',
                        'tools/test_violet_modules.c', '-Wl,--gc-sections', '-o', str(output)], cwd=root, check=True)
    subprocess.run([str(output)], check=True)
