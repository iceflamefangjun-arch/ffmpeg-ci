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
    export PATH="${TOOLCHAIN}/bin:${PATH}"

    export AR="${LLVM_LIB_TOOL}"
    export NM="${LLVM_NM_TOOL}"
    export MT="${LLVM_MT_TOOL}"
    export CC="${CLANG_CL_TOOL}"
    export CXX="${CLANG_CL_TOOL}"
    export LD="${LLD_LINK_TOOL}"
    export RANLIB="${LLVM_RANLIB_TOOL}"
    export STRIP="${LLVM_STRIP_TOOL}"

    set_msvc_arch_env "${archs[i]}"
    echo "INCLUDE:$INCLUDE"
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

    export CFLAGS="${OPTIMIZE} ${msvc_arch_cflags} -fuse-ld=lld -fms-compatibility -I${CURRENTPATH}/../zlib/${OUTPUT}/include"
    export CXXFLAGS="${CFLAGS} ${CXX_OPTIMIZE} /EHsc -std:c++11"
    #export LDFLAGS="${msvc_arch_ldflags}"

    # 设置CMAKE_MSVC_RUNTIME_LIBRARY禁止cmake自动设置-MD
    WSLPREFIX="${CURRENTPATH}/${OUTPUT}"
    rm -rf "${WSLPREFIX}" && mkdir -p "${WSLPREFIX}"
    run_cmake_configure "-DCMAKE_INSTALL_PREFIX=${WSLPREFIX}" \
          "-DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}" "-DCMAKE_INSTALL_LIBDIR=lib" \
          "-DCMAKE_SYSTEM_NAME=Windows" "-DCMAKE_MSVC_RUNTIME_LIBRARY=" \
          "-DCMAKE_AR=$(cmake_tool_path "${AR}")" \
          "-DCMAKE_NM=$(cmake_tool_path "${NM}")" \
          "-DCMAKE_MT=$(cmake_tool_path "${MT}")" \
          "-DCMAKE_RC_COMPILER=$(cmake_tool_path "${RC}")" \
          "-DCMAKE_LINKER=$(cmake_tool_path "${LD}")" \
          "-DCMAKE_C_COMPILER=$(cmake_tool_path "${CC}")" \
          "-DCMAKE_CXX_COMPILER=$(cmake_tool_path "${CXX}")" \
          "-DCMAKE_C_FLAGS_RELEASE=/Ob2" "-DCMAKE_CXX_FLAGS_RELEASE=/Ob2" \
          "-DBUILD_SHARED_LIBS=OFF" "-DLIBXML2_WITH_PROGRAMS=OFF" "-DLIBXML2_WITH_TESTS=OFF" \
          "-DLIBXML2_WITH_C14N=ON" "-DLIBXML2_WITH_HTML=OFF" "-DLIBXML2_WITH_CATALOG=OFF" \
          "-DLIBXML2_WITH_DEBUG=OFF" "-DLIBXML2_WITH_FTP=OFF" "-DLIBXML2_WITH_HTTP=OFF" \
          "-DLIBXML2_WITH_ICONV=OFF" "-DLIBXML2_WITH_ICU=OFF" "-DLIBXML2_WITH_ISO8859X=OFF" \
          "-DLIBXML2_WITH_LEGACY=OFF" "-DLIBXML2_WITH_LZMA=OFF" "-DLIBXML2_WITH_MODULES=OFF" \
          "-DLIBXML2_WITH_OUTPUT=OFF" "-DLIBXML2_WITH_PATTERN=OFF" "-DLIBXML2_WITH_PUSH=OFF" \
          "-DLIBXML2_WITH_PYTHON=OFF" "-DLIBXML2_WITH_READLINE=OFF" "-DLIBXML2_WITH_REGEXPS=OFF" \
          "-DLIBXML2_WITH_RELAXNG=OFF" "-DLIBXML2_WITH_SAX1=OFF" "-DLIBXML2_WITH_SCHEMAS=OFF" \
          "-DLIBXML2_WITH_TLS=OFF" "-DLIBXML2_WITH_VALID=OFF" "-DLIBXML2_WITH_ZLIB=ON" \
          "-DZLIB_INCLUDE_DIR=${CURRENTPATH}/../zlib/${OUTPUT}/include" \
          "-DZLIB_LIBRARY_RELEASE=${CURRENTPATH}/../zlib/${OUTPUT}/lib/zlib.lib" \
          "-DCMAKE_VERBOSE_MAKEFILE=ON" "${DEPENDSPATH}/libxml2"

    run_cmake_build_install && cmake --build . --target clean || exit
    mkdir -p "${CURRENTPATH}/${OUTPUT}"

    mv -f ${CURRENTPATH}/${OUTPUT}/lib/libxml2sd.lib ${CURRENTPATH}/${OUTPUT}/lib/xml2.lib
    mv -f ${CURRENTPATH}/${OUTPUT}/lib/libxml2s.lib ${CURRENTPATH}/${OUTPUT}/lib/xml2.lib

    popd
done

ls -l ${CURRENTPATH}/output/*/*/lib/*.lib
