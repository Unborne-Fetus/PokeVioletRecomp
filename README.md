# Violet Recomp

An experimental static recompilation port of **Pokémon Violet**, starting from a fresh fork of [ZA Recomp](https://github.com/Hexveil404/PokeZ-ARecomp), which is based on [LAS Recomp](https://github.com/peiikai/LASRecomp).

**Porting is in progress. A playable Violet build has not been verified.** The upstream project's Z-A screenshots, performance claims, patches and release downloads do not establish Violet compatibility.

The application reads the player's own Switch packages and keys, prepares private game files, translates ARM64 code into C and compiles it for the host. Players do not need to extract the game manually. No game files, keys or generated game code are distributed.

## Current state

- Importer targets Violet (`01008F6008C5E000`), its update and its DLC family.
- Executable profiles verified from local packages: **1.0.0** and **4.0.0**. These identify accepted files; they do not promise working gameplay.
- Full base + 4.0.0 update + one DLC import completed locally.
- All three required modules are configured: `main`, `subsdk0` (multimedia) and `sdk`.
- Full 4.0.0 code generation completed: 233,286 functions in 1,723 C chunks.
- The complete Windows runtime and game DLL compile and link locally. The launcher opens on Vulkan; guest startup reaches graphics/audio initialization and then aborts before its first displayed frame.
- Z-A/Zelda instruction patches, randomizer patches, Z-A resource preparation and Z-A party-save previews are disabled for Violet.
- Launcher and runtime share title, module and executable-version validation. Update links point to this fork.

Further startup/service compatibility work is needed before this is playable. See [porting notes](docs/VIOLET-PORT.md) for the current stopping point.

## Prepare your own game (Windows)

Requires the .NET 8 SDK. To generate C, also use Python with `lz4`, `capstone` and `unicorn`. The helper uses a portable SDK at `build/toolchain/dotnet/` when present, otherwise the installed SDK.

Place your base XCI/NSP, optional update NSP and optional DLC NSP in one folder, then run from PowerShell:

```powershell
.\tools\violet\prepare.ps1 -GameFolder 'D:\Switch\Violet' -Keys 'D:\Switch\prod.keys'
```

The default game folder is this checkout. Keys are also detected in the selected folder, its `keys` subfolder, Ryujinx's system folder or your `.switch` folder. `title.keys` beside `prod.keys` is used when necessary. Original packages and keys are read only.

The helper builds the importer and prepares `extracted/exefs`, `extracted/romfs.bin` and `extracted/aoc`. These are private build inputs, ignored by Git. The importer retains its upstream executable name, `zaimport.exe`, to keep the launcher protocol and helper paths consistent.

To also translate all modules into `generated/`:

```powershell
.\tools\violet\prepare.ps1 -Generate
```

For an executable-only developer inspection, without copying RomFS:

```powershell
.\tools\violet\prepare.ps1 -InspectOnly
```

This writes to `build/violet-inspect/` and is not a playable game installation. Use `-Package` with explicit paths when a folder contains multiple base games or update versions.

## Development

`runtime/game_target.h` defines the title and guest module layout. `runtime/violet_versions.h` records the verified main, multimedia and SDK build IDs. Both the C runtime and Python tools use these files.

```powershell
.\tools\venv\Scripts\python.exe tools\gen_all.py extracted\exefs generated
```

`make gen` uses the same driver. `make` includes generated C from all three modules. The game-code library uses ABI 2; a two-module upstream library cannot be reused.

The inherited runtime build instructions are in [docs/BUILD-windows.md](docs/BUILD-windows.md). The full SDL3/FFmpeg/Vulkan/shaderc runtime toolchain is separate from the importer and Python generator. Upstream release scripts under `tools/za/` still contain Z-A-specific packaging and are not a Violet release workflow.

**Launching Violet on Windows:** once your private game files and native game DLL have been prepared, double-click **`Play Violet.cmd`** in the repository folder, or run `.\tools\violet\run.ps1 -Play` in PowerShell. Both methods pass the absolute `extracted` path to the runtime, so switching to the user-data directory will not hide the game files. To check for missing files without launching anything, use `.\tools\violet\run.ps1 -CheckOnly`. If the guest aborts, run `.\tools\violet\test_boot.ps1` to capture a separate diagnostic log and JSON report. The launcher is runnable; **a working in-game boot has not yet been verified**.

This checkout also has a prepared private toolchain under `build/zig` and `build/msys-deps/ucrt64`. Rebuild it and open the development launcher with:

```powershell
.\tools\violet\build.ps1 -Game
.\tools\violet\run.ps1
```

`build.ps1` requires MSYS2 at `C:\msys64`, its x86-64 GCC support archive, the private Zig compiler/dependencies and generated game code. It recreates the host export table and large-function optimization settings. A new machine can use the standard installed-toolchain instructions instead. Development builds do not check for application updates.

Native regression checks (set `CC`/`CXX` to your compiler as needed):

```powershell
python tools\test_violet_target.py
python tools\test_violet_modules.py
python tools\test_gamebuild_resume.py
python tools\test_build_cache.py
```

## Credits and license

[ZA Recomp](https://github.com/Hexveil404/PokeZ-ARecomp) by Hexveil404 provides this fork's runtime and tools. [LAS Recomp](https://github.com/peiikai/LASRecomp) by Peiikai provides the original static recompiler and runtime architecture. Third-party components retain their own licenses; see their directories, the inherited [component/license list](docs/LASRecomp-README.md#license) and [LICENSE](LICENSE).

Pokémon and Nintendo Switch are trademarks of their respective owners. This project is independent of Nintendo, Game Freak and The Pokémon Company.
