#!/usr/bin/env bash
# Bundle host runtime and setup tools. Never bundle game dumps, keys, saves or generated game code.
set -euo pipefail
cd "$(dirname "$0")/../.."
tag="$1"
name="PokeVioletRecomp-$tag-Windows-x64"
stage="build/dist/violet"
out="build/dist/$name.zip"
package="$stage/Violet Recomp"

for file in build/win-release/lasrecomp.exe build/win-release/lasrecomp.dll.a \
            build/helper/lasgen/lasgen.exe build/zig-slim/zig.exe build/zaimport/zaimport.exe; do
    [[ -f "$file" ]] || { echo "Missing required release component: $file" >&2; exit 1; }
done

rm -rf "$stage"
mkdir -p "$package/gamelib-src"
cp build/win-release/lasrecomp.exe build/win-release/lasrecomp.dll.a "$package/"
cp -R build/helper/lasgen "$package/lasgen"
cp -R build/zig-slim "$package/zig"
mkdir -p "$package/zaimport"
cp build/zaimport/zaimport.exe "$package/zaimport/"
cp runtime/cpu.h runtime/simd.h runtime/simd_fp.h runtime/gamelib.h runtime/game_target.h \
   tools/gamelib_entry.c runtime/hle/hle_symbols.txt "$package/gamelib-src/"
cp README.md LICENSE docs/WINDOWS-RELEASE.md "$package/"
cp docs/icon/icon_1024.png "$package/icon.png"
cp third_party/fonts/Baloo2/Baloo2-SemiBold.ttf "$package/"
cp third_party/fonts/Baloo2/OFL.txt "$package/Baloo2-OFL.txt"
cp third_party/fonts/DejaVu/DejaVuSans.ttf third_party/fonts/DejaVu/DejaVuSans-Bold.ttf "$package/"
cp third_party/fonts/DejaVu/LICENSE "$package/DejaVu-LICENSE.txt"
if [[ -f build/deps-win/src/ffmpeg/COPYING.LGPLv2.1 ]]; then
    cp build/deps-win/src/ffmpeg/COPYING.LGPLv2.1 "$package/FFmpeg-LGPL-2.1.txt"
fi

gcc -O2 -municode -mwindows tools/violet/windows_entry.c -o "$package/PokeVioletRecomp.exe" -luser32

export PATH="$PWD/build/deps-win/bin:/ucrt64/bin:$PATH"
ldd build/win-release/lasrecomp.exe > build/dist/violet-deps.txt
if grep -q "not found" build/dist/violet-deps.txt; then
    cat build/dist/violet-deps.txt
    echo 'Unresolved native dependency; refusing to publish incomplete build.' >&2
    exit 1
fi
while IFS= read -r lib; do
    [[ -f "$lib" ]] || continue
    cp -u "$lib" "$package/"
done < <(awk '(/\/ucrt64\// || /\/deps-win\//) && $3 ~ /^\// {print $3}' build/dist/violet-deps.txt | sort -u)

for relative in PokeVioletRecomp.exe lasrecomp.exe lasrecomp.dll.a zaimport/zaimport.exe \
                lasgen/lasgen.exe zig/zig.exe gamelib-src/cpu.h; do
    [[ -s "$package/$relative" ]] || { echo "Missing or empty $relative" >&2; exit 1; }
done
if find "$package" -type f \( -iname '*.keys' -o -iname '*.nsp' -o -iname '*.xci' \
    -o -iname 'lasgame.dll' -o -iname 'romfs.bin' \) | grep -q .; then
    echo "Proprietary/generated game contents detected; refusing publication." >&2
    exit 1
fi

(
    cd "$stage"
    zip -q -r "../$name.zip" "Violet Recomp"
)
unzip -t "$out" | tail -1
sha256sum "$out"
echo "Packaged: $out"
