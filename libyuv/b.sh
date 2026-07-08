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
      OPTIMIZE="/O2 /MT /DNDEBUG /Z7 ${OPTIMIZE} /GF /Gy /Gw"
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

    export AR="${LLVM_LIB_TOOL}"
    export NM="${LLVM_NM_TOOL}"
    export MT="${LLVM_MT_TOOL}"
    export CC="${CLANG_CL_TOOL}"
    export CXX="${CLANG_CL_TOOL}"
    export LD="${LLD_LINK_TOOL}"
    export RANLIB="${LLVM_RANLIB_TOOL}"
    export STRIP="${LLVM_STRIP_TOOL}"

    set_msvc_arch_env "${archs[i]}"

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

    run_cmake_configure "-DCMAKE_INSTALL_PREFIX=${LINUX_INSTALL}" \
          "-DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}" \
          "-DCMAKE_SYSTEM_NAME=Windows" \
          "-DCMAKE_SYSTEM_PROCESSOR=${cmake_system_processor}" \
          "-DCMAKE_SIZEOF_VOID_P=${cmake_sizeof_void_p}" \
          "-DCMAKE_AR=$(cmake_tool_path "${AR}")" \
          "-DCMAKE_NM=$(cmake_tool_path "${NM}")" \
          "-DCMAKE_MT=$(cmake_tool_path "${MT}")" \
          "-DCMAKE_RC_COMPILER=$(cmake_tool_path "${RC}")" \
          "-DCMAKE_LINKER=$(cmake_tool_path "${LD}")" \
          "-DCMAKE_C_COMPILER=$(cmake_tool_path "${CC}")" \
          "-DCMAKE_CXX_COMPILER=$(cmake_tool_path "${CXX}")" \
          "-DCMAKE_C_FLAGS_RELEASE=/Ob0" "-DCMAKE_CXX_FLAGS_RELEASE=/Ob0" \
          "-DCMAKE_MSVC_RUNTIME_LIBRARY=${MSVC_RUNTIME}" \
          "-DCMAKE_VERBOSE_MAKEFILE=ON" "${DEPENDSPATH}/libyuv" \
          "-DBUILD_SHARED_LIBS=OFF"

    run_cmake_build_install && cmake --build . --target clean || exit

    mkdir -p "${CURRENTPATH}/${OUTPUT}"
done

popd

ls -l ${CURRENTPATH}/output/*/*/lib/*.lib
