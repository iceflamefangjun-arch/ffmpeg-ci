SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 1
cd "${SCRIPT_DIR}" || exit 1
source "${SCRIPT_DIR}/../env_config.sh"

CURRENTPATH="${SCRIPT_DIR}"
X264_REPO_URL="${X264_REPO_URL:-git@code2.sohuno.com:ifox-public/x264.git}"

set_target_archs "${2:-x64}"

OPTIMIZE="-fmerge-all-constants /Zc:sizedDealloc- /Zc:twoPhase /bigobj /utf-8"

if [ $# -lt 1 ]; then echo "Usage: $0 [debug|release|static] [x64]" >&2; exit; fi
case $1 in
  debug)
      BUILD="debug"
      OPTIMIZE="/Od /MDd /D_DEBUG ${OPTIMIZE}"
      x264_extra_args="disable-asm --enable-debug"
      ;;
  release)
      BUILD="release"
      OPTIMIZE="/O2 /MD /DNDEBUG ${OPTIMIZE} /GF /Gy /Gw -flto=thin -fsplit-lto-unit"
      x264_extra_args="enable-pic"
      ;;
  static)
      BUILD="static"
      OPTIMIZE="/O2 /MT /DNDEBUG ${OPTIMIZE} /GF /Gy /Gw -flto=thin -fsplit-lto-unit"
      x264_extra_args="enable-pic"
      ;;
  *)
      echo "Only support [debug|release|static]" >&2; exit
      ;;
esac

if [ ! -e "${DEPENDSPATH}/x264" ]; then
    echo "Downloading x264"
    pushd "${DEPENDSPATH}" || exit
    git clone "${X264_REPO_URL}" x264 || exit
    popd || exit
else
    echo "Update x264"
    pushd "${DEPENDSPATH}/x264" || exit
    #git pull
    popd || exit
fi

for ((i=0; i<${#archs[@]}; i++))
do
    OUTPUT="output/${BUILD}/${archs[i]}"
    rm -fr "${CURRENTPATH}/${OUTPUT}"

    WSLBUILD="${DEPENDSPATH}/x264-build/${BUILD}/${archs[i]}"
    rm -rf "${WSLBUILD}"
    mkdir -p "${WSLBUILD}"

    WSLSRC="${DEPENDSPATH}/x264-src/${BUILD}/${archs[i]}"
    rm -rf "${WSLSRC}"
    mkdir -p "$(dirname "${WSLSRC}")" || exit
    cp -r "${DEPENDSPATH}/x264" "${WSLSRC}" || exit
    patch --batch -N -d "${WSLSRC}" -p1 <"${CURRENTPATH}/configure.patch" || exit

    pushd "${WSLSRC}" || exit

    export ARCH=${archs[i]}
    export PATH="${TOOLCHAIN}/bin:${PATH}"

    export AR="${TOOLCHAIN}/bin/llvm-ar"
    export NM="${TOOLCHAIN}/bin/llvm-nm"
    export MT="${TOOLCHAIN}/bin/llvm-mt"
    export CC="${TOOLCHAIN}/bin/clang-cl"
    export CXX="${TOOLCHAIN}/bin/clang-cl"
    export LD="${TOOLCHAIN}/bin/lld-link"
    export RANLIB="${TOOLCHAIN}/bin/llvm-ranlib"
    export STRIP="${TOOLCHAIN}/bin/llvm-strip"

    export INCLUDE="${WINSDKINC}/winrt;${WINSDKINC}/ucrt;${WINSDKINC}/um;${WINSDKINC}/shared;${VCINC}"
    export LIB="${VCLIB}/${archs[i]};${WINSDKLIB}/um/${archs[i]};${WINSDKLIB}/ucrt/${archs[i]}"

    case ${ARCH} in
      x86)
          msvc_arch_cflags="--target=i686-pc-windows-msvc -m32 -msse3"
          ;;
      x64)
          msvc_arch_cflags="--target=x86_64-pc-windows-msvc -m64 -msse3"
          ;;
      *)
          msvc_arch_cflags=
          ;;
    esac

    export CFLAGS="${OPTIMIZE} ${msvc_arch_cflags} -fuse-ld=lld -fms-compatibility"
    export CXXFLAGS="${CFLAGS} ${CXX_OPTIMIZE} /EHsc -std:c++11"

    WSLPREFIX="${CURRENTPATH}/${OUTPUT}"
    rm -rf "${WSLPREFIX}" && mkdir -p "${WSLPREFIX}"

    ./configure --prefix="${WSLPREFIX}" \
                --host=${targets[i]} \
                --enable-static \
                --${x264_extra_args} \
                --disable-cli \
                --disable-opencl || exit

    make V=1 -j $(nproc) && make install && make clean || exit

    if [ -f "${WSLPREFIX}/lib/libx264.a" ]; then
        mv -f "${WSLPREFIX}/lib/libx264.a" "${WSLPREFIX}/lib/libx264.lib" || exit
    fi

    mkdir -p "${CURRENTPATH}/${OUTPUT}"
    sed -i "s|^prefix=.*|prefix=${CURRENTPATH}/${OUTPUT}|" "${CURRENTPATH}/${OUTPUT}/lib/pkgconfig/"*.pc 2>/dev/null || true

    if [ ! -f "${CURRENTPATH}/${OUTPUT}/lib/libx264.lib" ]; then
        echo "x264 output missing: ${CURRENTPATH}/${OUTPUT}/lib/libx264.lib" >&2
        popd || true
        exit 1
    fi

    popd || exit
done

ls -l ${CURRENTPATH}/output/*/*/lib/libx264.lib
