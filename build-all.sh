#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 1
cd "${SCRIPT_DIR}" || exit 1
CURRENTPATH="${SCRIPT_DIR}"
TODAY=$(date +%y%m%d)
TARGET_ARCH=${1:-all}
BUILD_TYPE=${2:-static}
USAGE="Usage: $0 [x86|x64|all] [debug|release|static] (defaults: all static)"

case "${TARGET_ARCH}" in
  x86|Win32|win32|x64|amd64|AMD64|all|both) ;;
  *) echo "${USAGE}" >&2; exit 1 ;;
esac

case "${BUILD_TYPE}" in
  debug|release|static) ;;
  *) echo "${USAGE}" >&2; exit 1 ;;
esac

#for subdir in amf ffnvcodec; do pushd ${subdir} && sh b.sh && popd || exit; done

#for subdir in json-c pthread-win32 libudfread libdvdread libbluray x264 x265 libvpx fdk-aac opus libmp3lame freetype2 libmfx zlib ffmpeg; do
for subdir in json-c pthread-win32 libudfread libdvdread libdvdnav libbluray zlib libxml2 libsmb2 ffmpeg; do
#for subdir in ffmpeg; do
  if [ ! -d "${subdir}" ]; then
    echo "Required dependency directory missing: ${subdir}" >&2
    exit 1
  fi
  pushd "${subdir}" >/dev/null || { echo "Failed to enter dependency directory: ${subdir}" >&2; exit 1; }
  ./b.sh "${BUILD_TYPE}" "${TARGET_ARCH}"
  if [ $? -ne 0 ]; then
    echo "Build failed at ${subdir}/b.sh" >&2
    popd >/dev/null
    exit 1
  fi
  popd >/dev/null
done

if [ ! -d "ffmpeg/output" ]; then
  echo "Packaging skipped: ffmpeg/output not found." >&2
  exit 1
fi
pushd ffmpeg/output >/dev/null || { echo "Failed to enter ffmpeg/output for packaging." >&2; exit 1; }
zip -r "${CURRENTPATH}/ffmpeg-7.1.1-${TARGET_ARCH}-${BUILD_TYPE}-${TODAY}.zip" * || {
  echo "Zip packaging failed." >&2
  popd >/dev/null
  exit 1
}
popd >/dev/null
