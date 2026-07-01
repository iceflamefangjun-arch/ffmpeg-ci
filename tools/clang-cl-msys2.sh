#!/usr/bin/env bash
# Wrap clang-cl on MSYS2 so Unix-style absolute paths embedded in compiler
# arguments are converted to Windows paths that the native clang-cl binary can
# open. FFmpeg's configure script generates MSVC-style flags like
# -Fo/d/a/_temp/.../test.o; MSYS2_ARG_CONV_EXCL keeps those flags intact but
# leaves the attached path as a Unix path, which clang-cl cannot resolve.
set -euo pipefail

real_clang_cl="${REAL_CLANG_CL_TOOL:-${CLANG_CL_TOOL:-clang-cl}}"
args=()

for arg in "$@"; do
    converted="${arg}"

    # Whole argument is a Unix absolute path like /d/a/...
    if [[ "${arg}" =~ ^/[a-zA-Z]/.*$ ]]; then
        converted="$(cygpath -w "${arg}")"
    # Option with an attached path using a colon, e.g. /LIBPATH:/d/a/...
    elif [[ "${arg}" =~ ^([-/][A-Za-z]+:)(/[a-zA-Z]/.*)$ ]]; then
        opt="${BASH_REMATCH[1]}"
        path="${BASH_REMATCH[2]}"
        converted="${opt}$(cygpath -w "${path}")"
    # Option with an attached path, e.g. -Fo/d/a/... or /I/d/a/...
    elif [[ "${arg}" =~ ^([-/][A-Za-z]+)(/[a-zA-Z]/.*)$ ]]; then
        opt="${BASH_REMATCH[1]}"
        path="${BASH_REMATCH[2]}"
        converted="${opt}$(cygpath -w "${path}")"
    fi

    args+=("${converted}")
done

exec "${real_clang_cl}" "${args[@]}"
