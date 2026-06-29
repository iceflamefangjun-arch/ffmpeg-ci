SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 1
cd "${SCRIPT_DIR}" || exit 1
source "${SCRIPT_DIR}/../env_config.sh"

VERSION="1.3.4"
CURRENTPATH="${SCRIPT_DIR}"

set_target_archs "${2:-x86}"

OPTIMIZE="-fmerge-all-constants /Zc:sizedDealloc- /Zc:twoPhase /bigobj /utf-8"

if [ $# -lt 1 ]; then echo "Usage: $0 [debug|release|static]" >&2; exit; fi
case $1 in
  debug)
      BUILD="debug"
      OPTIMIZE="/Od /MDd /D_DEBUG ${OPTIMIZE}"
      CMAKE_BUILD_TYPE="Debug"
      build_with_debug="--disable-optimizations"
      ;;
  release)
      BUILD="release"
      OPTIMIZE="/O2 /MD /DNDEBUG ${OPTIMIZE} /GF /Gy /Gw -flto=thin -fsplit-lto-unit"
      CMAKE_BUILD_TYPE="Release"
      ;;
  static)
      BUILD="static"
      OPTIMIZE="/O2 /MT /DNDEBUG ${OPTIMIZE} /GF /Gy /Gw -flto=thin -fsplit-lto-unit"
      CMAKE_BUILD_TYPE="Release"
      ;;
  *)
      echo "Only support [debug|release|static]" >&2; exit
      ;;
esac

############################################################################################
if [ ! -e ${DEPENDSPATH}/libbluray ]; then
    echo "Downloading libbluray"
    pushd ${DEPENDSPATH}
    git clone https://code.videolan.org/videolan/libbluray.git 
    cd libbluray && git checkout ${VERSION}
    popd
else
    echo "Update libbluray"
    pushd ${DEPENDSPATH}/libbluray
    #git checkout master && git pull
    #git checkout ${VERSION}
    popd
fi
############################################################################################

pushd ${DEPENDSPATH}/libbluray
git reset --hard && rm -f src/libbluray/bluray-fs.h
popd

patch -d ${DEPENDSPATH}/libbluray -p1 <${CURRENTPATH}/0001-skip-check-bdj-and-provide-reading-current-stream-fi.patch || exit
patch -d ${DEPENDSPATH}/libbluray -p1 <${CURRENTPATH}/0002-add-bd_open_fs-function.patch || exit
patch -d ${DEPENDSPATH}/libbluray -p1 <${CURRENTPATH}/0003-bluray-use-_wsopen-read-lseek-eg-function-operate-fi.patch || exit
patch -d ${DEPENDSPATH}/libbluray -p1 <${CURRENTPATH}/configure.patch || exit

############################################################################################
for ((i=0; i<${#archs[@]}; i++))
do
    OUTPUT="output/${BUILD}/${archs[i]}"
    rm -fr "${CURRENTPATH}/${OUTPUT}"

    rm -fr "${CURRENTPATH}/build"
    mkdir -p "${CURRENTPATH}/build"
    pushd "${CURRENTPATH}/build"

    echo "CURR DIR:" $(pwd)
    echo "Target:" ${archs[i]}

    export ARCH=${archs[i]}
    export PATH="${TOOLCHAIN}/bin:${PATH}"

    export AR="${LLVM_AR_TOOL}"
    export NM="${LLVM_NM_TOOL}"
    export MT="${LLVM_MT_TOOL}"
    export CC="${CLANG_CL_TOOL}"
    export CXX="${CLANG_CL_TOOL}"
    export LD="${LLD_LINK_TOOL}"
    export RANLIB="${LLVM_RANLIB_TOOL}"
    export STRIP="${LLVM_STRIP_TOOL}"

    set_msvc_arch_env "${archs[i]}"
    echo "$INCLUDE"
    echo "$LIB"

    case ${ARCH} in
      x86)
          msvc_arch_cflags="--target=i686-pc-windows-msvc -m32 -msse3"
          msvc_arch_ldflags="-Wl,/safeseh:no -Wl,/MACHINE:X86"
          ;;
      x64)
          msvc_arch_cflags="--target=x86_64-pc-windows-msvc -m64 -msse3"
          msvc_arch_ldflags="-Wl,/MACHINE:X64"
          ;;
      arm64)
          msvc_arch_cflags="--target=aarch64-pc-windows-msvc"
          msvc_arch_ldflags=""
          ;;
      *)
          msvc_arch_cflags=
          msvc_arch_ldflags=
          ;;
    esac

    export PKG_CONFIG_PATH="${CURRENTPATH}/../libudfread/${OUTPUT}/lib/pkgconfig:$PKG_CONFIG_PATH"
    export CFLAGS="${OPTIMIZE} ${msvc_arch_cflags} -fuse-ld=lld -fms-compatibility"
    export CXXFLAGS="${CFLAGS} ${CXX_OPTIMIZE} /EHsc -std:c++11"
    export LDFLAGS="${msvc_arch_ldflags}"

    pushd ${DEPENDSPATH}/libbluray && ./bootstrap || exit

    export ac_cv_c_bigendian=no
    WSLPREFIX="${CURRENTPATH}/${OUTPUT}"
    rm -rf "${WSLPREFIX}" && mkdir -p "${WSLPREFIX}"
    ${DEPENDSPATH}/libbluray/configure      \
        --host=${targets[i]}                \
        --prefix="${WSLPREFIX}"             \
        --disable-shared                    \
        --enable-static                     \
        --disable-examples                  \
        --disable-bdjava-jar                \
        --without-libxml2                   \
        --without-freetype                  \
        --without-fontconfig                \
        --without-java9                     \
        ${build_with_debug}                 \

    make V=1 -j $(nproc) 2>&1 | tee build.log && make install && make clean || exit
    mkdir -p "${CURRENTPATH}/${OUTPUT}"
    sed -i "s|^prefix=.*|prefix=${CURRENTPATH}/${OUTPUT}|" "${CURRENTPATH}/${OUTPUT}/lib/pkgconfig/"*.pc 2>/dev/null || true

    popd
done

ls -l ${CURRENTPATH}/output/*/*/lib/*.lib
