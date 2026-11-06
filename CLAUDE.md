# Violet Recomp development notes

This checkout is a fresh fork of ZA Recomp being retargeted to Pokémon Violet. Do not reuse assumptions, game addresses or generated files from an earlier Violet project. Gameplay has not been verified.

## Target and inputs

- Violet program ID: `01008F6008C5E000`. Update: `01008F6008C5E800`; DLC family: `01008F6008C5Fxxx`.
- `runtime/game_target.h`: title, module list and guest bases. `runtime/violet_versions.h`: verified build IDs for 1.0.0 and 4.0.0. `tools/violet_target.py` reads those same headers, including from the frozen generator's resources.
- Every target check must validate `main.npdm`, main's complete 20-byte build ID and all three matching NSOs. Do not fall back to another game's addresses or accept a build from its filename.
- `tools/zaimport/Program.cs` is now Violet's importer. Its historical name is retained for launcher/build compatibility. It reads XCI/NSP packages and applies updates/DLC automatically; manual extraction is not required.
- `tools/violet/prepare.ps1`: reproducible preparation; `-InspectOnly` reads ExeFS into a scratch folder, `-Generate` also translates the game.

## Compilation and runtime

- Modules: main at `0x7000000000`, multimedia/subsdk0 at `0x7006000000`, SDK at `0x7008000000`. Keep `GAME_MODULES` authoritative across loading, generation, cache bookkeeping and library entry tables.
- `tools/gen_all.py` drives all modules; `tools/gen.py` uses Violet's original instructions with no Z-A/Zelda/randomizer patches. Only SDK uses `runtime/hle/hle_symbols.txt`.
- `runtime/gamelib.h` ABI 2 represents every module; old upstream two-module libraries are incompatible.
- Run module constructors after nninitStartup installs Violet's heap/TLS allocators, in dependency order: SDK, multimedia, main. Running SDK constructors in the early callback crashed in main's malloc with TPIDR_EL0 = 0. Do not restore that order or fixed two-module indices.
- `runtime/gamebuild.c` and `runtime/build_cache.cpp` must retain, invalidate and clean receipts for subsdk0 too. Target/header changes participate in library and object-cache identities.
- Inherited Zelda helpers remain compiled for upstream maintenance, but `g_game_is_la` starts false and no Zelda address table is selected for Violet.
- Z-A's FPS hooks, resource/icon generators, battle-layout preparation and party-save decoder are not Violet implementations. Keep them disabled until mapped and verified for a specific Violet build.
- Runtime resources shipped for game compilation include `game_target.h`; frozen Python resources include both target and version headers.

## Validation

- `tools/test_violet_target.py`: actual C/Python target validation, wrong title, unknown full build IDs, mixed module versions, missing modules and image overlap.
- `tools/test_violet_modules.py`: production library entry, dispatch and host symbol lookup for all three modules.
- `tools/test_gamebuild_resume.py`: production build scheduler/cache with tiny generated fixtures, including cancellation/resume, multimedia invalidation and failed-build preservation.
- `tools/test_build_cache.py`: production cache receipts and filesystem handling.
- Full local 4.0.0 generation produced 233,286 functions / 1,723 chunks. A generation pass is not evidence of a working native boot.
- Complete native runtime/game-library builds and a launcher screenshot test passed. The guest now initializes all modules, RomFS/DLC, NVN and audio, but aborts later in startup before the first displayed frame. See docs/VIOLET-PORT.md; do not claim working gameplay.
- Run controlled boot tests with separate saves/settings. Warn the user before opening a test game window and never kill their running game.

## Working rules

- Never commit Nintendo files, keys, extracted data, generated game code, fonts, textures or saves. They stay in ignored directories.
- Keep LF source line endings (`.gitattributes`).
- Runtime dependencies: SDL3, FFmpeg, Vulkan, shaderc and the existing bundled libraries. Portable .NET and Zig used locally live under ignored `build/` paths.
- `tools/violet/build.ps1 -Game` rebuilds the prepared local toolchain; build_config.py creates explicit C exports for Zig (automatic exports were incomplete), correct DATA exports and the giant-function settings. `tools/violet/run.ps1` sets the private DLL search path and runs from this checkout.
- The scripts under `tools/za/` and most legacy documentation describe upstream Z-A. Do not publish a Violet release using their unmodified Z-A package contents or claims.
- Runtime UI and updates belong to `Unborne-Fetus/PokeVioletRecomp`; do not point its updater at the upstream Z-A release feed.
