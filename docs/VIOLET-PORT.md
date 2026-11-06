# Violet retargeting: initial milestone

The starting point is the Z-A fork in this checkout. No earlier Violet port code was reused.

## Verified locally

The package importer reads Violet's base XCI, the supplied 4.0.0 update NSP and one DLC NSP using the player's keys, without manual extraction. Control metadata identifies the base as 1.0.0 and the update as 4.0.0. A full merged RomFS and DLC image were written under ignored `extracted/`.

`runtime/violet_versions.h` records each version's complete 20-byte main, multimedia and SDK build IDs. Runtime and generator reject another title, an unknown main build or mixed-version NSOs.

| Module | Guest base | 1.0.0 image size | 4.0.0 image size | 4.0.0 functions | C chunks |
|---|---|---|---|---|---|
| main | `0x7000000000` | `0x43f5000` | `0x47d3000` | 180,337 | 1,379 |
| subsdk0 / multimedia.nss | `0x7006000000` | `0x69a000` | `0x69a000` | 13,662 | 156 |
| sdk / nnSdk.nss | `0x7008000000` | `0xda7000` | `0xda8000` | 39,287 | 188 |

Violet imports multimedia.nss. The upstream two-module loader, function tables, constructor callbacks, generation loop and build cache all required changes. Constructors run after nninitStartup installs the application's heap/TLS allocators: SDK first, multimedia second and main last. Running SDK constructors in the early callback reached newlocale -> main's malloc with TPIDR_EL0 = 0 and crashed; deferring them passed that point. The three-module game-code interface uses ABI 2.

All three 4.0.0 modules completed full code generation and native compilation/linking: 1,727 objects, including function tables and the library entry. The game DLL is about 830 MB. The synthetic module regression executes the production dispatcher and host symbol lookup. Target validation, build-resume and cache tests passed.

The native Vulkan launcher opened on the local RTX 5060 and saved `build/violet-launcher.png`. The controlled guest test used scratch settings/saves, disabled input and a 30-second limit. It loaded all three modules and reached all constructors, game-data reads, DLC detection, NVN device/window initialization and audio renderer startup.

The guest then called its own abort before the first displayed frame: `svcBreak` at `0x70083cd970`, with a Result payload of zero. This remains unresolved. The log records several placeholder services (`hwopus`, `bcat:u`, `bt`, `btm:u`, `ectx:aw`) and an unhandled IApplicationFunctions command 22. These are observations, not a proven cause of the abort. The return chain includes main addresses `0x7002ac3f4c`, `0x70009303d4`, `0x7000930588`, `0x700092c938`, `0x700165e87c`, `0x700165cb7c`.

The full run is in `build/violet-boot-deferred-stderr.log`. No user save was imported or modified. The test process exited after the game's abort.

Z-A/Zelda instruction patches and randomizer tables are not loaded. Z-A's prompt/battle resource preparer, party-save preview and frame-rate controls are disabled. The fork's launcher branding/update feed and Linux/macOS data identities are separate from upstream.

## Next milestone

Trace the application's startup abort and implement the required service behavior. Inspect the guest condition rather than bypassing its check or treating empty successful IPC replies as complete implementations. Repeat the controlled boot and verify a first presented frame before gameplay or performance work.

Violet-specific FPS patches, party previews, modified UI resources and DLC gameplay remain unverified. Upstream Z-A release scripts and old feature documentation are historical references until ported deliberately.

## Reproduce

See `tools/violet/prepare.ps1` for package preparation and `tools/gen_all.py` for code generation. `tools/violet/build.ps1 -Game` recreates the local Zig export/optimization configuration and rebuilds; `tools/violet/run.ps1` runs with the private DLL search path. Developer logs and local toolchains are under ignored `build/`; game files and generated code are not repository artifacts.
