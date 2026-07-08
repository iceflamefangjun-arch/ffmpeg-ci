SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 1
cd "${SCRIPT_DIR}" || exit 1
source "${SCRIPT_DIR}/../env_config.sh"

CURRENTPATH="${SCRIPT_DIR}"

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
      OPTIMIZE="/O2 /MD /DNDEBUG ${OPTIMIZE} /GF /Gy /Gw"
      CMAKE_BUILD_TYPE="Release"
      ;;
  static)
      BUILD="static"
      OPTIMIZE="/O2 /MT /DNDEBUG ${OPTIMIZE} /GF /Gy /Gw"
      CMAKE_BUILD_TYPE="Release"
      ;;
  *)
      echo "Only support [debug|release|static]" >&2; exit
      ;;
esac

if [ ! -e "${DEPENDSPATH}/mfx_dispatch" ]; then
    echo "Downloading mfx_dispatch"
    pushd "${DEPENDSPATH}" || exit
    git clone https://github.com/lu-zero/mfx_dispatch.git || exit
    popd || exit
else
    echo "Update mfx_dispatch"
    pushd "${DEPENDSPATH}/mfx_dispatch" || exit
    #git pull
    popd || exit
fi

for ((i=0; i<${#archs[@]}; i++))
do
    OUTPUT="output/${BUILD}/${archs[i]}"
    rm -fr "${CURRENTPATH}/${OUTPUT}"

    WSLSRC="${DEPENDSPATH}/mfx-dispatch-src/${BUILD}/${archs[i]}"
    rm -rf "${WSLSRC}"
    mkdir -p "$(dirname "${WSLSRC}")" || exit
    cp -r "${DEPENDSPATH}/mfx_dispatch" "${WSLSRC}" || exit

    WSLBUILD="${DEPENDSPATH}/mfx-dispatch-build/${BUILD}/${archs[i]}"
    rm -rf "${WSLBUILD}"
    mkdir -p "${WSLBUILD}"
    pushd "${WSLBUILD}" || exit

    export ARCH=${archs[i]}
    export PATH="${DEPENDSPATH}/bin:${TOOLCHAIN}/bin:${PATH}"

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

    run_cmake_configure "-DCMAKE_INSTALL_PREFIX=${WSLPREFIX}" \
          "-DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}" "-DCMAKE_INSTALL_LIBDIR=lib" \
          "-DCMAKE_POLICY_VERSION_MINIMUM=3.5" \
          "-DCMAKE_SYSTEM_NAME=Windows" "-DCMAKE_MSVC_RUNTIME_LIBRARY=" \
          "-DCMAKE_AR=$(cmake_tool_path "${AR}")" \
          "-DCMAKE_NM=$(cmake_tool_path "${NM}")" \
          "-DCMAKE_MT=$(cmake_tool_path "${MT}")" \
          "-DCMAKE_RC_COMPILER=$(cmake_tool_path "${RC}")" \
          "-DCMAKE_LINKER=$(cmake_tool_path "${LD}")" \
          "-DCMAKE_C_COMPILER=$(cmake_tool_path "${CC}")" \
          "-DCMAKE_CXX_COMPILER=$(cmake_tool_path "${CXX}")" \
          "-DCMAKE_C_FLAGS_RELEASE=/Ob2" "-DCMAKE_CXX_FLAGS_RELEASE=/Ob2" \
          "-DCMAKE_VERBOSE_MAKEFILE=ON" "${WSLSRC}" || exit

    run_cmake_build_install && cmake --build . --target clean || exit

    # Normalize library names for downstream consumers.
    if [ -f "${WSLPREFIX}/lib/libmfx.lib" ] && [ ! -f "${WSLPREFIX}/lib/mfx.lib" ]; then
        cp -f "${WSLPREFIX}/lib/libmfx.lib" "${WSLPREFIX}/lib/mfx.lib" || exit
    fi
    if [ -f "${WSLPREFIX}/lib/mfx.lib" ] && [ ! -f "${WSLPREFIX}/lib/libmfx.lib" ]; then
        cp -f "${WSLPREFIX}/lib/mfx.lib" "${WSLPREFIX}/lib/libmfx.lib" || exit
    fi

    if [ -f "${WSLPREFIX}/lib/pkgconfig/libmfx.pc" ]; then
        sed -i -r 's|^Libs:.*|Libs: -L${libdir} -lmfx -ladvapi32 -lole32|' "${WSLPREFIX}/lib/pkgconfig/libmfx.pc" 2>/dev/null || true
    fi

    mkdir -p "${WSLPREFIX}/lib/pkgconfig"
    cat >"${WSLPREFIX}/lib/pkgconfig/libmfx.pc" <<'EOF'
prefix=@PREFIX@
exec_prefix=${prefix}
libdir=${prefix}/lib
includedir=${prefix}/include

Name: libmfx
Description: Intel Media SDK Dispatched static library
Version: 1.35
Requires:
Requires.private:
Conflicts:
Libs: -L${libdir} -lmfx -ladvapi32 -lole32
Libs.private:
Cflags: -I${includedir}
EOF
    sed -i "s|@PREFIX@|${WSLPREFIX}|" "${WSLPREFIX}/lib/pkgconfig/libmfx.pc" || exit

    mkdir -p "${CURRENTPATH}/${OUTPUT}"
    sed -i "s|^prefix=.*|prefix=${CURRENTPATH}/${OUTPUT}|" "${CURRENTPATH}/${OUTPUT}/lib/pkgconfig/"*.pc 2>/dev/null || true

    if [ ! -f "${CURRENTPATH}/${OUTPUT}/lib/mfx.lib" ] && [ ! -f "${CURRENTPATH}/${OUTPUT}/lib/libmfx.lib" ]; then
        echo "libmfx output missing: ${CURRENTPATH}/${OUTPUT}/lib/{mfx.lib,libmfx.lib}" >&2
        popd || true
        exit 1
    fi

    popd || exit
done

ls -l ${CURRENTPATH}/output/*/*/lib/*mfx.lib
