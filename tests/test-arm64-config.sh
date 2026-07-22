#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

assert_contains() {
    local file="$1"
    local pattern="$2"

    if ! grep -Eq "${pattern}" "${ROOT_DIR}/${file}"; then
        echo "Missing ARM64 configuration in ${file}: ${pattern}" >&2
        exit 1
    fi
}

assert_contains env_config.sh "archs=\('arm64'\)"
assert_contains env_config.sh "targets=\('aarch64-w64-mingw32'\)"
assert_contains env_config.sh "CMAKE_SYSTEM_PROCESSOR=ARM64"
assert_contains env_config.sh 'LLVM_RC_TOOL'
assert_contains env_config.sh 'llvm-rc'
assert_contains env_config.sh 'LLVM_WINDRES_TOOL'
assert_contains env_config.sh 'llvm-windres'
assert_contains env_config.sh 'generate_llvm_rc_windres_wrapper'
assert_contains env_config.sh 'llvm-rc-windres'
assert_contains env_config.sh 'target=aarch64-pc-windows-msvc'
assert_contains ffmpeg/b.sh 'ffmpeg_windres_tool="\$\(windres_for_arch "\$\{archs\[i\]\}"\)" \|\| exit 1'

# Verify the generated llvm-rc adapter preserves FFmpeg's relevant windres
# arguments without needing an LLVM installation or a full cross-build.
eval "$(sed -n '/^generate_llvm_rc_windres_wrapper()/,/^export_msvc_environment()/p' "${ROOT_DIR}/env_config.sh" | sed '$d')"
wrapper_test_dir="$(mktemp -d)"
cleanup_wrapper_test() {
    rm -rf "${wrapper_test_dir}"
}
trap cleanup_wrapper_test EXIT

DEPENDSPATH="${wrapper_test_dir}"
wrapper_path="$(generate_llvm_rc_windres_wrapper)"
wrapped_args="$(LLVM_RC_TOOL=/bin/echo "${wrapper_path}" -I include -DTEST=1 --preprocessor-arg -MMD -o output.o input.rc)"
case "${wrapped_args}" in
  '-nologo -I include -DTEST=1 /fo output.o input.rc'|\
  -nologo\ -I\ */include\ -DTEST=1\ /fo\ */output.o\ */input.rc)
      ;;
  *)
      echo "llvm-rc windres adapter passed unexpected arguments: ${wrapped_args}" >&2
      exit 1
      ;;
esac

for file in \
    json-c/b.sh \
    pthread-win32/b.sh \
    libudfread/b.sh \
    libdvdread/b.sh \
    libdvdnav/b.sh \
    libbluray/b.sh \
    zlib/b.sh \
    libxml2/b.sh \
    libsmb2/b.sh \
    ffmpeg/b.sh; do
    assert_contains "${file}" "arm64\)"
    assert_contains "${file}" "aarch64-pc-windows-msvc"
done

assert_contains ffmpeg/b.sh 'ffmpeg_arch="aarch64"'
assert_contains ffmpeg/b.sh 'beenet_arch="aarch64"'
assert_contains ffmpeg/b.sh 'ASFLAGS="\$\{CFLAGS\}"'
assert_contains ffmpeg/b.sh 'ffmpeg_as_args=\(--as="\$\{CC\}"\)'
assert_contains pthread-win32/b.sh 'set\(TARGET_ARCH "ARM64"\)'
assert_contains libdvdread/include/stdint.h 'defined\(__clang__\) && defined\(_M_ARM64\)'
assert_contains libdvdread/include/stdint.h '#include_next <stdint.h>'
assert_contains zlib/b.sh "ADLER32_SIMD_NEON"

standard_shadow_headers="$({
    git -C "${ROOT_DIR}" ls-files |
        grep -E '(^|/)include/(stdint|inttypes|wchar|limits|stddef)\.h$' || true
} | sort)"
if [ "${standard_shadow_headers}" != "libdvdread/include/stdint.h" ]; then
    echo "Unexpected standard headers may shadow clang-cl/Windows SDK headers:" >&2
    printf '%s\n' "${standard_shadow_headers}" >&2
    exit 1
fi

for script in \
    env_config.sh \
    build-all.sh \
    build-all-live.sh \
    json-c/b.sh \
    pthread-win32/b.sh \
    libudfread/b.sh \
    libdvdread/b.sh \
    libdvdnav/b.sh \
    libbluray/b.sh \
    zlib/b.sh \
    libxml2/b.sh \
    libsmb2/b.sh \
    ffmpeg/b.sh; do
    bash -n "${ROOT_DIR}/${script}"
done

echo "ARM64 build configuration checks passed."
