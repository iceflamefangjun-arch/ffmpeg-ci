SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 1
cd "${SCRIPT_DIR}" || exit 1
source "${SCRIPT_DIR}/../env_config.sh"

# Official FFmpeg nv-codec-headers release, pinned to the tag's commit.
VERSION="12.2.72.0"
COMMIT="c69278340ab1d5559c7d7bf0edf615dc33ddbba7"
CURRENTPATH="${SCRIPT_DIR}"
SRC_DIR="${DEPENDSPATH}/nv-codec-headers-${VERSION}"
PREFIX="${CURRENTPATH}/output"
ffnvcodec_pc_file="${PREFIX}/lib/pkgconfig/ffnvcodec.pc"

if [ ! -e "${SRC_DIR}" ]; then
    echo "Downloading nv-codec-headers ${VERSION}"
    git clone --depth=1 --branch "n${VERSION}" https://github.com/FFmpeg/nv-codec-headers.git "${SRC_DIR}" || exit
fi

src_commit="$(git -C "${SRC_DIR}" -c safe.directory="${SRC_DIR}" rev-parse HEAD)" || exit
if [ "${src_commit}" != "${COMMIT}" ]; then
    echo "nv-codec-headers commit mismatch: expected ${COMMIT}, got ${src_commit}" >&2
    exit 1
fi

rm -rf "${PREFIX}"
make -C "${SRC_DIR}" PREFIX="${PREFIX}" install || {
    echo "ffnvcodec install failed." >&2
    exit 1
}

if [ ! -f "${PREFIX}/include/ffnvcodec/nvEncodeAPI.h" ] || [ ! -f "${ffnvcodec_pc_file}" ]; then
    echo "ffnvcodec headers or pkg-config file missing after install." >&2
    exit 1
fi

# Make the .pc file relocatable so the same output works from WSL and MSYS2.
sed -i \
    -e 's|^prefix=.*|prefix=${pcfiledir}/../..|' \
    -e 's|^includedir=.*|includedir=${prefix}/include|' \
    "${ffnvcodec_pc_file}" || exit

echo "ffnvcodec headers ready: ${PREFIX}"
