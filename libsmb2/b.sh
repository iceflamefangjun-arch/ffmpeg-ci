SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 1
cd "${SCRIPT_DIR}" || exit 1
source "${SCRIPT_DIR}/../env_config.sh"

CURRENTPATH="${SCRIPT_DIR}"
LIBSMB2_TAG="libsmb2-6.2"

if [ -z "${LIBSMB2_SRC_DIR:-}" ]; then
    if [ -d "${CURRENTPATH}/src/libsmb2" ]; then
        LIBSMB2_SRC_DIR="${CURRENTPATH}/src/libsmb2"
        LIBSMB2_MANAGED_SRC=0
    else
        LIBSMB2_SRC_DIR="${DEPENDSPATH}/libsmb2"
        LIBSMB2_MANAGED_SRC=1
    fi
else
    LIBSMB2_MANAGED_SRC=0
fi

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

if [ ! -e "${LIBSMB2_SRC_DIR}" ]; then
    echo "Downloading libsmb2"
    mkdir -p "$(dirname "${LIBSMB2_SRC_DIR}")" || exit
    pushd "$(dirname "${LIBSMB2_SRC_DIR}")" >/dev/null || exit
    git clone --depth 1 --branch "${LIBSMB2_TAG}" https://github.com/sahlberg/libsmb2.git "$(basename "${LIBSMB2_SRC_DIR}")" || exit
    popd >/dev/null || exit
elif [ ${LIBSMB2_MANAGED_SRC} -eq 1 ]; then
    echo "Update libsmb2"
    pushd "${LIBSMB2_SRC_DIR}" >/dev/null || exit
    #git pull
    git -c safe.directory="${LIBSMB2_SRC_DIR}" checkout "${LIBSMB2_TAG}" || exit
    popd >/dev/null || exit
else
    echo "Using local libsmb2 source mirror: ${LIBSMB2_SRC_DIR}"
fi
############################################################################################

if [ ${LIBSMB2_MANAGED_SRC} -eq 1 ]; then
    pushd "${LIBSMB2_SRC_DIR}" >/dev/null || exit
    git -c safe.directory="${LIBSMB2_SRC_DIR}" reset --hard || exit
    popd >/dev/null || exit
fi

for ((i=0; i<${#archs[@]}; i++))
do
    OUTPUT="output/${BUILD}/${archs[i]}"
    rm -fr "${CURRENTPATH}/${OUTPUT}"

    WSLBUILD="${DEPENDSPATH}/libsmb2-build/${BUILD}/${archs[i]}"
    rm -rf "${WSLBUILD}"
    mkdir -p "${WSLBUILD}"

    WSLSRC="${DEPENDSPATH}/libsmb2-src/${BUILD}/${archs[i]}"
    rm -rf "${WSLSRC}"
    mkdir -p "$(dirname "${WSLSRC}")" || exit
    cp -r "${LIBSMB2_SRC_DIR}" "${WSLSRC}" || exit

    patch --batch -N -d "${WSLSRC}" -p1 <"${CURRENTPATH}/0001-fix-smb2-not-support-longer-than-1024-characters-url.patch" || exit

    pushd "${WSLBUILD}" || exit

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
          msvc_arch_ldflags=(
            "/safeseh:no"
          )
          ;;
      x64)
          msvc_arch_cflags="--target=x86_64-pc-windows-msvc -m64 -msse3"
          msvc_arch_ldflags=()
          ;;
      *)
          msvc_arch_cflags=
          msvc_arch_ldflags=()
          ;;
    esac

    export CFLAGS="${OPTIMIZE} ${msvc_arch_cflags} -fuse-ld=lld -fms-compatibility"
    export CXXFLAGS="${CFLAGS} ${CXX_OPTIMIZE} /EHsc -std:c++11"
    export LDFLAGS="${msvc_arch_ldflags[@]}"

    WSLPREFIX="${CURRENTPATH}/${OUTPUT}"
    rm -rf "${WSLPREFIX}" && mkdir -p "${WSLPREFIX}"
        cmake -D CMAKE_INSTALL_PREFIX=${WSLPREFIX} \
          -D CMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE} -D CMAKE_INSTALL_LIBDIR=lib \
          -D CMAKE_SYSTEM_NAME=Windows -D CMAKE_MSVC_RUNTIME_LIBRARY="" \
          -D CMAKE_AR=${AR} -D CMAKE_NM=${NM} -D CMAKE_MT=${MT} -D CMAKE_RC_COMPILER=${TOOLCHAIN}/bin/llvm-rc \
          -D CMAKE_C_FLAGS_RELEASE="/Ob2" -D CMAKE_CXX_FLAGS_RELEASE="/Ob2" \
                -D BUILD_SHARED_LIBS=OFF -D CMAKE_VERBOSE_MAKEFILE=ON ${WSLSRC} || exit

    make V=1 -j $(nproc) && make install && make clean || exit
    mkdir -p "${CURRENTPATH}/${OUTPUT}"
    sed -i "s|^prefix=.*|prefix=${CURRENTPATH}/${OUTPUT}|" "${CURRENTPATH}/${OUTPUT}/lib/pkgconfig/"*.pc 2>/dev/null || true

    popd || exit
done

ls -l ${CURRENTPATH}/output/*/*/lib/*.lib
