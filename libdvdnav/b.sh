SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 1
cd "${SCRIPT_DIR}" || exit 1
source "${SCRIPT_DIR}/../env_config.sh"

CURRENTPATH="${SCRIPT_DIR}"
VERSION="6.1.1"

set_target_archs "${2:-x86}"

OPTIMIZE="-fmerge-all-constants /Zc:sizedDealloc- /Zc:twoPhase /bigobj /utf-8"

if [ $# -lt 1 ]; then echo "Usage: $0 [debug|release|static]" >&2; exit; fi
case $1 in
  debug)
      BUILD="debug"
      OPTIMIZE="/Od /MDd /D_DEBUG ${OPTIMIZE}"
      build_with_debug="--disable-optimizations"
      ;;
  release)
      BUILD="release"
      OPTIMIZE="/O2 /MD /DNDEBUG ${OPTIMIZE} /GF /Gy /Gw -flto=thin -fsplit-lto-unit"
      ;;
  static)
      BUILD="static"
      OPTIMIZE="/O2 /MT /DNDEBUG ${OPTIMIZE} /GF /Gy /Gw -flto=thin -fsplit-lto-unit"
      ;;
  *)
      echo "Only support [debug|release|static]" >&2; exit
      ;;
esac

############################################################################################
if [ ! -e "${DEPENDSPATH}/libdvdnav" ]; then
    echo "Downloading libdvdnav"
    pushd "${DEPENDSPATH}" >/dev/null
    git clone https://code.videolan.org/videolan/libdvdnav.git
    cd libdvdnav
    git checkout "${VERSION}"
    popd >/dev/null
else
    echo "Update libdvdnav"
    pushd "${DEPENDSPATH}/libdvdnav" >/dev/null
    #git checkout master && git pull
    git checkout "${VERSION}"
    popd >/dev/null
fi
############################################################################################
pushd "${DEPENDSPATH}/libdvdnav"
echo "reset src"
git reset --hard
popd

patch --batch -N -d "${DEPENDSPATH}/libdvdnav" -p1 <"${CURRENTPATH}/0002-fix-msvc-macros.patch" || exit
patch --batch -N -d "${DEPENDSPATH}/libdvdnav" -p1 <"${CURRENTPATH}/0003-fix-unistd.patch" || exit

############################################################################################
for ((i=0; i<${#archs[@]}; i++))
do
    OUTPUT="output/${BUILD}/${archs[i]}"
    rm -fr "${CURRENTPATH}/${OUTPUT}"

    echo "CURR DIR:" $(pwd)
    echo "Target:" ${targets[i]}

    export ARCH=${archs[i]}
    export PATH=${TOOLCHAIN}/bin:$PATH

    export AR="${TOOLCHAIN}/bin/llvm-ar"
    export NM="${TOOLCHAIN}/bin/llvm-nm"
    export MT="${TOOLCHAIN}/bin/llvm-mt"
    export CC="${TOOLCHAIN}/bin/clang-cl"
    export CXX="${TOOLCHAIN}/bin/clang-cl"
    export LD="${TOOLCHAIN}/bin/lld-link"
    export RANLIB="${TOOLCHAIN}/bin/llvm-ranlib"
    export STRIP="${TOOLCHAIN}/bin/llvm-strip"

    export INCLUDE="${CURRENTPATH}/../libdvdread/include;${WINSDKINC}/winrt;${WINSDKINC}/ucrt;${WINSDKINC}/um;${WINSDKINC}/shared;${VCINC}"
    echo "INCLUDE:$INCLUDE"
    export LIB="${VCLIB}/${archs[i]};${WINSDKLIB}/um/${archs[i]};${WINSDKLIB}/ucrt/${archs[i]}"
    echo "LIB:$LIB"

    case ${ARCH} in
      x86)
          msvc_arch_cflags="--target=i686-pc-windows-msvc -m32 -msse3"
          msvc_arch_ldflags="-Wl,/safeseh:no -Wl,/MACHINE:X86"
          ;;
      x64)
          msvc_arch_cflags="--target=x86_64-pc-windows-msvc -m64 -msse3"
          msvc_arch_ldflags="-Wl,/MACHINE:X64"
          ;;
      *)
          msvc_arch_cflags=
          msvc_arch_ldflags=
          ;;
    esac

    export PKG_CONFIG_PATH="${CURRENTPATH}/../libudfread/${OUTPUT}/lib/pkgconfig:$PKG_CONFIG_PATH"
    export PKG_CONFIG_PATH="${CURRENTPATH}/../libdvdread/${OUTPUT}/lib/pkgconfig:$PKG_CONFIG_PATH"

    export CFLAGS="${OPTIMIZE} ${msvc_arch_cflags} -fuse-ld=lld -fms-compatibility -I${CURRENTPATH}/../libdvdread/include"
    export CXXFLAGS="${CFLAGS} /EHsc -std:c++11"
    export LDFLAGS="${msvc_arch_ldflags}"

    pushd "${DEPENDSPATH}/libdvdnav"

    autoreconf -i || exit

    export ac_cv_c_bigendian=no
    WSLPREFIX="${CURRENTPATH}/${OUTPUT}"
    rm -rf "${WSLPREFIX}" && mkdir -p "${WSLPREFIX}"
    ./configure      \
        --host=${targets[i]}                \
        --prefix="${WSLPREFIX}"             \
        --disable-shared                    \
        --enable-static                     \
        --disable-examples                  \
        ${build_with_debug}                 \

    make V=1 -j $(nproc) 2>&1 | tee build.log && make install || exit
    mkdir -p "${CURRENTPATH}/${OUTPUT}"
    sed -i "s|^prefix=.*|prefix=${CURRENTPATH}/${OUTPUT}|" "${CURRENTPATH}/${OUTPUT}/lib/pkgconfig/"*.pc 2>/dev/null || true

    popd
done

ls -l ${CURRENTPATH}/output/*/*/lib/*.lib
