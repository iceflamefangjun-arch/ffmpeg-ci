#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 1
cd "${SCRIPT_DIR}" || exit 1
CURRENTPATH="${SCRIPT_DIR}"
BUILD_TYPE=${1:-static}
TARGET_ARCH=${2:-x64}

case "${TARGET_ARCH}" in
  x86|Win32|win32) TARGET_ARCH="x86" ;;
  x64|amd64|AMD64) TARGET_ARCH="x64" ;;
  *)
    echo "zlib live build only supports x86 or x64, got: ${TARGET_ARCH}" >&2
    exit 1
    ;;
esac

./b.sh "${BUILD_TYPE}" "${TARGET_ARCH}"
if [ $? -ne 0 ]; then
  echo "zlib base build failed." >&2
  exit 1
fi

SRC_OUTPUT="${CURRENTPATH}/output/${BUILD_TYPE}/${TARGET_ARCH}"
DST_OUTPUT="${CURRENTPATH}/output/live/${BUILD_TYPE}/${TARGET_ARCH}"

if [ ! -f "${SRC_OUTPUT}/lib/zlib.lib" ]; then
  echo "zlib output missing: ${SRC_OUTPUT}/lib/zlib.lib" >&2
  exit 1
fi

rm -rf "${DST_OUTPUT}"
mkdir -p "${DST_OUTPUT}"
cp -rd "${SRC_OUTPUT}/." "${DST_OUTPUT}/"
if [ $? -ne 0 ]; then
  echo "zlib live output copy failed." >&2
  exit 1
fi

ls -l "${DST_OUTPUT}/lib/zlib.lib"
