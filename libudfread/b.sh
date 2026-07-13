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
      build_with_debug="--disable-optimizations"
      ;;
  release)
      BUILD="release"
      OPTIMIZE="/O2 /MD /DNDEBUG ${OPTIMIZE} /GF /Gy /Gw"
      CMAKE_BUILD_TYPE="Release"
      ;;
  static)
      BUILD="static"
      # Thin LTO object files are much larger than normal object files and
      # overflow the GitHub Actions hosted Windows runner temp disk.
      # External dependencies do not need it for CI packages.
      OPTIMIZE="/O2 /MT /DNDEBUG ${OPTIMIZE}"
      CMAKE_BUILD_TYPE="Release"
      ;;
  *)
      echo "Only support [debug|release|static]" >&2; exit
      ;;
esac

VERSION_UDFREAD="1.1.2"
############################################################################################
if [ ! -e ${DEPENDSPATH}/libudfread ]; then
    echo "Downloading libudfread"
    pushd ${DEPENDSPATH}
    git clone https://code.videolan.org/videolan/libudfread.git
    pushd libudfread && git checkout ${VERSION_UDFREAD} && popd
    popd
else
    echo "Update libudfread"
    pushd ${DEPENDSPATH}/libudfread
    git checkout ${VERSION_UDFREAD}
    popd
fi
############################################################################################

pushd ${DEPENDSPATH}/libudfread
git reset --hard
popd

#trap "cd ${DEPENDSPATH}/libudfread && git reset --hard" EXIT

patch -d ${DEPENDSPATH}/libudfread -p1 <${CURRENTPATH}/ssize_t.patch || exit

############################################################################################
for ((i=0; i<${#archs[@]}; i++))
do
    OUTPUT="output/${BUILD}/${archs[i]}"
    rm -fr "${CURRENTPATH}/${OUTPUT}"

    rm -fr "${CURRENTPATH}/build"
    mkdir -p "${CURRENTPATH}/build"
    pushd "${CURRENTPATH}/build"

    echo "CURR DIR:" $(pwd)
    echo "Target:" ${archs[i]}

    export ARCH=${archs[i]}
    export PATH="${TOOLCHAIN}/bin:${PATH}"

    export AR="${LLVM_AR_TOOL}"
    export NM="${LLVM_NM_TOOL}"
    export MT="${LLVM_MT_TOOL}"
    export CC="${CLANG_CL_TOOL}"
    export CXX="${CLANG_CL_TOOL}"
    export LD="${LLD_LINK_TOOL}"
    export RANLIB="${LLVM_RANLIB_TOOL}"
    export STRIP="${LLVM_STRIP_TOOL}"

    set_msvc_arch_env "${archs[i]}"
    echo $LIB

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
      arm64)
          msvc_arch_cflags="--target=aarch64-pc-windows-msvc"
          msvc_arch_ldflags=(
            "/MACHINE:ARM64"
          )
          ;;
      *)
          msvc_arch_cflags=
          msvc_arch_ldflags=
          ;;
    esac

    export CFLAGS="${OPTIMIZE} ${msvc_arch_cflags} -fuse-ld=lld -fms-compatibility"
    export CXXFLAGS="${CFLAGS} ${CXX_OPTIMIZE} /EHsc -std:c++11"
    #export LDFLAGS="${msvc_arch_ldflags[@]}"

    pushd ${DEPENDSPATH}/libudfread && autoreconf -i && popd || exit

    WSLPREFIX="${CURRENTPATH}/${OUTPUT}"
    rm -rf "${WSLPREFIX}" && mkdir -p "${WSLPREFIX}"
    export ac_cv_c_bigendian=no
    ${DEPENDSPATH}/libudfread/configure     \
        --host=${targets[i]}                \
        --prefix="${WSLPREFIX}"             \
        --disable-shared                    \
        --enable-static                     \
        ${build_with_debug}                 \

    make V=1 -j $(nproc) && make install && make clean || exit
    mkdir -p "${CURRENTPATH}/${OUTPUT}"
    sed -i "s|^prefix=.*|prefix=${CURRENTPATH}/${OUTPUT}|" "${CURRENTPATH}/${OUTPUT}/lib/pkgconfig/"*.pc 2>/dev/null || true

    popd
done

ls -l ${CURRENTPATH}/output/*/*/lib/*.lib
