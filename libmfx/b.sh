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
            -D CMAKE_POLICY_VERSION_MINIMUM=3.5 \
          -D CMAKE_SYSTEM_NAME=Windows -D CMAKE_MSVC_RUNTIME_LIBRARY="" \
          -D CMAKE_AR=${AR} -D CMAKE_NM=${NM} -D CMAKE_MT=${MT} -D CMAKE_RC_COMPILER=${TOOLCHAIN}/bin/llvm-rc \
          -D CMAKE_C_FLAGS_RELEASE="/Ob2" -D CMAKE_CXX_FLAGS_RELEASE="/Ob2" \
          -D CMAKE_VERBOSE_MAKEFILE=ON ${WSLSRC} || exit

    make V=1 -j $(nproc) && make install && make clean || exit

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
