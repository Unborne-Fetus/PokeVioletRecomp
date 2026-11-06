# Pokémon Violet Recomp

**Experimental native-PC recompilation port of Pokémon Violet, built from the Z-A Recomp / LAS Recomp framework.**

> **Status: early port in progress. Not playable and no Violet build is available yet.**
> Do **not** use the original Z-A Recomp download as a Violet executable.

This fork reuses the open-source AArch64-to-C lifter, Horizon/SDK replacements, NVN renderer, Vulkan backend, SDL3 controller input, build system, and launcher concepts. It **does not** reuse Z-A's game-specific addresses or executable instruction patches.

### Current work

- **Violet dump validation:** tools/violet/check_dump.py checks the Violet NPDM title ID, main, sdk, subsdk0, and RomFS presence. It is read-only.
- **Violet package import:** tools/zaimport/Program.cs supports --game violet for a personally dumped base/update package. Default remains Z-A for the upstream workflow.
- **Patch-free Violet lifting:** tools/gen.py --game violet disables Z-A/Link's Awakening instruction patches for Violet.
- **Three-module runtime:** runtime/loader.c maps main, subsdk0 and sdk; runtime/dispatch.c indexes all three generated function tables, and runtime/main.c invokes the extra module initializers.
- **Incremental compilation:** runtime/gamebuild.c runs a third code generator for Violet's subsdk0 and links the game library with ABI 2.
- **Launcher and packaging:** Violet NPDM detection, Violet-targeted importer, own release feed, isolated Linux save/config path, and initial 30 FPS/1× resolution defaults.
- Synthetic-header tests in tests/test_violet_check_dump.py, C syntax checks and a .NET importer compilation are run by GitHub Actions. These are engineering checks, not boot tests.

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

For the full source build, run `make gen GAME_MODE=violet EXEFS=extracted/exefs` after installing upstream development dependencies, then compile the host and game library. Actual booting remains unverified. Generation can consume substantial CPU time and disk space.

### Remaining engineering blockers

1. **Boot testing on Violet binaries**: the extra module now has a loader, dispatch table, compilation path and initializer, but needs an actual Violet boot run to verify addresses, imports, and memory reservation.
2. **Violet-specific Horizon/NVN work**: validate Trinity engine memory allocation, shader/pipeline state, frame pacing, audio, video playback and save behavior. No Z-A instruction patches are reused.
3. **Executable validation and compatibility**: prove base 1.0.0 first; test updates separately before claiming compatibility. Current NPDM detection accepts the Violet title but unknown builds are experimental.
4. **Gameplay and performance**: reach first frame, language selection, intro, open world and saves on a real PC; then profile and tune toward stable 30 FPS.

**Current verified milestone:** GitHub Actions passed the synthetic preflight unit tests, C syntax checks, and a .NET importer build. The full game/runtime build and Violet boot have **not** been tested because the game files and authorized PC are unavailable.

### Origins and credits

- [PokeZ-ARecomp](https://github.com/Hexveil404/PokeZ-ARecomp) by Hexveil404 and contributors: reused porting framework and Z-A host support.
- [LASRecomp](https://github.com/peiikai/LASRecomp) by Peiikai and contributors: base static recompilation and runtime.
- Their MIT and third-party license notices remain in the repository.
- Original fork README: [docs/ZA-UPSTREAM-README.md](docs/ZA-UPSTREAM-README.md).

This is a fan development project; it is not affiliated with Nintendo, Game Freak, Creatures, or The Pokémon Company.
