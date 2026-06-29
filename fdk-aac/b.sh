SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 1
cd "${SCRIPT_DIR}" || exit 1
source "${SCRIPT_DIR}/../env_config.sh"

CURRENTPATH="${SCRIPT_DIR}"
FDK_AAC_REPO_URL="${FDK_AAC_REPO_URL:-git@code2.sohuno.com:ifox-public/fdk-aac.git}"

set_target_archs "${2:-x64}"

OPTIMIZE="-fmerge-all-constants /Zc:sizedDealloc- /Zc:twoPhase /bigobj /utf-8"

if [ $# -lt 1 ]; then echo "Usage: $0 [debug|release|static] [x64]" >&2; exit; fi
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

if [ ! -e "${DEPENDSPATH}/fdk-aac" ]; then
    echo "Downloading fdk-aac"
    pushd "${DEPENDSPATH}" || exit
    git clone "${FDK_AAC_REPO_URL}" fdk-aac || exit
    popd || exit
else
    echo "Update fdk-aac"
    pushd "${DEPENDSPATH}/fdk-aac" || exit
    #git pull
    popd || exit
fi

for ((i=0; i<${#archs[@]}; i++))
do
    OUTPUT="output/${BUILD}/${archs[i]}"
    rm -fr "${CURRENTPATH}/${OUTPUT}"

    WSLBUILD="${DEPENDSPATH}/fdk-aac-build/${BUILD}/${archs[i]}"
    rm -rf "${WSLBUILD}"
    mkdir -p "${WSLBUILD}"
    pushd "${WSLBUILD}" || exit

    export ARCH=${archs[i]}
    export PATH="${TOOLCHAIN}/bin:${PATH}"

    export AR="${TOOLCHAIN}/bin/llvm-lib"
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

    cmake -D CMAKE_INSTALL_PREFIX=${WSLPREFIX} \
          -D CMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE} -D CMAKE_INSTALL_LIBDIR=lib \
          -D CMAKE_SYSTEM_NAME=Windows -D CMAKE_MSVC_RUNTIME_LIBRARY="" \
          -D CMAKE_AR=${AR} -D CMAKE_NM=${NM} -D CMAKE_MT=${MT} -D CMAKE_RC_COMPILER=${TOOLCHAIN}/bin/llvm-rc \
          -D CMAKE_C_FLAGS_RELEASE="/Ob2" -D CMAKE_CXX_FLAGS_RELEASE="/Ob2" \
          -D BUILD_PROGRAMS=OFF -D BUILD_SHARED_LIBS=OFF -D CMAKE_VERBOSE_MAKEFILE=ON ${DEPENDSPATH}/fdk-aac || exit

    make V=1 -j $(nproc) && make install && make clean || exit

    # Keep both names for better compatibility with pkg-config/FFmpeg checks on Windows.
    if [ -f "${WSLPREFIX}/lib/fdk-aac.lib" ] && [ ! -f "${WSLPREFIX}/lib/libfdk-aac.lib" ]; then
        cp -f "${WSLPREFIX}/lib/fdk-aac.lib" "${WSLPREFIX}/lib/libfdk-aac.lib" || exit
    fi
    if [ -f "${WSLPREFIX}/lib/libfdk-aac.lib" ] && [ ! -f "${WSLPREFIX}/lib/fdk-aac.lib" ]; then
        cp -f "${WSLPREFIX}/lib/libfdk-aac.lib" "${WSLPREFIX}/lib/fdk-aac.lib" || exit
    fi

    mkdir -p "${WSLPREFIX}/lib/pkgconfig"
    cat >"${WSLPREFIX}/lib/pkgconfig/fdk-aac.pc" <<'EOF'
prefix=@PREFIX@
exec_prefix=${prefix}
libdir=${exec_prefix}/lib
includedir=${prefix}/include

Name: fdk-aac
Description: Fraunhofer FDK AAC codec library
Version: 2.0.3
Libs: -L${libdir} -lfdk-aac
Cflags: -I${includedir}
EOF
    sed -i "s|@PREFIX@|${WSLPREFIX}|" "${WSLPREFIX}/lib/pkgconfig/fdk-aac.pc" || exit

    mkdir -p "${CURRENTPATH}/${OUTPUT}"
    sed -i "s|^prefix=.*|prefix=${CURRENTPATH}/${OUTPUT}|" "${CURRENTPATH}/${OUTPUT}/lib/pkgconfig/fdk-aac.pc" || exit

    if [ ! -f "${CURRENTPATH}/${OUTPUT}/lib/libfdk-aac.lib" ] && [ ! -f "${CURRENTPATH}/${OUTPUT}/lib/fdk-aac.lib" ]; then
        echo "fdk-aac output missing: ${CURRENTPATH}/${OUTPUT}/lib/{fdk-aac.lib,libfdk-aac.lib}" >&2
        popd || true
        exit 1
    fi

    popd || exit
done

ls -l ${CURRENTPATH}/output/*/*/lib/*fdk-aac.lib
