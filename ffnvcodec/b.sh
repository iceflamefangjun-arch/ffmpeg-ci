SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 1
cd "${SCRIPT_DIR}" || exit 1
source "${SCRIPT_DIR}/../env_config.sh"

VERSION="12.2.72.0"
CURRENTPATH="${SCRIPT_DIR}"
ffnvcodec_pc_file="${CURRENTPATH}/nv-codec-headers/lib/pkgconfig/ffnvcodec.pc"

if [ ! -e "${DEPENDSPATH}/nv-codec-headers" ]; then
    echo "Downloading nv-codec-headers"
    pushd "${DEPENDSPATH}" || exit
    git clone --depth=1 --branch "n${VERSION}" https://github.com/FFmpeg/nv-codec-headers.git nv-codec-headers || exit
    popd || exit
else
    echo "Update nv-codec-headers"
    pushd "${DEPENDSPATH}/nv-codec-headers" || exit
    git checkout n${VERSION} || exit
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

if [ ! -f "${ffnvcodec_pc_file}" ]; then
    echo "ffnvcodec pkg-config file missing after install." >&2
    exit 1
fi

tmp_pc_file="$(mktemp)" || exit 1
sed \
    -e 's|^prefix=.*|prefix=${pcfiledir}/../..|' \
    -e 's|^includedir=.*|includedir=${prefix}/include|' \
    "${ffnvcodec_pc_file}" > "${tmp_pc_file}" || {
        rm -f "${tmp_pc_file}"
        exit 1
    }
cat "${tmp_pc_file}" > "${ffnvcodec_pc_file}" || {
    rm -f "${tmp_pc_file}"
    exit 1
}
rm -f "${tmp_pc_file}"

echo "ffnvcodec headers ready: ${CURRENTPATH}/nv-codec-headers"
