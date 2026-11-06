#!/usr/bin/env bash
# Invoke MSYS2 GNU Make directly so argument strings containing spaces remain single argv items.
# PowerShell -> bash -c 'make "$@"' loses the quotes around CC/CXX/GENOPT on some Windows versions,
# causing make to treat '-target' and '-DGUEST_VOLATILE' as command-line options.
set -euo pipefail

if (($# < 2 || $# > 3)); then
    echo "Usage: make_local.sh JOBS objects | JOBS link TARGET" >&2
    exit 2
fi
jobs=$1
stage=$2
if [[ ! $jobs =~ ^[0-9]+$ ]] || ((jobs < 1 || jobs > 32)); then
    echo "Invalid job count: $jobs (expected 1..32)" >&2
    exit 2
fi

# Force the make binary belonging to the same MSYS2 installation as bash.
make_bin=${VIOLET_MAKE_BIN:-/usr/bin/make.exe}
if [[ ! -x $make_bin ]]; then
    echo "Make is missing or not executable: $make_bin" >&2
    exit 2
fi

common=(
    --no-print-directory
    "-j$jobs"
    "B=build/violet-gnu"
    "DEPS=build/msys-deps/ucrt64"
    "CC=build/zig/zig.exe cc -target x86_64-windows-gnu"
    "CXX=build/zig/zig.exe c++ -target x86_64-windows-gnu"
    "GENARCH=-mcpu=x86_64_v3"
    "GENOPT=-O1 -DGUEST_VOLATILE"
    "WINDRES=/c/msys64/ucrt64/bin/windres.exe"
)

case $stage in
    objects)
        if (($# != 2)); then exit 2; fi
        exec "$make_bin" "${common[@]}" runtime-objs
        ;;
    link)
        if (($# != 3)); then exit 2; fi
        case $3 in
            build/violet-gnu/lasrecomp.exe|build/violet-gnu/lasgame.dll) ;;
            *) echo "Unsupported target: $3" >&2; exit 2 ;;
        esac
        exec "$make_bin" "${common[@]}" -f Makefile \
            -f build/violet-gnu/toolchain.mk -f build/violet-gnu/giants.mk "$3"
        ;;
    *)
        echo "Unsupported build stage: $stage" >&2
        exit 2
        ;;
esac
