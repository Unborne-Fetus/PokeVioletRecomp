# Violet Recomp Windows release (experimental)

A Windows x64 release ZIP contains the native launcher PokeVioletRecomp.exe, its real runtime lasrecomp.exe, dependency DLLs and on-device preparation tools.

## Run
1. Download PokeVioletRecomp-*-Windows-x64.zip from Releases.
2. Extract the entire ZIP into a writable folder (not Program Files).
3. Double-click PokeVioletRecomp.exe. Use the built-in start screen to select the folder containing your own legitimately obtained Pokemon Violet game files and keys.
4. Allow considerable time and disk space for the first local import and compilation. No game data, keys or compiled guest code ships in the ZIP.

**Experimental alpha**: Native code builds and static checks do not verify successful game boot, correct graphics, gameplay, or acceptable performance.

Requires Windows x64, a Vulkan-capable GPU, and for optimized game-code compilation an AVX2-capable CPU. The first import/build can be large. Saves/settings remain local.

## Build and distribution
The windows-violet-release.yml workflow builds the actual native runtime, LGPL-only FFmpeg, local importer, Python game-code generator, pinned Zig compiler, and a thin convenience launcher. It verifies the package contains no proprietary game content. It creates a prerelease only after successful compilation and packaging.

Updater limitations: the current runtime's old release-name matching does not recognize this prerelease reliably, so use the GitHub releases page for alpha updates. Do not treat a successful CI compile as a playable-game guarantee.
