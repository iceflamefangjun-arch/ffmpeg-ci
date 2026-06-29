SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 1
cd "${SCRIPT_DIR}" || exit 1
source "${SCRIPT_DIR}/../env_config.sh"

CURRENTPATH="${SCRIPT_DIR}"

set_target_archs "${2:-x86}"

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

VERSION_LIBDVDREAD="6.1.3"
############################################################################################
if [ ! -e ${DEPENDSPATH}/libdvdread ]; then
    echo "Downloading libdvdread"
    pushd ${DEPENDSPATH}
    git clone https://code.videolan.org/videolan/libdvdread.git
    popd
else
    echo "Update libdvdread"
    pushd ${DEPENDSPATH}/libdvdread
    #git checkout master && git pull
    popd
fi
############################################################################################
pushd ${DEPENDSPATH}/libdvdread
echo "reset src"
git checkout ${VERSION_LIBDVDREAD}
git reset --hard
popd

#trap "cd ${DEPENDSPATH}/libdvdread && git reset --hard" EXIT

patch --batch -N -d ${DEPENDSPATH}/libdvdread -p1 <${CURRENTPATH}/ssize_t.patch || exit
patch --batch -N -d ${DEPENDSPATH}/libdvdread -p1 <${CURRENTPATH}/unistd.patch || exit

############################################################################################
for ((i=0; i<${#archs[@]}; i++))
do
    OUTPUT="output/${BUILD}/${archs[i]}"
    rm -fr "${CURRENTPATH}/${OUTPUT}"

    rm -fr "${CURRENTPATH}/build"
    mkdir -p "${CURRENTPATH}/build"
    pushd "${CURRENTPATH}/build"

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

    export INCLUDE="${WINSDKINC}/winrt;${WINSDKINC}/ucrt;${WINSDKINC}/um;${WINSDKINC}/shared;${VCINC}"
    echo "INCLUDE:$INCLUDE"
    export LIB="${VCLIB}/${archs[i]};${WINSDKLIB}/um/${archs[i]};${WINSDKLIB}/ucrt/${archs[i]}"
    echo "LIB:$LIB"

    case ${ARCH} in
      x86)
          msvc_arch_cflags="--target=i686-pc-windows-msvc -m32 -msse3"
          msvc_arch_ldflags="/machine:x86 /safeseh:no"
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
    export CFLAGS="${CFLAGS} -I${CURRENTPATH}/include"
    export CXXFLAGS="${CFLAGS} ${CXX_OPTIMIZE} /EHsc -std:c++11"
    #export LDFLAGS="${msvc_arch_ldflags}"

    pushd ${DEPENDSPATH}/libdvdread && autoreconf -vif && popd || exit

    export ac_cv_c_bigendian=no
    #export ac_cv_sys_file_offset_bits=64
    #export ac_cv_sys_largefile_CC=" -D_FILE_OFFSET_BITS=64"
    #export ac_cv_header_sys_param_h=no
    #export ac_cv_c_compiler_gnu=yes
    sed -i -r -e 's|^(\s*ac_cv_c_bigendian=)unknown\s*$|\1no|' ${DEPENDSPATH}/libdvdread/configure

    WSLPREFIX="${CURRENTPATH}/${OUTPUT}"
    rm -rf "${WSLPREFIX}" && mkdir -p "${WSLPREFIX}"
    ${DEPENDSPATH}/libdvdread/configure     \
        --host=${targets[i]}                \
        --prefix="${WSLPREFIX}"             \
        --disable-shared                    \
        --enable-static                     \
        --without-libdvdcss                                  

    make V=1 -j $(nproc) 2>&1 | tee error.log && make install && make clean || exit
    mkdir -p "${CURRENTPATH}/${OUTPUT}"
    sed -i "s|^prefix=.*|prefix=${CURRENTPATH}/${OUTPUT}|" "${CURRENTPATH}/${OUTPUT}/lib/pkgconfig/"*.pc 2>/dev/null || true

    cp ${CURRENTPATH}/build/config.h ${CURRENTPATH}/${OUTPUT}/include || exit

    popd
done

ls -l ${CURRENTPATH}/output/*/*/lib/*.lib
