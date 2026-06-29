SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 1
cd "${SCRIPT_DIR}" || exit 1
source "${SCRIPT_DIR}/../env_config.sh"
CURRENTPATH="${SCRIPT_DIR}"

set_target_archs "${2:-all}"

OPTIMIZE="-fmerge-all-constants /Zc:sizedDealloc- /Zc:twoPhase /bigobj /utf-8"

MSVC_RUNTIME=""
if [ $# -lt 1 ]; then echo "Usage: $0 [debug|release|static] [x86|x64|all]" >&2; exit; fi
case $1 in
  debug)
      BUILD="debug"
      OPTIMIZE="/Od /MDd /D_DEBUG /Z7 ${OPTIMIZE}"
      CMAKE_BUILD_TYPE="Debug"
      MSVC_RUNTIME="MultiThreadedDebugDLL"
      ;;
  release)
      BUILD="release"
      OPTIMIZE="/O2 /MT /DNDEBUG /Z7 ${OPTIMIZE} /GF"
      CMAKE_BUILD_TYPE="Release"
      MSVC_RUNTIME="MultiThreaded"
      ;;
  static)
      BUILD="static"
      OPTIMIZE="/O2 /MT /DNDEBUG /Z7 ${OPTIMIZE} /GF /Gy /Gw -flto=thin -fsplit-lto-unit"
      CMAKE_BUILD_TYPE="Release"
      MSVC_RUNTIME="MultiThreaded"
      ;;
  *)
      echo "Only support [debug|release|static]" >&2; exit
      ;;
esac

############################################################################################
if [ ! -e ${DEPENDSPATH}/libyuv ]; then
    echo "Downloading libyuv"
    pushd ${DEPENDSPATH}
    git clone https://github.com/lemenkov/libyuv.git || { popd; exit 1; }
    popd
else
    echo "Update libyuv"
    pushd ${DEPENDSPATH}/libyuv
    #git pull
    popd
fi
############################################################################################

for ((i=0; i<${#archs[@]}; i++))
do
    OUTPUT="output/${BUILD}/${archs[i]}"
    rm -fr "${CURRENTPATH}/${OUTPUT}"

    # Build dir stays on Linux filesystem to avoid WSL/NTFS configure_file issues.
    # Install dir is the final output path under this script.
    LINUX_BUILD="${HOME}/.cache/shplayer/build/libyuv-${BUILD}/${archs[i]}"
    LINUX_INSTALL="${CURRENTPATH}/${OUTPUT}"
    rm -fr "${LINUX_BUILD}" "${LINUX_INSTALL}"
    mkdir -p "${LINUX_BUILD}" "${LINUX_INSTALL}"
    pushd "${LINUX_BUILD}"

    echo "CURR DIR:" $(pwd)
    echo "Target:" ${archs[i]}

    export ARCH=${archs[i]}
    export PATH=${TOOLCHAIN}bin:$PATH

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
          msvc_arch_ldflags=(
            "/safeseh:no"
            "/MACHINE:X86"
            "/DEBUG"
          )
          cmake_sizeof_void_p=4
          cmake_system_processor="X86"
          ;;
      x64)
          msvc_arch_cflags="--target=x86_64-pc-windows-msvc -m64 -msse3"
          msvc_arch_ldflags=(
            "/MACHINE:X64"
            "/DEBUG"
          )
          cmake_sizeof_void_p=8
          cmake_system_processor="AMD64"
          ;;
      *)
          msvc_arch_cflags=
          msvc_arch_ldflags=
          cmake_sizeof_void_p=8
          cmake_system_processor="AMD64"
          ;;
    esac

    export CFLAGS="${OPTIMIZE} ${msvc_arch_cflags} -fuse-ld=lld -fms-compatibility -DLIBYUV_EXPORTS"
    export CXXFLAGS="${CFLAGS} ${CXX_OPTIMIZE} /EHsc -std:c++11 -DLIBYUV_EXPORTS"
    export LDFLAGS="${msvc_arch_ldflags[@]}"

    echo "compile"$CC

    [ -d "${DEPENDSPATH}/libyuv" ] || { echo "Error: libyuv source not found at ${DEPENDSPATH}/libyuv" >&2; exit 1; }

    cmake -D CMAKE_INSTALL_PREFIX=${LINUX_INSTALL} \
          -D CMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE} \
          -D CMAKE_SYSTEM_NAME=Windows \
          -D CMAKE_SYSTEM_PROCESSOR=${cmake_system_processor} \
          -D CMAKE_SIZEOF_VOID_P=${cmake_sizeof_void_p} \
          -D CMAKE_AR=${AR} -D CMAKE_NM=${NM} -D CMAKE_MT=${MT} -D CMAKE_RC_COMPILER=${TOOLCHAIN}/bin/llvm-rc \
          -D CMAKE_C_FLAGS_RELEASE="/Ob0" -D CMAKE_CXX_FLAGS_RELEASE="/Ob0" \
          -D CMAKE_MSVC_RUNTIME_LIBRARY="${MSVC_RUNTIME}" \
          -D CMAKE_VERBOSE_MAKEFILE=ON ${DEPENDSPATH}/libyuv \
          -D BUILD_SHARED_LIBS=OFF

    make V=1 -j $(nproc) && make install && make clean || exit

    mkdir -p "${CURRENTPATH}/${OUTPUT}"
done

popd

ls -l ${CURRENTPATH}/output/*/*/lib/*.lib
