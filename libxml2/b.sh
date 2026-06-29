SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 1
cd "${SCRIPT_DIR}" || exit 1
source "${SCRIPT_DIR}/../env_config.sh"

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
if [ ! -e ${DEPENDSPATH}/libxml2 ]; then
    echo "Downloading libxml2"
    pushd ${DEPENDSPATH}
    git clone https://github.com/GNOME/libxml2.git
    popd
else
    echo "Update libxml2 "
    pushd ${DEPENDSPATH}/libxml2
    #git pull
    popd
fi
############################################################################################

#trap "cd ${DEPENDSPATH}/libdvdread && git reset --hard" EXIT

#patch -d ${DEPENDSPATH}/libdvdread -p1 <${CURRENTPATH}/ssize_t.patch || exit

############################################################################################
for ((i=0; i<${#archs[@]}; i++))
do
    OUTPUT="output/${BUILD}/${archs[i]}"
    rm -fr "${CURRENTPATH}/${OUTPUT}"

    WSLBUILD="${DEPENDSPATH}/libxml2-build/${BUILD}/${archs[i]}"
    rm -rf "${WSLBUILD}"
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
    echo "INCLUDE:$INCLUDE"
    export LIB="${VCLIB}/${archs[i]};${WINSDKLIB}/um/${archs[i]};${WINSDKLIB}/ucrt/${archs[i]}"
    echo "LIB:$LIB"

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
          -D BUILD_SHARED_LIBS=OFF \
          -D LIBXML2_WITH_C14N=ON -D LIBXML2_WITH_HTML=OFF -D LIBXML2_WITH_CATALOG=OFF \
          -D LIBXML2_WITH_DEBUG=OFF -D LIBXML2_WITH_FTP=OFF -D LIBXML2_WITH_HTTP=OFF \
          -D LIBXML2_WITH_ICONV=OFF -D LIBXML2_WITH_ICU=OFF -D LIBXML2_WITH_ISO8859X=OFF \
          -D LIBXML2_WITH_LEGACY=OFF -D LIBXML2_WITH_LZMA=OFF -D LIBXML2_WITH_MODULES=OFF \
          -D LIBXML2_WITH_OUTPUT=OFF -D LIBXML2_WITH_PATTERN=OFF -D LIBXML2_WITH_PUSH=OFF \
          -D LIBXML2_WITH_PYTHON=OFF -D LIBXML2_WITH_READLINE=OFF -D LIBXML2_WITH_REGEXPS=OFF \
          -D LIBXML2_WITH_RELAXNG=OFF -D LIBXML2_WITH_SAX1=OFF -D LIBXML2_WITH_SCHEMAS=OFF \
          -D LIBXML2_WITH_TLS=OFF -D LIBXML2_WITH_VALID=OFF -D LIBXML2_WITH_ZLIB=ON \
          -D ZLIB_INCLUDE_DIR=${CURRENTPATH}/../zlib/${OUTPUT}/include \
          -D ZLIB_LIBRARY_RELEASE=${CURRENTPATH}/../zlib/${OUTPUT}/lib/zlib.lib \
          -D CMAKE_VERBOSE_MAKEFILE=ON ${DEPENDSPATH}/libxml2

    make -j $(nproc) && make install && make clean || exit
    mkdir -p "${CURRENTPATH}/${OUTPUT}"

    mv -f ${CURRENTPATH}/${OUTPUT}/lib/libxml2sd.lib ${CURRENTPATH}/${OUTPUT}/lib/xml2.lib
    mv -f ${CURRENTPATH}/${OUTPUT}/lib/libxml2s.lib ${CURRENTPATH}/${OUTPUT}/lib/xml2.lib

    popd
done

ls -l ${CURRENTPATH}/output/*/*/lib/*.lib
