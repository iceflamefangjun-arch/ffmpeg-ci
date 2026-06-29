SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 1
cd "${SCRIPT_DIR}" || exit 1
source "${SCRIPT_DIR}/../env_config.sh"

VERSION="1.3.1"

CURRENTPATH="${SCRIPT_DIR}"

set_target_archs "${2:-all}"

OPTIMIZE="-fmerge-all-constants /Zc:sizedDealloc- /Zc:twoPhase /bigobj /utf-8"

if [ $# -lt 1 ]; then echo "Usage: $0 [debug|release|static]" >&2; exit; fi
case $1 in
  debug)
      BUILD="debug"
      OPTIMIZE="/Od /MDd /D_DEBUG ${OPTIMIZE}"
      CMAKE_BUILD_TYPE="Debug"
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
rm -fr "${DEPENDSPATH}/zlib-src" && mkdir -p "${DEPENDSPATH}/zlib-src" || exit

if [ ! -e ${DEPENDSPATH}/zlib-${VERSION}.tar.gz ]; then
    echo "Downloading zlib-${VERSION}.tar.gz"
    curl -s -L -o ${DEPENDSPATH}/zlib-${VERSION}.tar.gz https://github.com/madler/zlib/releases/download/v${VERSION}/zlib-${VERSION}.tar.gz
else
    echo "Using zlib-${VERSION}.tar.gz"
fi

tar zxf ${DEPENDSPATH}/zlib-${VERSION}.tar.gz -C "${DEPENDSPATH}/zlib-src"
############################################################################################

patch --batch -N -d ${DEPENDSPATH}/zlib-src/zlib-${VERSION} -p0 <CMakeLists.txt.patch || exit

############################################################################################
for ((i=0; i<${#archs[@]}; i++))
do
    OUTPUT="output/${BUILD}/${archs[i]}"
    rm -fr "${CURRENTPATH}/${OUTPUT}"

    WSLBUILD="${DEPENDSPATH}/zlib-build/${BUILD}/${archs[i]}"
    rm -fr "${WSLBUILD}"
    mkdir -p "${WSLBUILD}"
    pushd "${WSLBUILD}"

    echo "CURR DIR:" $(pwd)
    echo "Target:" ${targets[i]}

    export ARCH=${archs[i]}
    export PATH=${TOOLCHAIN}/bin:$PATH

    export AR="${TOOLCHAIN}/bin/llvm-lib"
    export NM="${TOOLCHAIN}/bin/llvm-nm"
    export MT="${TOOLCHAIN}/bin/llvm-mt"
    export CC="${TOOLCHAIN}/bin/clang-cl"
    export CXX="${TOOLCHAIN}/bin/clang-cl"
    export LD="${TOOLCHAIN}/bin/lld-link"
    export RANLIB="${TOOLCHAIN}/bin/llvm-ranlib"
    export STRIP="${TOOLCHAIN}/bin/llvm-strip"

    export INCLUDE="${WINSDKINC}/winrt;${WINSDKINC}/ucrt;${WINSDKINC}/um;${WINSDKINC}/shared;${VCINC}"
    echo "$INCLUDE"
    export LIB="${VCLIB}/${archs[i]};${WINSDKLIB}/um/${archs[i]};${WINSDKLIB}/ucrt/${archs[i]}"
    echo "$LIB"

    case ${ARCH} in
      x86)
          msvc_arch_cflags="--target=i686-pc-windows-msvc -m32 -msse3"
          msvc_arch_ldflags="/safeseh:no"
          ;;
      x64)
          msvc_arch_cflags="--target=x86_64-pc-windows-msvc -m64 -msse3"
          msvc_arch_ldflags=
          ;;
      *)
          msvc_arch_cflags=
          msvc_arch_ldflags=
          ;;
    esac

    export CFLAGS="${OPTIMIZE} ${msvc_arch_cflags} -fuse-ld=lld -fms-compatibility"
    export CXXFLAGS="${CFLAGS} ${CXX_OPTIMIZE} /EHsc -std:c++11"
    #export LDFLAGS="${msvc_arch_ldflags}"

    # 设置CMAKE_MSVC_RUNTIME_LIBRARY禁止cmake自动设置-MD
    WSLPREFIX="${CURRENTPATH}/${OUTPUT}"
    rm -rf "${WSLPREFIX}" && mkdir -p "${WSLPREFIX}"
    cmake -D CMAKE_INSTALL_PREFIX=${WSLPREFIX} \
          -D CMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE} -D CMAKE_INSTALL_LIBDIR=lib \
          -D CMAKE_SYSTEM_NAME=Windows -D CMAKE_MSVC_RUNTIME_LIBRARY="" \
          -D CMAKE_AR=${AR} -D CMAKE_NM=${NM} -D CMAKE_MT=${MT} -D CMAKE_RC_COMPILER=${TOOLCHAIN}/bin/llvm-rc \
          -D CMAKE_C_FLAGS_RELEASE="/Ob2" -D CMAKE_CXX_FLAGS_RELEASE="/Ob2" \
          -D CMAKE_VERBOSE_MAKEFILE=ON ${DEPENDSPATH}/zlib-src/zlib-${VERSION}

    make -j $(nproc) && make install && make clean || exit
    mkdir -p "${CURRENTPATH}/${OUTPUT}"

    mv -f ${CURRENTPATH}/${OUTPUT}/lib/zlibd.lib ${CURRENTPATH}/${OUTPUT}/lib/zlib.lib

    popd
done

ls -l ${CURRENTPATH}/output/*/*/lib/*.lib
