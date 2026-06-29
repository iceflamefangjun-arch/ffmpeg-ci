SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 1
cd "${SCRIPT_DIR}" || exit 1
source "${SCRIPT_DIR}/../env_config.sh"

VERSION="12.0"
CURRENTPATH="${SCRIPT_DIR}"

if [ ! -e "${DEPENDSPATH}/nv-codec-headers" ]; then
    echo "Downloading nv-codec-headers"
    pushd "${DEPENDSPATH}" || exit
    git clone https://git.videolan.org/git/ffmpeg/nv-codec-headers.git || exit
    pushd nv-codec-headers || exit
    git checkout sdk/${VERSION} || exit
    popd || exit
    popd || exit
else
    echo "Update nv-codec-headers"
    pushd "${DEPENDSPATH}/nv-codec-headers" || exit
    git checkout sdk/${VERSION} || exit
    #git pull
    popd || exit
fi

rm -rf "${CURRENTPATH}/nv-codec-headers"
mkdir -p "${CURRENTPATH}/nv-codec-headers"

pushd "${DEPENDSPATH}/nv-codec-headers" || exit
make PREFIX="${CURRENTPATH}/nv-codec-headers" install
if [ $? -ne 0 ]; then
    echo "ffnvcodec install failed." >&2
    popd || true
    exit 1
fi
popd || exit

if [ ! -f "${CURRENTPATH}/nv-codec-headers/include/ffnvcodec/nvEncodeAPI.h" ]; then
    echo "ffnvcodec header missing after install." >&2
    exit 1
fi

if [ ! -f "${CURRENTPATH}/nv-codec-headers/lib/pkgconfig/ffnvcodec.pc" ]; then
    echo "ffnvcodec pkg-config file missing after install." >&2
    exit 1
fi

echo "ffnvcodec headers ready: ${CURRENTPATH}/nv-codec-headers"
