# Violet — diagonal-striping graphics investigation (2026-11-06)

**State:** unresolved. Keep the successfully booting/playing `pokemon-za` build intact. None of the tested graphics overrides fixed the visible stripes.

## Evidence from the user's F9 capture

Local report: `violet-graphics-report-20261106-142020.zip` (109 contact-sheet entries for renderer frame **4979**; contains thumbnails, a pass index, and filtered draw-state log; **not** published to GitHub).

- The first clearly recognizable room image is **`pass_4979_032.png`**, output at **1920×1080**, NVN format **0x3f**. The striped walls/staircase/floor and player character are already visible here. Therefore post-processing or window presentation alone cannot be the original source.
- The room continues to appear in passes **062, 068–087, 091–097**. Downsample/blurring in later passes changes the sharpness but does not create the original lines.
- Initial passes **000–031** are mostly black/offscreen/depth/non-room captures. Their blackness is not evidence that they generated the stripes.
- The standalone dialogue UI in earlier user screenshots remains clean, so focus on scene geometry/material/texture/shader work rather than the final desktop blit or the general SDL window.
- The output log includes a **vertex-state mismatch** for VS address `0x7442117000`: shader attribute mask `0x21`, only one attribute bound (mask `0x1`), stride 12, followed by at least 20 skipped draws. The native guard in `runtime/nvn/vulkan/exec.c` intentionally skips these invalid layouts. This **may cause missing/stretched geometry**; it is *not yet established* as the source of the stripe artifact.
- The filtered log's end reports a **Vulkan device fault**. It places an address **448 KiB beyond** an 8,640 KiB bound image/memory range ending `0x1ce70000` and **1,152 KiB before** the next range starting at `0x1d000000`. The filtered report does not include the actual failing shader/draw or full fault address. Do not assume this is the striping cause. It may be correlated with F9 capture; compare to ordinary launches.
- Several scene draw records sample BC7 textures (`0x4d` unorm, `0x4e` sRGB), and material shader paths handle compressed and uncompressed resources. The capture does **not** include original sampled texture pixel dumps, so there is no proof that their swizzle/decode is defective.

## User-tested graphics experiments that did NOT clear the stripes

- `PackagedZero` (explicit zero block-height)
- `ConservativeUploads` (disable async unpack / force full hashing)
- `ShadowCompareOff` (bypass shadow-depth comparisons)
- `ShaderQuadDerivatives` (hardware fragment derivatives)
- `DepthEqualTolerance` (relax EQUAL pre-pass comparison)

**Do not claim any of these repaired the issue or repeat them without new evidence.** A `NoDepthTest` mode exists but was not reported as tested. The separate `BC5Unsigned` and `ShaderQuadControl` modes also have not been verified.

## Source findings

- `runtime/nvn/maxwell/translate.c` already emits **`invariant gl_Position; precise gl_Position;`** for Vulkan vertex stages. No basis to add that again.
- `runtime/nvn/tegra.c` implements GOB block-linear addressing; an included BNTX-editor reference in `third_party/LAS-Randomizer/RandomizerCore/Tools/bntx_editor/swizzle.py` provides independent address computations. No proven general swizzle discrepancy for the power-of-two BC7 textures used in the scene.
- `runtime/nvn/vulkan/exec.c` already contains F9 pass dumps, a screen-point probe (`LARECOMP_PROBE`), an optional full per-draw capture (`LARECOMP_FULLCAP=1`), and shader GLSL dump options (`LARECOMP_DUMP_GLSL`, `LARECOMP_SAVE_MSL`). Prefer these existing targeted tools over new global rendering overrides.

## Next engineering investigation

