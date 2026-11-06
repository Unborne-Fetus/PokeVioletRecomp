# Pokémon Violet Recomp

**Experimental native-PC recompilation port of Pokémon Violet, built from the Z-A Recomp / LAS Recomp framework.**

> **Status: early port in progress. Not playable and no Violet build is available yet.**
> Do **not** use the original Z-A Recomp download as a Violet executable.

This fork reuses the open-source AArch64-to-C lifter, Horizon/SDK replacements, NVN renderer, Vulkan backend, SDL3 controller input, build system, and launcher concepts. It **does not** reuse Z-A's game-specific addresses or executable instruction patches.

### Current work

- **Violet dump validation:** tools/violet/check_dump.py checks the Violet NPDM title ID, main, sdk, subsdk0, and RomFS presence. It is read-only.
- **Violet package import:** tools/zaimport/Program.cs supports --game violet for a personally dumped base/update package. Default remains Z-A for the upstream workflow.
- **Patch-free Violet lifting:** tools/gen.py --game violet disables the Z-A and Link's Awakening game-specific patches while generating C from a personally extracted NSO. This is only a **first generation milestone**, not a runnable port.
- Synthetic-header unit tests in tests/test_violet_check_dump.py.

### Use the validator

From the repository root:

~~~sh
python tools/violet/check_dump.py /path/to/your/extracted-game
python tools/violet/check_dump.py /path/to/your/extracted-game --json
python -m unittest discover -s tests -p 'test_violet_*.py' -v
~~~

Expected layout:

~~~text
your/extracted-game/
  exefs/
    main
    main.npdm
    sdk
    subsdk0
  romfs/
    arc/
      data.trpfs
~~~

The validator also accepts romfs.bin in place of the extracted romfs/ tree. A passing result **only** confirms the file layout and header metadata.

For original XCI/NSP packages owned and dumped by the user, the existing .NET importer can be invoked as:

~~~sh
dotnet run --project tools/zaimport -- --game violet /path/to/prod.keys output-folder base.xci optional-update.nsp
~~~

It extracts files **locally**. The project never distributes Nintendo executable code, assets, saves, firmware, or keys. Do not commit these files.

For a source-only **lifter experiment** (requires the Python dependencies used by the upstream generator):

~~~sh
python tools/gen.py main /path/to/exefs/main 0x7000000000 generated/main --game violet --simd c
~~~

The output is not yet linked into a working Violet host. Only use this command after the preflight passes. Generation can consume substantial CPU time and disk space.

### Remaining engineering blockers

1. **Three-module support**: the upstream runtime only loads and dispatches main and sdk; Violet also has subsdk0. Extend memory mapping, dynamic relocations, generated tables, and the game-code library ABI.
2. **Version detection and launcher**: replace Z-A-only build-ID allowlists, setup text, release links, and compatibility checks with verified Violet support. Never silently accept a different game.
3. **Game-specific Horizon/NVN behavior**: validate Violet's Trinity engine allocation, shader/pipeline state, frame pacing, audio, and video playback. Do not copy Z-A-specific memory addresses or frame patches.
4. **Boot and game testing**: run on the user's machine with their own extracted files. Establish first frame, language selection, intro, world loading, saves, controls, then optimize toward 30 FPS.

**Current verified milestone:** preflight unit tests pass on synthetic headers. There has been **no real-Violet boot test** because the game files and the authorized PC are not available to this session.

### Origins and credits

- [PokeZ-ARecomp](https://github.com/Hexveil404/PokeZ-ARecomp) by Hexveil404 and contributors: reused porting framework and Z-A host support.
- [LASRecomp](https://github.com/peiikai/LASRecomp) by Peiikai and contributors: base static recompilation and runtime.
- Their MIT and third-party license notices remain in the repository.
- Original fork README: [docs/ZA-UPSTREAM-README.md](docs/ZA-UPSTREAM-README.md).

This is a fan development project; it is not affiliated with Nintendo, Game Freak, Creatures, or The Pokémon Company.
