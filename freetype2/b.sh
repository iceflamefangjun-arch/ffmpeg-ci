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
if [ ! -e ${DEPENDSPATH}/freetype2 ]; then
    echo "Downloading freetype2"
    pushd ${DEPENDSPATH}
    git clone https://github.com/aseprite/freetype2.git
    popd
else
    echo "Update freetype2"
    pushd ${DEPENDSPATH}/freetype2
    #git pull
    popd
fi
############################################################################################

for ((i=0; i<${#archs[@]}; i++))
do
    OUTPUT="output/${BUILD}/${archs[i]}"
    rm -fr "${CURRENTPATH}/${OUTPUT}"

    WSLBUILD="${DEPENDSPATH}/freetype2-build/${BUILD}/${archs[i]}"
    rm -rf "${WSLBUILD}"
    mkdir -p "${WSLBUILD}"
    pushd "${WSLBUILD}"

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
          )
          ;;
      x64)
          msvc_arch_cflags="--target=x86_64-pc-windows-msvc -m64 -msse3"
          msvc_arch_ldflags=(
            "/MACHINE:X64"
          )
          ;;
      *)
          msvc_arch_cflags=
          msvc_arch_ldflags=
          ;;
    esac

    export CFLAGS="${OPTIMIZE} ${msvc_arch_cflags} -fuse-ld=lld -fms-compatibility"
    export CXXFLAGS="${CFLAGS} ${CXX_OPTIMIZE} /EHsc -std:c++11"
    export LDFLAGS="${msvc_arch_ldflags[@]}"

    echo "compile"$CC

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
          "-DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded$<$<CONFIG:Debug>:Debug>" \
          "-DCMAKE_VERBOSE_MAKEFILE=ON" "${DEPENDSPATH}/freetype2"

    run_cmake_build_install && cmake --build . --target clean || exit
    mkdir -p "${CURRENTPATH}/${OUTPUT}"

    mv ${CURRENTPATH}/${OUTPUT}/lib/freetyped.lib ${CURRENTPATH}/${OUTPUT}/lib/freetype.lib
done

popd

ls -l ${CURRENTPATH}/output/*/*/lib/*.lib