1. Use the **initial full-resolution scene pass** (first recognizable image around pass 032) to isolate the *first draw* that introduces a stripe on an otherwise flat wall. The existing F9 probe / full per-draw capture is more decisive than a whole-scene A/B toggle.
2. Inspect that draw's **vertex format/bindings, depth/stencil mode, shader ID, fragment interpolation, sampled texture formats, and uniform buffer ranges**. Verify any suspected invalid binding with a small reproducible regression before patching.
3. Dump **one sampled BC7 texture** from an affected material. If its own PNG already contains black slashes, debug upload/de-swizzle/format. If the source texture is intact, investigate interpolation/material shader and overdraw instead.
4. Investigate the **GPU device-address fault** separately using the full stderr log and whether it also happens without F9. A GPU fault during capture should not silently become evidence of the cause of normal-frame visual corruption.
5. Keep debug effects **opt-in**, avoid broad changes to the playable baseline, and test native boot after any actual fix. **Do not upload proprietary game assets to the public repo.**

## Scope of confidence

Verified: first visible full-scene pass already striped; multiple tested overrides ineffective; reported vertex mismatch and device fault exist.

Unverified: precise offending 3D draw, whether source compressed textures already contain artifacts, role of skipped vertex layouts, and whether the GPU fault contributes to stripe rendering.


## Subsequent source fixes (awaiting on-device visual validation)

- **Commit `a197e1a`**: Vulkan `texture_info()` now resolves a texture's current depth/stencil copy alias **before** hitting the per-frame sampled-view memo. This prevents reuse of an old image view after aliases change within a frame. This is a renderer correctness fix; it is **not proven** to cause the stripes.
- **Commit `403d8f8`**: The Maxwell Vulkan fragment translator now consumes SPH `ImapPixelVector` at offset `0x18`, encoding 0 = unused, 1 = constant (flat), 2 = perspective, 3 = screen-linear (noperspective). Previously the code incorrectly derived `flat` from the IPA opcode, never set `noperspective`, and multiplied every IPA PASS input by fragment position W even when the source interpolation was non-perspective. The patch restores type-dependent behavior, leaves the MSL path unchanged, and changes the translation cache version to invalidate old GLSL. The interpolation metadata layout was cross-checked against NVIDIA's public Shader Program Header specification.
- Linux CI for the full Maxwell source syntax, pure-C SPH mode tests, and source wiring/cache checks passed in run `42312935121`.
- **Outstanding:** The corrected native Windows binary has not been launched or visually inspected. This is a plausible source-level graphics fix, **not** confirmation the scene striping has disappeared. Avoid making users provide repeated screenshots; test with existing imagery/logs first.



## 2026-11-06 follow-up: persisted striping after shader rebuild

- User confirmed the latest native-rebuild attempt still shows stripes. The PixelImap correction and shader-cache rebuild are not sufficient.
- Reopened the private local F9 capture using the connected Autopilot Python test task (without uploading game assets): 2,086 `[draw]` records, 103 `[pass]` records and 152 `[vtxstate]` lines. The initial full-scene `pass_4979_032.png` is the first relevant 1920x1080 color scene, following the preceding black/offscreen passes. It is already corrupted.
- The intermediate pass dump's metadata immediately following that pass references scene VS `76e62e9c00`, FS `76e6353600` with NVN BC7 material samplers. The capture contains many subsequent draws; this is NOT proof that those two shader addresses create the stripe. Use the F9 per-draw screen-point probe to identify a culprit rather than guessing from adjacent log records.
- Most ordinary launch logs only contain a startup message `GPU address binding report: on (a device fault names ...)`. That message **is not a device fault**. The actual `[vk] device fault` and device loss in the sampled 23 local logs came from `20261106-221717-1125923-stderr.log`, the extended F9 capture. Do not misattribute that to normal gameplay.
- Added a pure-C `tests/test_violet_tegra_reference.c` comparing the active GOB importer to the independent BNTX offset formula across 7,500 cases (odd widths/heights, partial GOBs, 1–16 bytes per block, varying block height). The test passes in CI. This rules out the tested generic GOB byte-placement error, **not** incorrect source texture descriptor metadata or uploads.
- The graphics problem remains **unresolved**. Next actionable discriminator: run `tools/violet/graphics_probe_launch.ps1` in the striped scene, press F9 once, and use `draw-origin.log` alongside consecutively changed crops to isolate the first material draw adding the stripes. The diagnostic should stay local/private.
