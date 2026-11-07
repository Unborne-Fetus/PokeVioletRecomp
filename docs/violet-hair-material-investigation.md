# Violet rainbow-hair rendering investigation (2026-11-07)

**State: renderer source fix committed; hair not yet visually validated.** Preserve the confirmed missing-geometry recovery in `tools/violet/run.ps1`: for Violet the old `LARECOMP_SKIP_BAD_LAYOUT` guard defaults to 0, allowing the shader's safe constant-attribute fallback. Do not re-enable it while testing hair.

## Observations

- The user's player hair renders with vivid green, purple, and other irregular color patches; their outfit is also visibly noisy. The larger floor/wall striping is a separate issue, explicitly on hold.
- The prior full-quad override `LARECOMP_SHADER_QUAD_CONTROL=1` really activated on the user's GPU. Local launch log `20261107-040835-3919498-stderr.log` prints `quad swaps in full quads, quads kept together (quad control)`, yet a new screenshot still shows rainbow hair. This global override was removed from the Violet launcher; the GPU's normal compatibility logic remains.
- Prior graphics F9 capture was focused on the floor. Its report had hard-coded probe coordinates 400,780 even if the user requested another location. Updated local tools now persist the actual numeric target and rank shader draws by 64x64 pixel changes, hue entropy, and sampled NVN formats (not proprietary images).
- A new one-command hair-specific capture: `powershell -NoProfile -ExecutionPolicy Bypass -File .\\tools\\violet\\graphics_hair_probe_launch.ps1`. Default probe target 470,430 in normalized window coordinates, adjustable `-X` and `-Y`. Place hair there, press F9 once, close the game. No ZIP is made or needs to be shared. Local summary: `build/violet-graphics-diagnostics/latest-summary.json`. Per-draw images stay private.

## Concrete NVN color texture defect, fixed in pokemon-za

The renderer previously shifted the Nintendo NVN BGR/BGRA format IDs by one:

| NVN ID | SDK format | Correct size |
|---|---|---|
| 0x95 | BGR565 | 2 bytes |
| 0x96 | BGR5 | 2 bytes |
| 0x97 | BGR5A1 | 2 bytes |
| 0x98 | A1BGR5 | 2 bytes |
| 0x99 | BGRX8 | 4 bytes |
| 0x9A | BGRA8 | 4 bytes |
| 0x9B | BGRX8_SRGB | 4 bytes |
| 0x9C | BGRA8_SRGB | 4 bytes |

The original `runtime/nvn/formats.c` treated NVN 0x98 as four bytes (when it is two), and did not list 0x9C. `runtime/nvn/vulkan/textures.c` assigned 0x98 to BGRX8, 0x99 to BGRA8 and so on; 0x9C used a default RGBA interpretation, which reverses channels for BGRA data. Both tables are now aligned for 0x98 through 0x9C. The exact channel packing of 16-bit formats 0x95-0x97 may warrant separate validation; those were not broadened without tests.

Tests: `tests/test_violet_bgra_formats.c` checks exact bytes/block for 0x95-0x9C, and `tests/test_violet_bgra_wiring.py` asserts Vulkan mappings / alpha-one for BGRX. Graphics CI: `.github/workflows/violet-capture-correctness.yml`.

**Uncertainty:** This is an objectively incorrect texture-format mapping, but no captured hair draw yet proves it samples 0x98-0x9C. If the hair samples only BC7 (NVN 0x4D/0x4E), its rainbow color needs another cause; rely on the hair-specific draw/texture-format evidence, not an additional global shader override. No local native Windows runtime was launched from this chat.
