#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 1
cd "${SCRIPT_DIR}" || exit 1
CURRENTPATH="${SCRIPT_DIR}"
TODAY=$(date +%y%m%d)
TARGET_ARCH=${1:-x64}
BUILD_TYPE=${2:-static}
USAGE="Usage: $0 [x86|x64] [debug|release|static] (defaults: x64 static)"

case "${TARGET_ARCH}" in
  x86|Win32|win32) TARGET_ARCH="x86" ;;
  x64|amd64|AMD64) TARGET_ARCH="x64" ;;
  arm64|aarch64|ARM64)
    echo "Live build does not support ARM64; use build-all.sh for the player build." >&2
    exit 1
    ;;
  *)
    echo "${USAGE}" >&2
    exit 1
    ;;
esac

case "${BUILD_TYPE}" in
  debug|release|static) ;;
  *)
    echo "${USAGE}" >&2
    exit 1
    ;;
esac

run_required_step() {
  local subdir="$1"
  local script_name="$2"

  if [ ! -d "${subdir}" ]; then
    echo "Required dependency directory missing: ${subdir}" >&2
    exit 1
  fi

  pushd "${subdir}" >/dev/null || {
    echo "Failed to enter dependency directory: ${subdir}" >&2
    exit 1
  }
  if [ ! -f "${script_name}" ]; then
    echo "Required dependency script missing: ${subdir}/${script_name}" >&2
    popd >/dev/null
    exit 1
  fi

  chmod +x "${script_name}" >/dev/null 2>&1 || true
  ./${script_name} "${BUILD_TYPE}" "${TARGET_ARCH}"
  if [ $? -ne 0 ]; then
    echo "Build failed at ${subdir}/${script_name}" >&2
    popd >/dev/null
    exit 1
  fi
  popd >/dev/null
}

run_optional_step_if_exists() {
  local subdir="$1"
  local preferred_script="$2"

  if [ ! -d "${subdir}" ]; then
    echo "Skip optional dependency ${subdir}: directory not found."
    return 0
  fi

  pushd "${subdir}" >/dev/null || {
    echo "Failed to enter optional dependency directory: ${subdir}" >&2
    exit 1
  }

  local script_to_run=
  if [ -f "${preferred_script}" ]; then
    script_to_run="${preferred_script}"
  elif [ -f "b.sh" ]; then
    script_to_run="b.sh"
  else
    echo "Skip optional dependency ${subdir}: no build script found."
    popd >/dev/null
    return 0
  fi

  chmod +x "${script_to_run}" >/dev/null 2>&1 || true
  ./${script_to_run} "${BUILD_TYPE}" "${TARGET_ARCH}"
  if [ $? -ne 0 ]; then
    echo "Optional dependency build failed: ${subdir}/${script_to_run}" >&2
    popd >/dev/null
    exit 1
  fi

  popd >/dev/null
}

run_required_step "json-c" "b-live.sh"
run_required_step "pthread-win32" "b-live.sh"
run_required_step "zlib" "b-live.sh"

run_required_step "x264" "b-live.sh"
run_required_step "fdk-aac" "b-live.sh"
run_required_step "libmfx" "b-live.sh"
run_required_step "ffnvcodec" "b-live.sh"

if [ ! -d "ffmpeg" ]; then
  echo "Required dependency directory missing: ffmpeg" >&2
  exit 1
fi
pushd ffmpeg >/dev/null || { echo "Failed to enter dependency directory: ffmpeg" >&2; exit 1; }
chmod +x b-live.sh >/dev/null 2>&1 || true
./b-live.sh "${BUILD_TYPE}" "${TARGET_ARCH}"
if [ $? -ne 0 ]; then
  echo "Build failed at ffmpeg/b-live.sh" >&2
  popd >/dev/null
  exit 1
fi
popd >/dev/null

if [ -d "ffmpeg/output/live/${BUILD_TYPE}/${TARGET_ARCH}" ]; then
  pushd ffmpeg/output/live >/dev/null || { echo "Failed to enter ffmpeg/output/live for packaging." >&2; exit 1; }
  zip -r "${CURRENTPATH}/ffmpeg-live-7.1.1-${TARGET_ARCH}-${BUILD_TYPE}-${TODAY}.zip" "${BUILD_TYPE}/${TARGET_ARCH}" >/dev/null
  if [ $? -ne 0 ]; then
    echo "Zip packaging failed." >&2
    popd >/dev/null
    exit 1
  fi
  popd >/dev/null
fi

echo "Live toolchain build completed: ${TARGET_ARCH} ${BUILD_TYPE}"
