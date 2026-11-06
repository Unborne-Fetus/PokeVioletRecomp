#!/usr/bin/env bash
# Regression test: compiler flags with spaces must survive PowerShell->Bash make invocation.
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

cat > "$test_dir/mock_make.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$MOCK_ARG_LOG"
EOF
chmod +x "$test_dir/mock_make.sh"
export VIOLET_MAKE_BIN="$test_dir/mock_make.sh"
export MOCK_ARG_LOG="$test_dir/actual"

cat > "$test_dir/expected" <<'EOF'
--no-print-directory
-j4
B=build/violet-gnu
DEPS=build/msys-deps/ucrt64
CC=build/zig/zig.exe cc -target x86_64-windows-gnu
CXX=build/zig/zig.exe c++ -target x86_64-windows-gnu
GENARCH=-mcpu=x86_64_v3
GENOPT=-O1 -DGUEST_VOLATILE
WINDRES=/c/msys64/ucrt64/bin/windres.exe
runtime-objs
EOF
bash tools/violet/make_local.sh 4 objects
diff -u "$test_dir/expected" "$MOCK_ARG_LOG"

sed -i '$d' "$test_dir/expected"
cat >> "$test_dir/expected" <<'EOF'
-f
Makefile
-f
build/violet-gnu/toolchain.mk
-f
build/violet-gnu/giants.mk
build/violet-gnu/lasrecomp.exe
EOF
bash tools/violet/make_local.sh 4 link build/violet-gnu/lasrecomp.exe
diff -u "$test_dir/expected" "$MOCK_ARG_LOG"

echo "All Violet make arguments preserved correctly"
